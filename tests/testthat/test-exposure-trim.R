# Cutting the edge frame away instead of publishing it.
#
# The outer ring of a focal result is the window hanging off the edge of the
# data. The package has always said so in fev_extent_too_small; `trim` is the
# half of that advice it used not to supply.

fuel_grid <- function(n = 120, res = 25, seed = 4) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
                   ymin = 0, ymax = n * res, crs = "EPSG:2154")
  set.seed(seed)
  terra::values(r) <- sample(c(0, 1), terra::ncell(r), replace = TRUE,
                             prob = c(0.4, 0.6))
  r
}

inner_aoi <- function(r, inset) {
  bb <- as.vector(terra::ext(r))
  sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = bb[["xmin"]] + inset, ymin = bb[["ymin"]] + inset,
      xmax = bb[["xmax"]] - inset, ymax = bb[["ymax"]] - inset),
    crs = sf::st_crs(2154)
  )))
}

na_share <- function(x) {
  v <- terra::values(fev_data(x))
  sum(is.na(v)) / length(v)
}

test_that("trimming removes the frame instead of hiding it", {
  r <- fuel_grid()
  aoi <- inner_aoi(r, 600)

  whole <- fev_exposure(r, radius = 500, quiet = TRUE)
  cut <- fev_exposure(r, radius = 500, trim = aoi, quiet = TRUE)

  expect_gt(na_share(whole), 0.1)
  expect_lt(na_share(cut), 0.01)
})

test_that("the values that survive are the ones that were already computed", {
  # Trimming must not recompute anything: an edge cell is dropped, an inner
  # cell keeps exactly the number it had.
  r <- fuel_grid()
  aoi <- inner_aoi(r, 600)
  whole <- fev_data(fev_exposure(r, radius = 500, quiet = TRUE))
  cut <- fev_data(fev_exposure(r, radius = 500, trim = aoi, quiet = TRUE))

  common <- terra::crop(whole, cut)
  expect_equal(terra::values(common), terra::values(cut))
})

test_that("the result is smaller than what was computed", {
  r <- fuel_grid()
  aoi <- inner_aoi(r, 600)
  whole <- fev_data(fev_exposure(r, radius = 500, quiet = TRUE))
  cut <- fev_data(fev_exposure(r, radius = 500, trim = aoi, quiet = TRUE))
  expect_lt(terra::ncell(cut), terra::ncell(whole))
})

test_that("too thin a buffer is refused loudly rather than silently cropped", {
  # Cropping to something the buffer never covered hides part of the frame
  # inside the reported area, which is worse than leaving it visible.
  r <- fuel_grid()
  expect_warning(
    fev_exposure(r, radius = 500, trim = inner_aoi(r, 100), quiet = TRUE),
    class = "fev_trim_insufficient_buffer"
  )
})

test_that("a sufficient buffer passes without complaint", {
  r <- fuel_grid()
  expect_no_warning(
    fev_exposure(r, radius = 500, trim = inner_aoi(r, 600), quiet = TRUE)
  )
})

test_that("trimming is recorded in the provenance", {
  r <- fuel_grid()
  out <- fev_exposure(r, radius = 500, trim = inner_aoi(r, 600), quiet = TRUE)
  steps <- fev_layer_prov(out)$steps
  hit <- vapply(steps, function(st) isTRUE(st$params$trimmed_to_aoi),
                logical(1))
  expect_true(any(hit))
})

test_that("without trim nothing changes", {
  r <- fuel_grid()
  a <- fev_data(fev_exposure(r, radius = 500, quiet = TRUE))
  b <- fev_data(fev_exposure(r, radius = 500, trim = NULL, quiet = TRUE))
  expect_equal(terra::values(a), terra::values(b))
})

test_that("it reports what it kept", {
  r <- fuel_grid()
  expect_message(
    fev_exposure(r, radius = 500, trim = inner_aoi(r, 600)),
    regexp = "Trimmed to the reporting area"
  )
})

test_that("a non-rectangular reporting area is masked, not just cropped", {
  r <- fuel_grid()
  bb <- as.vector(terra::ext(r))
  ctr <- c((bb[["xmin"]] + bb[["xmax"]]) / 2, (bb[["ymin"]] + bb[["ymax"]]) / 2)
  disc <- sf::st_buffer(
    sf::st_as_sf(sf::st_sfc(sf::st_point(ctr), crs = 2154)), 700
  )
  out <- fev_exposure(r, radius = 500, trim = disc, quiet = TRUE)
  # A disc inside its own bounding box leaves empty corners.
  expect_gt(na_share(out), 0)
  expect_lt(na_share(out), 0.3)
})
