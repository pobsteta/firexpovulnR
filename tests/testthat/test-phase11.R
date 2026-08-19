# Phase 11: fitted radius, assets and interface, anisotropy, graded load.
#
# Network is out of scope here as everywhere else: fev_fetch_ghsl() and
# fev_fetch_dem() are exercised in test-integration-network.R behind
# FIREXPOVULNR_TEST_NETWORK. What is tested here is everything that can be
# wrong without a server.

grid <- function(n = 60, res = 10) {
  terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
              ymin = 0, ymax = n * res, crs = "EPSG:2154")
}

half_fuel <- function(n = 60) {
  # Burnable on the west half, bare on the east.
  terra::setValues(grid(n), rep(rep(c(1, 0), each = n / 2), n))
}

fires_at <- function(xmin, ymin, xmax, ymax, year = 2020) {
  # fire_year and area_ha present, so fev_validate_fires() takes the frame as
  # already prepared rather than reaching for an EFFIS FIREDATE column.
  geom <- sf::st_sfc(sf::st_polygon(list(cbind(
    c(xmin, xmax, xmax, xmin, xmin), c(ymin, ymin, ymax, ymax, ymin)
  ))), crs = 2154)
  sf::st_sf(fire_year = year, area_ha = as.numeric(sf::st_area(geom)) / 1e4,
            geometry = geom)
}

# --- 1. The fitted radius -------------------------------------------------

test_that("a constant exposure gives no AUC rather than exactly 0.5", {
  # The failure this guards against is not hypothetical: a fuel source built
  # from BD Foret alone is 1 inside its polygons and NA outside, never 0, so
  # every window that returns at all returns a full ring. The AUC of a constant
  # score is exactly 0.5, which reads as "no skill" when it means "no
  # measurement" -- and 0.5 is a publishable-looking number.
  g <- grid(40)
  fuel <- terra::setValues(g, 1)
  fires <- fires_at(50, 50, 150, 150)
  cal <- fev_exposure_calibrate(fuel, fires, radii = c(60, 120),
                                millesime = 2019, quiet = TRUE)
  expect_true(all(is.na(cal$table$auc)))
  expect_match(cal$table$note[1], "constant")
  expect_true(is.na(cal$best))
})

test_that("an unreachable radius is declared, not dropped", {
  g <- grid(40, res = 25)
  fuel <- half_fuel(40)
  terra::ext(fuel) <- terra::ext(g)
  fires <- fires_at(100, 100, 300, 300)
  cal <- fev_exposure_calibrate(fuel, fires, radii = c(30, 150),
                                millesime = 2019, quiet = TRUE)
  # Both radii appear; the 30 m one is refused for resolution, with a reason.
  expect_equal(nrow(cal$table), 2L)
  expect_false(cal$table$reachable[cal$table$radius == 30])
  expect_match(cal$table$note[cal$table$radius == 30], "res <=")
})

test_that("an optimum on the edge of the sweep says so", {
  g <- grid(60)
  set.seed(4)
  fuel <- terra::setValues(g, stats::rbinom(3600, 1, 0.5))
  fires <- fires_at(60, 60, 240, 240)
  cal <- fev_exposure_calibrate(fuel, fires, radii = c(40, 60, 90),
                                millesime = 2019, quiet = TRUE)
  scored <- cal$table$radius[!is.na(cal$table$auc)]
  if (length(scored) > 1) {
    expect_equal(cal$at_edge,
                 cal$best == min(scored) || cal$best == max(scored))
  }
})

# --- 2. The interface -----------------------------------------------------

test_that("the interface finds assets near fuel, and only those", {
  fuel <- half_fuel(20)
  pop <- terra::setValues(grid(20), 0)
  pop[10, 12] <- 50   # two cells east of the divide
  pop[10, 19] <- 50   # far east, nowhere near fuel
  w <- fev_wui(pop, fuel, distance = 30, quiet = TRUE)
  expect_equal(as.numeric(terra::global(fev_data(w), "sum", na.rm = TRUE)), 1)
  expect_equal(w$role, "wui")
})

test_that("the two sides answer different questions", {
  fuel <- half_fuel(20)
  pop <- terra::setValues(grid(20), 0)
  pop[10, 12] <- 50
  a <- as.numeric(terra::global(fev_data(
    fev_wui(pop, fuel, distance = 30, side = "assets", quiet = TRUE)), "sum"))
  f <- as.numeric(terra::global(fev_data(
    fev_wui(pop, fuel, distance = 30, side = "fuel", quiet = TRUE)), "sum"))
  # One inhabited cell, several fuel cells within reach of it.
  expect_equal(a, 1)
  expect_gt(f, a)
})

test_that("a distance below the cell size is refused", {
  expect_error(
    fev_wui(terra::setValues(grid(10), 1), half_fuel(10), distance = 2,
            quiet = TRUE),
    "below the cell size"
  )
})

test_that("mismatched grids are an error, not a silent resample", {
  other <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 500,
                       ymin = 0, ymax = 500, crs = "EPSG:2154")
  expect_error(
    fev_wui(terra::setValues(other, 1), half_fuel(20), quiet = TRUE),
    class = "fev_grid_mismatch"
  )
})

# --- 3. Anisotropy --------------------------------------------------------

test_that("with no wind and no slope the decomposition IS fev_exposure", {
  # The invariant the whole construction rests on. Sectors do not hold equal
  # numbers of cells, so weighting them equally would silently produce a
  # different metric; weighting by cell count reproduces the published one.
  set.seed(1)
  g <- grid(60)
  fuel <- terra::setValues(g, stats::rbinom(3600, 1, 0.45))
  a <- suppressMessages(fev_exposure(fuel, radius = 80, quiet = TRUE))
  for (ns in c(4L, 8L, 16L)) {
    b <- suppressMessages(
      fev_exposure_aniso(fuel, radius = 80, n_sectors = ns, quiet = TRUE)
    )
    d <- abs(terra::values(fev_data(a)) - terra::values(fev_data(b)))
    expect_lt(max(d, na.rm = TRUE), 1e-12)
  }
})

test_that("wind raises exposure on the side it blows from", {
  fuel <- half_fuel(60)      # burnable to the west
  probe <- function(r) terra::extract(fev_data(r),
                                      matrix(c(315, 300), ncol = 2))[1, 1]
  iso <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, quiet = TRUE)))
  west <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, wind = 270, kappa_wind = 2,
                       quiet = TRUE)))
  east <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, wind = 90, kappa_wind = 2,
                       quiet = TRUE)))
  # 270 is a west wind: it comes from where the fuel is.
  expect_gt(west, iso)
  expect_lt(east, iso)
})

test_that("slope raises exposure from downhill, because fire runs uphill", {
  fuel <- half_fuel(60)
  g <- grid(60)
  probe <- function(r) terra::extract(fev_data(r),
                                      matrix(c(315, 300), ncol = 2))[1, 1]
  iso <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, quiet = TRUE)))
  # Elevation rising eastwards: downhill is west, where the fuel is.
  down_west <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, dem = terra::init(g, "x") * 0.5,
                       kappa_slope = 3, quiet = TRUE)))
  down_east <- probe(suppressMessages(
    fev_exposure_aniso(fuel, radius = 80, dem = terra::init(g, "x") * -0.5,
                       kappa_slope = 3, quiet = TRUE)))
  expect_gt(down_west, iso)
  expect_lt(down_east, iso)
})

test_that("flat ground gets no slope anisotropy whatever the concentration", {
  # tan(slope) is the multiplier, so this is structural rather than a rule
  # bolted on for the flat case -- which is the reason it was built that way.
  set.seed(3)
  g <- grid(40)
  fuel <- terra::setValues(g, stats::rbinom(1600, 1, 0.5))
  flat <- terra::setValues(g, 100)
  a <- suppressMessages(fev_exposure_aniso(fuel, radius = 60, quiet = TRUE))
  b <- suppressMessages(fev_exposure_aniso(fuel, radius = 60, dem = flat,
                                           kappa_slope = 10, quiet = TRUE))
  d <- abs(terra::values(fev_data(a)) - terra::values(fev_data(b)))
  expect_lt(max(d, na.rm = TRUE), 1e-12)
})

test_that("the sectors partition the annulus exactly once", {
  w <- firexpovulnR:::fev_sector_windows(res = 10, radius = 80, n_sectors = 8)
  base <- firexpovulnR:::fev_annulus_window(10, 80)
  expect_equal(sum(w$counts), sum(!is.na(base)))
  # No cell in two sectors: the counts summing to the ring is necessary but not
  # sufficient, so check the overlap directly.
  stack <- Reduce(`+`, lapply(w$windows, function(m) !is.na(m)))
  expect_true(all(stack[!is.na(base)] == 1))
})

# --- 4. Graded load -------------------------------------------------------

test_that("a metric becomes an availability the graded path accepts", {
  g <- grid(40)
  set.seed(2)
  m <- terra::setValues(g, stats::runif(1600, 0.02, 0.5))
  names(m) <- "CBD_max"
  w <- fev_fuel_load_weight(m, quiet = TRUE)
  expect_equal(w$role, "availability")
  expect_equal(range(terra::values(fev_data(w)), na.rm = TRUE), c(0, 1))
  e <- suppressMessages(fev_exposure(w, radius = 60, quiet = TRUE))
  expect_s3_class(e, "fev_layer")
})

test_that("unmeasured ground stays NA rather than becoming no fuel", {
  # The distinction the whole file exists to protect: a LiDAR campaign covering
  # 2 km2 must not silently extend its authority over the other 300.
  g <- grid(40)
  set.seed(2)
  m <- terra::setValues(g, stats::runif(1600, 0.02, 0.5))
  names(m) <- "CBD_max"
  m[1:200] <- NA
  w <- fev_fuel_load_weight(m, quiet = TRUE)
  expect_true(anyNA(terra::values(fev_data(w))))
  filled <- fev_fuel_load_weight(m, fill = 0.2, quiet = TRUE)
  expect_false(anyNA(terra::values(fev_data(filled))))
})

test_that("an entirely unmeasured metric is an error, not an empty map", {
  g <- grid(10)
  m <- terra::setValues(g, NA_real_)
  names(m) <- "CBD_max"
  expect_error(fev_fuel_load_weight(m, quiet = TRUE), class = "fev_all_na")
})

test_that("a constant metric gives a flat weight, not a division by zero", {
  g <- grid(10)
  m <- terra::setValues(g, 0.3)
  names(m) <- "CBD_max"
  w <- fev_fuel_load_weight(m, quiet = TRUE)
  expect_true(all(terra::values(fev_data(w)) == 1))
})

test_that("the metric must be named, not taken by position", {
  g <- grid(10)
  m <- c(terra::setValues(g, 1), terra::setValues(g, 2))
  names(m) <- c("CBD_max", "CFL")
  expect_error(fev_fuel_load_weight(m, quiet = TRUE), "required")
  expect_error(fev_fuel_load_weight(m, metric = "nope", quiet = TRUE),
               "No layer named")
})

test_that("the tile grids are computed the way the products are named", {
  # Both were measured from the data on 2026-08-19; these lock the arithmetic
  # so a later edit cannot quietly shift the grid.
  maures <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 966000, ymin = 6240000, xmax = 990000, ymax = 6263000),
    crs = sf::st_crs(2154)))
  expect_equal(firexpovulnR:::fev_ghsl_tiles(maures), "R4_C19")
  expect_equal(firexpovulnR:::fev_dem_tiles(maures),
               "Copernicus_DSM_COG_10_N43_00_E006_00_DEM")
})
