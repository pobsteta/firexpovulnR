# ESA WorldCover import and its place in the hierarchy.
#
# The fetch itself needs the network, so those tests skip offline. Everything
# that can be decided without it -- tile arithmetic, the lookup, the ranking --
# runs always.

test_that("tiles are named by their south-west corner, floored to 3 degrees", {
  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(6.35, 43.3)), crs = 4326))
  t1 <- fev_worldcover_tiles(sf::st_buffer(pt, 0.05))
  expect_equal(t1$tile, "N42E006")
  expect_equal(t1$xmin, 6)
  expect_equal(t1$ymin, 42)
  expect_equal(t1$xmax - t1$xmin, 3)
})

test_that("an area straddling a tile boundary gets both", {
  bb <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 8.9, ymin = 43, xmax = 9.1, ymax = 43.2), crs = sf::st_crs(4326)
  )))
  expect_setequal(fev_worldcover_tiles(bb)$tile, c("N42E006", "N42E009"))
})

test_that("southern and western hemispheres get S and W", {
  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-55.5, -21.1)),
                                        crs = 4326))
  tl <- fev_worldcover_tiles(sf::st_buffer(pt, 0.05))
  expect_match(tl$tile, "^S")
  expect_match(tl$tile, "W")
})

test_that("the shipped extracts land on the tiles expected", {
  for (nm in c("maures", "couchey")) {
    gpkg <- system.file("extdata", paste0(nm, ".gpkg"),
                        package = "firexpovulnR")
    skip_if(!nzchar(gpkg), "extract not installed")
    tl <- fev_worldcover_tiles(sf::st_read(gpkg, "study_area", quiet = TRUE))
    expect_true(all(grepl("^N\\d{2}E\\d{3}$", tl$tile)))
  }
})

test_that("the URL follows the published pattern", {
  u <- firexpovulnR:::fev_worldcover_url("N42E006", "v200", 2021)
  expect_match(u, "^/vsicurl/")
  expect_match(u, "ESA_WorldCover_10m_2021_v200_N42E006_Map\\.tif$")
  expect_match(u, "v200/2021/map/")
})

test_that("an unpublished vintage is refused", {
  aoi <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(6.35, 43.3)),
                                         crs = 4326))
  expect_error(fev_fetch_worldcover(sf::st_buffer(aoi, 0.05), year = 2019))
})

# --------------------------------------------------------------------------
# The correspondence table
# --------------------------------------------------------------------------

test_that("the shipped table has the 11 published classes", {
  tab <- fev_fuel_lookup("worldcover")
  expect_equal(nrow(tab), 11L)
  expect_setequal(tab$code,
                  as.character(c(10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100)))
  expect_equal(tab$label[tab$code == "20"], "Shrubland")
  expect_equal(tab$label[tab$code == "10"], "Tree cover")
})

test_that("code 0 is absent: it is nodata, not a class", {
  expect_false("0" %in% fev_fuel_lookup("worldcover")$code)
  expect_equal(firexpovulnR:::.FEV_WORLDCOVER_NODATA, 0L)
})

test_that("worldcover does not fall through to another table", {
  expect_equal(nrow(fev_fuel_lookup("worldcover_2021")), 11L)
  expect_equal(fev_fuel_lookup("worldcover_2020"), fev_fuel_lookup("worldcover"))
  expect_false(identical(fev_fuel_lookup("worldcover"),
                         fev_fuel_lookup("clc")))
  expect_equal(nrow(fev_fuel_lookup("clc")), 44L)
})

test_that("the shrub class is flagged ambiguous, with the measurement in its note", {
  row <- fev_fuel_lookup("worldcover")
  row <- row[row$code == "20", ]
  expect_equal(row$fuel_type, "shrubland")
  expect_true(row$burnable)
  expect_equal(row$confidence, "ambiguous")
  expect_match(row$notes, "0.688")
})

test_that("every fuel type used is in the shared vocabulary", {
  tab <- fev_fuel_lookup("worldcover")
  expect_true(all(tab$fuel_type %in% fev_fuel_types()$fuel_type))
})

# --------------------------------------------------------------------------
# Where it sits when two sources compete
# --------------------------------------------------------------------------

mk_source <- function(type, code, n = 8, res = 25, millesime = 2014) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
                   ymin = 0, ymax = n * res, crs = "EPSG:2154")
  terra::values(r) <- rep(code, terra::ncell(r))
  levels(r) <- data.frame(id = code, class = as.character(code))
  names(r) <- "class"
  suppressMessages(fev_fuel_source(r, type = type, res = res,
                                   millesime = millesime,
                                   register = "categorical"))
}

test_that("WorldCover outranks BD Foret whichever position it is passed in", {
  wc <- mk_source("worldcover_2021", 20)
  bd <- mk_source("bdforet_v2", 20)

  a <- suppressWarnings(suppressMessages(fev_fuel_merge(bd, wc)))
  b <- suppressWarnings(suppressMessages(fev_fuel_merge(wc, bd)))
  winner <- function(m) {
    lv <- terra::levels(fev_fuel_categorical(m)[["source"]])[[1]]
    lv$class[1]
  }
  expect_equal(winner(a), "worldcover_2021")
  expect_equal(winner(b), "worldcover_2021")
})

test_that("the ranking is a property of the type, not of argument order", {
  h <- firexpovulnR:::fev_fuel_rank_hierarchy
  expect_equal(h(mk_source("bdforet_v2", 20), mk_source("worldcover_2021", 20)),
               "secondary_first")
  expect_equal(h(mk_source("worldcover_2021", 20), mk_source("bdforet_v2", 20)),
               "primary_first")
  # BD Forêt over CORINE, which is what every earlier version did.
  expect_equal(h(mk_source("bdforet_v2", 20), mk_source("clc_2018", 323)),
               "primary_first")
  expect_equal(h(mk_source("clc_2018", 323), mk_source("bdforet_v2", 20)),
               "secondary_first")
})

test_that("an unrankable source falls back to argument order", {
  h <- firexpovulnR:::fev_fuel_rank_hierarchy
  expect_equal(h(mk_source("custom", 1), mk_source("worldcover_2021", 20)),
               "primary_first")
  expect_equal(h(mk_source("bdforet_v2", 20), mk_source("custom", 1)),
               "primary_first")
})

test_that("an explicit hierarchy still overrides the ranking", {
  wc <- mk_source("worldcover_2021", 20)
  bd <- mk_source("bdforet_v2", 20)
  m <- suppressWarnings(suppressMessages(
    fev_fuel_merge(bd, wc, hierarchy = "primary_first")
  ))
  lv <- terra::levels(fev_fuel_categorical(m)[["source"]])[[1]]
  expect_equal(lv$class[1], "bdforet_v2")
})

test_that("a source that fills nothing is announced as a replacement", {
  # The consequence of putting a complete-coverage raster on top, which the
  # word "merge" makes easy to miss.
  wc <- mk_source("worldcover_2021", 20)
  bd <- mk_source("bdforet_v2", 20)
  expect_warning(suppressMessages(fev_fuel_merge(bd, wc)),
                 class = "fev_merge_no_contribution")
})

# --------------------------------------------------------------------------
# The fetch itself
# --------------------------------------------------------------------------

test_that("the window is read without downloading a tile", {
  # The package's own gate, not a weaker one of this file's invention: a
  # routine check must never reach the network.
  skip_unless_network()
  gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
  skip_if(!nzchar(gpkg), "Maures extract not installed")

  aoi <- sf::st_read(gpkg, "lidar_squares", quiet = TRUE)
  src <- suppressWarnings(fev_fetch_worldcover(aoi, year = 2021, quiet = TRUE))
  r <- fev_data(src)

  expect_s4_class(r, "SpatRaster")
  # A whole tile is 36 000 square; a couple of 500 m plots must be far smaller.
  expect_lt(terra::ncell(r), 1e6)
  expect_false(is.null(firexpovulnR:::fev_cat_levels(r)))
  expect_equal(fev_source_info(src)$millesime, 2021L)
  expect_match(fev_source_info(src)$query$read, "no tile downloaded")
})
