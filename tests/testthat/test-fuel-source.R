test_that("a polygon source rasterises onto an aligned grid", {
  aoi <- synth_fuel_aoi()
  f <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 25,
                       aoi = aoi, millesime = 2014)

  expect_s3_class(f, "fev_fuel_source")
  expect_equal(fev_fuel_registers(f), "categorical")
  r <- fev_fuel_categorical(f)
  expect_equal(terra::res(r), c(25, 25))
  # Origin snapped to a multiple of the cell size, so two AOIs processed
  # separately land on the same grid.
  expect_equal(terra::xmin(r) %% 25, 0)
  expect_equal(terra::ymin(r) %% 25, 0)
  expect_equal(fev_crs_label(r), "EPSG:2154")
})

test_that("the class layer is normalised whatever the source column is called", {
  aoi <- synth_fuel_aoi()
  bdf <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50,
                         aoi = aoi, millesime = 2014)
  clc <- fev_fuel_source(synth_clc(), type = "clc_2018", res = 50, aoi = aoi,
                         millesime = 2018)
  # code_tfv and code_18 both arrive as a layer named "class" with a level
  # table named id/class, so nothing downstream has to know its source.
  expect_equal(names(fev_fuel_categorical(bdf)), "class")
  expect_equal(names(fev_fuel_categorical(clc)), "class")
  expect_equal(names(terra::levels(fev_fuel_categorical(bdf))[[1]]),
               c("id", "class"))
})

test_that("the CORINE class column is read off the data, not the type", {
  aoi <- synth_fuel_aoi()
  x <- synth_clc()
  names(x)[names(x) == "code_18"] <- "code_12"
  f <- fev_fuel_source(x, type = "clc_2018", res = 50, aoi = aoi,
                       millesime = 2012)
  expect_true("323" %in% terra::levels(fev_fuel_categorical(f))[[1]]$class)
})

test_that("the BD Forêt vintage is required, and absence must be explicit", {
  aoi <- synth_fuel_aoi()

  expect_error(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50, aoi = aoi),
    class = "fev_millesime_required"
  )

  # Explicit NA is accepted -- "we looked and do not know" is a fact worth
  # recording -- but it warns, because fev_validate() will not be able to run.
  expect_warning(
    f <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50,
                         aoi = aoi, millesime = NA),
    class = "fev_millesime_missing"
  )
  expect_true(is.na(f$millesime))

  # CORINE has a common European reference date, so it is not blocking.
  expect_no_error(
    fev_fuel_source(synth_clc(), type = "clc_2018", res = 50, aoi = aoi)
  )
})

test_that("a vintage travelling with a fetched source is honoured", {
  src <- new_fev_source(synth_bdforet(), dataset = "bdforet_v2",
                        provider = "IGN", millesime = 2011)
  f <- fev_fuel_source(src, type = "bdforet_v2", res = 50,
                       aoi = synth_fuel_aoi())
  expect_equal(f$millesime, 2011)
  # And the fetch record becomes a provenance source, not a lost attribute.
  expect_equal(length(f$provenance$sources), 1L)
  expect_equal(f$provenance$sources[[1]]$millesime, 2011)
})

test_that("resolution choices are argued with, not silently accepted", {
  aoi <- synth_fuel_aoi()
  # Finer than BD Forêt's 20 m minimum mapped width: informative, not an error.
  expect_message(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 10, aoi = aoi,
                    millesime = 2014),
    class = "fev_res_too_fine"
  )
  # At CORINE's own native resolution the reason for preferring BD Forêt is
  # gone, and that is a warning.
  expect_warning(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 100, aoi = aoi,
                    millesime = 2014),
    class = "fev_res_too_coarse"
  )
  expect_error(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 0, aoi = aoi,
                    millesime = 2014),
    class = "fev_error"
  )
})

test_that("degraded inputs get a package message, never a terra failure", {
  aoi <- synth_fuel_aoi()

  # No features.
  empty <- synth_bdforet()[0, ]
  expect_error(
    fev_fuel_source(empty, type = "bdforet_v2", res = 50, aoi = aoi,
                    millesime = 2014),
    class = "fev_empty_result"
  )

  # No CRS.
  nocrs <- synth_bdforet()
  sf::st_crs(nocrs) <- NA
  expect_error(
    fev_fuel_source(nocrs, type = "bdforet_v2", res = 50, millesime = 2014),
    class = "fev_error"
  )

  # AOI somewhere else entirely.
  far <- sf::st_as_sf(synth_rect(500000, 500200, 6500000, 6500200))
  expect_error(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50, aoi = far,
                    millesime = 2014),
    class = "fev_disjoint_extent"
  )

  # Class column missing.
  wrong <- synth_bdforet()
  names(wrong)[names(wrong) == "code_tfv"] <- "something_else"
  expect_error(
    fev_fuel_source(wrong, type = "bdforet_v2", res = 50, aoi = aoi,
                    millesime = 2014),
    class = "fev_error"
  )

  # Not a spatial object at all.
  expect_error(
    fev_fuel_source(data.frame(a = 1), type = "custom"),
    class = "fev_error"
  )
})

test_that("reprojecting a categorical source warns before it happens", {
  # crs_work different from the primary's native CRS is exactly the case the
  # one-reprojection rule exists to make visible.
  expect_warning(
    f <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50,
                         crs_work = 3035, millesime = 2014),
    class = "fev_categorical_reprojected"
  )
  expect_equal(fev_crs_label(fev_fuel_categorical(f)), "EPSG:3035")
  steps <- f$provenance$steps
  expect_match(steps[[length(steps)]]$notes, "reprojected", fixed = TRUE)
})

test_that("touches = TRUE keeps features that fall between cell centres", {
  # A 10 m sliver on a 25 m grid: dropped by the cell-centre rule, kept by
  # touches. Both behaviours are defensible; the point is that the choice is
  # the caller's and is recorded.
  sliver <- sf::st_sf(code_tfv = "LA4",
                      geometry = synth_rect(0, 10, 0, 200))
  aoi <- synth_fuel_aoi()

  expect_warning(
    dropped <- fev_fuel_source(sliver, type = "bdforet_v2", res = 25,
                               aoi = aoi, millesime = 2014, touches = FALSE),
    class = "fev_all_na"
  )
  expect_true(fev_all_na(fev_fuel_categorical(dropped)))

  kept <- fev_fuel_source(sliver, type = "bdforet_v2", res = 25, aoi = aoi,
                          millesime = 2014, touches = TRUE)
  expect_false(fev_all_na(fev_fuel_categorical(kept)))

  last <- kept$provenance$steps[[length(kept$provenance$steps)]]
  expect_true(last$params$touches)
})

test_that("the two registers are separate and declared", {
  cat_r <- synth_class_raster()
  f <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)
  expect_equal(fev_fuel_registers(f), "categorical")
  expect_null(fev_fuel_continuous(f))

  # A plain numeric raster with no class table goes to the continuous
  # register. This is the path LiDAR will take in phase 8; exercising it now is
  # what proves the abstraction is not secretly categorical.
  num <- synth_raster(values = seq(0, 2, length.out = 100))
  names(num) <- "cbd"
  g <- fev_fuel_source(num, type = "custom", units = c(cbd = "kg/m3"))
  expect_equal(fev_fuel_registers(g), "continuous")
  expect_null(fev_fuel_categorical(g))
  expect_equal(names(fev_fuel_continuous(g)), "cbd")
})

test_that("a function refuses politely when its register is empty", {
  num <- synth_raster(values = 1)
  names(num) <- "cbd"
  g <- fev_fuel_source(num, type = "custom")
  expect_error(fev_fuel_binary(g), class = "fev_missing_register")
  expect_error(fev_fuel_type(g), class = "fev_missing_register")
  expect_error(fev_fuel_availability(g), class = "fev_missing_register")
})

test_that("lidarhd is refused as unimplemented, not as unknown", {
  expect_error(
    fev_fuel_source(synth_class_raster(), type = "lidarhd"),
    class = "fev_not_implemented"
  )
  expect_error(
    fev_fuel_source(synth_class_raster(), type = "nonsense"),
    class = "fev_error"
  )
})

test_that("a custom source has no lookup and says so when one is needed", {
  f <- fev_fuel_source(synth_class_raster(), type = "custom")
  expect_null(f$lookup)
  expect_error(fev_fuel_binary(f), class = "fev_no_lookup")
  # ... but accepts one passed in.
  expect_no_error(fev_fuel_binary(f, lookup = fev_fuel_lookup("bdforet_v2")))
})

test_that("summary counts cells per class and flags what the lookup misses", {
  f <- fev_fuel_source(synth_class_raster(c("FF2-57-57", "NOT-A-CODE")),
                       type = "bdforet_v2", millesime = 2014)
  s <- summary(f)
  expect_s3_class(s, "summary.fev_fuel_source")
  expect_equal(sum(s$classes$cells), 16L)
  expect_equal(s$unmatched, 1L)
})

test_that("print and plot methods run on both registers", {
  f <- fev_fuel_source(synth_class_raster(), type = "bdforet_v2",
                       millesime = 2014)
  expect_no_error(print(f))
  expect_output(print(summary(f)), "FF2-57-57")

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(f))
  expect_error(plot(f, register = "continuous"), class = "fev_error")
})

test_that("fev_data() points a fuel source at the right accessor", {
  f <- fev_fuel_source(synth_class_raster(), type = "bdforet_v2",
                       millesime = 2014)
  expect_error(fev_data(f), class = "fev_error")
  expect_s4_class(fev_data(fev_fuel_binary(f)), "SpatRaster")
})
