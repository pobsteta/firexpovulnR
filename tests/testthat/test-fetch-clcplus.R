# CLCplus Backbone import and correspondence table.
#
# No network: the product is not downloadable without EU Login anyway, which is
# precisely what these tests pin down. Rasters are synthetic and tiny.

clcplus_raster <- function(values, crs = "EPSG:3035", n = 10) {
  r <- terra::rast(nrows = n, ncols = n,
                   xmin = 4050000, xmax = 4050000 + n * 10,
                   ymin = 2300000, ymax = 2300000 + n * 10,
                   crs = crs)
  terra::values(r) <- rep(values, length.out = terra::ncell(r))
  r
}

write_clcplus <- function(values, ...) {
  path <- withr::local_tempfile(fileext = ".tif", .local_envir = parent.frame())
  terra::writeRaster(clcplus_raster(values, ...), path, overwrite = TRUE)
  path
}

test_that("the manual route is refused with an explanation, not a download", {
  expect_error(
    fev_fetch_clcplus(year = 2023),
    class = "fev_clcplus_manual"
  )
  # The message has to name the reason, or a user will file it as a bug.
  expect_error(fev_fetch_clcplus(year = 2023), regexp = "EU Login")
})

test_that("an unpublished vintage is refused", {
  expect_error(fev_fetch_clcplus(file = "x.tif", year = 2019))
  expect_error(fev_fetch_clcplus(file = "x.tif", year = 2019),
               regexp = "2018.*2021.*2023")
})

test_that("a missing file is refused before terra is reached", {
  expect_error(fev_fetch_clcplus(file = "does-not-exist.tif", year = 2023),
               regexp = "does not exist")
})

test_that("codes 254 and 255 become NA, and 253 does not", {
  path <- write_clcplus(c(4L, 254L, 255L, 253L))
  src <- fev_fetch_clcplus(path, year = 2023, crs_work = 3035, quiet = TRUE)
  vals <- terra::values(fev_data(src))

  expect_true(anyNA(vals))
  # 253 is the seawater buffer: a surface, so it survives as a class.
  expect_true(253 %in% vals[!is.na(vals)])
  expect_false(any(vals[!is.na(vals)] %in% c(254, 255)))
  # A quarter of cells were 254 and a quarter 255.
  expect_equal(sum(is.na(vals)), terra::ncell(fev_data(src)) / 2)
})

test_that("absence is counted and reported", {
  path <- write_clcplus(c(4L, 5L, 254L, 2L))
  expect_message(
    fev_fetch_clcplus(path, year = 2023, crs_work = 3035),
    regexp = "outside the product area"
  )
})

test_that("the weak class is warned about, once per session", {
  path <- write_clcplus(c(4L, 5L))
  fev_reset_once()
  expect_warning(
    suppressMessages(fev_fetch_clcplus(path, year = 2023, crs_work = 3035)),
    class = "fev_clcplus_weak_class"
  )
  # Once means once: a second import in the same session stays quiet.
  expect_no_warning(
    suppressMessages(fev_fetch_clcplus(path, year = 2023, crs_work = 3035))
  )
})

test_that("the per-file report is not folded into the once-per-session caveat", {
  # Folding them together hid the cell counts of every import after the first.
  path <- write_clcplus(c(4L, 5L, 254L))
  fev_reset_once()
  suppressWarnings(fev_fetch_clcplus(path, year = 2023, crs_work = 3035))
  expect_message(
    suppressWarnings(fev_fetch_clcplus(path, year = 2023, crs_work = 3035)),
    regexp = "outside the product area"
  )
})

test_that("2023 does not borrow a validation figure from another vintage", {
  path <- write_clcplus(c(4L, 5L))
  expect_message(
    suppressWarnings(fev_fetch_clcplus(path, year = 2023, crs_work = 3035)),
    regexp = "No independent validation figure"
  )
  path2 <- write_clcplus(c(4L, 5L))
  expect_message(
    suppressWarnings(fev_fetch_clcplus(path2, year = 2021, crs_work = 3035)),
    regexp = "85.3"
  )
})

test_that("a raster without a CRS is refused rather than assumed to be 3035", {
  r <- clcplus_raster(c(4L, 5L))
  terra::crs(r) <- ""
  path <- withr::local_tempfile(fileext = ".tif")
  terra::writeRaster(r, path, overwrite = TRUE)

  expect_error(fev_fetch_clcplus(path, year = 2023, quiet = TRUE),
               class = "fev_crs_missing")
})

test_that("reprojection to the working CRS is announced and recorded", {
  path <- write_clcplus(c(4L, 5L))
  expect_message(
    src <- fev_fetch_clcplus(path, year = 2023, crs_work = 2154),
    regexp = "Nearest neighbour"
  )
  expect_true(isTRUE(fev_source_info(src)$reprojected))
})

test_that("quiet silences the standing caveat too, like fev_exposure", {
  path <- write_clcplus(c(4L, 5L))
  fev_reset_once()
  expect_no_warning(
    fev_fetch_clcplus(path, year = 2023, crs_work = 3035, quiet = TRUE)
  )
})

test_that("staying in the native CRS reprojects nothing", {
  path <- write_clcplus(c(4L, 5L))
  src <- fev_fetch_clcplus(path, year = 2023, crs_work = 3035, quiet = TRUE)
  expect_false(isTRUE(fev_source_info(src)$reprojected))
})

test_that("provenance records the manual route and the vintage", {
  path <- write_clcplus(c(4L, 5L))
  info <- fev_source_info(
    fev_fetch_clcplus(path, year = 2021, crs_work = 3035, quiet = TRUE)
  )
  expect_equal(info$millesime, 2021)
  expect_equal(info$import, "local file")
  expect_match(info$query$route, "manual")
  expect_match(info$notes, "does not handle personal tokens")
})

test_that("a non-overlapping AOI is refused", {
  path <- write_clcplus(c(4L, 5L))
  far <- sf::st_as_sf(sf::st_sfc(
    sf::st_polygon(list(cbind(c(0, 100, 100, 0, 0), c(0, 0, 100, 100, 0)))),
    crs = 2154
  ))
  expect_error(
    fev_fetch_clcplus(path, aoi = far, year = 2023, quiet = TRUE),
    class = "fev_no_overlap"
  )
})

test_that("an overlapping AOI crops", {
  path <- write_clcplus(c(4L, 5L), n = 20)
  full <- fev_fetch_clcplus(path, year = 2023, crs_work = 3035, quiet = TRUE)
  bb <- as.vector(terra::ext(fev_data(full)))
  small <- sf::st_as_sf(sf::st_as_sfc(
    sf::st_bbox(c(xmin = bb[["xmin"]], ymin = bb[["ymin"]],
                  xmax = bb[["xmin"]] + 50, ymax = bb[["ymin"]] + 50),
                crs = sf::st_crs(3035))
  ))
  cropped <- fev_fetch_clcplus(path, aoi = small, year = 2023,
                               crs_work = 3035, quiet = TRUE)
  expect_lt(terra::ncell(fev_data(cropped)), terra::ncell(fev_data(full)))
})

# --------------------------------------------------------------------------
# The correspondence table
# --------------------------------------------------------------------------

test_that("the shipped table has the 11 classes plus the seawater buffer", {
  tab <- fev_fuel_lookup("clcplus")
  expect_equal(nrow(tab), 12L)
  expect_setequal(tab$code, c(as.character(1:11), "253"))
  expect_true(all(tab$nomenclature == "clcplus"))
})

test_that("254 and 255 are absent from the table on purpose", {
  tab <- fev_fuel_lookup("clcplus")
  expect_false(any(c("254", "255") %in% tab$code))
})

test_that("every vintage resolves to the same vintage-independent table", {
  base <- fev_fuel_lookup("clcplus")
  for (y in c(2018, 2021, 2023)) {
    expect_equal(fev_fuel_lookup(paste0("clcplus_", y)), base)
  }
})

test_that("clcplus does not silently fall through to the CORINE table", {
  # "clcplus_2023" starts with "clc", so a naive prefix test would load the
  # 44-row CORINE table and match not one code.
  expect_false(identical(fev_fuel_lookup("clcplus_2023"),
                         fev_fuel_lookup("clc_2018")))
  expect_equal(nrow(fev_fuel_lookup("clc_2018")), 44L)
})

test_that("evergreen and deciduous broadleaf are separated, which CORINE cannot", {
  tab <- fev_fuel_lookup("clcplus")
  expect_equal(tab$fuel_type[tab$code == "4"], "sclerophyll_closed")
  expect_equal(tab$fuel_type[tab$code == "3"], "broadleaf_closed")
  # CORINE 311 has to hold both.
  clc <- fev_fuel_lookup("clc")
  expect_equal(clc$fuel_type[clc$code == "311"], "broadleaf_closed")
})

test_that("all three regionally weak classes are recorded, not just the maquis", {
  weak <- firexpovulnR:::.FEV_CLCPLUS_ACCURACY$weak_classes
  # 9 was missed on the first pass: the producers name three classes below the
  # per-class target, not two.
  expect_setequal(weak, c(5L, 8L, 9L))
  expect_equal(firexpovulnR:::.FEV_CLCPLUS_ACCURACY$target_per_class_pct, 85)

  tab <- fev_fuel_lookup("clcplus")
  for (code in as.character(weak)) {
    expect_equal(tab$confidence[tab$code == code], "ambiguous")
  }
})

test_that("the weak class is flagged ambiguous and its note says why", {
  tab <- fev_fuel_lookup("clcplus")
  row <- tab[tab$code == "5", ]
  expect_equal(row$fuel_type, "shrubland")
  expect_true(row$burnable)
  expect_equal(row$confidence, "ambiguous")
  expect_match(row$notes, "WEAKEST CLASS")
})

test_that("every fuel type used is in the shared vocabulary", {
  tab <- fev_fuel_lookup("clcplus")
  expect_true(all(tab$fuel_type %in% fev_fuel_types()$fuel_type))
})

# --------------------------------------------------------------------------
# What a native raster changes for gap repair
# --------------------------------------------------------------------------

test_that("a raster-native source is registered as such", {
  for (y in c(2018, 2021, 2023)) {
    spec <- firexpovulnR:::.FEV_FUEL_MMU[[paste0("clcplus_", y)]]
    expect_equal(spec$native, "raster")
    expect_true(spec$complete)
    # No minimum mapping unit: the smallest representable object is one cell.
    expect_true(is.na(spec$mmu_ha))
    expect_equal(spec$min_width_m, 10)
  }
})

test_that("fev_fuel_mmu separates raster-native from partial coverage", {
  raster_native <- firexpovulnR:::fev_fuel_mmu("clcplus_2023")
  expect_equal(raster_native$reason, "raster_native")
  expect_true(is.na(raster_native$mmu_ha))

  partial <- firexpovulnR:::fev_fuel_mmu("bdforet_v2")
  expect_equal(partial$reason, "partial_coverage")

  vector_complete <- firexpovulnR:::fev_fuel_mmu("clc_2018")
  expect_equal(vector_complete$reason, "mmu")
  expect_equal(vector_complete$mmu_ha, 25)
})

test_that("a mixed merge still lets the vector component license a fill", {
  # CORINE polygons really were rasterised and really do leave slivers, so its
  # unit still applies even when a CLCplus raster sits in the same object.
  mixed <- firexpovulnR:::fev_fuel_mmu(c("clcplus_2023", "clc_2018"))
  expect_equal(mixed$reason, "mmu")
  expect_equal(mixed$mmu_ha, 25)
})

# --------------------------------------------------------------------------
# The resolution floor is a property of the source, not a constant
# --------------------------------------------------------------------------

test_that("the floor follows the source instead of citing BD Foret at everyone", {
  expect_message(firexpovulnR:::fev_check_res(10, "bdforet_v2"),
                 regexp = "minimum mapped width is 20")
  expect_message(firexpovulnR:::fev_check_res(5, "clcplus_2023"),
                 regexp = "minimum mapped width is 10")
})

test_that("an auxiliary source is not scolded for matching the primary's grid", {
  # Regression guard. Reading min_width_m for every source made CORINE at 25 m
  # -- the package's own normal workflow -- emit a "finer than its own detail"
  # notice on every call. An auxiliary source has no choice but to be gridded
  # onto whatever the primary picked.
  expect_no_message(firexpovulnR:::fev_check_res(25, "clc_2018"))
  expect_no_message(firexpovulnR:::fev_check_res(10, "clc_2018"))
  expect_false(firexpovulnR:::.FEV_FUEL_MMU$clc_2018$grid_driver)
  expect_true(firexpovulnR:::.FEV_FUEL_MMU$bdforet_v2$grid_driver)
  expect_true(firexpovulnR:::.FEV_FUEL_MMU$clcplus_2023$grid_driver)
})

test_that("a 10 m source is exactly what the radiant radius needs", {
  # fev_exposure() requires res <= radius / 3, and the radiant radius is 30 m.
  radiant <- fev_exposure_radii()
  r30 <- radiant$max_m[radiant$type == "radiant"]
  expect_equal(r30, 30)
  expect_true(10 <= r30 / 3)
  expect_false(25 <= r30 / 3)
})

# --------------------------------------------------------------------------
# Which tiles to download, since the download is manual
# --------------------------------------------------------------------------

aoi_2154 <- function(xmin, ymin, xmax, ymax) {
  sf::st_sf(geometry = sf::st_sfc(
    sf::st_polygon(list(cbind(c(xmin, xmax, xmax, xmin, xmin),
                              c(ymin, ymin, ymax, ymax, ymin)))),
    crs = 2154
  ))
}

test_that("the tile code is size plus corner in units of that size", {
  # A 100 km tile with its corner at 4 000 000 E, 2 200 000 N is E40N22.
  tiles <- fev_clcplus_tiles(aoi_2154(972000, 6252000, 975000, 6255000))
  expect_equal(nrow(tiles), 1L)
  expect_equal(tiles$tile, "E40N22")
  expect_equal(tiles$xmin, 4.0e6)
  expect_equal(tiles$ymin, 2.2e6)
  expect_equal(tiles$xmax - tiles$xmin, 1e5)
})

test_that("an area straddling a boundary gets every tile, not just one", {
  gpkg <- system.file("extdata", "couchey.gpkg", package = "firexpovulnR")
  skip_if(!nzchar(gpkg), "Couchey extract not installed")
  # Couchey crosses the 2 700 000 m northing, so one tile would leave a gap.
  tiles <- fev_clcplus_tiles(sf::st_read(gpkg, "study_area", quiet = TRUE))
  expect_setequal(tiles$tile, c("E39N26", "E39N27"))
})

test_that("the Maures fit in a single tile", {
  gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
  skip_if(!nzchar(gpkg), "Maures extract not installed")
  tiles <- fev_clcplus_tiles(sf::st_read(gpkg, "study_area", quiet = TRUE))
  expect_equal(tiles$tile, "E40N22")
})

test_that("the returned bounds actually contain the area", {
  aoi <- aoi_2154(972000, 6252000, 975000, 6255000)
  tiles <- fev_clcplus_tiles(aoi)
  bb <- sf::st_bbox(sf::st_transform(aoi, 3035))
  expect_lte(min(tiles$xmin), bb[["xmin"]])
  expect_gte(max(tiles$xmax), bb[["xmax"]])
  expect_lte(min(tiles$ymin), bb[["ymin"]])
  expect_gte(max(tiles$ymax), bb[["ymax"]])
})

test_that("an AOI without a CRS is refused rather than assumed", {
  bad <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_polygon(list(cbind(c(0, 1, 1, 0, 0), c(0, 0, 1, 1, 0))))
  ))
  expect_error(fev_clcplus_tiles(bad))
})

test_that("the manual refusal names the tiles when an AOI is given", {
  aoi <- aoi_2154(972000, 6252000, 975000, 6255000)
  expect_error(fev_fetch_clcplus(aoi = aoi, year = 2023), regexp = "E40N22")
  # And says how to get that help when it cannot.
  expect_error(fev_fetch_clcplus(year = 2023), regexp = "name the tiles")
})

test_that("an area outside the EEA grid is refused, not given a fake tile", {
  # Réunion forced through EPSG:3035 lands at a negative northing and used to
  # come back as "E99N-31" -- arithmetically fine, geographically meaningless.
  re <- sf::st_buffer(
    sf::st_transform(
      sf::st_as_sf(data.frame(lon = 55.5, lat = -21.1),
                   coords = c("lon", "lat"), crs = 4326),
      32740
    ),
    5000
  )
  expect_error(fev_clcplus_tiles(re), class = "fev_outside_eea_grid")
  expect_error(fev_clcplus_tiles(re), regexp = "overseas")
})

test_that("the labels match the producer's own legend", {
  # Verified against the WMS GetLegendGraphic for the 2023 layer, 2026-08-18 --
  # which is what took these labels from "read in a search result" to "read
  # from the provider".
  tab <- fev_fuel_lookup("clcplus")
  expect_equal(tab$label[tab$code == "1"], "Sealed")
  expect_equal(tab$label[tab$code == "5"], "Low-growing woody plants")
  expect_equal(tab$label[tab$code == "9"], "Non and sparsely vegetated")
  expect_equal(tab$label[tab$code == "253"], "Coastal seawater buffer")
})
