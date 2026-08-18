# Repairing rasterisation gaps.
#
# The threshold under test is not a tuning knob: CORINE cannot map anything under
# 25 ha, so a hole smaller than that inside its extent cannot be a real
# land-cover unit. Crossing that line turns a repair into an invention, and these
# tests pin both sides of it.

# 25 m cells, so one cell is 0.0625 ha and 25 ha is 400 cells.
gfuel <- function(mod, type = "clc_2018", millesime = 2018, n = 60) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * 25,
                   ymin = 0, ymax = n * 25, crs = "EPSG:2154")
  terra::values(r) <- rep(1, terra::ncell(r))
  levels(r) <- data.frame(id = 1, code_18 = "311")
  fev_fuel_source(mod(r), type = type, millesime = millesime)
}

gna <- function(f) {
  as.numeric(terra::global(is.na(fev_fuel_categorical(f)[[1]]), "sum",
                           na.rm = TRUE)[1, 1])
}

test_that("slivers below the minimum mapping unit are repaired", {
  f <- gfuel(function(r) {
    r[5, 5] <- NA                 # a single cell, 0.0625 ha
    r[10, 10] <- NA               # a two-cell sliver
    r[11, 10] <- NA
    r
  })
  expect_equal(gna(f), 3)

  g <- suppressMessages(fev_fuel_fill_gaps(f))
  expect_equal(gna(g), 0)
  # The class comes from the neighbourhood, so it must be the one that was there.
  expect_equal(sort(unique(terra::values(fev_fuel_categorical(g)[[1]],
                                        mat = FALSE))), 1)
  # And the level table survives the focal pass, which drops it.
  expect_false(is.null(fev_cat_levels(fev_fuel_categorical(g)[[1]])))
})

test_that("a hole above the minimum mapping unit is left alone", {
  # 30 x 30 cells = 900 cells = 56.25 ha, well over CORINE's 25 ha.
  f <- gfuel(function(r) {
    r[10:39, 10:39] <- NA
    r
  })
  expect_equal(gna(f), 900)

  expect_warning(g <- fev_fuel_fill_gaps(f), class = "fev_gaps_too_large")
  expect_equal(gna(g), 900)
  # Nothing was touched, so no step should claim otherwise.
  expect_identical(g$provenance, f$provenance)
})

test_that("a sliver and a real hole in the same layer are treated differently", {
  f <- gfuel(function(r) {
    r[50, 50] <- NA               # sliver
    r[10:39, 10:39] <- NA         # 56.25 ha
    r
  })
  expect_equal(gna(f), 901)

  g <- suppressWarnings(suppressMessages(fev_fuel_fill_gaps(f)))
  expect_equal(gna(g), 900)       # the sliver went, the hole stayed

  step <- g$provenance$steps[[length(g$provenance$steps)]]
  expect_equal(step$params$cells_filled, 1)
  expect_equal(step$params$gaps_left, 1)
  expect_equal(step$params$max_gap_ha, 25)
})

test_that("the threshold comes from the source, and is recorded", {
  f <- gfuel(function(r) {
    r[5, 5] <- NA
    r
  })
  g <- suppressMessages(fev_fuel_fill_gaps(f))
  step <- g$provenance$steps[[length(g$provenance$steps)]]
  expect_match(step$params$threshold_source, "clc_2018")
  expect_equal(step$params$max_gap_ha, 25)

  # An explicit value is honoured and marked as such, because it is then an
  # assumption rather than a property of the data.
  h <- suppressWarnings(suppressMessages(fev_fuel_fill_gaps(f, max_gap = 0.01)))
  expect_equal(gna(h), 1)         # 0.0625 ha is above 0.01 ha, so kept

  h2 <- suppressMessages(fev_fuel_fill_gaps(f, max_gap = 100))
  step2 <- h2$provenance$steps[[length(h2$provenance$steps)]]
  expect_equal(step2$params$threshold_source, "explicit")

  expect_error(fev_fuel_fill_gaps(f, max_gap = -1), "positive")
  expect_error(fev_fuel_fill_gaps(f, max_gap = c(1, 2)), "single")
})

test_that("a partial-coverage source cannot license a repair", {
  # BD Forêt maps vegetation formations only, so its silence means "not forest",
  # which is information rather than a gap. Its 0.5 ha minimum mapping unit must
  # not be used to fill anything.
  f <- gfuel(function(r) {
    r[5, 5] <- NA
    r
  }, type = "bdforet_v2", millesime = 2014)

  expect_warning(g <- fev_fuel_fill_gaps(f),
                 class = "fev_no_complete_coverage")
  expect_equal(gna(g), 1)

  # Unless the caller says so explicitly, which is then on the record.
  g2 <- suppressMessages(fev_fuel_fill_gaps(f, max_gap = 1))
  expect_equal(gna(g2), 0)
})

test_that("repaired cells are marked rather than attributed to a dataset", {
  # The `source` layer of a merged register says which dataset supplied each
  # pixel. A repaired cell was supplied by none, so it must not borrow a
  # neighbour's name.
  mk <- function(codes, type, millesime) {
    r <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
                     ymin = 0, ymax = 1000, crs = "EPSG:2154")
    terra::values(r) <- codes
    r
  }
  cat_r <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
                       ymin = 0, ymax = 1000, crs = "EPSG:2154")
  terra::values(cat_r) <- rep(1, terra::ncell(cat_r))
  levels(cat_r) <- data.frame(id = 1, code_18 = "311")
  cat_r[7, 7] <- NA
  primary <- fev_fuel_source(cat_r, type = "clc_2018", millesime = 2018)

  src <- cat_r
  levels(src) <- data.frame(id = 1, source = "clc_2018")
  stacked <- c(cat_r, src)
  names(stacked) <- c("class", "source")
  fuel <- primary
  fuel$categorical <- stacked

  g <- suppressMessages(fev_fuel_fill_gaps(fuel))
  lv <- fev_cat_levels(fev_fuel_categorical(g)[["source"]])
  expect_true("gap_filled" %in% lv[[2]])

  id <- lv[[1]][lv[[2]] == "gap_filled"]
  vals <- terra::values(fev_fuel_categorical(g)[["source"]], mat = FALSE)
  expect_equal(sum(vals == id, na.rm = TRUE), 1)
  # The class layer is filled from the neighbourhood, not stamped.
  expect_equal(gna(g), 0)
})

test_that("a clean layer and a continuous-only source are handled", {
  f <- gfuel(function(r) r)
  expect_message(g <- fev_fuel_fill_gaps(f), "No empty cell")
  expect_identical(g$provenance, f$provenance)

  bare <- structure(list(categorical = NULL, continuous = NULL,
                         type = "custom"), class = "fev_fuel_source")
  expect_error(fev_fuel_fill_gaps(bare), class = "fev_no_categorical")
  expect_error(fev_fuel_fill_gaps(42), "fev_fuel_source")
})

test_that("fev_exposure announces what the gaps will cost", {
  # 42 empty cells out of 469 989 emptied 26 303 on the Couchey extract, an
  # amplification of 626. Nothing announced it before this warning existed.
  r <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 1500,
                   ymin = 0, ymax = 1500, crs = "EPSG:2154")
  terra::values(r) <- rep(1, terra::ncell(r))
  r[30, 30] <- NA

  expect_warning(e <- fev_exposure(r, radius = 200, type = "ember"),
                 class = "fev_focal_gaps")
  # And the propagation it warns about is real.
  expect_gt(as.numeric(terra::global(is.na(fev_data(e)), "sum",
                                     na.rm = TRUE)[1, 1]), 100)

  # Silent when there is nothing to say, and silent when asked to ignore gaps.
  terra::values(r) <- rep(1, terra::ncell(r))
  expect_no_warning(fev_exposure(r, radius = 200, type = "ember",
                                 quiet = TRUE))
  r[30, 30] <- NA
  expect_no_warning(fev_exposure(r, radius = 200, type = "ember",
                                 na_rm = TRUE, quiet = TRUE))
})

test_that("repairing the gaps changes nothing the exposure already knew", {
  # The repair must be invisible wherever the unrepaired pass produced a value:
  # if it moved an existing number, it would be an interpolation, not a repair.
  r <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 1500,
                   ymin = 0, ymax = 1500, crs = "EPSG:2154")
  set.seed(1)
  terra::values(r) <- sample(c(0, 1), terra::ncell(r), replace = TRUE)
  levels(r) <- NULL
  raw <- r
  raw[30, 30] <- NA

  e_raw <- fev_data(suppressWarnings(
    fev_exposure(raw, radius = 200, type = "ember", quiet = TRUE)))
  # Fill that one cell with its modal neighbour, as fev_fuel_fill_gaps does.
  patched <- terra::focal(raw, w = 3, fun = "modal", na.policy = "only",
                          na.rm = TRUE)
  e_fix <- fev_data(fev_exposure(patched, radius = 200, type = "ember",
                                 quiet = TRUE))

  defined <- !is.na(e_raw)
  delta <- terra::global(abs(terra::mask(e_fix, defined, maskvalues = c(0, NA))
                             - e_raw), "max", na.rm = TRUE)[1, 1]
  expect_lt(as.numeric(delta), 0.02)
  expect_lt(as.numeric(terra::global(is.na(e_fix), "sum", na.rm = TRUE)[1, 1]),
            as.numeric(terra::global(is.na(e_raw), "sum", na.rm = TRUE)[1, 1]))
})
