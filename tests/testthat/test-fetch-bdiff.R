# No test in this file touches the network. The data.gouv.fr route is not
# exercised anywhere: it has never been confirmed against the live service, and
# a mocked test of an unverified contract would assert our guess rather than
# the producer's behaviour. What is tested is everything downstream of the
# bytes -- which is where every bug found while writing this actually was.

local_cache <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir, .local_envir = env)
  dir
}

# Writing the CSV rather than shipping a fixture per case: the separator, the
# encoding and the header wording are exactly what is under test here, so they
# have to be settable per test.
write_bdiff <- function(rows, sep = ";", enc = "UTF-8", header = NULL,
                        env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  head <- header %||% names(rows)
  lines <- c(
    paste(head, collapse = sep),
    apply(rows, 1, function(r) paste(r, collapse = sep))
  )
  con <- file(path, open = "wb", encoding = "native.enc")
  writeLines(iconv(lines, from = "UTF-8", to = enc), con, useBytes = TRUE)
  close(con)
  path
}

sample_rows <- function() {
  data.frame(
    `Année` = c("2021", "2022", "2019"),
    `Numéro` = c("2021-83-0001", "2022-21-0012", "2019-21-0003"),
    `Département` = c("83", "21", "21"),
    `Code INSEE` = c("83039", "21193", "21231"),
    Commune = c("Le Cannet-des-Maures", "Couchey", "Dijon"),
    `Date de première alerte` = c("2021-08-16", "2022-07-18", "2019-06-30"),
    `Surface parcourue (m2)` = c("65100000", "15000", "4500"),
    `Surface forêt (m2)` = c("42000000", "12000", "0"),
    `Surface autres terres boisées (m2)` = c("18000000", "1000", "0"),
    `Surface autres terres (m2)` = c("5100000", "2000", "4500"),
    Nature = c("Involontaire", "Involontaire", "Malveillance"),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

synth_communes <- function(codes = c("83039", "21193", "21231"),
                           key = "INSEE_COM") {
  polys <- lapply(seq_along(codes), function(i) {
    x0 <- (i - 1) * 1000
    sf::st_polygon(list(cbind(
      c(x0, x0 + 900, x0 + 900, x0, x0),
      c(0, 0, 900, 900, 0)
    )))
  })
  out <- sf::st_sf(
    stats::setNames(list(codes), key),
    geometry = sf::st_sfc(polys, crs = 2154),
    stringsAsFactors = FALSE
  )
  out
}

# Reading -----------------------------------------------------------------------

test_that("a BDIFF export becomes the canonical columns", {
  path <- write_bdiff(sample_rows())
  src <- suppressWarnings(fev_fetch_bdiff(file = path))

  expect_s3_class(src, "fev_source")
  d <- fev_data(src)
  expect_setequal(
    names(d),
    c("fire_id", "fire_date", "fire_year", "insee", "commune", "dep",
      "area_ha", "area_forest_ha", "area_other_wooded_ha", "area_other_ha",
      "cause")
  )
  expect_equal(nrow(d), 3L)
  expect_s3_class(d$fire_date, "Date")
  expect_type(d$insee, "character")
  expect_equal(d$fire_year, c(2021L, 2022L, 2019L))
})

test_that("square metres are converted to hectares", {
  path <- write_bdiff(sample_rows())
  d <- fev_data(suppressWarnings(fev_fetch_bdiff(file = path)))

  # 65 100 000 m2 is the 6 510 ha of the 2021 Cannet-des-Maures fire.
  expect_equal(d$area_ha[1], 6510)
  expect_equal(d$area_forest_ha[1], 4200)
  expect_equal(d$area_ha[2], 1.5)
})

test_that("the source record carries provenance, not just data", {
  path <- write_bdiff(sample_rows())
  rec <- fev_source_info(suppressWarnings(fev_fetch_bdiff(file = path)))

  expect_equal(rec$dataset, "bdiff")
  expect_true(is.na(rec$licence))          # never read at the producer
  expect_true(rec$endpoint_verified)       # the file route is the tested one
  expect_equal(rec$n_features, 3L)
  expect_equal(rec$area_units_declared, "m2")
  expect_match(rec$exhaustivity, "declarative")
  expect_match(rec$geolocation, "no geometry")
  expect_equal(unname(rec$columns_matched[["insee"]]), "Code INSEE")
})

test_that("the shipped export reads end to end", {
  # A committed file rather than a generated one: this is the route the docs
  # call the tested one, and it exercises the real on-disk read.
  path <- test_path("fixtures", "bdiff_sample.csv")
  skip_if_not(file.exists(path))

  d <- fev_data(suppressWarnings(fev_fetch_bdiff(file = path)))
  expect_equal(nrow(d), 6L)
  expect_equal(sort(unique(d$dep)), c("21", "25", "39", "71", "83"))
  expect_equal(d$commune[6], "Besan\u00e7on")   # the accent survived the read
  expect_equal(round(sum(d$area_ha)), 7516)
})

test_that("a byte-order mark does not swallow the first header", {
  # sub("^\\ufeff", ...) matches nothing and fails silently, so a BOM used to
  # ride into "Annee" and stop it matching any candidate.
  rows <- sample_rows()
  path <- write_bdiff(rows)
  bom <- withr::local_tempfile(fileext = ".csv")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), readBin(path, "raw", file.size(path))),
           bom)

  d <- fev_data(suppressWarnings(fev_fetch_bdiff(file = bom)))
  expect_equal(nrow(d), 3L)
  expect_equal(d$fire_year, c(2021L, 2022L, 2019L))
})

test_that("a semicolon and a comma export read the same", {
  rows <- sample_rows()
  a <- fev_data(suppressWarnings(fev_fetch_bdiff(file = write_bdiff(rows, sep = ";"))))
  b <- fev_data(suppressWarnings(fev_fetch_bdiff(file = write_bdiff(rows, sep = ","))))
  expect_equal(a, b)
})

test_that("a latin1 export reads as well as a UTF-8 one", {
  # The failure this guards is not an error: read.csv(fileEncoding=) under a C
  # locale returns a header and zero rows on an accented byte.
  rows <- sample_rows()
  utf8 <- fev_data(suppressWarnings(fev_fetch_bdiff(file = write_bdiff(rows))))
  lat1 <- fev_data(suppressWarnings(
    fev_fetch_bdiff(file = write_bdiff(rows, enc = "latin1"))
  ))
  expect_equal(nrow(lat1), 3L)
  expect_equal(lat1$area_ha, utf8$area_ha)
})

test_that("French decimal commas are read as decimals", {
  num <- firexpovulnR:::fev_bdiff_num
  expect_equal(num("1 234,5"), 1234.5)
  expect_equal(num("1,5"), 1.5)
  expect_equal(num("1,234.5"), 1234.5)   # a dot present means C convention
  expect_true(is.na(num("n/a")))
})

# Column matching ---------------------------------------------------------------

test_that("header matching folds accents whatever the locale", {
  norm <- firexpovulnR:::fev_bdiff_normalise
  expect_equal(norm("Date de première alerte"), "date_de_premiere_alerte")
  expect_equal(norm("Surface parcourue (m2)"), "surface_parcourue_m2")
  expect_equal(norm("Année"), "annee")
  expect_equal(norm("Cœur"), "coeur")
})

test_that("a missing required column names the headers that are present", {
  rows <- sample_rows()
  rows[["Code INSEE"]] <- NULL
  path <- write_bdiff(rows)

  expect_error(
    fev_fetch_bdiff(file = path),
    class = "fev_bdiff_missing_column"
  )
  # The message has to be enough to write the override from.
  err <- tryCatch(fev_fetch_bdiff(file = path), error = function(e) e)
  expect_match(conditionMessage(err), "Commune", fixed = TRUE)
})

test_that("a renamed column is recovered by overriding the mapping", {
  rows <- sample_rows()
  names(rows)[names(rows) == "Nature"] <- "Origine du feu"
  path <- write_bdiff(rows)

  default <- fev_data(suppressWarnings(fev_fetch_bdiff(file = path)))
  expect_true(all(is.na(default$cause)))

  fixed <- fev_data(suppressWarnings(fev_fetch_bdiff(
    file = path, columns = fev_bdiff_columns(cause = "origine_du_feu")
  )))
  expect_equal(fixed$cause[3], "Malveillance")
})

test_that("fev_bdiff_columns rejects a column it does not have", {
  expect_error(fev_bdiff_columns(surface = "x"), class = "fev_error")
  expect_type(fev_bdiff_columns()$insee, "character")
})

# INSEE codes -------------------------------------------------------------------

test_that("a commune code that lost its leading zero is repadded", {
  rows <- sample_rows()
  rows[["Code INSEE"]] <- c("1004", "21193", "21231")   # spreadsheet damage
  path <- write_bdiff(rows)

  d <- fev_data(suppressWarnings(fev_fetch_bdiff(file = path)))
  expect_equal(d$insee[1], "01004")
  expect_true(all(nchar(d$insee) == 5L))
})

test_that("the department falls back to the commune code when absent", {
  rows <- sample_rows()
  rows[["Département"]] <- NULL
  path <- write_bdiff(rows)

  d <- fev_data(suppressWarnings(fev_fetch_bdiff(file = path)))
  expect_equal(d$dep, c("83", "21", "21"))
})

# Filtering ---------------------------------------------------------------------

test_that("period and department filters keep what they say", {
  path <- write_bdiff(sample_rows())

  p <- fev_data(suppressWarnings(
    fev_fetch_bdiff(file = path, period = c(2020, 2023))
  ))
  expect_equal(nrow(p), 2L)
  expect_true(all(p$fire_year >= 2020))

  d <- fev_data(suppressWarnings(
    fev_fetch_bdiff(file = path, departements = "21")
  ))
  expect_equal(nrow(d), 2L)
  expect_true(all(d$dep == "21"))

  # A single-digit code is padded rather than silently matching nothing.
  expect_equal(
    nrow(fev_data(suppressWarnings(
      fev_fetch_bdiff(file = write_bdiff(within(sample_rows(), {
        `Département` <- c("83", "1", "1")
        `Code INSEE` <- c("83039", "01004", "01005")
      })), departements = "01")
    ))),
    2L
  )
})

test_that("a period starting before the extract warns with the years", {
  path <- write_bdiff(sample_rows())
  expect_warning(
    fev_fetch_bdiff(file = path, period = c(2006, 2023)),
    class = "fev_period_truncated"
  )
})

test_that("an absent department warns rather than returning nothing quietly", {
  path <- write_bdiff(sample_rows())
  expect_warning(
    try(fev_fetch_bdiff(file = path, departements = "99"), silent = TRUE),
    class = "fev_bdiff_absent_departement"
  )
  expect_error(
    suppressWarnings(fev_fetch_bdiff(file = path, departements = "99")),
    class = "fev_empty_result"
  )
})

# Areas -------------------------------------------------------------------------

test_that("declaring the wrong unit is caught, in both directions", {
  # Areas published in hectares but read as square metres: every fire becomes
  # a ten-thousandth of its size, silently.
  rows <- sample_rows()
  rows[["Surface parcourue (m2)"]] <- c("6510", "1.5", "0.45")
  expect_warning(
    fev_fetch_bdiff(file = write_bdiff(rows), area_units = "m2"),
    class = "fev_bdiff_area_units"
  )
  expect_warning(
    fev_fetch_bdiff(file = write_bdiff(sample_rows()), area_units = "ha"),
    class = "fev_bdiff_area_units"
  )
  # And the correct declaration says nothing.
  expect_no_warning(
    suppressWarnings(  # the once-per-session declarative caveat is not this
      withCallingHandlers(
        fev_fetch_bdiff(file = write_bdiff(sample_rows()), area_units = "m2"),
        fev_bdiff_area_units = function(w) stop("unit warning fired")
      )
    )
  )
})

# Geolocation -------------------------------------------------------------------

test_that("commune polygons turn the table into an sf", {
  path <- write_bdiff(sample_rows())
  out <- suppressWarnings(
    fev_fetch_bdiff(file = path, communes = synth_communes())
  )
  d <- fev_data(out)

  expect_s3_class(d, "sf")
  expect_equal(nrow(d), 3L)
  expect_equal(sf::st_crs(d)$epsg, 2154L)
  expect_match(fev_source_info(out)$geolocation, "commune polygon")
})

test_that("records matching no commune are counted, not dropped in silence", {
  # The commune layer is missing 21231: a fire there must be reported as lost,
  # because on an occurrence map it is indistinguishable from a commune that
  # never burnt.
  path <- write_bdiff(sample_rows())
  expect_warning(
    fev_fetch_bdiff(file = path, communes = synth_communes(c("83039", "21193"))),
    class = "fev_bdiff_unmatched_communes"
  )
  d <- fev_data(suppressWarnings(
    fev_fetch_bdiff(file = path, communes = synth_communes(c("83039", "21193")))
  ))
  expect_equal(nrow(d), 2L)
})

test_that("the commune key is auto-detected, and overridable", {
  path <- write_bdiff(sample_rows())
  expect_message(
    suppressWarnings(fev_fetch_bdiff(file = path,
                                     communes = synth_communes(key = "code_insee"))),
    "code_insee"
  )
  expect_error(
    suppressWarnings(fev_fetch_bdiff(
      file = path, communes = synth_communes(key = "zzz"))),
    class = "fev_bdiff_no_commune_key"
  )
  expect_s3_class(
    fev_data(suppressWarnings(fev_fetch_bdiff(
      file = path, communes = synth_communes(key = "zzz"),
      communes_key = "zzz"))),
    "sf"
  )
})

test_that("an AOI without communes is refused, with the reason", {
  path <- write_bdiff(sample_rows())
  expect_error(
    fev_fetch_bdiff(file = path, aoi = synth_communes()),
    class = "fev_bdiff_no_geometry"
  )
})

test_that("an AOI clips the geolocated records", {
  path <- write_bdiff(sample_rows())
  com <- synth_communes()
  aoi <- sf::st_as_sfc(sf::st_bbox(com[1, ]))

  d <- fev_data(suppressWarnings(
    fev_fetch_bdiff(file = path, communes = com, aoi = aoi)
  ))
  expect_equal(nrow(d), 1L)
  expect_equal(d$insee, "83039")
})

# Consolidation -----------------------------------------------------------------

test_that("years that cannot be consolidated yet are flagged", {
  warn_cons <- firexpovulnR:::fev_bdiff_warn_consolidation
  this_year <- as.integer(format(Sys.Date(), "%Y"))

  expect_warning(warn_cons(c(2020L, this_year)), class = "fev_bdiff_provisional")
  expect_false(suppressWarnings(warn_cons(c(2010L, 2015L))))
})

# The registry ------------------------------------------------------------------

test_that("the data.gouv.fr endpoint is declared unverified", {
  # It is the only endpoint in the registry that was never confirmed by a real
  # call. Asserting it here is what stops the caveat quietly disappearing.
  src <- fev_sources()
  expect_true("data_gouv_api" %in% names(src$endpoints))
  expect_true("data_gouv_api" %in% src$unverified)
  expect_equal(src$verified, "2026-08-15")
})

# Cache -------------------------------------------------------------------------

test_that("a tabular cache entry can be listed and cleared", {
  # BDIFF caches as rds, like the weather. Before this, fev_cache_info() only
  # matched gpkg and tif, so an rds entry was invisible -- and therefore also
  # unreachable by fev_cache_clear(), which works off that table.
  local_cache()
  key <- firexpovulnR:::fev_cache_key("bdiff", list(resource = "auto"))
  firexpovulnR:::fev_cache_write(
    key, data.frame(a = 1:3), list(dataset = "bdiff", millesime = 2025),
    ext = "rds"
  )

  info <- suppressMessages(fev_cache_info())
  expect_true("bdiff" %in% info$dataset)
  removed <- suppressMessages(
    fev_cache_clear(dataset = "bdiff", confirm = FALSE)
  )
  expect_length(removed, 2L)          # data and its provenance sidecar
  expect_false(firexpovulnR:::fev_cache_hit(key, ext = "rds"))
})
