# Burn severity from Sentinel-2.
#
# Three defects were found by running this against the Cannet-des-Maures fire,
# and each one produced a plausible-looking map with a wrong number. They are
# what these tests exist for:
#
#   1. the margin counted from the fire's START picked a scene taken two hours
#      before containment: most of the perimeter had not burned yet;
#   2. the least-cloudy candidate was an EDGE-OF-SWATH partial covering 1% of
#      the area, published at 0.0% cloud;
#   3. the coverage check itself measured the CROPPED result rather than the
#      area, so a scene carrying 46.6% of the fire reported 100%. The fire
#      straddles a tile edge and needs two tiles mosaicked.
#
# Note what the three have in common: none was a crash. Each returned a
# severity map that a reader would have accepted.

fire_sf <- function(start = "2021-08-16", end = "2021-08-19") {
  geom <- sf::st_sfc(sf::st_polygon(list(cbind(
    c(6.25, 6.40, 6.40, 6.25, 6.25), c(43.35, 43.35, 43.42, 43.42, 43.35)
  ))), crs = 4326)
  sf::st_sf(FIREDATE = paste(start, "20:35:00"),
            FINALDATE = paste(end, "12:32:00"),
            area_ha = 6510, geometry = geom)
}

test_that("the fire's span is read from EFFIS dates when they are there", {
  s <- firexpovulnR:::fev_fire_span(fire_sf(), NULL, quiet = TRUE)
  expect_equal(s$start, as.Date("2021-08-16"))
  expect_equal(s$end, as.Date("2021-08-19"))
})

test_that("two dates are taken as start and end, in either order", {
  a <- firexpovulnR:::fev_fire_span(NULL, c("2021-08-19", "2021-08-16"),
                                    quiet = TRUE)
  expect_equal(a$start, as.Date("2021-08-16"))
  expect_equal(a$end, as.Date("2021-08-19"))
})

test_that("one date is accepted, and the assumption is stated", {
  # A large fire burns for days; the margin then runs from the wrong end. The
  # function says so rather than deciding quietly.
  s <- firexpovulnR:::fev_fire_span(NULL, "2021-08-16", quiet = TRUE)
  expect_equal(s$start, s$end)
  expect_message(
    firexpovulnR:::fev_fire_span(NULL, "2021-08-16", quiet = FALSE),
    "burns for days"
  )
})

test_that("no date and no dates in the data is an error, not a guess", {
  bare <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(6.3, 43.4)),
                                          crs = 4326))
  expect_error(firexpovulnR:::fev_fire_span(bare, NULL, quiet = TRUE),
               class = "fev_no_fire_date")
})

test_that("a fire end before its start collapses to the start", {
  # EFFIS occasionally carries a FINALDATE that predates FIREDATE. Taking it at
  # face value would make the post-fire window start before the fire.
  f <- fire_sf(start = "2021-08-16", end = "2021-08-10")
  s <- firexpovulnR:::fev_fire_span(f, NULL, quiet = TRUE)
  expect_equal(s$start, s$end)
})

test_that("coverage is the valid fraction, which is what a swath edge breaks", {
  g <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
                   ymin = 0, ymax = 100, crs = "EPSG:2154")
  full <- terra::setValues(g, 1)
  expect_equal(firexpovulnR:::fev_coverage(full), 1)
  part <- full
  part[1:95] <- NA
  expect_equal(firexpovulnR:::fev_coverage(part), 0.05)
})

test_that("the search parses a STAC response without a JSON package", {
  # yaml is already an import and JSON is a subset of YAML, so the package does
  # not gain a dependency for one search.
  txt <- paste0('{"type":"FeatureCollection","features":[',
                '{"id":"S2A_31TGH_20210718_1_L2A",',
                '"properties":{"datetime":"2021-07-18T10:39:05.000Z",',
                '"eo:cloud_cover":0.0,"grid:code":"MGRS-31TGH"},',
                '"assets":{"nir":{"href":"http://x/nir.tif"},',
                '"swir22":{"href":"http://x/swir.tif"}}}]}')
  d <- yaml::yaml.load(txt)
  expect_equal(length(d$features), 1L)
  expect_equal(d$features[[1]]$properties[["grid:code"]], "MGRS-31TGH")
  expect_equal(d$features[[1]]$assets$nir$href, "http://x/nir.tif")
})

test_that("bad windows are refused before any download", {
  expect_error(
    fev_fetch_severity(fire_sf(), pre_window = -1, quiet = TRUE),
    "non-negative"
  )
  expect_error(
    fev_fetch_severity(fire_sf(), fire_date = "pas une date", quiet = TRUE),
    "one date, or two"
  )
})

# --- end to end, network only ----------------------------------------------

test_that("the Cannet-des-Maures fire comes back at the measured severity", {
  skip_unless_network()
  # The regression that matters. Measured 2026-08-19 over two mosaicked tiles
  # and 663 000 cells: 0.576 inside the perimeter, 0.000 outside, 41.9% above
  # the high-severity threshold. The bounds are loose because the scene choice
  # can legitimately move; they are here to catch a partial scene, a mis-timed
  # pair or a lost tile, each of which halves the answer.
  feux <- sf::st_read(system.file("extdata", "maures.gpkg",
                                  package = "firexpovulnR"),
                      "burnt_areas", quiet = TRUE)
  gros <- feux[which.max(feux$area_ha), ]
  sev <- suppressMessages(fev_fetch_severity(gros, quiet = TRUE))
  d <- fev_data(sev)
  v <- terra::vect(sf::st_transform(gros, terra::crs(d)))
  inside <- stats::na.omit(terra::values(terra::mask(d, v))[, 1])
  outside <- stats::na.omit(terra::values(
    terra::mask(d, v, inverse = TRUE))[, 1])

  expect_gt(stats::median(inside), 0.4)
  # The control. A dNBR that does not return to zero on ground that did not
  # burn is measuring phenology, haze or a partial scene -- not fire.
  expect_lt(abs(stats::median(outside)), 0.1)
  expect_gt(stats::median(inside) - stats::median(outside), 0.4)
})

test_that("an edge-of-swath scene is refused rather than differenced", {
  skip_unless_network()
  # Demanding total coverage over an area that straddles two tiles leaves no
  # candidate, and the function says why instead of returning a map built on
  # 1% of the pixels.
  wide <- sf::st_sf(
    FIREDATE = "2021-08-16 20:35:00", FINALDATE = "2021-08-19 12:32:00",
    geometry = sf::st_sfc(sf::st_polygon(list(cbind(
      c(5.6, 7.4, 7.4, 5.6, 5.6), c(43.1, 43.1, 43.9, 43.9, 43.1)
    ))), crs = 4326))
  # 5.6 to 7.4 degrees of longitude is wider than any single pass returns
  # complete here, so no candidate reaches total coverage.
  expect_error(
    suppressMessages(fev_fetch_severity(wide, min_coverage = 0.9999,
                                        n_candidates = 1, pre_window = 12,
                                        post_window = 12, quiet = TRUE)),
    class = "fev_scene_partial"
  )
})
