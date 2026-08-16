grid4 <- function(values) {
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 50, ymin = 0,
                   ymax = 50, crs = "EPSG:2154")
  terra::values(r) <- values
  r
}

test_that("each combination method computes what it says", {
  d <- grid4(c(0, 50, 80, 100))     # percentile ranks
  a <- grid4(c(1, 1, 0.5, 0.25))    # availability
  v <- function(x) as.numeric(terra::values(fev_data(x)))

  expect_equal(v(fev_danger_index(d, a, normalise = "percentile")),
               c(0, 0.5, 0.4, 0.25))
  expect_equal(v(fev_danger_index(d, a, method = "min",
                                  normalise = "percentile")),
               c(0, 0.5, 0.5, 0.25))
  expect_equal(v(fev_danger_index(d, a, method = "mean",
                                  normalise = "percentile")),
               c(0.5, 0.75, 0.65, 0.625))
  expect_equal(v(fev_danger_index(d, a, method = "geometric",
                                  normalise = "percentile")),
               sqrt(c(0, 0.5, 0.4, 0.25)))
})

test_that("no fuel means no danger under the default method", {
  # The reason product is the default: a fuel break or a lake should zero the
  # index however bad the weather is, and only a multiplicative rule does that.
  d <- grid4(rep(100, 4))
  a <- grid4(c(0, 0, 1, 1))
  v <- as.numeric(terra::values(fev_data(
    fev_danger_index(d, a, normalise = "percentile")
  )))
  expect_equal(v, c(0, 0, 1, 1))

  # Under "mean" it does not, which is the point of documenting the choice.
  v2 <- as.numeric(terra::values(fev_data(
    fev_danger_index(d, a, method = "mean", normalise = "percentile")
  )))
  expect_equal(v2, c(0.5, 0.5, 1, 1))
})

test_that("mismatched grids are refused rather than silently resampled", {
  # The scale gap between kilometric danger and decametric fuel is the single
  # most consequential step in the chain. It happens in one named place.
  d <- grid4(rep(50, 4))
  a <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 50, ymin = 0,
                   ymax = 50, crs = "EPSG:2154")
  terra::values(a) <- 0.5
  expect_error(fev_danger_index(d, a, normalise = "percentile"),
               class = "fev_grid_mismatch")

  # Different CRS is the same refusal.
  b <- grid4(rep(0.5, 4))
  terra::crs(b) <- "EPSG:3035"
  expect_error(fev_danger_index(d, b, normalise = "percentile"),
               class = "fev_grid_mismatch")
})

test_that("normalisation is never guessed from the value range", {
  # A layer of values between 0 and 60 could be raw FWI or a percentile rank.
  # Guessing turns one into the other with no visible symptom.
  d <- grid4(c(5, 20, 40, 60))
  a <- grid4(rep(0.8, 4))
  expect_error(fev_danger_index(d, a), class = "fev_normalise_ambiguous")

  # A fev_fwi_percentile() result is a percentile by construction, so auto
  # resolves there and only there.
  r <- synth_danger_series(n = 40, start = "2020-05-01", nrow = 2, ncol = 2)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10)
  ))
  avail <- terra::rast(fev_data(p)[[1]])
  terra::values(avail) <- 0.5
  expect_no_error(fev_danger_index(p, avail))
})

test_that("out-of-range inputs are caught on both sides", {
  d <- grid4(c(0, 50, 80, 100))

  bad_a <- grid4(c(0, 1, 2, 3))
  expect_error(fev_danger_index(d, bad_a, normalise = "percentile"),
               class = "fev_bad_range")

  raw_fwi <- grid4(c(10, 60, 120, 200))
  a <- grid4(rep(0.5, 4))
  expect_error(fev_danger_index(raw_fwi, a, normalise = "percentile"),
               class = "fev_bad_range")
  expect_error(fev_danger_index(d, a, normalise = "none"),
               class = "fev_bad_range")

  already <- grid4(c(0, 0.3, 0.6, 1))
  expect_no_error(fev_danger_index(already, a, normalise = "none"))
})

test_that("min-max normalisation warns that it depends on the extent", {
  d <- grid4(c(10, 20, 30, 40))
  a <- grid4(rep(1, 4))
  expect_warning(out <- fev_danger_index(d, a, normalise = "minmax"),
                 class = "fev_extent_dependent")
  expect_equal(as.numeric(terra::values(fev_data(out))), c(0, 1 / 3, 2 / 3, 1))

  flat <- grid4(rep(20, 4))
  expect_error(fev_danger_index(flat, a, normalise = "minmax"),
               class = "fev_bad_range")
})

test_that("mean weights are validated", {
  d <- grid4(c(0, 50, 80, 100))
  a <- grid4(rep(0.5, 4))
  expect_error(
    fev_danger_index(d, a, method = "mean", normalise = "percentile",
                     weights = c(0.6, 0.6)),
    class = "fev_error"
  )
  expect_error(
    fev_danger_index(d, a, method = "mean", normalise = "percentile",
                     weights = 1),
    class = "fev_error"
  )
  expect_no_error(
    fev_danger_index(d, a, method = "mean", normalise = "percentile",
                     weights = c(0.7, 0.3))
  )
})

test_that("a multi-layer danger series keeps its layers", {
  r <- synth_danger_series(n = 12, start = "2020-05-01", nrow = 2, ncol = 2)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 5)
  ))
  a <- terra::rast(fev_data(p)[[1]])
  terra::values(a) <- c(1, 1, 0.5, 0)
  out <- fev_danger_index(p, a)
  expect_equal(terra::nlyr(fev_data(out)), 12L)
  expect_equal(names(fev_data(out)), names(fev_data(p)))
  # The zero-fuel cell is zero on every day.
  expect_true(all(terra::values(fev_data(out))[4, ] == 0))
})

test_that("both inputs' provenance travels into the result", {
  r <- synth_danger_series(n = 40, start = "2020-05-01", nrow = 4, ncol = 4)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10)
  ))
  cat_r <- synth_class_raster(c("FF2-57-57", "LA4"), nrow = 4, ncol = 4)
  cat_r <- terra::rast(fev_data(p)[[1]]) |>
    (\(tpl) {
      out <- terra::rast(tpl)
      terra::values(out) <- rep_len(1:2, terra::ncell(tpl))
      levels(out) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
      names(out) <- "class"
      out
    })()
  fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)
  avail <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))

  out <- fev_danger_index(p, avail)
  funs <- vapply(out$provenance$steps, function(s) s$fun, character(1))
  expect_true("fev_fwi_percentile" %in% funs)
  expect_true("fev_fuel_availability" %in% funs)
  expect_equal(funs[length(funs)], "fev_danger_index")

  step <- out$provenance$steps[[length(funs)]]
  expect_equal(step$params$method, "product")
  expect_equal(step$params$normalise, "percentile")
  expect_equal(step$params$danger_role, "fwi_percentile")
})

test_that("a multi-layer availability is refused", {
  d <- grid4(c(0, 50, 80, 100))
  a <- c(grid4(rep(0.5, 4)), grid4(rep(0.7, 4)))
  expect_error(fev_danger_index(d, a, normalise = "percentile"),
               class = "fev_error")
  expect_error(fev_danger_index(d, "not a raster"), class = "fev_error")
})

test_that("the result prints and plots", {
  d <- grid4(c(0, 50, 80, 100))
  a <- grid4(rep(0.5, 4))
  out <- fev_danger_index(d, a, normalise = "percentile")
  expect_no_error(print(out))
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(out))
})
