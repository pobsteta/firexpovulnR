# What a focal pass costs before it is run, and which radii are reachable.

cost_grid <- function(res = 25, n = 100) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
                   ymin = 0, ymax = n * res, crs = "EPSG:2154")
  terra::values(r) <- 1
  r
}

test_that("all three shipped radii are costed by default", {
  out <- fev_exposure_cost(cost_grid())
  expect_equal(nrow(out), 3L)
  expect_setequal(out$radius, fev_exposure_radii()$max_m)
})

test_that("the radiant radius is out of reach at 25 m and reachable at 10 m", {
  # This is the whole argument for a 10 m source, so it is pinned here.
  at25 <- fev_exposure_cost(cost_grid(), res = 25)
  at10 <- fev_exposure_cost(cost_grid(), res = 10)

  expect_false(at25$reachable[at25$radius == 30])
  expect_true(at10$reachable[at10$radius == 30])
  # And 10 m is the boundary exactly: 10 == 30 / 3.
  expect_true(fev_exposure_cost(cost_grid(), res = 10.1)$reachable[1] == FALSE)
})

test_that("an unreachable radius reports NA cost rather than a made-up one", {
  out <- fev_exposure_cost(cost_grid(), res = 25, radius = 30)
  expect_false(out$reachable)
  expect_true(is.na(out$ops))
  expect_true(is.na(out$ring_cells))
})

test_that("cost grows as the fourth power of the inverse cell size", {
  # ncell and the window area each scale as res^-2, so halving res multiplies
  # the total by about 16. Discretising the annulus keeps it approximate.
  a <- fev_exposure_cost(cost_grid(), res = 40, radius = 500)
  b <- fev_exposure_cost(cost_grid(), res = 20, radius = 500)
  expect_gt(b$ops / a$ops, 13)
  expect_lt(b$ops / a$ops, 19)
})

test_that("the 25 m to 10 m step is about forty-fold, not two-and-a-half", {
  a <- fev_exposure_cost(cost_grid(), res = 25, radius = 500)
  b <- fev_exposure_cost(cost_grid(), res = 10, radius = 500)
  ratio <- b$ops / a$ops
  expect_gt(ratio, 35)
  expect_lt(ratio, 45)
})

test_that("costing a hypothetical resolution does not touch the raster", {
  r <- cost_grid(res = 25)
  before <- terra::res(r)
  fev_exposure_cost(r, res = 5)
  expect_equal(terra::res(r), before)
})

test_that("it accepts the objects a user actually holds", {
  r <- cost_grid()
  from_raster <- fev_exposure_cost(r, radius = 500)

  poly <- sf::st_sf(
    code_tfv = "FF1-00-00",
    geometry = sf::st_sfc(
      sf::st_polygon(list(cbind(c(0, 2500, 2500, 0, 0),
                                c(0, 0, 2500, 2500, 0)))),
      crs = 2154
    )
  )
  fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 25,
                          millesime = 2014)
  from_source <- fev_exposure_cost(fuel, radius = 500)
  expect_equal(from_source$ring_cells, from_raster$ring_cells)
})

test_that("a bad resolution or radius is refused", {
  r <- cost_grid()
  expect_error(fev_exposure_cost(r, res = 0))
  expect_error(fev_exposure_cost(r, res = -5))
  expect_error(fev_exposure_cost(r, radius = c(100, NA)))
  expect_error(fev_exposure_cost("not a raster"))
})

test_that("the estimate agrees with what fev_exposure actually weighs", {
  # The cost function must not drift from the window fev_exposure builds.
  r <- cost_grid(res = 25)
  out <- fev_exposure_cost(r, res = 25, radius = 500)
  w <- firexpovulnR:::fev_annulus_window(25, 500)
  expect_equal(out$ring_cells, sum(!is.na(w)))
  expect_equal(out$ops, as.numeric(terra::ncell(r)) * sum(!is.na(w)))
})

test_that("radiant exposure runs at 10 m and is refused at 25 m", {
  fine <- cost_grid(res = 10, n = 120)
  set.seed(3)
  terra::values(fine) <- sample(c(0, 1), terra::ncell(fine), replace = TRUE)
  e <- fev_exposure(fine, type = "radiant", quiet = TRUE)
  v <- terra::values(fev_data(e))
  v <- v[!is.na(v)]
  expect_true(length(v) > 0)
  expect_true(all(v >= 0 & v <= 1))

  coarse <- cost_grid(res = 25, n = 120)
  terra::values(coarse) <- 1
  expect_error(fev_exposure(coarse, type = "radiant", quiet = TRUE),
               class = "fev_res_too_coarse")
})
