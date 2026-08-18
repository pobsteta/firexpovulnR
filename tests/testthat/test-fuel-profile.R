# Confronting a classification with a measurement.
#
# Synthetic grids throughout, except the two tests that use the shipped Maures
# LiDAR extracts -- those are the real phase 10 step 2 measurement, and they are
# here so that a change in the fuel tables cannot move it silently.

grid <- function(n = 20, res = 25, crs = "EPSG:2154") {
  terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
              ymin = 0, ymax = n * res, crs = crs)
}

classified <- function(n = 20, res = 25) {
  r <- grid(n, res)
  terra::values(r) <- rep(c(4, 5), each = terra::ncell(r) / 2)
  levels(r) <- data.frame(id = c(4, 5), class = c("4", "5"))
  r
}

measured <- function(n = 20, res = 25, lo = 0.5, hi = 4.5, sd = 0.1) {
  r <- grid(n, res)
  half <- terra::ncell(r) / 2
  set.seed(42)
  terra::values(r) <- c(stats::rnorm(half, lo, sd), stats::rnorm(half, hi, sd))
  names(r) <- "H_Bush"
  r
}

test_that("a class that really is distinct separates near 1", {
  p <- fev_fuel_profile(classified(), measured(), class = "5", quiet = TRUE)
  expect_s3_class(p, "fev_fuel_profile")
  expect_gt(p$separability$separability, 0.99)
})

test_that("a class that carries no information separates near 0.5", {
  cls <- classified()
  noise <- grid()
  set.seed(1)
  terra::values(noise) <- stats::rnorm(terra::ncell(noise))
  names(noise) <- "H_Bush"

  p <- fev_fuel_profile(cls, noise, class = "5", quiet = TRUE)
  expect_lt(abs(p$separability$separability - 0.5), 0.1)
  # And the variance accounted for collapses with it.
  expect_lt(p$explained$explained, 0.05)
})

test_that("variance accounted for is high when the class predicts the metric", {
  p <- fev_fuel_profile(classified(), measured(), quiet = TRUE)
  expect_gt(p$explained$explained, 0.95)
})

test_that("the summary has one row per class and metric", {
  p <- fev_fuel_profile(classified(), measured(), quiet = TRUE)
  expect_equal(nrow(p$summary), 2L)
  expect_setequal(p$summary$class, c("4", "5"))
  expect_true(all(p$summary$n > 0))
  expect_true(all(p$summary$q25 <= p$summary$median))
  expect_true(all(p$summary$median <= p$summary$q75))
})

test_that("a categorical reference is refused: the point is to test against a measurement", {
  expect_error(
    fev_fuel_profile(classified(), classified(), quiet = TRUE),
    class = "fev_profile_no_continuous"
  )
})

test_that("a fuel layer without classes is refused", {
  plain <- measured()
  expect_error(
    fev_fuel_profile(plain, measured(), quiet = TRUE),
    class = "fev_profile_no_categorical"
  )
})

test_that("an absent class is named rather than silently scoring NA", {
  expect_error(
    fev_fuel_profile(classified(), measured(), class = "99", quiet = TRUE),
    class = "fev_profile_absent_class"
  )
})

test_that("a metric the reference does not carry is refused", {
  expect_error(
    fev_fuel_profile(classified(), measured(), metrics = "CBD_max",
                     quiet = TRUE),
    class = "fev_profile_missing_metric"
  )
})

test_that("too few cells withholds the statistic but keeps the profile", {
  p <- fev_fuel_profile(classified(n = 6), measured(n = 6), class = "5",
                        min_cells = 30, quiet = TRUE)
  expect_true(is.na(p$separability$separability))
  expect_equal(nrow(p$summary), 2L)
})

test_that("upsampling is detected and stated, not left to be noticed", {
  # A 10 m classification against a 25 m measurement: the phase 10 case.
  fine <- terra::rast(nrows = 50, ncols = 50, xmin = 0, xmax = 500,
                      ymin = 0, ymax = 500, crs = "EPSG:2154")
  terra::values(fine) <- rep(c(4, 5), each = 1250)
  levels(fine) <- data.frame(id = c(4, 5), class = c("4", "5"))

  coarse <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 500,
                        ymin = 0, ymax = 500, crs = "EPSG:2154")
  terra::values(coarse) <- seq_len(400)
  names(coarse) <- "H_Bush"

  p <- fev_fuel_profile(fine, coarse, quiet = TRUE)
  expect_true(p$upsampled)
  expect_true(any(grepl("UPSAMPLING", p$notes)))
})

test_that("matching grids are not resampled and not flagged", {
  p <- fev_fuel_profile(classified(), measured(), quiet = TRUE)
  expect_false(p$upsampled)
  expect_length(p$notes, 0L)
})

test_that("the default metrics are the understorey-bearing ones", {
  ref <- c(grid(), grid(), grid())
  names(ref) <- c("Height", "H_Bush", "FL_0_1")
  expect_equal(firexpovulnR:::fev_profile_default_metrics(names(ref)),
               c("H_Bush", "FL_0_1"))
  # With none of them present, everything is profiled rather than nothing.
  expect_equal(firexpovulnR:::fev_profile_default_metrics(c("a", "b")),
               c("a", "b"))
})

# --------------------------------------------------------------------------
# The real measurement, on the shipped Maures LiDAR plots
# --------------------------------------------------------------------------

maures_profile <- function() {
  gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
  skip_if(!nzchar(gpkg), "Maures extract not installed")

  sq <- sf::st_read(gpkg, "lidar_squares", quiet = TRUE)
  bdf <- sf::st_read(gpkg, "bdforet_v2", quiet = TRUE)
  clc <- sf::st_read(gpkg, "clc_2018", quiet = TRUE)
  aoi <- sf::st_union(sf::st_buffer(sq, 25))

  prim <- fev_fuel_source(bdf, type = "bdforet_v2", res = 25, aoi = aoi,
                          millesime = 2014)
  aux <- fev_fuel_source(clc, type = "clc_2018", res = 25, aoi = aoi,
                         millesime = 2018)
  fuel <- suppressMessages(fev_fuel_merge(prim, aux))

  lid <- terra::merge(
    terra::rast(system.file("extdata", "lidar_burnt.tif",
                            package = "firexpovulnR")),
    terra::rast(system.file("extdata", "lidar_control.tif",
                            package = "firexpovulnR"))
  )
  fev_fuel_profile(fuel, lid, quiet = TRUE)
}

test_that("the current sources describe the canopy far better than the understorey", {
  # This is the package's central methodological limitation, measured rather
  # than asserted. Cover is what BD Forêt and CORINE actually record, and the
  # 1-3 m band is the maquis stratum that carries surface fire.
  p <- maures_profile()
  ex <- stats::setNames(p$explained$explained, p$explained$metric)

  expect_gt(ex[["Cover"]], 0.35)
  expect_lt(ex[["FL_1_3"]], 0.15)
  # The gap is the point: canopy information, no understorey information.
  expect_gt(ex[["Cover"]] - ex[["FL_1_3"]], 0.25)
})

test_that("both LiDAR plots carry the same dominant BD Foret class", {
  # The clearest form of the limitation: one class, two very different grounds.
  gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
  skip_if(!nzchar(gpkg), "Maures extract not installed")
  sq <- sf::st_read(gpkg, "lidar_squares", quiet = TRUE)
  expect_equal(length(unique(sq$tfv_dominant)), 1L)

  burnt <- terra::rast(system.file("extdata", "lidar_burnt.tif",
                                   package = "firexpovulnR"))
  control <- terra::rast(system.file("extdata", "lidar_control.tif",
                                     package = "firexpovulnR"))
  h_burnt <- terra::global(burnt[["H_Bush"]], "mean", na.rm = TRUE)[1, 1]
  h_control <- terra::global(control[["H_Bush"]], "mean", na.rm = TRUE)[1, 1]
  # Same class, and the understorey differs by a factor of several.
  expect_gt(h_control / h_burnt, 3)
})
