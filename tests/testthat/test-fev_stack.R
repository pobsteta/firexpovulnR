test_that("fev_stack builds from named SpatRasters and carries provenance", {
  s <- fev_stack(exposure = synth_raster(), crs_work = 2154)

  expect_s3_class(s, "fev_stack")
  expect_named(s, "exposure")
  expect_s4_class(s[["exposure"]], "SpatRaster")

  prov <- attr(s, "provenance")
  expect_equal(prov$crs_work, 2154)
  expect_length(prov$steps, 1L)
  expect_equal(prov$steps[[1]]$fun, "fev_stack")
})

test_that("fev_stack rejects unnamed, duplicated and non-raster layers", {
  r <- synth_raster()

  expect_error(fev_stack(r), class = "fev_error")
  expect_error(fev_stack(), class = "fev_error")

  # Duplicated names would make [[ ambiguous and silently return the first.
  expect_error(
    do.call(fev_stack, stats::setNames(list(r, r), c("a", "a"))),
    class = "fev_error"
  )

  expect_error(fev_stack(a = 1:10), class = "fev_error")
  expect_error(fev_stack(a = synth_aoi()), class = "fev_error")
})

test_that("fev_stack refuses to mix CRS", {
  a <- synth_raster(crs = "EPSG:2154")
  b <- synth_raster(crs = "EPSG:3035")

  expect_error(fev_stack(a = a, b = b), class = "fev_error")
})

test_that("fev_stack refuses layers with no CRS rather than guessing one", {
  r <- synth_raster()
  terra::crs(r) <- ""

  expect_error(fev_stack(a = r), class = "fev_error")
})

test_that("an all-NA layer warns instead of failing silently", {
  r <- synth_raster()
  terra::values(r) <- NA_real_

  expect_warning(fev_stack(empty = r), class = "fev_warning")
})

test_that("layers may sit on different grids, and print says so", {
  # This is the scale gap the whole package exists to manage: a kilometric
  # danger layer and a decametric exposure layer legitimately coexist until
  # fev_align() is called. Construction must not silently resample.
  fine   <- synth_raster(nrow = 10, ncol = 10, res = 25)
  coarse <- synth_raster(nrow = 10, ncol = 10, res = 1000)

  s <- fev_stack(exposure = fine, danger = coarse)
  expect_length(s, 2L)
  expect_equal(terra::res(s[["exposure"]])[1], 25)
  expect_equal(terra::res(s[["danger"]])[1], 1000)

  expect_snapshot_output(print(s))
})

test_that("summary reports per-layer geometry and NA share", {
  r <- synth_raster(nrow = 4, ncol = 4, values = c(1, 2, NA, 4))
  sm <- summary(fev_stack(x = r))

  expect_s3_class(sm, "summary.fev_stack")
  expect_equal(sm$layers$layer, "x")
  expect_equal(sm$layers$nrow, 4)
  expect_equal(sm$layers$pct_na, 25)
})

test_that("subsetting keeps the class and the provenance", {
  s <- fev_stack(a = synth_raster(), b = synth_raster())
  sub <- s["a"]

  expect_s3_class(sub, "fev_stack")
  expect_named(sub, "a")
  expect_equal(attr(sub, "provenance")$crs_work, attr(s, "provenance")$crs_work)
})

test_that("fev_stack_save round-trips through disk with provenance intact", {
  # A plain saveRDS() of a SpatRaster writes a dead C++ pointer. This is the
  # whole reason fev_stack_save() exists, so the test must actually reload
  # values rather than just check the file appeared.
  s <- fev_stack(fuel = synth_raster(nrow = 4, ncol = 4), crs_work = 2154)
  f <- withr::local_tempfile(fileext = ".rds")

  fev_stack_save(s, f)
  s2 <- fev_stack_read(f)

  expect_s3_class(s2, "fev_stack")
  expect_named(s2, "fuel")
  expect_equal(terra::values(s2[["fuel"]]), terra::values(s[["fuel"]]))
  expect_equal(attr(s2, "provenance")$crs_work, 2154)
})

test_that("fev_stack_read rejects an RDS that is not a saved stack", {
  f <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(a = 1), f)

  expect_error(fev_stack_read(f), class = "fev_error")
})

test_that("as_fev_stack splits a multi-layer SpatRaster", {
  r <- c(synth_raster(), synth_raster())
  names(r) <- c("danger", "exposure")

  s <- as_fev_stack(r, crs_work = 2154)
  expect_named(s, c("danger", "exposure"))

  # Idempotent on something already a stack.
  expect_identical(as_fev_stack(s), s)
})
