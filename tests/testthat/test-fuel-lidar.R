# The LiDAR fuel pipeline, exercised for real without a network.
#
# This is the part of phase 8 that could have been left untested behind a
# "requires a real tile" excuse. It is not: a synthetic point cloud built with
# lidR -- ground, shrub layer, canopy -- traverses lidarforfuel's actual
# pretreatment and metrics functions and comes back with plausible values. So
# the band naming, the -1 sentinel, the density control and the register
# plumbing are all checked against the real thing.
#
# lidR and lidarforfuel are in Suggests. lidarforfuel installs from GitHub and
# is named in lowercase, unlike its repository.

skip_if_no_lidar <- function() {
  skip_if_not_installed("lidR")
  skip_if_not_installed("lidarforfuel")
}

test_that("pulse density is not point density", {
  skip_if_not_installed("lidR")
  # The specification is written in pulses, and a pulse gives several returns in
  # vegetation. Confusing the two overstates coverage by a factor that grows
  # with canopy density.
  d <- fev_lidar_density(synth_las(side = 60, pulses = 10))
  expect_equal(d$pulses_per_m2, 10)
  expect_gt(d$points_per_m2, d$pulses_per_m2)
  expect_equal(d$n_pulses, 36000L)
  expect_gt(d$n_points, d$n_pulses)
  expect_equal(d$area_m2, 3600)
})

test_that("a cloud with no ReturnNumber says the figure is points", {
  skip_if_not_installed("lidR")
  las <- synth_las(side = 40, pulses = 5)
  las@data$ReturnNumber <- NULL
  expect_warning(d <- fev_lidar_density(las), class = "fev_no_return_number")
  expect_equal(d$pulses_per_m2, d$points_per_m2)
})

test_that("thin clouds are flagged with the direction of the bias", {
  skip_if_not_installed("lidR")
  # Not just "low density": the message has to say which way the error goes,
  # because a thin tile reports a SAFER landscape than it is and that is the
  # dangerous direction.
  thin <- fev_lidar_density(synth_las(side = 60, pulses = 2))
  expect_warning(fev_check_pulse_density(thin, 10),
                 class = "fev_low_pulse_density")

  msg <- tryCatch(fev_check_pulse_density(thin, 10),
                  condition = function(c) paste(conditionMessage(c),
                                                collapse = " "))
  expect_match(msg, "too low")
  expect_match(msg, "too high")
  # And the altitude exception, which is a legitimate reason to sit at 5.
  expect_match(msg, "3200")

  # At specification, silence.
  ok <- fev_lidar_density(synth_las(side = 60, pulses = 10))
  expect_no_warning(fev_check_pulse_density(ok, 10))
})

test_that("the empty cloud is refused", {
  skip_if_not_installed("lidR")
  las <- synth_las(side = 30, pulses = 2)
  las@data <- las@data[0, ]
  expect_error(fev_lidar_density(las), class = "fev_empty_result")
  expect_error(fev_as_las(42), class = "fev_error")
})

# --- the real pipeline -------------------------------------------------------

test_that("the pipeline runs and gives plausible fuel metrics", {
  skip_if_no_lidar()
  # canopy at 8 m over a shrub layer at 1.2 m: the crown base must land above
  # the shrubs and below the canopy top, and there must be a real gap.
  fuel <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50)
  ))

  expect_s3_class(fuel, "fev_fuel_source")
  expect_equal(fuel$type, "lidarhd")
  # The register the whole fuel module was shaped around since phase 4.
  expect_equal(fev_fuel_registers(fuel), "continuous")
  expect_null(fev_fuel_categorical(fuel))

  r <- fev_fuel_continuous(fuel)
  v <- terra::values(r)[1, ]
  expect_gt(v[["Height"]], 8)
  expect_gt(v[["CBH"]], 1.2)
  expect_lt(v[["CBH"]], v[["Height"]])
  expect_gt(v[["FSG"]], 0)
  # Loads are positive and the total is at least the canopy part.
  expect_gt(v[["CFL"]], 0)
  expect_gte(v[["TFL"]], v[["CFL"]])
  expect_gt(v[["CBD_max"]], 0)
  expect_true(v[["Cover"]] > 0 && v[["Cover"]] <= 1)
})

test_that("the default output is the fuel subset, not all 175 bands", {
  skip_if_no_lidar()
  fuel <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50)
  ))
  expect_setequal(names(fev_fuel_continuous(fuel)), .FEV_LIDAR_FUEL_METRICS)

  # "all" gives the 25 named metrics ...
  all25 <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50,
                   metrics = "all")
  ))
  expect_equal(names(fev_fuel_continuous(all25)), .FEV_LIDAR_METRICS)
  expect_equal(terra::nlyr(fev_fuel_continuous(all25)), 25L)

  # ... and profile = TRUE adds the 150 bulk density layers, for 175.
  full <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50,
                   metrics = "all", profile = TRUE)
  ))
  expect_equal(terra::nlyr(fev_fuel_continuous(full)), 175L)
  expect_equal(names(fev_fuel_continuous(full))[26], "CBD_1")
  expect_equal(names(fev_fuel_continuous(full))[175], "CBD_150")
})

test_that("the band contract is 175 bands and 25 metrics, not the README's 173", {
  # The single most consequential finding of phase 8. Reading the profile from
  # band 24 on the README's word takes Cover_4 and Cover_6 for bulk density and
  # shifts everything by two.
  expect_length(.FEV_LIDAR_METRICS, 25L)
  expect_equal(.FEV_LIDAR_CBD_LAYERS, 150L)
  expect_equal(length(.FEV_LIDAR_METRICS) + .FEV_LIDAR_CBD_LAYERS, 175L)
  expect_equal(.FEV_LIDAR_METRICS[23:25], c("Cover", "Cover_4", "Cover_6"))
  expect_equal(.FEV_LIDAR_NULL_VALUE, -1)
})

test_that("a change in the upstream bands is an error, not a workaround", {
  skip_if_no_lidar()
  # Simulated by pinning against a wrong expectation: the guard must fire on
  # any mismatch, because plausible wrong numbers are the failure mode here.
  las <- suppressWarnings(suppressMessages(
    lidarforfuel::fPCpretreatment(synth_las(side = 60, pulses = 10))
  ))
  r <- suppressWarnings(lidR::pixel_metrics(
    las, ~list(a = mean(Z), b = max(Z)), res = 30
  ))
  # Reuse the checker's logic by calling it with a raster it cannot recognise.
  expect_error(
    fev_lidar_clean(r, c("Height", "CBH")),
    class = "error"
  )
})

test_that("the -1 sentinel becomes NA", {
  skip_if_not_installed("lidR")
  # Left alone, -1 gives negative crown base heights and negative fuel loads,
  # which pass any naive plausibility check.
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 100, ymin = 0,
                   ymax = 100, crs = "EPSG:2154", nlyr = 2)
  terra::values(r) <- cbind(c(3.5, -1, 4.0, -1), c(0.4, -1, 0.5, -1))
  names(r) <- c("CBH", "CFL")

  out <- fev_lidar_clean(r, c("CBH", "CFL"))
  v <- terra::values(out)
  expect_equal(sum(is.na(v)), 4L)
  expect_true(all(v[!is.na(v)] > 0))
})

test_that("metric selection is validated", {
  skip_if_no_lidar()
  # The trajectory fallback fires on any synthetic cloud and has its own test;
  # suppressed here so only the validation under test is asserted.
  expect_error(
    suppressWarnings(fev_fuel_lidar(synth_las(side = 60, pulses = 10),
                                    res = 30,
                                    metrics = c("CBH", "not_a_metric"))),
    class = "fev_error"
  )
  expect_setequal(fev_lidar_select(NULL, FALSE), .FEV_LIDAR_FUEL_METRICS)
  expect_length(fev_lidar_select("all", TRUE), 175L)
  expect_setequal(fev_lidar_select(c("CBH", "FSG"), FALSE), c("CBH", "FSG"))
})

test_that("a resolution finer than the cloud supports is flagged", {
  skip_if_no_lidar()
  expect_message(
    suppressWarnings(fev_fuel_lidar(synth_las(side = 60, pulses = 10),
                                    res = 5)),
    class = "fev_res_too_fine"
  )
  expect_error(fev_fuel_lidar(synth_las(side = 30, pulses = 5), res = 0),
               class = "fev_error")
})

test_that("the trajectory fallback is surfaced, not swallowed", {
  skip_if_no_lidar()
  # A synthetic cloud has no reconstructable trajectory, so lidarforfuel falls
  # back to a nominal 1400 m flight height. That changes the scanning-angle
  # correction, so it must not pass silently in a loop over a thousand tiles.
  cls <- warning_classes(
    fuel <- fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50)
  )
  expect_true("fev_trajectory_fallback" %in% cls)

  step <- fuel$provenance$steps[[length(fuel$provenance$steps)]]
  expect_match(step$params$trajectory, "fallback")
  expect_match(step$params$trajectory, "1400")
})

test_that("what was assumed is recorded, including that it is unsourced", {
  skip_if_no_lidar()
  fuel <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50,
                   lma = 95, wd = 520, millesime = 2025)
  ))
  step <- fuel$provenance$steps[[length(fuel$provenance$steps)]]
  expect_equal(step$params$lma, 95)
  expect_equal(step$params$wd, 520)
  # LMA and wood density scale the loads directly and were not traced to a
  # primary source. The record says so.
  expect_false(step$params$lma_wd_sourced)
  expect_equal(step$params$engine, "lidarforfuel::fCBDprofile_fuelmetrics")
  expect_true(nzchar(step$params$engine_version))

  # Density travels with the source record, so a thin tile can be found later.
  src <- fuel$provenance$sources[[1]]
  expect_equal(src$dataset, "lidarhd")
  expect_equal(src$millesime, 2025)
  expect_gt(src$pulses_per_m2, 0)
})

test_that("units are attached, and FMA is left unlabelled on purpose", {
  skip_if_no_lidar()
  fuel <- suppressWarnings(suppressMessages(
    fev_fuel_lidar(synth_las(side = 100, pulses = 10), res = 50,
                   metrics = "all")
  ))
  u <- fuel$units
  expect_equal(u[["CBH"]], "m")
  expect_equal(u[["CBD_max"]], "kg/m3")
  expect_equal(u[["CFL"]], "kg/m2")
  expect_equal(u[["Cover"]], "fraction")
  # A wrong unit is worse than none: FMA's meaning was not established.
  expect_true(is.na(u[["FMA"]]))
})

# --- attaching to the categorical register -----------------------------------

test_that("attach fills the continuous register without touching the classes", {
  cat_r <- synth_class_raster(c("FF2-57-57", "LA4"), nrow = 8, ncol = 8)
  fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)

  cont <- terra::rast(cat_r)
  terra::values(cont) <- stats::runif(64, 0, 0.4)
  names(cont) <- "CBD_max"
  lidar <- fev_fuel_source(cont, type = "custom", register = "continuous",
                           units = c(CBD_max = "kg/m3"))

  both <- suppressMessages(fev_fuel_attach(fuel, lidar))
  expect_setequal(fev_fuel_registers(both), c("categorical", "continuous"))
  # The classes are untouched: attach arbitrates nothing.
  expect_equal(terra::values(fev_fuel_categorical(both)),
               terra::values(fev_fuel_categorical(fuel)))
  expect_equal(names(fev_fuel_continuous(both)), "CBD_max")
  expect_equal(both$units[["CBD_max"]], "kg/m3")
  expect_match(both$type, "lidarhd")
})

test_that("attach reports how much of the categorical register it covers", {
  # LiDAR HD is still being flown, so the two registers describe different
  # subsets of the map and that is easy to misread.
  cat_r <- synth_class_raster(c("FF2-57-57", "LA4"), nrow = 8, ncol = 8)
  fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)

  cont <- terra::rast(cat_r)
  v <- stats::runif(64, 0, 0.4)
  v[1:32] <- NA          # half the tile unflown
  terra::values(cont) <- v
  names(cont) <- "CBD_max"
  lidar <- fev_fuel_source(cont, type = "custom", register = "continuous")

  expect_warning(both <- fev_fuel_attach(fuel, lidar),
                 class = "fev_partial_continuous")
  step <- both$provenance$steps[[length(both$provenance$steps)]]
  expect_equal(step$params$pct_categorical_covered, 50)
})

test_that("attach needs the right register on each side", {
  cat_r <- synth_class_raster(nrow = 4, ncol = 4)
  fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)
  expect_error(fev_fuel_attach(fuel, fuel), class = "fev_missing_register")

  cont <- terra::rast(cat_r)
  terra::values(cont) <- 0.2
  names(cont) <- "CBD_max"
  lidar <- fev_fuel_source(cont, type = "custom", register = "continuous")
  expect_error(fev_fuel_attach(lidar, lidar), class = "fev_missing_register")
  expect_error(fev_fuel_attach("nope", lidar), class = "fev_error")
})

test_that("attach realigns a continuous grid, with bilinear this time", {
  # Unlike the categorical path, where only nearest neighbour is defensible.
  cat_r <- synth_class_raster(nrow = 8, ncol = 8)
  fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)

  coarse <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 200,
                        ymin = 0, ymax = 200, crs = "EPSG:2154")
  terra::values(coarse) <- stats::runif(16, 0, 0.4)
  names(coarse) <- "CBD_max"
  lidar <- fev_fuel_source(coarse, type = "custom", register = "continuous")

  expect_warning(both <- suppressMessages(fev_fuel_attach(fuel, lidar)),
                 class = "fev_continuous_resampled")
  expect_equal(terra::res(fev_fuel_continuous(both)),
               terra::res(fev_fuel_categorical(both)))
})
