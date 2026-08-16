# The two published schemes disagree by a factor of three, and a classified
# GeoTIFF carries no note of which one produced it. These tests pin the
# difference and check that the scheme reaches the provenance record.

dgrid <- function(values) {
  r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100, ymin = 0,
                   ymax = 100, crs = "EPSG:2154")
  terra::values(r) <- values
  r
}

test_that("classification returns a categorical layer of the scheme's labels", {
  r <- dgrid(seq(0, 75, length.out = 16))
  out <- fev_danger_class(r)
  expect_s3_class(out, "fev_danger_layer")
  lv <- terra::levels(fev_data(out))[[1]]
  expect_equal(lv$class, as.character(fev_fwi_classes()$class))
  expect_equal(names(fev_data(out)), "danger_class")
})

test_that("the same value lands in different classes under the two schemes", {
  # An FWI of 40: Very High under EFFIS, Extreme under caliver. If this ever
  # stops being true, one of the two tables has drifted from its source.
  r <- dgrid(rep(40, 16))
  label <- function(x) {
    lv <- terra::levels(fev_data(x))[[1]]
    unique(lv$class[match(terra::values(fev_data(x))[, 1], lv$id)])
  }
  expect_equal(label(fev_danger_class(r, "effis")), "Very High")
  expect_equal(label(fev_danger_class(r, "caliver_europe")), "Extreme")
})

test_that("the scheme and its source reach the provenance", {
  r <- dgrid(seq(0, 75, length.out = 16))

  a <- fev_danger_class(r, "effis")
  step <- a$provenance$steps[[length(a$provenance$steps)]]
  expect_equal(step$params$scheme, "effis")
  expect_equal(step$params$breaks, c(11.2, 21.3, 38.0, 50.0, 70.0))
  expect_match(step$params$source, "EFFIS")

  b <- fev_danger_class(r, "caliver_europe")
  step_b <- b$provenance$steps[[length(b$provenance$steps)]]
  expect_equal(step_b$params$breaks, c(2, 5, 10, 19, 33))
  expect_match(step_b$params$source, "Vitolo")
})

test_that("breaks derived from the record can be used directly", {
  set.seed(7)
  series <- synth_danger_series(n = 214, start = "2020-04-01",
                                values = matrix(stats::runif(4 * 214, 0, 60),
                                                nrow = 4))
  th <- fev_fwi_thresholds(series)
  out <- fev_danger_class(dgrid(seq(0, 75, length.out = 16)),
                          breaks = as.numeric(th))
  step <- out$provenance$steps[[length(out$provenance$steps)]]
  expect_equal(step$params$scheme, "custom")
  expect_equal(step$params$breaks, as.numeric(th))
  expect_match(step$params$source, "user-supplied")
})

test_that("percentile ranks are refused, since FWI breaks mean nothing to them", {
  r <- synth_danger_series(n = 30, start = "2020-05-01", nrow = 2, ncol = 2)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10)
  ))
  expect_error(fev_danger_class(p), class = "fev_wrong_scale")
})

test_that("custom without breaks is refused", {
  r <- dgrid(seq(0, 75, length.out = 16))
  expect_error(fev_danger_class(r, "custom"), class = "fev_error")
  expect_error(fev_danger_class(r, breaks = c(1, 2)), class = "fev_error")
})

test_that("every value gets a class, including the extremes", {
  r <- dgrid(c(-5, 0, 11.2, 21.3, 38, 50, 70, 200, rep(25, 8)))
  out <- fev_danger_class(r)
  expect_false(anyNA(terra::values(fev_data(out))))
  lv <- terra::levels(fev_data(out))[[1]]
  labels <- lv$class[match(terra::values(fev_data(out))[, 1], lv$id)]
  # Breaks are lower-closed, so a value exactly on a break belongs to the
  # class above it.
  expect_equal(labels[3], "Moderate")
  expect_equal(labels[8], "Very Extreme")
})
