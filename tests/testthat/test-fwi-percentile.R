# The percentile calibration is the methodological core, so it is tested
# against analytic values rather than against its own previous output. The
# fixture gives every cell the values 1..n in layer order, so the rank of
# layer j is exactly 100 * j / n.

test_that("percentile ranks match the analytic value", {
  r <- synth_danger_series(n = 100)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10)
  ))
  v <- terra::values(fev_data(p))
  expect_equal(v[1, ], 100 * seq_len(100) / 100, ignore_attr = TRUE)
  # Every cell carries the same series, so every row is the same.
  expect_true(all(apply(v, 2, function(col) length(unique(col)) == 1L)))
})

test_that("ranks stay inside 0-100 and keep one layer per input layer", {
  r <- synth_danger_series(n = 60)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10)
  ))
  out <- fev_data(p)
  expect_equal(terra::nlyr(out), 60L)
  expect_equal(names(out), names(r))
  expect_equal(terra::time(out), terra::time(r))
  vals <- terra::values(out)
  expect_true(all(vals >= 0 & vals <= 100, na.rm = TRUE))
})

test_that("the reference period is a subset, but every layer is still ranked", {
  # Two years; rank the whole record against the first year only.
  r <- synth_danger_series(n = 730, start = "2019-01-01")
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, ref_period = c(2019, 2019), season = NULL)
  ))
  out <- fev_data(p)
  expect_equal(terra::nlyr(out), 730L)
  # Values in year two all exceed every reference value, so they saturate.
  v <- terra::values(out)[1, ]
  expect_equal(unname(v[730]), 100)
  expect_equal(unname(v[365]), 100)
  expect_lt(v[100], 100)

  step <- p$provenance$steps[[length(p$provenance$steps)]]
  expect_equal(step$params$n_ref_layers, 365L)
  expect_equal(step$params$ref_years, 1L)
})

test_that("the fire season default excludes the off-season from the reference", {
  r <- synth_danger_series(n = 365, start = "2020-01-01")
  # 1 April to 31 October in a leap year: 214 days.
  p <- suppressWarnings(suppressMessages(fev_fwi_percentile(r)))
  step <- p$provenance$steps[[length(p$provenance$steps)]]
  expect_equal(step$params$n_ref_layers, 214L)
  expect_equal(step$params$ref_first, "2020-04-01")
  expect_equal(step$params$ref_last, "2020-10-31")

  # And season = NULL really does use everything.
  p2 <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL)
  ))
  step2 <- p2$provenance$steps[[length(p2$provenance$steps)]]
  expect_equal(step2$params$n_ref_layers, 365L)
})

test_that("undated layers are refused rather than assumed", {
  r <- synth_danger_series(n = 40)
  terra::time(r) <- NULL
  expect_error(fev_fwi_percentile(r), class = "fev_no_time")

  # ... but dates can be supplied.
  expect_no_error(suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 10,
                       time = seq(as.Date("2020-06-01"), by = "day",
                                  length.out = 40))
  )))
  expect_error(
    fev_fwi_percentile(r, time = seq(as.Date("2020-06-01"), by = "day",
                                     length.out = 3)),
    class = "fev_error"
  )
})

test_that("an empty reference is an error, not an empty result", {
  r <- synth_danger_series(n = 40, start = "2020-01-01")
  # January only, against the April-October default season.
  expect_error(fev_fwi_percentile(r), class = "fev_empty_reference")
  expect_error(
    fev_fwi_percentile(r, ref_period = c(1990, 1995), season = NULL),
    class = "fev_empty_reference"
  )
})

test_that("a short reference period is reported, not silently accepted", {
  # The WMO standard normal is 30 years; anything shorter is a choice the
  # record has to show. A short period is usually also a thin one, so both
  # warnings fire together and are asserted as a set.
  r <- synth_danger_series(n = 200, start = "2020-04-01")
  cls <- warning_classes(fev_fwi_percentile(r, season = NULL))
  expect_true("fev_short_reference" %in% cls)
  expect_true("fev_thin_reference" %in% cls)

  # Ten full years clears the span warning; only the sample-size one remains.
  long <- synth_danger_series(n = 3650, start = "2011-01-01")
  cls2 <- warning_classes(fev_fwi_percentile(long, season = NULL,
                                             min_ref = 5000))
  expect_false("fev_short_reference" %in% cls2)
  expect_true("fev_thin_reference" %in% cls2)
})

test_that("no ref_period says so instead of silently using everything", {
  r <- synth_danger_series(n = 40, start = "2020-05-01")
  expect_message(
    suppressWarnings(fev_fwi_percentile(r, season = NULL, min_ref = 10)),
    class = "fev_default_reference"
  )
})

test_that("by = region needs regions", {
  r <- synth_danger_series(n = 40, start = "2020-05-01")
  expect_error(
    suppressWarnings(suppressMessages(fev_fwi_percentile(r, by = "region"))),
    class = "fev_no_regions"
  )
})

test_that("regional pooling ranks a value against its own region", {
  # Region 1 cells run 1..50, region 2 cells run 101..150. The same absolute
  # value therefore means completely different things in the two, which is the
  # whole reason for calibrating regionally.
  n <- 50
  vals <- rbind(
    matrix(rep(seq_len(n), each = 2), nrow = 2),          # cells 1-2
    matrix(rep(100 + seq_len(n), each = 2), nrow = 2)     # cells 3-4
  )
  r <- synth_danger_series(n = n, start = "2020-05-01", values = vals)
  zones <- terra::rast(r[[1]])
  terra::values(zones) <- c(1, 1, 2, 2)

  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, by = "region", regions = zones, season = NULL,
                       min_ref = 10)
  ))
  v <- terra::values(fev_data(p))
  # Last layer is the maximum of both pools.
  expect_equal(unname(v[1, n]), 100)
  expect_equal(unname(v[3, n]), 100)
  # Mid-record sits mid-distribution in both, despite values differing by 100.
  expect_equal(unname(v[1, n / 2]), unname(v[3, n / 2]))
})

test_that("regions can be given as polygons", {
  r <- synth_danger_series(n = 40, start = "2020-05-01", nrow = 2, ncol = 2)
  sq <- function(x1, x2) {
    sf::st_polygon(list(cbind(c(x1, x2, x2, x1, x1), c(0, 0, 50, 50, 0))))
  }
  rg <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(sq(0, 25), sq(25, 50),
                                                  crs = 2154))
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, by = "region", regions = rg, season = NULL,
                       min_ref = 10)
  ))
  expect_equal(terra::nlyr(fev_data(p)), 40L)
  expect_false(anyNA(terra::values(fev_data(p))))
})

test_that("a thin regional pool is reported with its size", {
  # A region pool is cells times layers, so it can never be larger than the
  # per-pixel reference -- both thin warnings fire, and nested expect_warning()
  # cannot assert twice on one class.
  r <- synth_danger_series(n = 20, start = "2020-05-01")
  zones <- terra::rast(r[[1]])
  terra::values(zones) <- c(1, 1, 2, 2)
  cls <- warning_classes(
    fev_fwi_percentile(r, by = "region", regions = zones, season = NULL,
                       min_ref = 365)
  )
  expect_equal(sum(cls == "fev_thin_reference"), 2L)
})

test_that("the calibration parameters end up in the provenance", {
  r <- synth_danger_series(n = 300, start = "2020-01-01")
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, ref_period = c(2020, 2020))
  ))
  step <- p$provenance$steps[[length(p$provenance$steps)]]
  expect_equal(step$fun, "fev_fwi_percentile")
  expect_equal(step$params$by, "pixel")
  expect_equal(step$params$ref_period, "2020..2020")
  expect_equal(step$params$season, c("04-01", "10-31"))
  expect_s3_class(p, "fev_danger_layer")
  expect_equal(p$units, "percentile rank, 0-100")
})

# --- caliver threshold derivation -------------------------------------------

test_that("thresholds reproduce caliver's extreme value definition", {
  # The extreme value is the median across years of each year's 98th
  # percentile. Recomputed here independently of the implementation.
  set.seed(3)
  n <- 3 * 214
  vals <- matrix(stats::runif(4 * n, 0, 60), nrow = 4)
  r <- synth_danger_series(n = n, start = "2019-04-01", values = vals)
  # Keep only April-October of each year so the fixture matches the default.
  th <- fev_fwi_thresholds(r)

  dates <- terra::time(r)
  md <- format(dates, "%m-%d")
  keep <- which(md >= "04-01" & md <= "10-31")
  years <- format(dates[keep], "%Y")
  v <- terra::values(r)[, keep, drop = FALSE]
  yearly <- vapply(unique(years), function(y) {
    x <- as.numeric(v[, which(years == y), drop = FALSE])
    as.numeric(stats::quantile(x[!is.na(x)], 0.98))
  }, numeric(1))
  expect_equal(attr(th, "extreme"), stats::median(yearly))
})

test_that("thresholds are five strictly increasing breaks", {
  set.seed(4)
  r <- synth_danger_series(n = 214, start = "2020-04-01",
                           values = matrix(stats::runif(4 * 214, 0, 60),
                                           nrow = 4))
  th <- fev_fwi_thresholds(r)
  expect_length(th, 5L)
  expect_false(is.unsorted(th))
  expect_true(all(th >= 0))
  # ndays = 4 is caliver's default and yields the 98th percentile exactly --
  # floor() before the division, not 0.98904.
  expect_equal(attr(th, "percentile"), 0.98)
  expect_equal(attr(fev_fwi_thresholds(r, ndays = 18), "percentile"), 0.95)
})

test_that("thresholds feed straight into fev_fwi_classes()", {
  set.seed(5)
  r <- synth_danger_series(n = 214, start = "2020-04-01",
                           values = matrix(stats::runif(4 * 214, 0, 60),
                                           nrow = 4))
  th <- fev_fwi_thresholds(r)
  cls <- fev_fwi_classes(breaks = as.numeric(th),
                         labels = c("Very Low", "Low", "Moderate", "High",
                                    "Very High", "Extreme"))
  expect_equal(nrow(cls), 6L)
  expect_equal(cls$upper[1], as.numeric(th[1]))
})

test_that("an all-NA record yields NA thresholds, with a warning", {
  r <- synth_danger_series(n = 214, start = "2020-04-01",
                           values = matrix(NA_real_, nrow = 4, ncol = 214))
  expect_warning(th <- fev_fwi_thresholds(r), class = "fev_all_na")
  expect_true(all(is.na(th)))
  expect_length(th, 5L)
})

# --- the two published class schemes ----------------------------------------

test_that("both danger class schemes are shipped, with their own breaks", {
  effis <- fev_fwi_classes()
  expect_equal(effis$upper[1:5], c(11.2, 21.3, 38.0, 50.0, 70.0))
  expect_equal(as.character(effis$class[1]), "Low")

  # Vitolo et al. 2018, ERA-Interim 1980-2016, April-October, Europe.
  cal <- fev_fwi_classes("caliver_europe")
  expect_equal(cal$upper[1:5], c(2, 5, 10, 19, 33))
  expect_equal(as.character(cal$class[1]), "Very Low")

  # They really do disagree: an FWI of 40 is not the same class under each.
  band <- function(tab, x) as.character(tab$class[x >= tab$lower & x < tab$upper])
  expect_equal(band(effis, 40), "Very High")
  expect_equal(band(cal, 40), "Extreme")
})

test_that("class overrides are validated", {
  expect_error(fev_fwi_classes(breaks = c(1, 2)), class = "fev_error")
  expect_error(fev_fwi_classes(breaks = c(5, 2, 8, 9, 10)), class = "fev_error")
  expect_error(fev_fwi_classes("nonsense"), class = "error")
})
