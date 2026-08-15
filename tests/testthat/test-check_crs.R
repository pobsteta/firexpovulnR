test_that("a clean projected input passes and reports no issues", {
  r <- synth_raster(crs = "EPSG:2154")

  expect_message(chk <- fev_check_crs(fuel = r, crs_work = 2154, primary = "fuel"))
  expect_s3_class(chk, "fev_crs_check")
  expect_length(chk$issues, 0L)
  expect_true(chk$inputs$projected)
  expect_equal(chk$inputs$crs, "EPSG:2154")
})

test_that("geographic coordinates are refused", {
  # Radii and resolutions are in metres throughout the package. A degree is
  # not a metre at any latitude the package targets, so lon/lat input would
  # produce plausible numbers that mean nothing.
  r <- synth_raster(crs = "EPSG:4326", res = 0.01)

  expect_error(fev_check_crs(fuel = r), class = "fev_crs_geographic")
  expect_warning(
    chk <- fev_check_crs(fuel = r, strict = FALSE),
    class = "fev_warning"
  )
  expect_match(chk$issues, "geographic")
})

test_that("a missing CRS is an error, not an assumption", {
  r <- synth_raster()
  terra::crs(r) <- ""

  expect_error(fev_check_crs(fuel = r), class = "fev_crs_missing")
  expect_warning(
    chk <- fev_check_crs(fuel = r, strict = FALSE),
    class = "fev_warning"
  )
  expect_match(chk$issues, "no CRS")
})

test_that("crs_work differing from the primary source's CRS warns loudly", {
  # The whole working-CRS rule exists to avoid reprojecting the categorical
  # primary fuel source. Silently accepting the mismatch would defeat it.
  r <- synth_raster(crs = "EPSG:3035")

  expect_warning(
    chk <- fev_check_crs(fuel = r, crs_work = 2154, primary = "fuel"),
    class = "fev_crs_primary_mismatch"
  )
  expect_match(chk$issues, "crs_work != primary")
})

test_that("a matching primary CRS produces no mismatch warning", {
  r <- synth_raster(crs = "EPSG:2154")

  expect_message(chk <- fev_check_crs(fuel = r, crs_work = 2154, primary = "fuel"))
  expect_false(any(grepl("crs_work", chk$issues)))
})

test_that("disjoint extents are reported before they empty every join", {
  a <- synth_raster(origin = c(0, 0), res = 25)
  b <- synth_raster(origin = c(500000, 500000), res = 25)

  expect_warning(
    chk <- fev_check_crs(fuel = a, aoi = b),
    class = "fev_extent_disjoint"
  )
  expect_match(chk$issues, "disjoint")
})

test_that("overlapping extents in different projected CRS do not warn", {
  # Comparison happens in WGS84 so inputs in different CRS can be compared at
  # all. Nothing reprojected during the check is returned to the caller.
  a <- synth_raster(origin = c(970000, 6243000), res = 25, crs = "EPSG:2154")
  b <- sf::st_transform(synth_aoi(a), 3035)

  expect_silent(suppressMessages(
    chk <- fev_check_crs(fuel = a, aoi = b, crs_work = 2154)
  ))
  expect_false(any(grepl("disjoint", chk$issues)))
})

test_that("inputs must be named spatial objects", {
  r <- synth_raster()

  expect_error(fev_check_crs(r), class = "fev_error")
  expect_error(fev_check_crs(), class = "fev_error")
  expect_error(fev_check_crs(a = 1:10), class = "fev_error")
})

test_that("primary must name one of the inputs", {
  r <- synth_raster()

  expect_error(fev_check_crs(fuel = r, primary = "absent"), class = "fev_error")
})

test_that("sf and SpatVector inputs are accepted alongside rasters", {
  r <- synth_raster()
  aoi <- synth_aoi(r)

  expect_message(chk <- fev_check_crs(fuel = r, aoi = aoi, crs_work = 2154))
  expect_equal(nrow(chk$inputs), 2L)
  expect_true(all(chk$inputs$projected))
})
