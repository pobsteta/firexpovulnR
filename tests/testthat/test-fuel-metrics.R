test_that("the burnable mask is 0/1 and follows the lookup", {
  f <- fev_fuel_source(synth_class_raster(c("FF2-57-57", "LA4")),
                       type = "bdforet_v2", millesime = 2014)
  b <- fev_fuel_binary(f)
  expect_s3_class(b, "fev_fuel_layer")
  r <- fev_data(b)
  expect_equal(names(r), "burnable")
  expect_setequal(terra::unique(r)[, 1], 1)

  # A non-burnable class comes back as 0, not NA.
  g <- fev_fuel_source(synth_class_raster(c("323", "512")), type = "clc_2018")
  vals <- terra::unique(fev_data(fev_fuel_binary(g)))[, 1]
  expect_setequal(vals, c(0, 1))
})

test_that("NA in the source stays NA in the mask", {
  r <- synth_class_raster(c("FF2-57-57", "LA4"))
  v <- terra::values(r)
  v[1:4] <- NA
  terra::values(r) <- v
  levels(r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
  names(r) <- "class"
  f <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
  out <- terra::values(fev_data(fev_fuel_binary(f)))[, 1]
  expect_equal(sum(is.na(out)), 4L)
})

test_that("an unmatched class becomes NA and is reported with numbers", {
  # Silently calling an unknown class non-burnable would understate exposure
  # exactly where the data is weakest, so it must be NA and it must be loud.
  f <- fev_fuel_source(synth_class_raster(c("FF2-57-57", "NOT-A-CODE")),
                       type = "bdforet_v2", millesime = 2014)
  expect_warning(b <- fev_fuel_binary(f), class = "fev_unmatched_class")
  out <- terra::values(fev_data(b))[, 1]
  expect_equal(sum(is.na(out)), 8L)
  expect_false(any(out == 0, na.rm = TRUE))

  step <- b$provenance$steps[[length(b$provenance$steps)]]
  expect_equal(step$params$unmatched_classes, "NOT-A-CODE")
  expect_equal(step$params$pct_cells_unmatched, 50)
})

test_that("fuel types come back as a categorical layer of the vocabulary", {
  f <- fev_fuel_source(synth_class_raster(c("FF1G06-06", "LA4")),
                       type = "bdforet_v2", millesime = 2014)
  ft <- fev_fuel_type(f)
  lv <- terra::levels(fev_data(ft))[[1]]
  expect_setequal(lv$class, c("sclerophyll_closed", "shrubland"))
  expect_true(all(lv$class %in% fev_fuel_types()$fuel_type))
  expect_equal(names(fev_data(ft)), "fuel_type")
})

test_that("two nomenclatures reaching the same fuel type merge into one class", {
  # CLC 322 and 323 are both shrubland: the point of a shared vocabulary is
  # that a merged layer has one shrubland class, not two.
  f <- fev_fuel_source(synth_class_raster(c("322", "323")), type = "clc_2018")
  lv <- terra::levels(fev_data(fev_fuel_type(f)))[[1]]
  expect_equal(nrow(lv), 1L)
  expect_equal(lv$class, "shrubland")
})

test_that("fuel type refuses when nothing in the layer is in the lookup", {
  f <- fev_fuel_source(synth_class_raster(c("XX", "YY")), type = "custom",
                       lookup = fev_fuel_lookup("bdforet_v2"))
  expect_error(suppressWarnings(fev_fuel_type(f)), class = "fev_no_match")
})

test_that("availability grades the mask instead of flattening it", {
  f <- fev_fuel_source(synth_class_raster(c("FF1-09-09", "LA4")),
                       type = "bdforet_v2", millesime = 2014)
  w <- fev_fuel_weights(quiet = TRUE)
  av <- fev_fuel_availability(f, weights = w)
  vals <- sort(terra::unique(fev_data(av))[, 1])
  # Beech (broadleaf_closed) below heath (shrubland), both burnable.
  expect_equal(vals, sort(unname(w[c("broadleaf_closed", "shrubland")])))
  expect_true(all(vals >= 0 & vals <= 1))
})

test_that("availability and the burnable mask agree on every pixel", {
  # The invariant that keeps the two functions from contradicting each other:
  # weight > 0 exactly where the mask says 1.
  f <- fev_fuel_source(synth_class_raster(c("323", "512", "211")),
                       type = "clc_2018")
  w <- fev_fuel_weights(quiet = TRUE)
  mask <- terra::values(fev_data(fev_fuel_binary(f)))[, 1]
  av <- terra::values(fev_data(fev_fuel_availability(f, weights = w)))[, 1]
  expect_equal(av > 0, mask == 1)
})

test_that("availability refuses weights that do not cover the lookup", {
  f <- fev_fuel_source(synth_class_raster(c("FF2-57-57", "LA4")),
                       type = "bdforet_v2", millesime = 2014)
  w <- fev_fuel_weights(quiet = TRUE)
  expect_error(fev_fuel_availability(f, weights = w[1:3]),
               class = "fev_missing_weight")
})

test_that("the weights actually used are written into the provenance", {
  # Whatever numbers produced the result must be readable six months later,
  # including the ones the caller never typed.
  f <- fev_fuel_source(synth_class_raster(c("FF2-57-57", "LA4")),
                       type = "bdforet_v2", millesime = 2014)
  w <- fev_fuel_weights(c(shrubland = 0.5), quiet = TRUE)
  av <- fev_fuel_availability(f, weights = w)
  step <- av$provenance$steps[[length(av$provenance$steps)]]
  expect_equal(step$params$weights$shrubland, 0.5)
  expect_false(step$params$weights_sourced)
})

test_that("derived layers carry the provenance of the source they came from", {
  aoi <- synth_fuel_aoi()
  f <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50,
                       aoi = aoi, millesime = 2014)
  b <- fev_fuel_binary(f)
  funs <- vapply(b$provenance$steps, function(s) s$fun, character(1))
  expect_equal(funs, c("fev_fuel_source", "fev_fuel_binary"))
  expect_equal(b$provenance$sources[[1]]$millesime, 2014)
})

test_that("a merged source produces layers across both vocabularies", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  b <- fev_fuel_binary(m)
  # The CORINE half of the fixture is water, so the mask must contain both
  # values and no NA -- one lookup, two vocabularies, full coverage.
  vals <- terra::values(fev_data(b))[, 1]
  expect_false(anyNA(vals))
  expect_setequal(unique(vals), c(0, 1))

  ft <- fev_fuel_type(m)
  # Aleppo pine and holm oak from BD Forêt on the left half; sclerophyllous
  # vegetation and water from CORINE on the right.
  expect_setequal(terra::levels(fev_data(ft))[[1]]$class,
                  c("conifer_closed", "sclerophyll_closed", "shrubland",
                    "non_fuel"))
})

test_that("fuel layers print and plot", {
  f <- fev_fuel_source(synth_class_raster(), type = "bdforet_v2",
                       millesime = 2014)
  # cli writes through its own connection, so the assertion is that the
  # methods run over both a numeric and a categorical layer, not on the text.
  expect_no_error(print(fev_fuel_binary(f)))
  expect_no_error(print(fev_fuel_type(f)))

  pdf(NULL)
  on.exit(dev.off(), add = TRUE)
  expect_no_error(plot(fev_fuel_binary(f)))
})
