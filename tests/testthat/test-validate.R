# Risk rising towards the south. Row 1 of a SpatRaster is its northern edge,
# so values run 0 at the top to 1 at the bottom -- which is the detail that
# makes a validation fixture read backwards if it is got wrong.
vrisk <- function(n = 20, extent = 2000) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = extent, ymin = 0,
                   ymax = extent, crs = "EPSG:2154")
  terra::values(r) <- rep(seq(0, 1, length.out = n), each = n)
  r
}

vfire <- function(dates, ymin, ymax, xmax = 2000) {
  geom <- Map(function(a, b) {
    sf::st_polygon(list(cbind(c(0, xmax, xmax, 0, 0), c(a, a, b, b, a))))
  }, ymin, ymax)
  sf::st_sf(FIREDATE = dates, geometry = sf::st_sfc(geom, crs = 2154))
}

test_that("a map that ranks fires correctly gets AUC 1, and the reverse 0", {
  r <- vrisk()
  south <- vfire("2016-07-18", 0, 500)
  north <- vfire("2016-07-18", 1500, 2000)

  expect_equal(fev_validate(r, south, millesime = 2014)$auc, 1)
  expect_equal(fev_validate(r, north, millesime = 2014)$auc, 0)
})

test_that("a map with no information gets AUC near 0.5", {
  r <- vrisk()
  terra::values(r) <- 0.5
  # A constant map cannot discriminate: every comparison is a tie, and the
  # rank-based AUC scores ties at 0.5 by construction.
  v <- fev_validate(r, vfire("2016-07-18", 0, 500), millesime = 2014)
  expect_equal(v$auc, 0.5)
})

test_that("the class table shows where burnt area concentrates", {
  v <- fev_validate(vrisk(), vfire("2016-07-18", 0, 500), millesime = 2014)
  tab <- v$classes
  expect_equal(nrow(tab), 5L)
  expect_equal(sum(tab$pct_of_area), 100)
  expect_equal(sum(tab$pct_of_burnt), 100)
  # The fixture puts every burnt cell in the two top classes, so the ratio
  # there exceeds 1 and is 0 below.
  expect_gt(tab$ratio[5], 1)
  expect_equal(tab$ratio[1], 0)
})

test_that("the ROC curve spans the unit square and is monotone", {
  v <- fev_validate(vrisk(), vfire("2016-07-18", 0, 500), millesime = 2014)
  roc <- v$roc
  expect_true(all(roc$tpr >= 0 & roc$tpr <= 1))
  expect_true(all(roc$fpr >= 0 & roc$fpr <= 1))
  expect_false(is.unsorted(roc$tpr))
  expect_false(is.unsorted(roc$fpr))
  expect_equal(roc$tpr[1], 0)
  expect_equal(roc$tpr[nrow(roc)], 1)
})

# --- the temporal bias check ------------------------------------------------

test_that("burnt area postdating the vintage is reported with a number", {
  # This is the warning the brief asks for, in the form it asks for.
  r <- vrisk()
  fires <- vfire(c("2016-07-18", "2022-08-01"), c(0, 600), c(500, 900))
  expect_warning(v <- fev_validate(r, fires, millesime = 2014),
                 class = "fev_temporal_bias")

  tab <- v$temporal$table
  expect_equal(nrow(tab), 3L)
  expect_equal(sum(tab$n_fires), 2L)
  expect_equal(sum(tab$pct_area), 100)
  # 2022 is eight years after the 2014 vintage, so that fire lands in the
  # "> 5" row and the other does not.
  expect_equal(tab$n_fires[3], 1L)
  expect_equal(v$temporal$n_beyond, 1L)
  expect_gt(v$temporal$pct_area, 0)
})

test_that("max_lag_years drops the fires it reports on", {
  r <- vrisk()
  fires <- vfire(c("2016-07-18", "2022-08-01"), c(0, 600), c(500, 900))

  kept <- suppressWarnings(fev_validate(r, fires, millesime = 2014))
  dropped <- suppressWarnings(
    fev_validate(r, fires, millesime = 2014, max_lag_years = 5)
  )
  expect_equal(nrow(kept$temporal$fires), 2L)
  expect_equal(nrow(dropped$temporal$fires), 1L)
  expect_lt(dropped$n_burnt, kept$n_burnt)

  step <- dropped$provenance$steps[[length(dropped$provenance$steps)]]
  expect_equal(step$params$max_lag_years, 5)
  expect_equal(step$params$n_fires, 1L)
  expect_equal(step$params$n_fires_supplied, 2L)
})

test_that("a fire before the vintage is counted separately, not as a lag", {
  # BD Forêt v2 spans 2007-2018, so a 2016 fire against a 2018 vintage is a
  # real and common case: the fuel layer postdates the fire.
  r <- vrisk()
  v <- fev_validate(r, vfire("2016-07-18", 0, 500), millesime = 2018)
  expect_equal(v$temporal$table$n_fires, c(1L, 0L, 0L))
  expect_equal(v$temporal$n_beyond, 0L)
})

test_that("the vintage is read from the provenance, not asked for twice", {
  # The point of carrying provenance: a risk layer built through the chain
  # already knows which vintage its fuel had.
  aoi <- sf::st_as_sf(synth_rect(0, 2000, 0, 2000))
  poly <- sf::st_sf(code_tfv = "FF2-57-57",
                    geometry = synth_rect(0, 2000, 0, 2000))
  fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 50, aoi = aoi,
                          millesime = 2011)
  avail <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))

  danger <- terra::rast(fev_data(avail))
  terra::values(danger) <- rep(seq(0, 100, length.out = 40), each = 40)
  # The layer objects are passed, not their rasters: fev_data() would hand
  # over a bare SpatRaster and the vintage would stop travelling here.
  idx <- fev_danger_index(danger, avail, normalise = "percentile")
  risk <- fev_risk(idx, avail, normalise = "none")

  v <- suppressWarnings(fev_validate(risk, vfire("2022-08-01", 0, 500)))
  expect_equal(v$temporal$millesime, 2011)
})

test_that("an unknown vintage warns, and refuses to filter", {
  r <- vrisk()
  fires <- vfire("2016-07-18", 0, 500)

  expect_warning(v <- fev_validate(r, fires), class = "fev_millesime_missing")
  expect_true(is.na(v$temporal$pct_area))
  expect_match(v$temporal$note, "vintage unknown")

  # Asking for a filter with nothing to filter against is an error, not a
  # silently skipped step.
  expect_error(fev_validate(r, fires, max_lag_years = 5),
               class = "fev_millesime_required")
})

test_that("filtering everything out is an error, not an empty result", {
  r <- vrisk()
  fires <- vfire("2022-08-01", 0, 500)
  expect_error(
    suppressWarnings(fev_validate(r, fires, millesime = 2000,
                                  max_lag_years = 5)),
    class = "fev_empty_sample"
  )
})

# --- degraded inputs --------------------------------------------------------

test_that("fires that miss the layer are named as a location mismatch", {
  r <- vrisk()
  far <- vfire("2016-07-18", 900000, 901000, xmax = 900000)
  expect_error(fev_validate(r, far, millesime = 2014),
               class = "fev_disjoint_extent")
})

test_that("a fully burnt extent is refused", {
  r <- vrisk()
  expect_error(
    fev_validate(r, vfire("2016-07-18", 0, 2000), millesime = 2014),
    class = "fev_degenerate_sample"
  )
})

test_that("a missing or unparseable date is named", {
  r <- vrisk()
  no_date <- sf::st_sf(
    id = 1,
    geometry = sf::st_sfc(sf::st_polygon(list(cbind(
      c(0, 2000, 2000, 0, 0), c(0, 0, 500, 500, 0)
    ))), crs = 2154)
  )
  expect_error(fev_validate(r, no_date, millesime = 2014), class = "fev_error")

  bad_date <- vfire("not a date", 0, 500)
  expect_error(fev_validate(r, bad_date, millesime = 2014), class = "fev_error")
})

test_that("wrong-shaped inputs are refused", {
  r <- vrisk()
  expect_error(fev_validate(r, "not fires", millesime = 2014),
               class = "fev_error")
  expect_error(fev_validate(r, vfire("2016-07-18", 0, 500)[0, ],
                            millesime = 2014),
               class = "fev_empty_result")

  empty <- terra::rast(r)
  terra::values(empty) <- NA
  expect_error(fev_validate(empty, vfire("2016-07-18", 0, 500),
                            millesime = 2014),
               class = "fev_all_na")
})

test_that("fires in another CRS are reprojected onto the risk layer", {
  r <- vrisk()
  fires <- vfire("2016-07-18", 0, 500)
  in_wgs84 <- sf::st_transform(fires, 4326)
  a <- fev_validate(r, fires, millesime = 2014)
  b <- fev_validate(r, in_wgs84, millesime = 2014)
  expect_equal(a$auc, b$auc)
})

test_that("results print and plot", {
  v <- fev_validate(vrisk(), vfire("2016-07-18", 0, 500), millesime = 2014)
  expect_no_error(print(v))
  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(v))

  quiet <- suppressWarnings(fev_validate(vrisk(), vfire("2016-07-18", 0, 500)))
  expect_no_error(print(quiet))
})

test_that("the AUC survives a sample large enough to overflow an integer", {
  # sum() of a logical returns an INTEGER, so n1 * n0 and n1 * (n1 + 1) overflow
  # 32-bit integers. With half a million unburnt cells that happens above about
  # 4 400 burnt cells -- 275 ha at 25 m, which any real fire sample passes -- and
  # R answers NA rather than erroring. The Maures article published NA as its AUC.
  set.seed(1)
  n <- 600000L
  positive <- rep(FALSE, n)
  positive[sample(n, 110000)] <- TRUE

  n1 <- sum(positive)
  n0 <- sum(!positive)
  expect_true(is.na(suppressWarnings(n1 * n0)))  # the trap is real
  expect_gt(as.numeric(n1) * as.numeric(n0), .Machine$integer.max)

  auc <- fev_auc(runif(n), positive)
  expect_false(is.na(auc))
  expect_gt(auc, 0.45)
  expect_lt(auc, 0.55)

  # Bounds must still hold at this size.
  expect_equal(fev_auc(as.numeric(positive), positive), 1)
  expect_equal(fev_auc(-as.numeric(positive), positive), 0)
})

test_that("printing a validation with a non-finite AUC does not fail", {
  # `if (NA < 0.55)` is an error rather than FALSE, so the print method used to
  # die on exactly the objects that most needed inspecting.
  v <- fev_validate(vrisk(), vfire("2016-07-18", 0, 500), millesime = 2014)
  v$auc <- NA_real_
  expect_no_error(capture.output(print(v)))
  expect_match(paste(capture.output(print(v), type = "message"), collapse = " "),
               "not finite")
})
