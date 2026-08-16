test_that("tabular input matches the cffdrs engine exactly", {
  # This wrapper must not change the physics. If it ever diverges from
  # cffdrs::fwi() on the same input, the wrapper is wrong, not cffdrs.
  w <- synth_weather_table()
  ours <- fev_fwi_calc(w)
  theirs <- cffdrs::fwi(
    w, init = data.frame(ffmc = 85, dmc = 6, dc = 15, lat = 43.3)
  )
  expect_equal(ours$FWI, theirs$FWI)
  expect_equal(ours$DC, theirs$DC)
  expect_true(all(c("FFMC", "DMC", "DC", "ISI", "BUI", "FWI", "DSR") %in%
                    names(ours)))
})

test_that("missing latitude is refused, not defaulted to British Columbia", {
  # cffdrs substitutes 55 N and warns in passing. Latitude drives the
  # day-length adjustment in DMC and DC, so the substitution silently biases
  # two of the three moisture codes for any European study.
  w <- synth_weather_table()
  expect_error(fev_fwi_calc(w[, setdiff(names(w), "lat")]),
               class = "fev_no_latitude")
})

test_that("the latitude adjustment is banded, which is the real argument", {
  # Documented because it is counter-intuitive and because the docs claim it:
  # metropolitan France and the substituted 55 N sit in the same >= 30 N band,
  # so the substitution is harmless there and only there.
  # Wind kept above the m/s heuristic so the only condition under test is
  # latitude.
  tbl <- function(lat) synth_weather_table(n = 60, lat = lat,
                                           ws = c(10, 25, 35, 45, 20))
  fr <- fev_fwi_calc(tbl(43.3))
  bc <- fev_fwi_calc(tbl(55))
  expect_equal(fr$DMC, bc$DMC)
  expect_equal(fr$DC, bc$DC)

  # Below 30 N -- the DROM -- it is not harmless, which is why lat is required
  # rather than defaulted.
  trop <- fev_fwi_calc(tbl(16))
  expect_false(isTRUE(all.equal(fr$DMC, trop$DMC)))
  expect_false(isTRUE(all.equal(fr$DC, trop$DC)))
  expect_lt(trop$DMC[10], fr$DMC[10])
})

test_that("missing weather columns are named", {
  w <- synth_weather_table()
  expect_error(fev_fwi_calc(w[, setdiff(names(w), "rh")]),
               class = "fev_bad_weather")
  expect_error(fev_fwi_calc(w[, setdiff(names(w), c("temp", "ws"))]),
               class = "fev_bad_weather")
})

test_that("impossible values are errors and suspicious ones are warnings", {
  w <- synth_weather_table()

  bad_rh <- w
  bad_rh$rh <- 0.4  # a fraction rather than a percentage
  expect_no_error(fev_fwi_calc(bad_rh))  # 0.4 is a legal percentage
  bad_rh$rh <- 140
  expect_error(fev_fwi_calc(bad_rh), class = "fev_bad_weather")

  bad_ws <- w
  bad_ws$ws <- -1
  expect_error(fev_fwi_calc(bad_ws), class = "fev_bad_weather")

  hot <- w
  hot$temp <- 95
  expect_warning(fev_fwi_calc(hot), class = "fev_suspicious_weather")
})

test_that("wind that looks like metres per second is flagged", {
  # Not an error: 8 km/h is a legal wind. But a 60-day record that never
  # exceeds 30 km/h is what m/s looks like, and would understate ISI and FWI
  # throughout without any other symptom.
  w <- synth_weather_table(n = 60)
  w$ws <- rep_len(c(2, 3, 4, 5), 60)
  expect_warning(fev_fwi_calc(w), class = "fev_suspicious_units")

  # A short record says nothing, so it does not warn.
  short <- synth_weather_table(n = 5)
  short$ws <- 3
  expect_no_warning(fev_fwi_calc(short))
})

test_that("a single weather grid returns a danger layer", {
  g <- synth_weather_grid()
  out <- fev_fwi_calc(g)
  expect_s3_class(out, "fev_danger_layer")
  r <- fev_data(out)
  expect_true(all(c("FFMC", "DMC", "DC", "ISI", "BUI", "FWI") %in% names(r)))
  # Same forcings as the tabular fixture's first row, so the same FWI.
  expect_equal(as.numeric(terra::values(r[["FWI"]])[1]),
               cffdrs::fwi(synth_weather_table(n = 1))$FWI, tolerance = 1e-6)
})

test_that("a sequence carries the moisture codes forward", {
  # Five rainless days must accumulate drought: DC on the last day has to
  # exceed DC on the first. Re-initialising each step -- the mistake this loop
  # exists to prevent -- would make them identical.
  days <- replicate(5, synth_weather_grid(prec = 0), simplify = FALSE)
  expect_warning(out <- fev_fwi_calc(days, months = rep(7, 5)),
                 class = "fev_scalar_carryover")
  r <- fev_data(out)
  dc <- r[[grep("^DC", names(r))]]
  first <- as.numeric(terra::values(dc[[1]])[1])
  last <- as.numeric(terra::values(dc[[terra::nlyr(dc)]])[1])
  expect_gt(last, first)
})

test_that("gridded input is validated layer by layer", {
  g <- synth_weather_grid()
  names(g) <- c("temperature", "rh", "ws", "prec")
  expect_error(fev_fwi_calc(g), class = "fev_bad_weather")

  ok <- synth_weather_grid()
  expect_error(fev_fwi_calc(list(ok, ok), months = c(6, 7, 8)),
               class = "fev_error")
  expect_error(fev_fwi_calc("not weather"), class = "fev_error")
})

test_that("the parameters used are recorded", {
  g <- synth_weather_grid()
  out <- fev_fwi_calc(g, months = 8)
  step <- out$provenance$steps[[1]]
  expect_equal(step$fun, "fev_fwi_calc")
  expect_equal(step$params$months, 8)
  expect_equal(step$params$engine, "cffdrs::fwiRaster")
  expect_equal(step$params$init$ffmc, 85)
})
