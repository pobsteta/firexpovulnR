test_that("exposure is a proportion, computed on a ring around each cell", {
  fuel <- synth_exposure_landscape()
  e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
  expect_s3_class(e, "fev_exposure_layer")
  r <- fev_data(e)
  expect_equal(names(r), "exposure")
  v <- terra::values(r)
  expect_true(all(v >= 0 & v <= 1, na.rm = TRUE))

  # Deep inside the block every ring cell is burnable, so exposure is 1.
  centre <- terra::extract(r, cbind(750, 750))[, 1]
  expect_equal(centre, 1)
  # Far outside it, nothing is. The point is kept a full radius inside the
  # layer, or the window would not fit and the answer would be NA.
  outside <- terra::extract(r, cbind(200, 200))[, 1]
  expect_equal(outside, 0)
})

test_that("the assessment cell itself is excluded from its own window", {
  # The metric asks what can reach a place, not what is already there. An
  # isolated burnable cell must therefore score 0 at its own location.
  fuel <- synth_exposure_landscape(patch = NULL)
  fuel[30, 30] <- 1
  e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
  xy <- terra::xyFromCell(fuel, terra::cellFromRowCol(fuel, 30, 30))
  expect_equal(as.numeric(terra::extract(fev_data(e), xy)[, 1]), 0)
  # ... while its neighbours see it.
  expect_gt(max(terra::values(fev_data(e)), na.rm = TRUE), 0)
})

test_that("the analytic value of a known window is reproduced", {
  # Every cell burnable: every ring cell is burnable, so exposure is exactly 1
  # everywhere the window fits. No tolerance needed -- it is a proportion of
  # ones.
  fuel <- synth_exposure_landscape(patch = NULL)
  terra::values(fuel) <- 1
  e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
  v <- terra::values(fev_data(e))
  expect_equal(unique(v[!is.na(v)]), 1)
})

test_that("the three published radii are the defaults behind type", {
  radii <- fev_exposure_radii()
  expect_equal(radii$max_m[radii$type == "radiant"], 30)
  expect_equal(radii$max_m[radii$type == "ember_short"], 100)
  expect_equal(radii$max_m[radii$type == "ember"], 500)

  fuel <- synth_exposure_landscape(nrow = 120, ncol = 120, res = 25)
  e <- fev_exposure(fuel, type = "ember", quiet = TRUE)
  step <- e$provenance$steps[[length(e$provenance$steps)]]
  expect_equal(step$params$radius, 500)
  expect_match(step$params$radius_source, "Beverly")
})

test_that("a grid too coarse for the radius is refused", {
  # Below res <= radius/3 the ring is a handful of cells and the proportion is
  # quantised. Same constraint as fireexposuR.
  fuel <- synth_exposure_landscape(res = 25)
  expect_error(fev_exposure(fuel, radius = 60, quiet = TRUE),
               class = "fev_res_too_coarse")
  expect_no_error(fev_exposure(fuel, radius = 75, quiet = TRUE))
})

test_that("a layer too small for the window is refused with the reason", {
  fuel <- synth_exposure_landscape(nrow = 20, ncol = 20, res = 25)
  expect_error(fev_exposure(fuel, radius = 500, quiet = TRUE),
               class = "fev_extent_too_small")
})

test_that("the radius caveat is emitted once per session", {
  fev_reset_once()
  fuel <- synth_exposure_landscape()
  expect_message(fev_exposure(fuel, radius = 100),
                 class = "fev_unvalidated_radius")
  # Second call in the same session stays quiet -- but the radius is still in
  # the record, which is the part that has to survive.
  expect_no_message(e <- fev_exposure(fuel, radius = 100))
  step <- e$provenance$steps[[length(e$provenance$steps)]]
  expect_equal(step$params$radius, 100)
  fev_reset_once()
})

test_that("exposure accepts a fuel source and reduces it itself", {
  aoi <- synth_fuel_aoi()
  # A larger AOI than the fuel tests use, so the window fits.
  big <- sf::st_as_sf(synth_rect(0, 1500, 0, 1500))
  poly <- sf::st_sf(code_tfv = "FF2-57-57",
                    geometry = synth_rect(300, 1200, 300, 1200))
  fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 25, aoi = big,
                          millesime = 2014)
  e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
  expect_s3_class(e, "fev_exposure_layer")

  funs <- vapply(e$provenance$steps, function(s) s$fun, character(1))
  expect_equal(funs, c("fev_fuel_source", "fev_fuel_binary", "fev_exposure"))
})

test_that("a graded availability layer gives weighted exposure, and says so", {
  aoi <- sf::st_as_sf(synth_rect(0, 1500, 0, 1500))
  poly <- sf::st_sf(code_tfv = c("FF2-57-57", "FF1-09-09"),
                    geometry = c(synth_rect(300, 750, 300, 1200),
                                 synth_rect(750, 1200, 300, 1200)))
  fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 25, aoi = aoi,
                          millesime = 2014)
  avail <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))

  graded <- fev_exposure(avail, radius = 100, quiet = TRUE)
  binary <- fev_exposure(fev_fuel_binary(fuel), radius = 100, quiet = TRUE)

  step <- graded$provenance$steps[[length(graded$provenance$steps)]]
  expect_true(step$params$graded)
  # Aleppo pine weighs 0.95 and beech 0.60, so the graded version is strictly
  # below the binary one wherever there is fuel.
  gv <- terra::values(fev_data(graded))
  bv <- terra::values(fev_data(binary))
  ok <- !is.na(gv) & bv > 0
  expect_true(all(gv[ok] < bv[ok]))
})

test_that("degraded and wrong-shaped inputs are refused clearly", {
  fuel <- synth_exposure_landscape()

  bad <- fuel * 5
  expect_error(fev_exposure(bad, radius = 100, quiet = TRUE),
               class = "fev_bad_range")

  empty <- terra::rast(fuel)
  terra::values(empty) <- NA
  expect_error(fev_exposure(empty, radius = 100, quiet = TRUE),
               class = "fev_all_na")

  cat_r <- terra::rast(fuel)
  terra::values(cat_r) <- rep_len(1:2, terra::ncell(cat_r))
  levels(cat_r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
  expect_error(fev_exposure(cat_r, radius = 100, quiet = TRUE),
               class = "fev_categorical_input")

  expect_error(fev_exposure(fuel, radius = -1, quiet = TRUE),
               class = "fev_error")
  expect_error(fev_exposure("not a raster", quiet = TRUE), class = "fev_error")
})

test_that("no_burn is validated and masks the result", {
  fuel <- synth_exposure_landscape()
  bad <- terra::rast(fuel)
  terra::values(bad) <- 2
  expect_error(fev_exposure(fuel, radius = 100, no_burn = bad, quiet = TRUE),
               class = "fev_bad_no_burn")

  off_grid <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 1500,
                          ymin = 0, ymax = 1500, crs = "EPSG:2154")
  terra::values(off_grid) <- 1
  expect_error(
    fev_exposure(fuel, radius = 100, no_burn = off_grid, quiet = TRUE),
    class = "fev_grid_mismatch"
  )
})

# --- directional -------------------------------------------------------------

test_that("directional vulnerability finds the bearing the fuel is on", {
  r <- synth_directional_landscape()
  d <- fev_directional(r, point = c(3000, 3000),
                       seg_lengths = c(500, 500, 500), interval = 45)
  expect_s3_class(d, "fev_directional")

  # The high-exposure block sits due north, so north and its neighbours are
  # viable and nothing else is.
  viable <- d$table$bearing[d$table$viable]
  expect_setequal(viable, c(45, 315, 360))
  expect_false(180 %in% viable)
})

test_that("bearings are compass bearings, not mathematical angles", {
  # A block due east must show up at 90 degrees, not at 0. Getting this wrong
  # produces a plausible map rotated by 90 degrees.
  r <- synth_directional_landscape(side = "east")
  d <- fev_directional(r, point = c(3000, 3000),
                       seg_lengths = c(500, 500, 500), interval = 90)
  expect_true(d$table$viable[d$table$bearing == 90])
  expect_false(d$table$viable[d$table$bearing == 270])
  expect_false(d$table$viable[d$table$bearing == 360])
})

test_that("n_wedges is an alternative way of saying interval", {
  r <- synth_directional_landscape()
  a <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                       interval = 45)
  b <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                       n_wedges = 8)
  expect_equal(a$table, b$table)
  expect_equal(nrow(b$table), 8L)
})

test_that("max_dist splits into three equal segments", {
  r <- synth_directional_landscape()
  d <- fev_directional(r, point = c(3000, 3000), max_dist = 1500,
                       interval = 90)
  expect_equal(d$params$seg_lengths, rep(500, 3))
})

test_that("the published thresholds are the defaults", {
  # 0.6 and 0.8 are measured values from Beverly & Forbes 2023, not package
  # conventions, and they must not drift.
  defaults <- fev_directional_defaults()
  expect_equal(defaults$thresh_exp, 0.6)
  expect_equal(defaults$thresh_viable, 0.8)
  expect_equal(defaults$interval, 1)
  expect_equal(defaults$seg_lengths, c(5000, 5000, 5000))

  r <- synth_directional_landscape()
  d <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                       interval = 90)
  step <- d$provenance$steps[[length(d$provenance$steps)]]
  expect_equal(step$params$thresh_exp, 0.6)
  expect_equal(step$params$thresh_viable, 0.8)
  expect_match(step$params$source, "Beverly")
})

test_that("the thresholds actually decide viability", {
  r <- synth_directional_landscape(value = 0.5)
  # Exposure of 0.5 is below the default 0.6, so nothing is viable ...
  d1 <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                        interval = 90)
  expect_false(any(d1$table$viable))
  # ... until the threshold is lowered.
  d2 <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                        interval = 90, thresh_exp = 0.4)
  expect_true(any(d2$table$viable))
})

test_that("transects running off the layer are reported, not silently dropped", {
  r <- synth_directional_landscape()
  expect_warning(
    fev_directional(r, point = c(3000, 3000), seg_lengths = c(2000, 2000, 2000),
                    interval = 90),
    class = "fev_transect_off_grid"
  )
})

test_that("the point is validated against the layer", {
  r <- synth_directional_landscape()
  expect_error(fev_directional(r, point = c(99999, 99999)),
               class = "fev_disjoint_extent")
  expect_error(fev_directional(r, point = "somewhere"), class = "fev_error")

  two <- sf::st_sf(id = 1:2,
                   geometry = sf::st_sfc(sf::st_point(c(3000, 3000)),
                                         sf::st_point(c(3100, 3100)),
                                         crs = 2154))
  expect_error(fev_directional(r, point = two), class = "fev_error")
})

test_that("a point given as sf is reprojected onto the layer", {
  r <- synth_directional_landscape()
  centre <- sf::st_sfc(sf::st_point(c(3000, 3000)), crs = 2154)
  in_wgs84 <- sf::st_transform(centre, 4326)
  a <- fev_directional(r, point = centre, seg_lengths = rep(500, 3),
                       interval = 90)
  b <- fev_directional(r, point = in_wgs84, seg_lengths = rep(500, 3),
                       interval = 90)
  expect_equal(a$table$viable, b$table$viable)
})

test_that("directional results print and plot", {
  r <- synth_directional_landscape()
  d <- fev_directional(r, point = c(3000, 3000), seg_lengths = rep(500, 3),
                       interval = 90)
  expect_no_error(print(d))
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(d))

  none <- synth_directional_landscape(value = 0)
  expect_no_error(print(fev_directional(none, point = c(3000, 3000),
                                        seg_lengths = rep(500, 3),
                                        interval = 90)))
})
