# The brief asks specifically for two properties here: that the merge is
# idempotent, and that the per-pixel source layer is coherent. Both are tested
# against a fixture where the primary genuinely has a gap -- a merge that never
# fills anything would pass either test trivially.

test_that("the auxiliary fills the primary's gaps and nothing else", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))

  expect_s3_class(m, "fev_fuel_source")
  expect_equal(names(fev_fuel_categorical(m)), c("class", "source"))

  prim <- fev_fuel_categorical(p$primary)[["class"]]
  merged <- fev_fuel_categorical(m)[["class"]]

  # Everything the primary mapped, the merge still maps.
  n_prim <- terra::global(!is.na(prim), "sum", na.rm = TRUE)[[1]]
  n_merged <- terra::global(!is.na(merged), "sum", na.rm = TRUE)[[1]]
  expect_gt(n_merged, n_prim)
  # The fixture's primary covers the left half of the AOI.
  expect_equal(n_prim / terra::ncell(prim), 0.5)
  expect_equal(n_merged / terra::ncell(merged), 1)
})

test_that("the per-pixel source layer is coherent with the class layer", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))

  src <- fev_fuel_categorical(m)[["source"]]
  cls <- fev_fuel_categorical(m)[["class"]]
  labels <- terra::levels(src)[[1]]
  expect_setequal(labels$class, c("bdforet_v2", "clc_2018"))

  codes <- terra::levels(cls)[[1]]
  bdf_codes <- terra::levels(fev_fuel_categorical(p$primary)[["class"]])[[1]]$class
  clc_codes <- terra::levels(fev_fuel_categorical(p$secondary)[["class"]])[[1]]$class

  vals <- data.frame(
    src = terra::values(src)[, 1],
    cls = terra::values(cls)[, 1]
  )
  vals$src_lab <- labels$class[match(vals$src, labels$id)]
  vals$cls_lab <- codes$class[match(vals$cls, codes$id)]

  # Every pixel attributed to a source carries a code from that source's own
  # vocabulary. Without this the merged layer cannot be interpreted at all.
  bdf_rows <- vals[!is.na(vals$src_lab) & vals$src_lab == "bdforet_v2", ]
  clc_rows <- vals[!is.na(vals$src_lab) & vals$src_lab == "clc_2018", ]
  expect_true(all(bdf_rows$cls_lab %in% bdf_codes))
  expect_true(all(clc_rows$cls_lab %in% clc_codes))
  expect_gt(nrow(bdf_rows), 0)
  expect_gt(nrow(clc_rows), 0)

  # And a pixel is attributed exactly when it has a class.
  expect_equal(is.na(vals$src), is.na(vals$cls))
})

test_that("primary values are preserved pixel for pixel", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))

  prim <- fev_fuel_categorical(p$primary)[["class"]]
  merged <- fev_fuel_categorical(m)[["class"]]
  p_lv <- terra::levels(prim)[[1]]
  m_lv <- terra::levels(merged)[[1]]

  p_lab <- p_lv$class[match(terra::values(prim)[, 1], p_lv$id)]
  m_lab <- m_lv$class[match(terra::values(merged)[, 1], m_lv$id)]

  keep <- !is.na(p_lab)
  expect_equal(m_lab[keep], p_lab[keep])
})

test_that("merging is idempotent", {
  p <- synth_fuel_pair()
  once <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  twice <- suppressMessages(fev_fuel_merge(once, p$secondary))

  expect_equal(terra::values(fev_fuel_categorical(once)),
               terra::values(fev_fuel_categorical(twice)))
  expect_equal(terra::levels(fev_fuel_categorical(once)),
               terra::levels(fev_fuel_categorical(twice)))
  expect_equal(once$lookup, twice$lookup)
  expect_equal(once$type, twice$type)
  expect_equal(once$millesime, twice$millesime)

  # The provenance is deliberately NOT idempotent: doing the same operation
  # twice is a fact about the analysis, and the record says what happened.
  expect_gt(length(twice$provenance$steps), length(once$provenance$steps))
  # Sources, on the other hand, are de-duplicated -- CORINE was fetched once.
  expect_equal(length(once$provenance$sources),
               length(twice$provenance$sources))
})

test_that("a pixel already attributed keeps its original source", {
  # This is what makes idempotence hold: a second merge must not relabel
  # BD Forêt pixels as coming from the auxiliary.
  p <- synth_fuel_pair()
  once <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  twice <- suppressMessages(fev_fuel_merge(once, p$secondary))

  s1 <- fev_fuel_categorical(once)[["source"]]
  s2 <- fev_fuel_categorical(twice)[["source"]]
  l1 <- terra::levels(s1)[[1]]
  l2 <- terra::levels(s2)[[1]]
  expect_equal(l1$class[match(terra::values(s1)[, 1], l1$id)],
               l2$class[match(terra::values(s2)[, 1], l2$id)])
})

test_that("hierarchy = secondary_first swaps which source wins", {
  p <- synth_fuel_pair()
  a <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  b <- suppressMessages(
    fev_fuel_merge(p$primary, p$secondary, hierarchy = "secondary_first")
  )

  share <- function(m, label) {
    src <- fev_fuel_categorical(m)[["source"]]
    lv <- terra::levels(src)[[1]]
    v <- lv$class[match(terra::values(src)[, 1], lv$id)]
    mean(v == label, na.rm = TRUE)
  }
  expect_equal(share(a, "clc_2018"), 0.5)
  expect_equal(share(b, "clc_2018"), 1)
})

test_that("the merged lookup is the union of both vocabularies", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  expect_equal(nrow(m$lookup), 32L + 44L)
  expect_equal(anyDuplicated(m$lookup$code), 0L)
  expect_setequal(unique(m$lookup$nomenclature), c("bdforet_v2", "clc"))
})

test_that("components and vintages are tracked per source, not collapsed", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  expect_equal(m$type, "bdforet_v2+clc_2018")
  expect_equal(m$millesime$bdforet_v2, 2014)
  expect_equal(m$millesime$clc_2018, 2018)
})

test_that("the merge reports how much the auxiliary contributed", {
  p <- synth_fuel_pair()
  m <- suppressMessages(fev_fuel_merge(p$primary, p$secondary))
  step <- m$provenance$steps[[length(m$provenance$steps)]]
  expect_equal(step$fun, "fev_fuel_merge")
  expect_equal(step$params$pct_filled_by_secondary, 50)
  expect_equal(step$params$cells_filled_by_secondary, 32L)
})

test_that("a mismatched auxiliary grid is realigned, loudly", {
  aoi <- synth_fuel_aoi()
  primary <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 25,
                             aoi = aoi, millesime = 2014)
  coarse <- fev_fuel_source(synth_clc(), type = "clc_2018", res = 50,
                            aoi = aoi, millesime = 2018)
  expect_warning(
    m <- fev_fuel_merge(primary, coarse),
    class = "fev_categorical_resampled"
  )
  # The primary's grid is the one that survives -- it is never resampled.
  expect_equal(terra::res(fev_fuel_categorical(m)), c(25, 25))
})

test_that("a mismatched auxiliary CRS is reprojected, loudly, never the primary", {
  aoi <- synth_fuel_aoi()
  primary <- fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 25,
                             aoi = aoi, millesime = 2014)
  other <- suppressWarnings(
    fev_fuel_source(synth_clc(), type = "clc_2018", res = 25, crs_work = 3035,
                    millesime = 2018)
  )
  expect_warning(
    m <- fev_fuel_merge(primary, other),
    class = "fev_categorical_reprojected"
  )
  expect_equal(fev_crs_label(fev_fuel_categorical(m)), "EPSG:2154")
})

test_that("two vocabularies using one code for different fuel are refused", {
  # Neither shipped nomenclature can collide -- TFV codes are alphanumeric,
  # CORINE codes are three digits -- but a custom vocabulary can, and a silent
  # collision attributes pixels to the wrong fuel type with no symptom.
  aoi <- synth_fuel_aoi()
  a <- fev_fuel_source(synth_class_raster("323"), type = "custom",
                       lookup = fev_fuel_lookup("clc"))
  bad <- fev_fuel_lookup("clc")
  bad$fuel_type[bad$code == "323"] <- "non_fuel"
  bad$burnable[bad$code == "323"] <- FALSE
  b <- fev_fuel_source(synth_class_raster("323"), type = "custom", lookup = bad)
  expect_error(fev_fuel_merge(a, b), class = "fev_code_collision")
})

test_that("merging needs a categorical register on both sides", {
  p <- synth_fuel_pair()
  num <- synth_raster(values = 1)
  names(num) <- "cbd"
  cont <- fev_fuel_source(num, type = "custom")
  expect_error(fev_fuel_merge(p$primary, cont), class = "fev_missing_register")
  expect_error(fev_fuel_merge(cont, p$primary), class = "fev_missing_register")
  expect_error(fev_fuel_merge(p$primary, "not a source"), class = "fev_error")
})
