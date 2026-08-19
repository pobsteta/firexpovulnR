# Topographic downscaling of the danger term.
#
# The measurement this file exists to protect, from the Maures on 16 August
# 2021 over 597 840 cells: crossing elevation bands with each reanalysis
# point's territory took the FWI field from 17 distinct values to 77, and the
# align ratio from 141 000 fine cells per coarse cell to 1.05. Bands ALONE gave
# 8 -- fewer than the coarse chain -- because they replace the horizontal
# variation instead of adding to it. That is the failure mode the crossing
# exists for, and the one a later edit could silently reintroduce.

# The grid sits where the stations are. An earlier version of this file put the
# ramp at the Lambert-93 origin and the stations in the Var, several hundred
# kilometres apart: one station was then nearest to every cell, the crossing
# produced a single territory, and the test for it failed for a reason that had
# nothing to do with the code.
MAURES_X <- 966000
MAURES_Y <- 6240000

dem_ramp <- function(n = 40, top = 800, cell = 500) {
  g <- terra::rast(nrows = n, ncols = n,
                   xmin = MAURES_X, xmax = MAURES_X + n * cell,
                   ymin = MAURES_Y, ymax = MAURES_Y + n * cell,
                   crs = "EPSG:2154")
  (terra::init(g, "y") - MAURES_Y) / (n * cell) * top
}

# Dates through a real calendar rather than day 1..40 of one month: an earlier
# version asked for 2021-07-40, which is NA, and the failure surfaced as a date
# "not in the weather" instead of as a bad fixture.
weather_at <- function(ids = c("a", "b"), lat = c(43.32, 43.40),
                       long = c(6.15, 6.35), elev = 100, days = 40) {
  d <- seq(as.Date("2021-07-01"), by = "day", length.out = days)
  do.call(rbind, lapply(seq_along(ids), function(k) {
    data.frame(id = ids[k], lat = lat[k], long = long[k],
               yr = as.integer(format(d, "%Y")),
               mon = as.integer(format(d, "%m")),
               day = as.integer(format(d, "%d")),
               temp = 30 + k, rh = 35, ws = 12, prec = 0,
               elev_m = elev, stringsAsFactors = FALSE)
  }))
}

LAST_DAY <- as.Date("2021-07-01") + 39

test_that("bands are quantiles, so each holds a comparable area", {
  z <- fev_topo_zones(dem_ramp(), n_elev = 4, quiet = TRUE)
  tab <- attr(z, "zones")
  expect_equal(nrow(tab), 4L)
  # Equal intervals on a ramp would also be equal-area; the point of the test is
  # that the counts do not differ by more than rounding.
  expect_lt(max(tab$n_cells) - min(tab$n_cells), 5)
  expect_true(all(diff(tab$elev_mean) > 0))
})

test_that("without stations the zones are bands alone, and say so", {
  z <- fev_topo_zones(dem_ramp(), n_elev = 4, quiet = TRUE)
  expect_false("station" %in% names(attr(z, "zones")))
  w <- weather_at()
  # Downscaling on such zones pools cells from across the whole area under one
  # series. It still works, and it warns, because that is the configuration
  # that made the Maures field flatter than the coarse chain.
  expect_warning(
    fev_downscale_weather(w, z, quiet = TRUE),
    class = "fev_zones_without_stations"
  )
})

test_that("crossing with stations multiplies the zones, not replaces them", {
  d <- dem_ramp()
  w <- weather_at()
  bands <- fev_topo_zones(d, n_elev = 4, quiet = TRUE)
  crossed <- fev_topo_zones(d, n_elev = 4, stations = w, quiet = TRUE)
  expect_equal(nrow(attr(bands, "zones")), 4L)
  # Two points x four bands: more zones than either factor alone, which is the
  # whole correction.
  expect_gt(nrow(attr(crossed, "zones")), 4L)
  expect_true("station" %in% names(attr(crossed, "zones")))
  expect_setequal(unique(attr(crossed, "zones")$station), c("a", "b"))
})

test_that("temperature falls with height at the stated rate", {
  d <- dem_ramp(top = 1000)
  w <- weather_at(elev = 0)
  z <- fev_topo_zones(d, n_elev = 4, stations = w, quiet = TRUE)
  ds <- fev_downscale_weather(w, z, lapse_rate = 6.5, quiet = TRUE)
  zt <- attr(z, "zones")
  one <- ds[ds$zone == zt$zone[which.max(zt$elev_mean)], ][1, ]
  src <- w[w$id == one$from_id, ][1, ]
  expect_equal(one$temp, src$temp - 6.5 * (one$elev_m - src$elev_m) / 1000,
               tolerance = 1e-8)
})

test_that("cooling at constant dewpoint raises the humidity", {
  # Thermodynamics, not a fitted relation: the same water in colder air is
  # closer to saturation.
  expect_gt(firexpovulnR:::fev_rh_at_temperature(30, 40, 25), 40)
  expect_lt(firexpovulnR:::fev_rh_at_temperature(30, 40, 35), 40)
})

test_that("humidity is clamped to a physical range", {
  # A lapse rate extrapolated far enough up a mountain crosses saturation.
  expect_lte(firexpovulnR:::fev_rh_at_temperature(30, 95, -20), 100)
  expect_gte(firexpovulnR:::fev_rh_at_temperature(10, 5, 60), 1)
})

test_that("wind and rain pass through untouched", {
  # Not an oversight: neither has a calibration this package can defend, and
  # the documentation states the consequence for ISI, DMC and DC.
  d <- dem_ramp()
  w <- weather_at()
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  ds <- fev_downscale_weather(w, z, quiet = TRUE)
  expect_setequal(unique(ds$ws), unique(w$ws))
  expect_setequal(unique(ds$prec), unique(w$prec))
})

test_that("weather with no reference elevation is refused", {
  d <- dem_ramp()
  w <- weather_at()
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  expect_error(
    fev_downscale_weather(w[, setdiff(names(w), "elev_m")], z, quiet = TRUE),
    class = "fev_no_reference_elevation"
  )
})

test_that("the FWI accumulates per zone and lands back on the grid", {
  d <- dem_ramp()
  w <- weather_at(days = 30)
  z <- fev_topo_zones(d, n_elev = 4, stations = w, quiet = TRUE)
  ds <- fev_downscale_weather(w, z, quiet = TRUE)
  out <- suppressWarnings(
    fev_fwi_zonal(ds, z, dates = as.Date("2021-07-30"), quiet = TRUE)
  )
  r <- fev_data(out)
  expect_equal(terra::nlyr(r), 1L)
  expect_true(terra::compareGeom(r, fev_data(z), stopOnError = FALSE))
  # One value per zone, no more: the map is a lookup, not an interpolation.
  vals <- unique(stats::na.omit(terra::values(r)[, 1]))
  expect_lte(length(vals), nrow(attr(z, "zones")))
  expect_gt(length(vals), 1L)
})

test_that("a date outside the weather is an error, not an empty layer", {
  d <- dem_ramp()
  w <- weather_at(days = 30)
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  ds <- fev_downscale_weather(w, z, quiet = TRUE)
  expect_error(
    suppressWarnings(fev_fwi_zonal(ds, z, dates = as.Date("2021-11-01"),
                                   quiet = TRUE)),
    "not in the weather"
  )
})

test_that("higher ground comes out less dangerous, all else equal", {
  # The end-to-end sign check. Cooler and moister with height means a lower
  # fine-fuel code, so the FWI must decrease upslope on a uniform-weather ramp.
  # If a sign ever flips in the lapse rate or the humidity conversion, this is
  # what catches it -- none of the unit tests above would.
  d <- dem_ramp(top = 1200)
  w <- weather_at(ids = "a", lat = 43.3, long = 6.3, elev = 0, days = 40)
  z <- fev_topo_zones(d, n_elev = 5, stations = w, quiet = TRUE)
  ds <- fev_downscale_weather(w, z, quiet = TRUE)
  out <- suppressWarnings(
    fev_fwi_zonal(ds, z, dates = LAST_DAY, quiet = TRUE)
  )
  zt <- attr(z, "zones")
  v <- terra::values(fev_data(out))[, 1]
  zv <- terra::values(fev_data(z))[, 1]
  fwi_by_zone <- vapply(zt$zone, function(k) mean(v[zv == k], na.rm = TRUE),
                        numeric(1))
  expect_lt(stats::cor(zt$elev_mean, fwi_by_zone), 0)
})

# Wind and rain, the two the first version passed through --------------------

test_that("curvature is positive on a ridge and negative in a valley", {
  g <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 4000,
                   ymin = 0, ymax = 4000, crs = "EPSG:2154")
  x <- terra::init(g, "x")
  ridge <- 300 - abs(x - 2000) / 10
  cv <- fev_curvature(ridge, length_scale = 400, quiet = TRUE)
  v <- terra::values(fev_data(cv))[, 1]
  xs <- terra::values(x)[, 1]
  # On the crest, convex; on the flanks, straight; the crest must win.
  crest <- mean(v[abs(xs - 2000) < 150], na.rm = TRUE)
  flank <- mean(v[abs(xs - 2000) > 800], na.rm = TRUE)
  expect_gt(crest, flank)
  expect_gt(crest, 0)
  # And a valley is the same shape upside down.
  cvv <- fev_curvature(-ridge, length_scale = 400, quiet = TRUE)
  expect_lt(mean(terra::values(fev_data(cvv))[abs(xs - 2000) < 150],
                 na.rm = TRUE), 0)
})

test_that("curvature stays on the published scale", {
  cv <- fev_curvature(dem_ramp(top = 900), length_scale = 2000, quiet = TRUE)
  v <- stats::na.omit(terra::values(fev_data(cv))[, 1])
  expect_lte(max(abs(v)), 0.5 + 1e-9)
})

test_that("a length scale larger than the map is refused", {
  expect_error(fev_curvature(dem_ramp(n = 20), length_scale = 1e5,
                             quiet = TRUE),
               "not curvature")
})

test_that("flat ground gives no curvature and no wind change", {
  g <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 3000,
                   ymin = 0, ymax = 3000, crs = "EPSG:2154")
  flat <- terra::setValues(g, 200)
  cv <- fev_curvature(flat, length_scale = 500, quiet = TRUE)
  v <- stats::na.omit(terra::values(fev_data(cv))[, 1])
  expect_true(all(abs(v) < 1e-9))
})

test_that("the wind multiplier follows the curvature and its weight", {
  d <- dem_ramp(top = 600)
  w <- weather_at()
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  cv <- fev_curvature(d, length_scale = 2000, quiet = TRUE)
  a <- fev_downscale_weather(w, z, wind = "curvature", curvature = cv,
                             curve_weight = 0.5, quiet = TRUE)
  b <- fev_downscale_weather(w, z, wind = "curvature", curvature = cv,
                             curve_weight = 1, quiet = TRUE)
  base <- fev_downscale_weather(w, z, quiet = TRUE)
  # Doubling the weight doubles the departure from the untouched wind.
  da <- a$ws - base$ws
  db <- b$ws - base$ws
  expect_equal(db, 2 * da, tolerance = 1e-8)
  # And the published bound holds: gamma_c = 0.5 over a curvature in
  # [-0.5, 0.5] can never leave [0.75, 1.25].
  expect_true(all(a$ws / base$ws >= 0.75 - 1e-9))
  expect_true(all(a$ws / base$ws <= 1.25 + 1e-9))
})

test_that("asking for curvature wind without a curvature layer is an error", {
  d <- dem_ramp()
  w <- weather_at()
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  expect_error(fev_downscale_weather(w, z, wind = "curvature", quiet = TRUE),
               "needs a")
})

test_that("a rain gradient that is not there is refused, loudly", {
  # The Maures case, which is the useful one: 20 points over 464 m give
  # R2 = 0.087 and p = 0.21. The correction must not be applied, and the
  # analysis must not be told it was.
  set.seed(7)
  w <- do.call(rbind, lapply(1:12, function(k) {
    data.frame(id = letters[k], elev_m = k * 40,
               prec = stats::rnorm(20, 2, 0.6))
  }))
  g <- fev_rain_gradient(w)
  expect_false(g$usable)
  expect_equal(g$n_points, 12L)
})

test_that("a rain gradient that is there is found", {
  # Noise on purpose: an exactly linear fixture makes lm warn about a perfect
  # fit, and it would also let a broken significance test pass.
  set.seed(11)
  w <- do.call(rbind, lapply(1:12, function(k) {
    data.frame(id = letters[k], elev_m = k * 40,
               prec = 1 + k * 0.1 + stats::rnorm(5, 0, 0.05))
  }))
  g <- fev_rain_gradient(w)
  expect_true(g$usable)
  expect_gt(g$slope, 0)
  expect_gt(g$r_squared, 0.9)
})

test_that("rain is corrected only when the fit supports it", {
  d <- dem_ramp(top = 900)
  # Two stations at the same elevation: no gradient can exist.
  w <- weather_at(elev = 100)
  z <- fev_topo_zones(d, n_elev = 3, stations = w, quiet = TRUE)
  expect_warning(
    out <- fev_downscale_weather(w, z, rain = "fitted", quiet = TRUE),
    class = "fev_no_rain_gradient"
  )
  expect_setequal(unique(out$prec), unique(w$prec))
})

test_that("a corrected rain never goes negative", {
  # A gradient extrapolated down a valley can subtract more rain than fell, and
  # cffdrs would accept the negative without complaint.
  set.seed(12)
  w <- do.call(rbind, lapply(1:10, function(k) {
    data.frame(id = letters[k], lat = 43.3, long = 6.2,
               yr = 2021L, mon = 7L, day = 1:20,
               temp = 30, rh = 35, ws = 10,
               prec = pmax(0.01, k * 0.4 + stats::rnorm(20, 0, 0.05)),
               elev_m = 400 + k * 40)
  }))
  d <- dem_ramp(top = 900)
  z <- fev_topo_zones(d, n_elev = 4, stations = w, quiet = TRUE)
  out <- fev_downscale_weather(w, z, rain = "fitted", quiet = TRUE)
  expect_true(all(out$prec >= 0))
})
