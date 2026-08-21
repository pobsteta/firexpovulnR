# Van Wagner's thresholds and Byram's intensity.
#
# The strongest tests available here are the source's own worked examples: Scott
# and Reinhardt (2001) state that CBH 3 m at 100% FMC requires 875 kW/m to
# initiate crowning, and that CBD 0.2 kg/m3 requires 15.0 m/min to sustain it.
# Reproducing a published number exactly is a better check than re-reading the
# equation, and it is what settled the two renderings of equation 11 that
# circulate -- they differ in where the 1.5 exponent sits and only one returns
# 875.

test_that("the paper's crown initiation example reproduces exactly", {
  i <- fev_crown_fire(cbh = 3, fmc = 100, quiet = TRUE)[["i_initiation"]]
  expect_equal(round(i), 875)
})

test_that("the paper's active crowning example reproduces exactly", {
  r <- fev_crown_fire(cbh = 3, cbd = 0.2, quiet = TRUE)[["r_active"]]
  expect_equal(r, 15.0)
})

test_that("initiation rises steeply with crown base height", {
  # A factor of six in height for a factor of about fifteen in the intensity
  # needed. This is why CBH matters more than species, and why the campaign
  # measures it.
  low <- fev_crown_fire(cbh = 1, fmc = 100, quiet = TRUE)[["i_initiation"]]
  high <- fev_crown_fire(cbh = 6, fmc = 100, quiet = TRUE)[["i_initiation"]]
  expect_gt(high / low, 10)
  expect_lt(high / low, 20)
})

test_that("a crown touching the ground crowns at any intensity", {
  # Measured on the Maures: several windows have CBH of exactly 0.
  expect_equal(fev_crown_fire(cbh = 0, quiet = TRUE)[["i_initiation"]], 0)
})

test_that("a sparser canopy needs a faster fire to keep crowning", {
  sparse <- fev_crown_fire(cbh = 3, cbd = 0.06, quiet = TRUE)[["r_active"]]
  dense <- fev_crown_fire(cbh = 3, cbd = 0.32, quiet = TRUE)[["r_active"]]
  expect_gt(sparse, dense)
  # The Maures range of CBD_max, 0.05 to 0.32, spans a real decision.
  expect_gt(sparse / dense, 3)
})

test_that("moister foliage raises the bar", {
  dry <- fev_crown_fire(cbh = 3, fmc = 70, quiet = TRUE)[["i_initiation"]]
  wet <- fev_crown_fire(cbh = 3, fmc = 130, quiet = TRUE)[["i_initiation"]]
  expect_gt(wet, dry)
})

test_that("a supplied intensity turns the threshold into an answer", {
  r <- fev_crown_fire(cbh = 3, fmc = 100, intensity = 2000, quiet = TRUE)
  expect_true(r[["crowns"]])
  r <- fev_crown_fire(cbh = 3, fmc = 100, intensity = 500, quiet = TRUE)
  expect_false(r[["crowns"]])
})

test_that("active crowning needs both a density and a spread rate", {
  r <- fev_crown_fire(cbh = 3, cbd = 0.2, spread_rate = 20, quiet = TRUE)
  expect_true(r[["active"]])
  r <- fev_crown_fire(cbh = 3, cbd = 0.2, spread_rate = 10, quiet = TRUE)
  expect_false(r[["active"]])
  # Without a density there is no criterion to apply, and none is invented.
  r <- fev_crown_fire(cbh = 3, spread_rate = 20, quiet = TRUE)
  expect_false("active" %in% names(r))
})

test_that("Byram reduces to kW/m through the factor of 60", {
  # H Wf R / 60 with H = 18 000, Wf = 1 kg/m2, R = 15 m/min.
  expect_equal(fev_byram_intensity(1, 15), 18000 * 1 * 15 / 60)
  expect_equal(fev_byram_intensity(2, 15), 2 * fev_byram_intensity(1, 15))
  expect_equal(fev_byram_intensity(1, 0), 0)
})

test_that("Byram refuses inputs that are not a rate or a heat", {
  expect_error(fev_byram_intensity(1, -5), "non-negative")
  expect_error(fev_byram_intensity(1, 15, heat_yield = 0), "positive")
})

test_that("the two work on rasters, which is how the campaign feeds them", {
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20,
                   ymin = 0, ymax = 20, crs = "EPSG:2154")
  cbh <- terra::setValues(g, c(0, 2.33, 6.5, 8.5))
  cbd <- terra::setValues(g, c(0.07, 0.18, 0.06, 0.21))
  r <- fev_crown_fire(cbh, cbd, quiet = TRUE)
  expect_s4_class(r, "SpatRaster")
  expect_true(all(c("i_initiation", "r_active") %in% names(r)))
  v <- terra::values(r[["i_initiation"]])[, 1]
  expect_equal(v[1], 0)
  expect_gt(v[4], v[2])
})

test_that("a fev_layer is accepted, since that is what fuel_lidar returns", {
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20,
                   ymin = 0, ymax = 20, crs = "EPSG:2154")
  l <- new_fev_layer(terra::setValues(g, 3), role = "custom")
  expect_s4_class(fev_crown_fire(l, quiet = TRUE), "SpatRaster")
  expect_error(fev_crown_fire("trois", quiet = TRUE), "must be a number")
})

test_that("an impossible foliar moisture is refused", {
  expect_error(fev_crown_fire(cbh = 3, fmc = 0, quiet = TRUE), "positive")
})
