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

# Opt-in is an explicit truthy value, not merely a non-empty one. The workflow
# sets FIREXPOVULNR_TEST_NETWORK: "0" to mean off, and nzchar("0") is TRUE -- so
# every one of these ran in CI, and stayed green only for as long as IGN and
# EFFIS did. The first DNS timeout at data.geopf.fr turned the check red, which
# is precisely what the brief forbids.
# skip_unless_network() now lives in helper-network.R, shared by every test
# that touches the network.

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

# --- Open-Meteo, the token-free weather route ---------------------------------

test_that("Open-Meteo still serves the four FWI variables without a key", {
  skip_unless_network()
  # The whole point of this route is that it needs no credential. If that ever
  # changes, this is where it shows -- and no key is read here, deliberately.
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(maures_aoi(), period = c("2021-08-14", "2021-08-16"),
                      cache = FALSE)
  ))
  tab <- fev_data(w)
  expect_s3_class(w, "fev_source")
  expect_setequal(unique(tab$day), c(14L, 15L, 16L))
  expect_true(all(c("temp", "rh", "ws", "prec") %in% names(tab)))
  expect_true(isTRUE(w$source$third_party))
})

test_that("the Maures on 16 August 2021 come back as recorded in phase 9", {
  skip_unless_network()
  # Observed 2026-08-17 at the reanalysis point nearest the Cannet-des-Maures
  # fire, 43.3 N / 6.4 E: 33.8 C, 21 % relative humidity, 25.6 km/h.
  #
  # Pinned because these four numbers are what the shipped Maures article's
  # danger map rests on. A drift here means the archive was revised, and the
  # article's figures need regenerating rather than quietly disagreeing with
  # their caption.
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(maures_aoi(), period = c("2021-08-16", "2021-08-16"),
                      cache = FALSE)
  ))
  tab <- fev_data(w)
  row <- tab[abs(tab$lat - 43.3) < 1e-8 & abs(tab$long - 6.4) < 1e-8, ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$temp, 33.8, tolerance = 0.05)
  expect_equal(row$rh, 21, tolerance = 0.05)
  expect_equal(row$ws, 25.6, tolerance = 0.05)
  expect_equal(row$prec, 0, tolerance = 1e-8)
})

test_that("wind is served in km/h, not m/s", {
  skip_unless_network()
  # The single most consequential unit trap in the FWI system: E-OBS serves FG
  # in m/s, and treating it as km/h understates ISI by a factor of 3.6. A
  # August afternoon in the Maures at 25 km/h would be 25 m/s -- 90 km/h -- if
  # this ever silently changed.
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(maures_aoi(), period = c("2021-08-16", "2021-08-16"),
                      cache = FALSE)
  ))
  ws <- fev_data(w)$ws
  expect_true(max(ws) > 10)
  expect_true(max(ws) < 150)
})

test_that("the archive reaches back far enough for a WMO normal", {
  skip_unless_network()
  # fev_fwi_percentile() calibrates against a reference climatology, and the
  # WMO normal is 30 years. 1991 has to be reachable for 1991-2020 to be.
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(maures_aoi(), period = c("1991-07-01", "1991-07-02"),
                      cache = FALSE)
  ))
  expect_true(all(fev_data(w)$yr == 1991L))
})

test_that("the day of the Cannet-des-Maures fire is the season's worst", {
  skip_unless_network()
  # An end-to-end check with no fire data in it: weather in, FWI out, and the
  # 6 510 ha fire of 16 August 2021 comes out first of 153 days on median FWI
  # over the massif. Verified 2026-08-17.
  #
  # This is the closest thing to external validation the danger module has --
  # the ranking is produced by ERA5 and cffdrs alone.
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(maures_aoi(), period = c("2021-05-01", "2021-09-30"))
  ))
  r <- suppressWarnings(fev_fwi_from_weather(w, index = "FWI"))
  d <- fev_data(r)
  med <- terra::global(d, stats::median, na.rm = TRUE)[, 1]
  expect_equal(as.Date(terra::time(d))[which.max(med)], as.Date("2021-08-16"))
  expect_gt(max(med), 50)  # EFFIS "extreme" begins at 50
})

# Phase 11 sources -----------------------------------------------------------
#
# Both tile grids were MEASURED from the products rather than read off a
# datasheet -- the GHSL x-origin carries a -41 000 m offset no product sheet
# states. That makes these two the tests that matter most in this file: they are
# the only thing standing between a silent change of tiling upstream and a
# package that computes tile names nobody publishes.

test_that("GHS-POP comes back over the Maures test box", {
  skip_unless_network()
  pop <- suppressMessages(fev_fetch_ghsl(maures_aoi(), epoch = 2020))
  r <- fev_data(pop)
  expect_true(inherits(r, "SpatRaster"))
  total <- as.numeric(terra::global(r, "sum", na.rm = TRUE)[1, 1])
  # The test box is 5 km of wooded massif, not a town: 89 residents on
  # 2026-08-19. The bounds are wide on purpose -- they exist to catch a tiling
  # error handing back somebody else's square of the planet, not to pin a
  # number that the epoch or the box can legitimately move.
  expect_gt(total, 1)
  expect_lt(total, 50000)
  # The record lives in $source, not on the object: a SpatRaster is S4 and
  # drops user attributes at the first arithmetic operation.
  expect_equal(pop$source$dataset, "ghs_pop_2020")
  expect_equal(pop$source$millesime, 2020L)
})

test_that("reprojecting the population conserves the headcount", {
  skip_unless_network()
  # The reason project(method = "sum") is used rather than bilinear: bilinear
  # invented 5% of the Maures population over the study area, 35 039 becoming
  # 36 783. A total that drifts at every reprojection is the kind of error that
  # survives to publication because the number still looks right.
  #
  # Compared in the product's own projection against the working one, which is
  # the only way to see the drift at all.
  moll <- suppressMessages(fev_fetch_ghsl(maures_aoi(), epoch = 2020,
                                          crs_work = NULL, quiet = TRUE))
  lamb <- suppressMessages(fev_fetch_ghsl(maures_aoi(), epoch = 2020,
                                          crs_work = 2154, quiet = TRUE))
  a <- as.numeric(terra::global(fev_data(moll), "sum", na.rm = TRUE)[1, 1])
  b <- as.numeric(terra::global(fev_data(lamb), "sum", na.rm = TRUE)[1, 1])
  expect_lt(abs(b - a) / a, 0.01)
})

test_that("the Copernicus DEM covers the Maures with plausible relief", {
  skip_unless_network()
  dem <- suppressMessages(fev_fetch_dem(maures_aoi()))
  rng <- as.numeric(terra::global(fev_data(dem), range, na.rm = TRUE)[1, ])
  # The massif runs from sea level to about 780 m at Notre-Dame des Anges.
  expect_gte(rng[1], -20)
  expect_lt(rng[2], 1200)
  expect_gt(rng[2] - rng[1], 50)
})
