# No test in this file touches the network. Live integration tests live in
# test-integration-network.R and are skipped unless explicitly enabled.

local_cache <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir, .local_envir = env)
  dir
}

# fev_as_aoi -------------------------------------------------------------------

test_that("fev_as_aoi accepts the shapes users actually have", {
  as_aoi <- firexpovulnR:::fev_as_aoi
  r <- synth_raster()

  expect_s3_class(as_aoi(synth_aoi(r)), "sf")
  expect_s3_class(as_aoi(sf::st_geometry(synth_aoi(r))), "sf")
  expect_s3_class(as_aoi(sf::st_bbox(synth_aoi(r))), "sf")
  expect_s3_class(as_aoi(r), "sf")
  expect_s3_class(as_aoi(terra::vect(synth_aoi(r))), "sf")
})

test_that("fev_as_aoi refuses a missing CRS instead of assuming one", {
  as_aoi <- firexpovulnR:::fev_as_aoi
  aoi <- synth_aoi()
  sf::st_crs(aoi) <- NA

  expect_error(as_aoi(aoi), class = "fev_error")
  expect_error(as_aoi(NULL), class = "fev_error")
  expect_error(as_aoi(1:4), class = "fev_error")
})

test_that("fev_as_aoi reprojects to the requested CRS", {
  aoi <- firexpovulnR:::fev_as_aoi(synth_aoi(), crs = 4326)
  expect_true(sf::st_is_longlat(aoi))
})

# fev_source -------------------------------------------------------------------

test_that("a fev_source carries data and its record separately", {
  s <- firexpovulnR:::new_fev_source(
    synth_aoi(), dataset = "demo", provider = "test", millesime = 2014
  )

  expect_s3_class(s, "fev_source")
  expect_s3_class(fev_data(s), "sf")
  expect_equal(fev_source_info(s)$dataset, "demo")
  expect_equal(fev_source_info(s)$millesime, 2014)
  expect_false(is.na(fev_source_info(s)$downloaded_at))
  expect_equal(fev_source_info(s)$n_features, 1L)
})

test_that("printing a source names an unknown vintage as unknown", {
  # A silently missing vintage is how a temporal-bias check ends up never
  # running. It must be visible in the default print.
  s <- firexpovulnR:::new_fev_source(synth_aoi(), dataset = "bdforet_v2")
  expect_snapshot_output(print(s))
})

test_that("accessors reject anything that is not a fev_source", {
  expect_error(fev_data(synth_aoi()), class = "fev_error")
  expect_error(fev_source_info(1:5), class = "fev_error")
})

# Period handling --------------------------------------------------------------

test_that("period parsing accepts years and dates, and rejects nonsense", {
  py <- firexpovulnR:::fev_period_years

  expect_equal(py(c("2016", "2025")), c(2016L, 2025L))
  expect_equal(py(c(2016, 2025)), c(2016L, 2025L))
  expect_equal(py(c("2016-01-01", "2025-12-31")), c(2016L, 2025L))

  expect_error(py(c("2025", "2016")), class = "fev_error")
  expect_error(py("2016"), class = "fev_error")
  expect_error(py(c("abcd", "efgh")), class = "fev_error")
})

# Burnt area preparation -------------------------------------------------------

synth_burnt <- function(years = c(2016, 2018, 2020, 2023), crs = 4326) {
  geoms <- lapply(seq_along(years), function(i) {
    sf::st_polygon(list(cbind(
      c(6.3, 6.31, 6.31, 6.3, 6.3) + i * 0.02,
      c(43.2, 43.2, 43.21, 43.21, 43.2)
    )))
  })
  sf::st_sf(
    FIREDATE = paste0(years, "-07-15 00:00:00"),
    AREA_HA  = as.character(c(120, 340, 55, 900)[seq_along(years)]),
    COUNTRY  = "FR",
    geometry = sf::st_sfc(geoms, crs = crs)
  )
}

test_that("burnt area preparation parses EFFIS string columns", {
  # EFFIS delivers every attribute as a string, AREA_HA included.
  prep <- firexpovulnR:::fev_burnt_prepare
  out <- prep(synth_burnt(), crs_work = 2154)

  expect_s3_class(out$fire_date, "Date")
  expect_equal(out$fire_year, c(2016L, 2018L, 2020L, 2023L))
  expect_type(out$area_ha, "double")
  expect_equal(out$area_ha[1], 120)
  expect_true(sf::st_crs(out) == sf::st_crs(2154))
})

test_that("an unset CRS is forced to 4326 with an explicit message", {
  # EFFIS ships a .prj declaring GCS_unknown for plain WGS84 data. Forcing it
  # is correct; forcing it silently is not.
  prep <- firexpovulnR:::fev_burnt_prepare
  ba <- synth_burnt()
  sf::st_crs(ba) <- NA

  expect_message(out <- prep(ba, crs_work = 2154), regexp = "forcing")
  expect_true(sf::st_crs(out) == sf::st_crs(2154))
})

test_that("missing or unparseable FIREDATE fails with a useful message", {
  prep <- firexpovulnR:::fev_burnt_prepare

  no_date <- synth_burnt()
  no_date$FIREDATE <- NULL
  expect_error(prep(no_date, 2154), class = "fev_error")

  bad_date <- synth_burnt()
  bad_date$FIREDATE <- "not-a-date"
  expect_error(prep(bad_date, 2154), class = "fev_error")
})

test_that("area falls back to computed geometry when AREA_HA is absent", {
  prep <- firexpovulnR:::fev_burnt_prepare
  ba <- synth_burnt()
  ba$AREA_HA <- NULL

  out <- prep(ba, crs_work = 2154)
  expect_true(all(out$area_ha > 0))
})

# fev_fetch_burnt, local-file path ---------------------------------------------

test_that("fev_fetch_burnt reads a local extract and filters on period", {
  local_cache()
  f <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(synth_burnt(), f, quiet = TRUE)

  suppressMessages(
    ba <- fev_fetch_burnt(synth_aoi(synth_raster(crs = "EPSG:2154")),
                          period = c(2018, 2020), file = f)
  )

  expect_s3_class(ba, "fev_source")
  expect_equal(nrow(fev_data(ba)), 2L)
  expect_equal(fev_source_info(ba)$period_returned, "2018-2020")
  expect_equal(fev_source_info(ba)$period_requested, "2018-2020")
  expect_match(fev_source_info(ba)$crs_override, "EPSG:4326")
})

test_that("requesting years before the source starts warns with numbers", {
  # The brief's target workflow asks for 2006; the public endpoint serves
  # 2016 onward. Believing you validated on eighteen years while validating
  # on ten is the failure this warning exists to prevent.
  local_cache()
  f <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(synth_burnt(), f, quiet = TRUE)

  expect_warning(
    suppressMessages(
      ba <- fev_fetch_burnt(synth_aoi(), period = c(2006, 2023), file = f)
    ),
    class = "fev_period_truncated"
  )
  expect_equal(fev_source_info(ba)$period_returned, "2016-2023")
})

test_that("an empty period selection fails with counts, not a bare error", {
  local_cache()
  f <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(synth_burnt(), f, quiet = TRUE)

  expect_error(
    suppressMessages(suppressWarnings(
      fev_fetch_burnt(synth_aoi(), period = c(1990, 1995), file = f)
    )),
    class = "fev_empty_result"
  )
})

test_that("a missing local file is reported with the request-form hint", {
  local_cache()
  expect_error(
    fev_fetch_burnt(synth_aoi(), file = "/nonexistent/burnt.gpkg"),
    class = "fev_error"
  )
})

# fev_fetch_corine, local-file path --------------------------------------------

test_that("fev_fetch_corine validates a local file and clips it", {
  local_cache()
  aoi <- synth_aoi(synth_raster(res = 1000))
  clc <- sf::st_sf(
    code_18 = c("323", "112", "512"),
    geometry = sf::st_geometry(sf::st_as_sf(sf::st_make_grid(aoi, n = c(3, 1))))
  )
  f <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(clc, f, quiet = TRUE)

  suppressMessages(
    src <- fev_fetch_corine(aoi, year = 2018, file = f)
  )

  expect_s3_class(src, "fev_source")
  expect_equal(fev_source_info(src)$millesime, 2018)
  expect_equal(fev_source_info(src)$mmu_ha, 25)
  expect_equal(fev_source_info(src)$import, "local file")
})

test_that("fev_fetch_corine rejects a bad year, missing file or wrong column", {
  local_cache()
  aoi <- synth_aoi()

  expect_error(fev_fetch_corine(aoi, year = 2019), class = "fev_error")
  expect_error(fev_fetch_corine(aoi, file = "/nope.gpkg"), class = "fev_error")

  clc <- sf::st_sf(wrong_col = "323", geometry = sf::st_geometry(aoi))
  f <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(clc, f, quiet = TRUE)
  expect_error(suppressMessages(fev_fetch_corine(aoi, file = f)),
               class = "fev_error")
})

test_that("a CORINE file with no CRS is refused, not assumed to be 3035", {
  local_cache()
  aoi <- synth_aoi()
  clc <- sf::st_sf(code_18 = "323", geometry = sf::st_geometry(aoi))
  sf::st_crs(clc) <- NA
  f <- withr::local_tempfile(fileext = ".shp")
  suppressWarnings(sf::st_write(clc, f, quiet = TRUE))

  expect_error(suppressMessages(fev_fetch_corine(aoi, file = f)),
               class = "fev_crs_missing")
})

# fev_fetch_fwi, offline request building --------------------------------------

test_that("the EWDS request is built with verified identifiers", {
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.2, ymin = 43.1, xmax = 6.6, ymax = 43.4), crs = sf::st_crs(4326)
  ))
  req <- fev_fetch_fwi(aoi, period = c("2020-01-01", "2021-12-31"),
                       transfer = FALSE)

  expect_equal(req$dataset_short_name, "cems-fire-historical-v1")
  expect_equal(req$product_type, "reanalysis")
  expect_equal(req$dataset_type, "consolidated_dataset")
  expect_equal(req$year, c("2020", "2021"))
  expect_true("fire_weather_index" %in% req$variable)
  expect_true("drought_code" %in% req$variable)
})

test_that("the EWDS area is North/West/South/East, not xmin/ymin/xmax/ymax", {
  # Getting this order wrong returns a valid raster for the wrong place --
  # the worst kind of failure, because nothing errors.
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.2, ymin = 43.1, xmax = 6.6, ymax = 43.4), crs = sf::st_crs(4326)
  ))
  req <- fev_fetch_fwi(aoi, period = c(2020, 2020), transfer = FALSE)

  expect_equal(req$area, c(43.4, 6.2, 43.1, 6.6))
})

test_that("the FWI request reprojects a projected AOI to lon/lat", {
  aoi <- synth_aoi(synth_raster(origin = c(970000, 6243000), res = 1000))
  req <- fev_fetch_fwi(aoi, period = c(2020, 2020), transfer = FALSE)

  # Massif des Maures: roughly 6.4E, 43.3N.
  expect_true(req$area[2] > 5 && req$area[2] < 8)
  expect_true(req$area[1] > 42 && req$area[1] < 45)
})

test_that("missing credentials are reported without leaking any token", {
  withr::local_envvar(ECMWF_KEY = "")
  skip_if_not_installed("ecmwfr")

  err <- tryCatch(
    firexpovulnR:::fev_fwi_credentials(user = "fev-no-such-user"),
    condition = function(e) e
  )
  # Either it aborts with our class, or a keyring entry exists on this
  # machine; both are acceptable, but it must never print a key.
  if (inherits(err, "error")) {
    expect_s3_class(err, "fev_no_credentials")
    expect_no_match(conditionMessage(err), "[A-Za-z0-9]{32,}")
  } else {
    succeed()
  }
})
