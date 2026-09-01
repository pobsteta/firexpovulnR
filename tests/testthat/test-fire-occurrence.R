# Nothing here touches the network: the input is the output of
# fev_fetch_bdiff(), which is a table plus commune polygons, and both are built
# in the test.

square <- function(x0, side = 2000) {
  sf::st_polygon(list(cbind(
    c(x0, x0 + side, x0 + side, x0, x0),
    c(0, 0, side, side, 0)
  )))
}

synth_com <- function(codes = c("21001", "21002"), key = "INSEE_COM",
                      side = 2000) {
  geo <- lapply(seq_along(codes), function(i) square((i - 1) * side, side))
  sf::st_sf(
    stats::setNames(list(codes), key),
    geometry = sf::st_sfc(geo, crs = 2154),
    stringsAsFactors = FALSE
  )
}

synth_fires <- function(insee = c("21001", "21001"),
                        years = c(2010L, 2015L),
                        area_ha = c(3, 12),
                        com = synth_com()) {
  key <- names(com)[1]
  idx <- match(insee, com[[key]])
  sf::st_sf(
    insee = insee, fire_year = years, area_ha = area_ha,
    geometry = sf::st_geometry(com)[idx], stringsAsFactors = FALSE
  )
}

synth_grid <- function(res = 500) {
  terra::rast(terra::ext(0, 4000, 0, 2000), resolution = res,
              crs = "EPSG:2154")
}

# The arithmetic ----------------------------------------------------------------

test_that("the rate is fires per 100 km2 per year, and it is exactly that", {
  # 2 fires, a 4 km2 commune, a 20-year window: 2 / 4 / 20 * 100 = 2.5
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2006, 2025), quiet = TRUE
  ))
  vals <- sort(terra::unique(fev_data(occ))[, 1])
  expect_equal(vals, c(0, 2.5))
  expect_s3_class(occ, "fev_layer")
  expect_equal(occ$role, "occurrence")
  expect_match(occ$units, "per 100 km2 per year")
})

test_that("count and burnt_rate answer different questions", {
  args <- list(synth_fires(), synth_grid(), communes = synth_com(),
               period = c(2006, 2025), quiet = TRUE)

  cnt <- suppressWarnings(do.call(fev_fire_occurrence,
                                  c(args, measure = "count")))
  expect_equal(sort(terra::unique(fev_data(cnt))[, 1]), c(0, 2))
  expect_match(cnt$units, "2006-2025")

  # 15 ha burnt over 4 km2 over 20 years: 15 / 4 / 20 * 100 = 18.75
  brn <- suppressWarnings(do.call(fev_fire_occurrence,
                                  c(args, measure = "burnt_rate")))
  expect_equal(sort(terra::unique(fev_data(brn))[, 1]), c(0, 18.75))
})

test_that("the period is a denominator, so it changes the rate", {
  ten <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2016, 2025), quiet = TRUE
  ))
  # Same two fires, half the window, twice the rate.
  expect_equal(max(terra::unique(fev_data(ten))[, 1]), 5)
})

test_that("output = communes returns the table the raster was built from", {
  cc <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2006, 2025), output = "communes", quiet = TRUE
  ))
  expect_s3_class(cc, "sf")
  expect_equal(nrow(cc), 2L)
  expect_equal(cc$n_fires, c(2L, 0L))
  expect_equal(cc$burnt_ha, c(15, 0))
  expect_equal(cc$area_km2, c(4, 4))
  expect_false(is.null(attr(cc, "provenance")))
})

# Absent is not zero -------------------------------------------------------------

test_that("without a commune layer, unrecorded ground is NA and it says so", {
  expect_warning(
    fev_fire_occurrence(synth_fires(), synth_grid(),
                        period = c(2006, 2025), quiet = TRUE),
    class = "fev_occ_no_zero_communes"
  )
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), period = c(2006, 2025), quiet = TRUE
  ))
  r <- fev_data(occ)
  # Only the commune that recorded something is mapped; the other half of the
  # grid is unobserved, not fire-free.
  expect_true(terra::global(r, "notNA")[[1]] < terra::ncell(r))
  expect_equal(sort(unique(terra::values(r, na.rm = TRUE))), 2.5)
})

test_that("with a commune layer, silence becomes zero and the record says why", {
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2006, 2025), quiet = TRUE
  ))
  expect_equal(terra::global(fev_data(occ), "notNA")[[1]],
               terra::ncell(fev_data(occ)))

  step <- utils::tail(occ$provenance$steps, 1)[[1]]
  expect_equal(step$params$n_communes_zero, 1L)
  expect_match(step$params$zeros_assumed_from, "no declared fire")
  expect_true(step$params$information_is_communal)
})

# The scale mismatch --------------------------------------------------------------

test_that("a grid finer than the commune warns, with the ratio", {
  expect_warning(
    fev_fire_occurrence(synth_fires(), synth_grid(res = 100),
                        communes = synth_com(), period = c(2006, 2025),
                        quiet = TRUE),
    class = "fev_occ_scale_mismatch"
  )
  # And the ratio is recorded whether or not the warning fired.
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(res = 100), communes = synth_com(),
    period = c(2006, 2025), quiet = TRUE
  ))
  step <- utils::tail(occ$provenance$steps, 1)[[1]]
  expect_equal(step$params$cell_m, 100)
  expect_gt(step$params$commune_equivalent_diameter_m, 2000)
})

test_that("a grid at the communal scale does not warn", {
  # 2 km cells against a ~2.3 km commune: ratio near 1, nothing to flag.
  expect_no_warning(
    withCallingHandlers(
      fev_fire_occurrence(synth_fires(), synth_grid(res = 2000),
                          communes = synth_com(), period = c(2006, 2025),
                          quiet = TRUE),
      fev_occ_scale_mismatch = function(w) stop("scale warning fired")
    )
  )
})

# The denominator ----------------------------------------------------------------

test_that("an absent period is inferred from the data, loudly", {
  # The span of the records is a LOWER bound on the window observed, so the
  # rate comes out too high and that has to be said, not assumed away.
  expect_warning(
    fev_fire_occurrence(synth_fires(), synth_grid(), communes = synth_com(),
                        quiet = TRUE),
    class = "fev_occ_period_inferred"
  )
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(), quiet = TRUE
  ))
  # 2010-2015 is six years, not twenty: 2 / 4 / 6 * 100
  expect_equal(max(terra::unique(fev_data(occ))[, 1]), 2 / 4 / 6 * 100,
               tolerance = 1e-6)   # terra stores float32
})

test_that("the period is read from the source record when there is one", {
  src <- structure(
    list(data = synth_fires(),
         source = list(dataset = "bdiff", period_requested = "2006-2025")),
    class = "fev_source"
  )
  occ <- suppressWarnings(fev_fire_occurrence(
    src, synth_grid(), communes = synth_com(), quiet = TRUE
  ))
  expect_equal(max(terra::unique(fev_data(occ))[, 1]), 2.5)

  step <- utils::tail(occ$provenance$steps, 1)[[1]]
  expect_equal(step$params$period, "2006-2025")
  expect_match(step$params$period_source, "source record")
})

# Refusals -------------------------------------------------------------------------

test_that("records without geometry are refused, and told how to fix it", {
  flat <- sf::st_drop_geometry(synth_fires())
  expect_error(
    fev_fire_occurrence(flat, synth_grid()),
    class = "fev_occ_no_geometry"
  )
  err <- tryCatch(fev_fire_occurrence(flat, synth_grid()),
                  error = function(e) e)
  expect_match(conditionMessage(err), "communes", fixed = TRUE)
})

test_that("a template with no CRS is refused rather than guessed", {
  g <- synth_grid()
  terra::crs(g) <- ""
  expect_error(
    fev_fire_occurrence(synth_fires(), g, communes = synth_com()),
    class = "fev_error"
  )
})

test_that("missing columns name what is present", {
  f <- synth_fires()
  f$fire_year <- NULL
  expect_error(
    fev_fire_occurrence(f, synth_grid()),
    class = "fev_occ_missing_column"
  )
})

test_that("min_area_ha filters before counting, and can empty the result", {
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2006, 2025), min_area_ha = 10, quiet = TRUE
  ))
  # Only the 12 ha fire survives: 1 / 4 / 20 * 100
  expect_equal(max(terra::unique(fev_data(occ))[, 1]), 1.25)

  expect_error(
    suppressWarnings(fev_fire_occurrence(
      synth_fires(), synth_grid(), communes = synth_com(),
      period = c(2006, 2025), min_area_ha = 1000, quiet = TRUE
    )),
    class = "fev_empty_result"
  )
  expect_error(
    fev_fire_occurrence(synth_fires(), synth_grid(), min_area_ha = -1),
    class = "fev_error"
  )
})

test_that("a commune with records but absent from the layer is reported", {
  fires <- synth_fires(insee = c("21001", "21999"), years = c(2010L, 2012L),
                       area_ha = c(3, 4),
                       com = synth_com(c("21001", "21999")))
  expect_warning(
    fev_fire_occurrence(fires, synth_grid(), communes = synth_com(),
                        period = c(2006, 2025), quiet = TRUE),
    class = "fev_occ_unmatched_communes"
  )
})

# Areas that are not there ----------------------------------------------------------

test_that("burnt_rate without any area is refused, not answered with zeros", {
  # Summing absent areas with na.rm gives 0 everywhere: a uniform zero map
  # labelled "ha burnt", which reads as "nothing burnt" instead of "nothing
  # supplied". Found by chasing an uncovered line, not by a failing test.
  f <- synth_fires()
  f$area_ha <- NULL

  expect_error(
    fev_fire_occurrence(f, synth_grid(), communes = synth_com(),
                        period = c(2006, 2025), measure = "burnt_rate",
                        quiet = TRUE),
    class = "fev_occ_no_areas"
  )
  # count and rate do not need a size, so they still work on the same input.
  occ <- suppressWarnings(fev_fire_occurrence(
    f, synth_grid(), communes = synth_com(), period = c(2006, 2025),
    measure = "count", quiet = TRUE
  ))
  expect_equal(sort(terra::unique(fev_data(occ))[, 1]), c(0, 2))
})

test_that("a few missing areas understate the rate, and say so", {
  f <- synth_fires(insee = c("21001", "21001"), area_ha = c(12, NA))
  expect_warning(
    fev_fire_occurrence(f, synth_grid(), communes = synth_com(),
                        period = c(2006, 2025), measure = "burnt_rate",
                        quiet = TRUE),
    class = "fev_occ_partial_areas"
  )
  occ <- suppressWarnings(fev_fire_occurrence(
    f, synth_grid(), communes = synth_com(), period = c(2006, 2025),
    measure = "burnt_rate", quiet = TRUE
  ))
  # The NA counted as zero: 12 ha, not 15.
  expect_equal(max(terra::unique(fev_data(occ))[, 1]), 12 / 4 / 20 * 100)

  step <- utils::tail(occ$provenance$steps, 1)[[1]]
  expect_equal(step$params$n_fires_without_area, 1L)
})

# The remaining guards ---------------------------------------------------------------

test_that("degenerate geometry is refused rather than divided by", {
  # A commune of zero area would make every rate infinite.
  flat <- sf::st_sf(
    INSEE_COM = "21001",
    geometry = sf::st_sfc(
      sf::st_polygon(list(cbind(c(0, 1000, 0, 0), c(0, 0, 0, 0)))),
      crs = 2154
    )
  )
  fires <- sf::st_sf(insee = "21001", fire_year = 2010L, area_ha = 3,
                     geometry = sf::st_geometry(flat))
  expect_error(
    fev_fire_occurrence(fires, synth_grid(), communes = flat,
                        period = c(2006, 2025), quiet = TRUE),
    class = "fev_error"
  )
})

test_that("communes must be an sf, and empty records are refused", {
  expect_error(
    fev_fire_occurrence(synth_fires(), synth_grid(),
                        communes = data.frame(INSEE_COM = "21001"),
                        period = c(2006, 2025), quiet = TRUE),
    class = "fev_error"
  )
  expect_error(
    fev_fire_occurrence(synth_fires()[0, ], synth_grid()),
    class = "fev_empty_result"
  )
})

test_that("the report speaks when it is not silenced", {
  # Not box-ticking: a cli message only builds when it is emitted, so an
  # unexercised {} interpolation is an error nobody has seen yet. This package
  # has already shipped one such -- a pluralisation with no quantity.
  expect_message(
    suppressWarnings(fev_fire_occurrence(
      synth_fires(), synth_grid(), communes = synth_com(),
      period = c(2006, 2025), min_area_ha = 5, quiet = FALSE
    )),
    "Median commune"
  )
  expect_message(
    suppressWarnings(fev_fire_occurrence(
      synth_fires(), synth_grid(), communes = synth_com(),
      period = c(2006, 2025), min_area_ha = 5, quiet = FALSE
    )),
    "no declared fire"
  )
  # And the denominator read from the source record announces itself.
  src <- structure(
    list(data = synth_fires(),
         source = list(dataset = "bdiff", period_requested = "2006-2025")),
    class = "fev_source"
  )
  expect_message(
    suppressWarnings(fev_fire_occurrence(src, synth_grid(),
                                         communes = synth_com(), quiet = FALSE)),
    "read from the source record"
  )
})

# It feeds the rest of the package ---------------------------------------------------

test_that("the layer enters fev_risk as one more dimension", {
  occ <- suppressWarnings(fev_fire_occurrence(
    synth_fires(), synth_grid(), communes = synth_com(),
    period = c(2006, 2025), quiet = TRUE
  ))
  g <- synth_grid()
  danger <- terra::setValues(g, seq(0, 1, length.out = terra::ncell(g)))
  vuln <- terra::setValues(g, rev(seq(0, 1, length.out = terra::ncell(g))))

  risk <- fev_risk(danger, vuln, ignition = occ, normalise = "minmax")
  expect_s3_class(risk, "fev_risk_layer")
  expect_true(isTRUE(terra::compareGeom(fev_data(risk), g,
                                        stopOnError = FALSE)))
})
