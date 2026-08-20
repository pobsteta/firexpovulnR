# SUFOSAT clear-cuts.
#
# The measurement this file protects, from the Maures study area on 2026-08-20:
# 2 626 ha detected for 2021, of which **97% inside the Cannet-des-Maures fire
# perimeter**, median detection on day 246 -- fifteen days after containment.
# The method sees vegetation gone and cannot say what removed it, so a severe
# fire reads as a clear-cut. Everything here exists to keep that from becoming
# a silent fuel correction.

test_that("YYDDD decodes into a year and a day", {
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20,
                   ymin = 0, ymax = 20, crs = "EPSG:2154")
  # 21228 = 2021, day 228 = 16 August, the day the Cannet-des-Maures started.
  r <- terra::setValues(g, c(21228L, 18001L, 25366L, 0L))
  d <- firexpovulnR:::fev_sufosat_decode(r)
  y <- terra::values(d[["cut_year"]])[, 1]
  j <- terra::values(d[["cut_doy"]])[, 1]
  expect_equal(y[1:3], c(2021, 2018, 2025))
  expect_equal(j[1:3], c(228, 1, 366))
  # Nodata must not become year 2000 day 0, which would look like a detection.
  expect_true(is.na(y[4]))
  expect_true(is.na(j[4]))
})

test_that("a day of year never leaves 1 to 366", {
  g <- terra::rast(nrows = 1, ncols = 9, xmin = 0, xmax = 90,
                   ymin = 0, ymax = 10, crs = "EPSG:2154")
  r <- terra::setValues(g, as.integer(c(17001, 18100, 19200, 20300, 21366,
                                        22015, 23180, 24240, 25244)))
  j <- stats::na.omit(terra::values(
    firexpovulnR:::fev_sufosat_decode(r)[["cut_doy"]])[, 1])
  expect_true(all(j >= 1 & j <= 366))
})

test_that("fire perimeters are accepted in every shape the package produces", {
  poly <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 10, 10, 0, 0), c(0, 0, 10, 10, 0)))), crs = 2154))
  from_sf <- firexpovulnR:::fev_sufosat_fires(poly, "EPSG:2154")
  from_vect <- firexpovulnR:::fev_sufosat_fires(terra::vect(poly), "EPSG:2154")
  expect_s4_class(from_sf, "SpatVector")
  expect_s4_class(from_vect, "SpatVector")
  expect_error(firexpovulnR:::fev_sufosat_fires("pas une geometrie",
                                                "EPSG:2154"),
               "must be a")
})

test_that("an impossible probability is refused before any download", {
  zone <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(6.2, 6.3, 6.3, 6.2, 6.2), c(43.3, 43.3, 43.4, 43.4, 43.3)))), crs = 4326))
  expect_error(fev_fetch_sufosat(zone, min_prob = 150, quiet = TRUE),
               "percentage")
})

# --- network only ----------------------------------------------------------

test_that("the Maures clear-cuts are mostly the 2021 fire", {
  skip_unless_network()
  # The regression that matters, and the reason `fires` exists. Without the
  # exclusion the map reports thousands of hectares of "clear-cut" that are an
  # incendie; with it, a plausible background of real forestry.
  gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
  zone <- sf::st_read(gpkg, "study_area", quiet = TRUE)
  feux <- sf::st_read(gpkg, "burnt_areas", quiet = TRUE)

  raw <- suppressWarnings(fev_fetch_sufosat(zone, quiet = TRUE))
  clean <- fev_fetch_sufosat(zone, fires = feux, quiet = TRUE)

  n <- function(x) sum(!is.na(terra::values(
    fev_data(x)[["cut_year"]])[, 1]))
  expect_gt(n(raw), n(clean))
  # Most of what the raw map calls a cut is inside a fire perimeter.
  expect_gt((n(raw) - n(clean)) / n(raw), 0.8)

  y <- stats::na.omit(terra::values(fev_data(raw)[["cut_year"]])[, 1])
  expect_true(all(y >= 2017 & y <= 2026))
  # 2021 dominates, and it is the fire.
  expect_equal(as.numeric(names(which.max(table(y)))), 2021)
})

test_that("asking without fire perimeters warns rather than obliging", {
  skip_unless_network()
  zone <- sf::st_read(system.file("extdata", "maures.gpkg",
                                  package = "firexpovulnR"),
                      "study_area", quiet = TRUE)
  expect_warning(fev_fetch_sufosat(zone, quiet = TRUE),
                 class = "fev_sufosat_fires_included")
})
