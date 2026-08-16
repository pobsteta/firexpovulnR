# fev_align() is the only function in the package allowed to change a grid.
# Everything else refuses and points here, so these tests are also what makes
# those refusals meaningful.

agrid <- function(n, values, crs = "EPSG:2154") {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = 1000, ymin = 0,
                   ymax = 1000, crs = crs)
  terra::values(r) <- values
  r
}

test_that("layers land on one grid and come back as a stack", {
  danger <- agrid(2, c(10, 20, 30, 40))
  expo <- agrid(40, runif(1600))
  s <- suppressWarnings(fev_align(danger = danger, exposure = expo))

  expect_s3_class(s, "fev_stack")
  expect_named(s, c("danger", "exposure"))
  res <- vapply(s, function(r) terra::res(r)[1], numeric(1))
  expect_equal(unname(res), c(25, 25))
})

test_that("direction chooses which grid survives", {
  danger <- agrid(2, c(10, 20, 30, 40))
  expo <- agrid(40, runif(1600))

  fine <- suppressWarnings(fev_align(danger = danger, exposure = expo))
  coarse <- suppressWarnings(
    fev_align(danger = danger, exposure = expo, direction = "coarsest")
  )
  expect_equal(terra::res(fine$danger)[1], 25)
  expect_equal(terra::res(coarse$exposure)[1], 500)
})

test_that("an explicit target wins over direction", {
  danger <- agrid(2, c(10, 20, 30, 40))
  expo <- agrid(40, runif(1600))
  mid <- agrid(10, rep(1, 100))

  by_name <- suppressWarnings(
    fev_align(danger = danger, exposure = expo, to = "danger")
  )
  expect_equal(terra::res(by_name$exposure)[1], 500)

  by_raster <- suppressWarnings(
    fev_align(danger = danger, exposure = expo, to = mid)
  )
  expect_equal(terra::res(by_raster$danger)[1], 100)

  expect_error(fev_align(danger = danger, to = "nope"), class = "fev_error")
  expect_error(fev_align(danger = danger, to = 42), class = "fev_error")
})

test_that("the scale ratio is warned about and recorded", {
  # The single most consequential number in the chain: it has to be impossible
  # to miss and impossible to lose.
  danger <- agrid(2, c(10, 20, 30, 40))
  expo <- agrid(40, runif(1600))
  expect_warning(s <- fev_align(danger = danger, exposure = expo),
                 class = "fev_scale_gap")

  prov <- fev_provenance(s)
  step <- prov$steps[[which(vapply(prov$steps, function(x) x$fun,
                                   character(1)) == "fev_align")]]
  expect_equal(step$params$scale_ratio, 20)
  expect_equal(step$params$cells_per_coarse_cell, 400)
  expect_equal(step$params$direction, "finest")
  # Danger is downscaled with nearest neighbour; exposure defines the target
  # grid, so it is not resampled at all and the record says so rather than
  # naming a method that never ran.
  expect_equal(step$params$methods$danger, "near")
  expect_equal(step$params$methods$exposure, "none")
})

test_that("quiet silences the warning but not the record", {
  danger <- agrid(2, c(10, 20, 30, 40))
  expo <- agrid(40, runif(1600))
  expect_no_warning(s <- fev_align(danger = danger, exposure = expo,
                                   quiet = TRUE))
  prov <- fev_provenance(s)
  step <- prov$steps[[which(vapply(prov$steps, function(x) x$fun,
                                   character(1)) == "fev_align")]]
  expect_equal(step$params$scale_ratio, 20)
})

test_that("downscaling uses nearest neighbour, not an invented gradient", {
  # Bilinear between two 25 km cell centres draws a smooth field the
  # reanalysis never resolved. Nearest neighbour keeps the blocks visible,
  # which is what the data actually says.
  danger <- agrid(2, c(0, 0, 100, 100))
  expo <- agrid(20, rep(0.5, 400))
  s <- fev_align(danger = danger, exposure = expo, quiet = TRUE)
  expect_setequal(unique(terra::values(s$danger)[, 1]), c(0, 100))

  # And bilinear is available when explicitly asked for.
  s2 <- fev_align(danger = danger, exposure = expo, method = "bilinear",
                  quiet = TRUE)
  expect_gt(length(unique(terra::values(s2$danger)[, 1])), 2)
})

test_that("upscaling averages rather than sampling one cell", {
  coarse <- agrid(2, c(1, 1, 1, 1))
  fine <- agrid(20, rep(c(0, 1), 200))
  s <- fev_align(danger = coarse, exposure = fine, direction = "coarsest",
                 quiet = TRUE)
  expect_equal(unique(round(terra::values(s$exposure)[, 1], 6)), 0.5)
})

test_that("a categorical layer is always resampled with nearest neighbour", {
  cat_r <- agrid(20, rep_len(1:2, 400))
  levels(cat_r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
  cont <- agrid(4, runif(16))

  expect_warning(
    s <- fev_align(fuel = cat_r, danger = cont, direction = "coarsest",
                   method = "bilinear", quiet = TRUE),
    class = "fev_categorical_resampled"
  )
  # Class codes survive as codes rather than becoming averages.
  vals <- terra::values(s$fuel)[, 1]
  expect_true(all(vals %in% c(1, 2, NA)))
})

test_that("layers in different CRS are reprojected onto the target", {
  a <- agrid(20, runif(400))
  b <- agrid(4, runif(16), crs = "EPSG:3035")
  expect_message(
    s <- suppressWarnings(fev_align(exposure = a, danger = b)),
    class = "fev_align_reproject"
  )
  crs_labels <- vapply(s, fev_crs_label, character(1))
  expect_equal(unname(unique(crs_labels)), "EPSG:2154")
})

test_that("aligned layers can then be combined, which is the point", {
  # fev_danger_index() refuses mismatched grids. This is the round trip that
  # makes the refusal actionable rather than a dead end.
  danger <- agrid(2, c(0, 50, 80, 100))
  avail <- agrid(20, rep(0.5, 400))
  expect_error(fev_danger_index(danger, avail, normalise = "percentile"),
               class = "fev_grid_mismatch")

  s <- fev_align(danger = danger, availability = avail, quiet = TRUE)
  expect_no_error(
    fev_danger_index(s$danger, s$availability, normalise = "percentile")
  )
})

test_that("inputs are named and non-empty", {
  danger <- agrid(2, c(10, 20, 30, 40))
  expect_error(fev_align(), class = "fev_error")
  expect_error(fev_align(danger), class = "fev_error")
  expect_error(fev_align(danger = "not a raster"), class = "fev_error")
})

test_that("a single layer is aligned to itself without complaint", {
  danger <- agrid(4, runif(16))
  expect_no_warning(s <- fev_align(danger = danger))
  expect_equal(terra::res(s$danger), terra::res(danger))
})

test_that("provenance from the inputs travels into the stack", {
  r <- synth_danger_series(n = 20, start = "2020-05-01", nrow = 4, ncol = 4)
  p <- suppressWarnings(suppressMessages(
    fev_fwi_percentile(r, season = NULL, min_ref = 5)
  ))
  expo <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 100,
                      ymin = 0, ymax = 100, crs = "EPSG:2154")
  terra::values(expo) <- runif(400)

  s <- fev_align(danger = p, exposure = expo, quiet = TRUE)
  funs <- vapply(fev_provenance(s)$steps, function(x) x$fun, character(1))
  expect_true("fev_fwi_percentile" %in% funs)
  expect_true("fev_align" %in% funs)
})
