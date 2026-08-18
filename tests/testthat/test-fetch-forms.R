# FORMS import. Synthetic rasters: the real product is a national mosaic on
# Zenodo, and the point of this function is that the package does not fetch it.

forms_raster <- function(crs = "EPSG:2154", n = 10, res = 10) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 900000, xmax = 900000 + n * res,
                   ymin = 6250000, ymax = 6250000 + n * res, crs = crs)
  set.seed(7)
  terra::values(r) <- stats::runif(terra::ncell(r), 0, 30)
  r
}

write_forms <- function(...) {
  path <- withr::local_tempfile(fileext = ".tif", .local_envir = parent.frame())
  terra::writeRaster(forms_raster(...), path, overwrite = TRUE)
  path
}

test_that("the manual route is refused with the DOI, not a download", {
  expect_error(fev_fetch_forms(), class = "fev_forms_manual")
  expect_error(fev_fetch_forms(), regexp = "zenodo")
})

test_that("a missing file is refused before terra is reached", {
  expect_error(fev_fetch_forms(file = "nope.tif"), regexp = "does not exist")
})

test_that("the variable names the layer and sets the units", {
  path <- write_forms()
  for (v in c("height", "biomass", "volume")) {
    src <- fev_fetch_forms(path, variable = v, quiet = TRUE)
    expect_equal(names(fev_data(src)), v)
    expect_equal(fev_source_info(src)$units,
                 firexpovulnR:::.FEV_FORMS_UNITS[[v]])
  }
})

test_that("an unknown variable is refused", {
  path <- write_forms()
  expect_error(fev_fetch_forms(path, variable = "carbon", quiet = TRUE))
})

test_that("a categorical raster is refused: FORMS holds a measured quantity", {
  r <- forms_raster()
  terra::values(r) <- rep(c(1, 2), length.out = terra::ncell(r))
  levels(r) <- data.frame(id = c(1, 2), class = c("a", "b"))
  path <- withr::local_tempfile(fileext = ".tif")
  terra::writeRaster(r, path, overwrite = TRUE)

  expect_error(fev_fetch_forms(path, quiet = TRUE),
               class = "fev_forms_categorical")
})

test_that("a raster without a CRS is refused rather than assumed", {
  r <- forms_raster()
  terra::crs(r) <- ""
  path <- withr::local_tempfile(fileext = ".tif")
  terra::writeRaster(r, path, overwrite = TRUE)
  expect_error(fev_fetch_forms(path, quiet = TRUE), class = "fev_crs_missing")
})

test_that("reprojection is bilinear, because this is a surface not a class layer", {
  path <- write_forms(crs = "EPSG:3035")
  src <- fev_fetch_forms(path, crs_work = 2154, quiet = TRUE)
  expect_true(isTRUE(fev_source_info(src)$reprojected))
  # Bilinear on a continuous field leaves values off the original grid.
  expect_gt(length(unique(terra::values(fev_data(src)))), 2L)
})

test_that("the vintage is fixed at 2020 and recorded", {
  path <- write_forms()
  info <- fev_source_info(fev_fetch_forms(path, quiet = TRUE))
  expect_equal(info$millesime, 2020L)
  expect_equal(info$import, "local file")
  expect_match(info$notes, "2020 composite")
  expect_match(info$notes, "Mediterranean forests are")
})

test_that("height and biomass are not presented as equally reliable", {
  q <- firexpovulnR:::.FEV_FORMS_QUALITY
  expect_gt(q$height$r2, 0.6)
  expect_lt(q$biomass$r2, 0.25)
  # The gap is the point: reporting one figure for "FORMS" would mislead.
  expect_gt(q$height$r2 - q$biomass$r2, 0.4)
})

test_that("the caveats are warned once per session", {
  path <- write_forms()
  fev_reset_once()
  expect_warning(
    suppressMessages(fev_fetch_forms(path)),
    class = "fev_forms_caveats"
  )
  expect_no_warning(suppressMessages(fev_fetch_forms(path)))
})

test_that("the per-file report still prints after the caveat is spent", {
  path <- write_forms()
  fev_reset_once()
  suppressWarnings(suppressMessages(fev_fetch_forms(path)))
  expect_message(suppressWarnings(fev_fetch_forms(path)), regexp = "FORMS height")
})

test_that("a non-overlapping AOI is refused", {
  path <- write_forms()
  far <- sf::st_as_sf(sf::st_sfc(
    sf::st_polygon(list(cbind(c(0, 100, 100, 0, 0), c(0, 0, 100, 100, 0)))),
    crs = 2154
  ))
  expect_error(fev_fetch_forms(path, aoi = far, quiet = TRUE),
               class = "fev_no_overlap")
})

test_that("it feeds the continuous register and can serve as a profile reference", {
  # The reason step 4 is worth doing: a reference beyond the LiDAR footprint.
  path <- write_forms(n = 20)
  h <- fev_fetch_forms(path, variable = "height", quiet = TRUE)

  cls <- terra::rast(fev_data(h))
  terra::values(cls) <- rep(c(4, 5), each = terra::ncell(cls) / 2)
  levels(cls) <- data.frame(id = c(4, 5), class = c("4", "5"))

  p <- fev_fuel_profile(cls, fev_data(h), metrics = "height", quiet = TRUE)
  expect_equal(nrow(p$summary), 2L)
  expect_true(all(p$summary$metric == "height"))
})
