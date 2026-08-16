# Load test for the focal exposure pass.
#
# Off by default, like the network tests: it allocates a department-sized
# raster and takes over a minute. Run it with
#
#   FIREXPOVULNR_TEST_LOAD=1 Rscript -e 'testthat::test_local(filter = "load")'
#
# It exists because the brief asks for a documented load test on a realistic
# extent, and because the cost of this pass is not linear in anything obvious:
# the window is expressed in metres and materialised in cells, so the work goes
# as the inverse fourth power of the cell size. The nemeton project met exactly
# this with the same metric at 2 m and sat at 51% of one core for 75 minutes.
#
# Reference measurements, this machine, 2026-08-16, random burnable at p = 0.4:
#
#   emprise      res    cells        window     elapsed   peak
#   100 km2      25 m     160 000      1 256      1.0 s      -
#   400 km2      25 m     640 000      1 256      4.5 s      -
#   6 006 km2    25 m   9 610 000      1 256   61-83 s   155 Mb
#
# The spread on the last row is run-to-run variation on the same machine, not
# two different measurements: it is the honest width of a single timing.
#
# The assertions below are deliberately loose. They are there to catch a change
# of algorithmic class -- a quadratic scan creeping into the window build, say
# -- not to pin a timing that depends on the machine.

skip_if_no_load_test <- function() {
  testthat::skip_if_not(
    identical(Sys.getenv("FIREXPOVULNR_TEST_LOAD"), "1"),
    "load test disabled (set FIREXPOVULNR_TEST_LOAD=1)"
  )
}

load_landscape <- function(n, res = 25, p = 0.4) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
                   ymin = 0, ymax = n * res, crs = "EPSG:2154")
  terra::values(r) <- stats::rbinom(terra::ncell(r), 1, p)
  names(r) <- "burnable"
  r
}

test_that("cost grows with cells, not faster", {
  skip_if_no_load_test()
  withr::local_seed(1)

  small <- load_landscape(400)
  large <- load_landscape(800)   # four times the cells

  t_small <- system.time(
    fev_exposure(small, radius = 500, quiet = TRUE)
  )[["elapsed"]]
  t_large <- system.time(
    fev_exposure(large, radius = 500, quiet = TRUE)
  )[["elapsed"]]

  # Four times the cells for the same window should be roughly four times the
  # work. Allowing up to eight leaves room for cache effects and a slow
  # machine while still failing on anything quadratic.
  expect_lt(t_large / max(t_small, 0.05), 8)
})

test_that("a department-sized extent completes and streams to disk", {
  skip_if_no_load_test()
  withr::local_seed(2)

  # 3100 x 3100 cells at 25 m is 6006 km2 -- the size of the Var.
  r <- load_landscape(3100)
  expect_equal(round(terra::ncell(r) * 625 / 1e6), 6006)

  f <- withr::local_tempfile(fileext = ".tif")
  elapsed <- system.time(
    e <- fev_exposure(r, radius = 500, quiet = TRUE, filename = f,
                      overwrite = TRUE)
  )[["elapsed"]]

  message(sprintf("department-sized pass: %.1f s", elapsed))
  expect_true(file.exists(f))
  expect_s3_class(e, "fev_exposure_layer")

  vals <- terra::values(fev_data(e))
  expect_true(all(vals >= 0 & vals <= 1, na.rm = TRUE))
  # Random burnable at p = 0.4 gives an exposure centred on 0.4, whatever the
  # machine: a correctness check that survives being run anywhere.
  expect_equal(mean(vals, na.rm = TRUE), 0.4, tolerance = 0.01)

  # Ten minutes is not a performance target, it is the line between "slow" and
  # "something is algorithmically wrong".
  expect_lt(elapsed, 600)
})

test_that("the cost estimate matches what the pass actually costs", {
  skip_if_no_load_test()
  withr::local_seed(3)

  r <- load_landscape(800)
  w <- fev_annulus_window(25, 500)
  ops <- as.numeric(terra::ncell(r)) * sum(!is.na(w))

  elapsed <- system.time(
    fev_exposure(r, radius = 500, quiet = TRUE)
  )[["elapsed"]]
  throughput <- ops / elapsed / 1e6
  message(sprintf("%.0f M weighted operations per second", throughput))

  # Measured at 180-210 M ops/s when this was written. The band is wide
  # because it is a machine property, not a package one.
  expect_gt(throughput, 20)
})

test_that("the guard fires before an infeasible pass, not during it", {
  # This one needs no big allocation: the estimate is computed from the grid
  # geometry, so it runs in the normal suite.
  r <- terra::rast(nrows = 2500, ncols = 2000, xmin = 0, xmax = 4000,
                   ymin = 0, ymax = 5000, crs = "EPSG:2154")
  w <- fev_annulus_window(2, 500)
  expect_warning(
    fev_check_focal_cost(r, sum(!is.na(w)), 2, 500, quiet = FALSE),
    class = "fev_focal_cost"
  )
  # The nemeton case: 2 m, 500 m radius, five million cells.
  ops <- as.numeric(terra::ncell(r)) * sum(!is.na(w))
  expect_gt(ops, 9e11)

  # And it stays quiet at a workable resolution.
  expect_no_warning(
    fev_check_focal_cost(r, sum(!is.na(fev_annulus_window(25, 500))), 25, 500,
                         quiet = FALSE)
  )
})
