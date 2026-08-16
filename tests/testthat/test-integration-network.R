# Live integration tests.
#
# These contact IGN and EFFIS for real. They are skipped unless
# FIREXPOVULNR_TEST_NETWORK is set, so a routine `R CMD check` never depends
# on a third-party service being up -- the brief forbids network-dependent
# tests, and a red check caused by someone else's outage teaches nothing.
#
# Run them deliberately, when you want to know whether an endpoint verified in
# phase 2 still behaves:
#
#   FIREXPOVULNR_TEST_NETWORK=1 Rscript -e 'devtools::test()'
#
# If one of these fails, re-verify the endpoint and update
# specs/phase2-rapport-faisabilite.md along with R/constants.R.

skip_unless_network <- function() {
  if (!nzchar(Sys.getenv("FIREXPOVULNR_TEST_NETWORK"))) {
    skip("network tests disabled (set FIREXPOVULNR_TEST_NETWORK=1)")
  }
  testthat::skip_if_offline()
}

# A small AOI in the Massif des Maures: forested, Mediterranean, and small
# enough that every request below returns in seconds.
maures_aoi <- function() {
  sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 970000, ymin = 6243000, xmax = 975000, ymax = 6248000),
    crs = sf::st_crs(2154)
  )))
}

test_that("BD Forêt v2 WFS still serves the expected schema", {
  skip_unless_network()
  skip_if_not_installed("happign")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  suppressMessages(suppressWarnings(
    bdf <- fev_fetch_bdforet(maures_aoi(), millesime = 2014, dept = "83")
  ))

  d <- fev_data(bdf)
  expect_s3_class(d, "sf")
  expect_gt(nrow(d), 0L)
  expect_true(all(c("code_tfv", "tfv", "tfv_g11", "essence") %in% names(d)))
  # == rather than expect_equal: the WFS returns the CRS as WKT, so $input
  # reads "RGF93 v1 / Lambert-93" rather than "EPSG:2154". Same CRS, different
  # label; sf's == comparison is the one that means what we want to assert.
  expect_true(sf::st_crs(d) == sf::st_crs(2154))

  # The Maures are holm oak and Aleppo pine country. If neither code shows up,
  # either the nomenclature moved or the AOI is not where we think it is.
  expect_true(any(d$code_tfv %in% c("FF1G06-06", "FF2-57-57", "FF1G01-01")))

  expect_equal(fev_source_info(bdf)$millesime, 2014)
  expect_equal(fev_source_info(bdf)$provider, "IGN")
})

test_that("BD Forêt v2 warns when no vintage is supplied", {
  skip_unless_network()
  skip_if_not_installed("happign")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  expect_warning(
    suppressMessages(fev_fetch_bdforet(maures_aoi())),
    class = "fev_millesime_missing"
  )
})

test_that("the cache is used on a second identical BD Forêt request", {
  skip_unless_network()
  skip_if_not_installed("happign")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  suppressMessages(suppressWarnings(
    first <- fev_fetch_bdforet(maures_aoi(), millesime = 2014)
  ))
  t0 <- Sys.time()
  suppressMessages(suppressWarnings(
    second <- fev_fetch_bdforet(maures_aoi(), millesime = 2014)
  ))
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  expect_equal(nrow(fev_data(second)), nrow(fev_data(first)))
  expect_lt(elapsed, 5)

  info <- fev_cache_info()
  expect_true("bdforet_v2" %in% info$dataset)
})

test_that("CORINE 2018 WFS still serves code_18", {
  skip_unless_network()
  skip_if_not_installed("happign")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  suppressMessages(clc <- fev_fetch_corine(maures_aoi(), year = 2018))

  d <- fev_data(clc)
  expect_gt(nrow(d), 0L)
  expect_true("code_18" %in% names(d))
  expect_equal(fev_source_info(clc)$millesime, 2018)
})

test_that("EFFIS still serves burnt areas with FIREDATE", {
  skip_unless_network()
  skip_if_not_installed("httr2")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  # A wider box: burnt areas are sparse, and a 5 km square may hold none.
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.0, ymin = 43.0, xmax = 7.0, ymax = 43.7), crs = sf::st_crs(4326)
  )))

  suppressMessages(suppressWarnings(
    ba <- fev_fetch_burnt(aoi, period = c(2016, 2025))
  ))

  d <- fev_data(ba)
  expect_gt(nrow(d), 0L)
  expect_true(all(c("fire_date", "fire_year", "area_ha") %in% names(d)))
  expect_true(all(d$fire_year >= 2016 & d$fire_year <= 2025))
  expect_true(sf::st_crs(d) == sf::st_crs(2154))
})

test_that("EFFIS coverage still starts around 2016, as recorded in phase 2", {
  skip_unless_network()
  skip_if_not_installed("httr2")
  dir <- withr::local_tempdir()
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir)

  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.0, ymin = 43.0, xmax = 7.0, ymax = 43.7), crs = sf::st_crs(4326)
  )))

  # If this stops warning, the service has extended its public history and
  # .FEV_EFFIS_MIN_YEAR should be revisited -- a welcome failure.
  expect_warning(
    suppressMessages(fev_fetch_burnt(aoi, period = c(2006, 2025))),
    class = "fev_period_truncated"
  )
})

test_that("the BD ORTHO mosaicking graph still serves date_vol", {
  skip_unless_network()
  # The whole vintage recovery rests on this field existing and being a date.
  # If IGN ever drops it, fev_bdforet_millesime() has no route left and the
  # phase 2 blocker comes back -- so it is checked against the live service.
  # The Var has two campaigns in the window, so this warns; the ambiguity has
  # its own test below.
  tab <- suppressWarnings(fev_bdforet_millesime(maures_aoi(), cache = FALSE))
  expect_s3_class(tab, "fev_millesime")
  expect_gt(nrow(tab), 0L)
  expect_true(all(c("dep", "pva", "date_vol", "year", "pct_area") %in%
                    names(tab)))
  expect_true(all(tab$year >= 2007 & tab$year <= 2018))
  # The Maures sit in the Var.
  expect_true("83" %in% tab$dep)
  expect_equal(sum(tab$pct_area), 100, tolerance = 0.5)
})

test_that("the Var's BD ORTHO campaigns are the ones recorded in phase 7", {
  skip_unless_network()
  # Observed 2026-08-16: 2008 and 2014 inside the BD Forêt v2 window. Pinned
  # so a change in the archived graphs is noticed rather than silently
  # changing every vintage the package derives.
  tab <- suppressWarnings(fev_bdforet_millesime(maures_aoi(), cache = FALSE))
  expect_setequal(unique(tab$year), c(2008L, 2014L))
})

test_that("millesime = auto reaches fev_fetch_bdforet", {
  skip_unless_network()
  bdf <- suppressWarnings(
    fev_fetch_bdforet(maures_aoi(), millesime = "auto", cache = FALSE)
  )
  rec <- fev_source_info(bdf)
  expect_false(all(is.na(rec$millesime)))
  expect_true(rec$millesime %in% 2007:2018)
})
