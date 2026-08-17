# Open-Meteo response parsing, offline.
#
# The bug this file exists to prevent: a single point returns a JSON object, a
# grid of points returns an array. jsonlite turns the array into a data frame
# whose `hourly` column is itself a data frame of lists, and `parsed$hourly` is
# non-NULL in BOTH shapes -- so branching on it silently treated twelve points
# as one and produced a table cffdrs could not sort.
#
# Fixtures were recorded from real calls on 2026-08-17 over the Maures, two days
# spanning the Cannet-des-Maures fire. Recorded rather than hand-written so the
# shape under test is the service's, not my idea of it.

fixture <- function(name) {
  readLines(test_path("fixtures", name), warn = FALSE)
}

# 43.4/6.3, 43.4/6.4, 43.3/6.3, 43.3/6.4 -- the order fev_weather_grid() emits.
grid4 <- data.frame(id = 1:4, lat = c(43.4, 43.4, 43.3, 43.3),
                    long = c(6.3, 6.4, 6.3, 6.4))

test_that("a multi-point response is split into one series per point", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  out <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                             as.Date("2021-08-16"), 12L)

  expect_equal(nrow(out), 8L)
  expect_equal(sort(unique(out$id)), 1:4)
  expect_setequal(names(out), c("id", "lat", "long", "yr", "mon", "day",
                               "temp", "rh", "ws", "prec"))

  # Each point keeps its own series. Before the fix all four collapsed into one.
  noon16 <- out[out$day == 16L, ]
  expect_equal(noon16$temp[order(noon16$id)], c(34.8, 35.4, 34.1, 33.8))
  expect_equal(noon16$rh[order(noon16$id)], c(23, 23, 23, 21))
})

test_that("a single-point response gives the same numbers as the grid", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_1pt.json"))
  one <- fev_open_meteo_year(
    data.frame(id = 1L, lat = 43.3, long = 6.4),
    as.Date("2021-08-15"), as.Date("2021-08-16"), 12L
  )

  expect_equal(nrow(one), 2L)

  # The object branch and the array branch must agree: this point is the fourth
  # of grid4, and the two fixtures were recorded minutes apart.
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  many <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                              as.Date("2021-08-16"), 12L)
  same <- many[many$id == 4L, c("yr", "mon", "day", "temp", "rh", "ws", "prec")]
  expect_equal(one[, c("yr", "mon", "day", "temp", "rh", "ws", "prec")], same,
               ignore_attr = TRUE)
})

test_that("only the requested hour is kept", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  out <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                             as.Date("2021-08-16"), 12L)
  # 48 hours transferred per point, two kept: the price of an exact noon.
  expect_equal(nrow(out), 8L)
  expect_setequal(out$day, c(15L, 16L))

  none <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                              as.Date("2021-08-16"), 3L)
  expect_equal(nrow(none), 8L)  # 03:00 exists too
  expect_false(identical(none$temp, out$temp))
})

test_that("the station id follows the requested point, not the served cell", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  out <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                             as.Date("2021-08-16"), 12L)
  served <- attr(out, "served")

  # Points 1 and 2 are in ONE reanalysis cell and are still two series: the
  # service adjusts temperature to the requested location's elevation, 274 m
  # against 77 m. Keying on the served coordinates merged them and lost a point.
  expect_equal(served$cell_lat[1], served$cell_lat[2])
  expect_equal(served$cell_long[1], served$cell_long[2])
  expect_equal(served$elev_m[1:2], c(274, 77))
  expect_false(out$temp[out$id == 1L][1] == out$temp[out$id == 2L][1])

  # The coordinates in the table are the requested ones, because that is where
  # the series applies.
  expect_equal(unique(out$lat[out$id == 1L]), 43.4)
  expect_equal(nrow(served), 4L)
})

test_that("a count mismatch fails rather than shifting the weather", {
  # Series are matched to points by position and nothing in the response keys
  # them back, so a short array must not be quietly recycled.
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  expect_error(
    fev_open_meteo_year(rbind(grid4, data.frame(id = 5L, lat = 43.2, long = 6.5)),
                        as.Date("2021-08-15"), as.Date("2021-08-16"), 12L),
    class = "fev_weather_mismatch"
  )
})

test_that("a JSON-level refusal is reported, not parsed", {
  # Defensive: in practice Open-Meteo answers a bad request with HTTP 400, which
  # fails in fev_read_url() before this branch is reached. Verified 2026-08-17.
  local_mocked_bindings(
    fev_read_url = function(...) '{"error":true,"reason":"Value out of range"}'
  )
  expect_error(
    fev_open_meteo_year(grid4, as.Date("2021-08-15"), as.Date("2021-08-16"), 12L),
    class = "fev_weather_failed"
  )
})

test_that("a network failure is named, and does not leak the URL machinery", {
  local_mocked_bindings(readLines = function(...) stop("cannot open URL"),
                        .package = "base")
  expect_error(fev_read_url("https://example.invalid", year = "2021"),
               class = "fev_weather_failed")
})

test_that("the point grid covers the AOI and is ordered for a raster", {
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.32, ymin = 43.22, xmax = 6.48, ymax = 43.38),
    crs = sf::st_crs(4326)
  )))
  g <- fev_weather_grid(aoi, 0.1)

  expect_true(min(g$long) <= 6.32 && max(g$long) >= 6.48)
  expect_true(min(g$lat) <= 43.22 && max(g$lat) >= 43.38)
  # North to south, then west to east, so row order maps onto raster cells.
  expect_false(is.unsorted(rev(g$lat)))
  expect_identical(g$id, seq_len(nrow(g)))

  expect_error(fev_weather_grid(aoi, -1), "positive")
})

test_that("too large a job is refused before anything is downloaded", {
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 42, xmax = 8, ymax = 50), crs = sf::st_crs(4326)
  )))
  expect_error(fev_fetch_weather(aoi, period = c("2021", "2021"), cache = FALSE),
               class = "fev_too_many_points")
})

test_that("fev_fwi_from_weather turns a point-day table into a dated raster", {
  # Two points, five days, one hot and dry and one cool and damp.
  w <- expand.grid(day = 1:5, id = 1:2)
  w$lat <- c(43.2, 43.3)[w$id]
  w$long <- c(6.3, 6.4)[w$id]
  w$yr <- 2021L
  w$mon <- 8L
  w$temp <- c(32, 19)[w$id]
  w$rh <- c(20, 70)[w$id]
  w$ws <- c(25, 6)[w$id]
  w$prec <- c(0, 4)[w$id]

  r <- suppressWarnings(fev_fwi_from_weather(w, index = "FWI"))
  expect_s3_class(r, "fev_danger_layer")
  d <- fev_data(r)
  expect_equal(terra::nlyr(d), 5L)
  expect_equal(as.Date(terra::time(d)), as.Date("2021-08-01") + 0:4)

  # The hot dry point must end above the cool wet one, and the codes must
  # accumulate per point: day 5 above day 1 at the dry point.
  v <- terra::values(d)
  dry <- which.max(v[, 5])
  expect_gt(v[dry, 5], v[dry, 1])
  expect_gt(max(v[, 5], na.rm = TRUE), min(v[, 5], na.rm = TRUE))

  expect_error(fev_fwi_from_weather(w[, setdiff(names(w), "rh")]),
               class = "fev_bad_weather")
  expect_error(suppressWarnings(fev_fwi_from_weather(w, index = "NOPE")),
               "No index")
})

test_that("the provenance says the source is a third party", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.31, ymin = 43.31, xmax = 6.36, ymax = 43.36),
    crs = sf::st_crs(4326)
  )))
  w <- suppressMessages(suppressWarnings(
    fev_fetch_weather(aoi, period = c("2021-08-15", "2021-08-16"),
                      cache = FALSE, crs_work = 4326)
  ))

  expect_s3_class(w, "fev_source")
  expect_true(isTRUE(w$source$third_party))
  expect_match(w$source$provider, "Open-Meteo")
  # The served cell travels beside the requested point, so a reader can see the
  # snapping and the elevation adjustment for themselves.
  expect_true(all(c("cell_lat", "cell_long", "elev_m") %in%
                    names(w$source$points)))

  r <- suppressWarnings(fev_fwi_from_weather(w, index = "FWI"))
  funs <- vapply(r$provenance$steps, function(s) s$fun, character(1))
  expect_true("fev_fwi_from_weather" %in% funs)
  # The third-party flag has to survive into the derived layer, or a reader of
  # the risk map cannot tell which weather product produced it.
  expect_true(any(vapply(r$provenance$sources,
                         function(s) isTRUE(s$third_party), logical(1))))
})

test_that("precipitation is the 24-hour sum, not the noon hour's rain", {
  # The FWI system's rain input is accumulated over the 24 hours ending at the
  # observation, and reading the noon hour instead threw away 23 hours a day.
  # Measured consequence over three years in the Maures: rain on 10% of days
  # instead of 39%, and DC 1 949 instead of 619 on 2021-08-16.
  #
  # The fixture has 48 hours per point, so noon on the second day has a full
  # window inside it and can be checked against the raw series.
  raw <- jsonlite::fromJSON(fixture("open_meteo_4pt.json"))
  hours <- raw$hourly$time[[1]]
  k <- which(substr(hours, 12, 13) == "12")[2]
  want <- sum(raw$hourly$precipitation[[1]][(k - 23L):k])

  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  out <- fev_open_meteo_year(grid4, as.Date("2021-08-15"),
                             as.Date("2021-08-16"), 12L)
  got <- out$prec[out$id == 1L & out$day == 16L]
  expect_equal(got, want)

  # Not the single hour -- which is what the first version returned.
  expect_false(isTRUE(all.equal(got, raw$hourly$precipitation[[1]][k])) &&
                 want != raw$hourly$precipitation[[1]][k])
})

test_that("an extra day is fetched so the first window is full", {
  # The 24-hour total for the first noon reaches into the previous evening. If
  # the request started on the first day asked for, every chunk boundary would
  # silently zero part of a day's rain.
  seen <- NULL
  local_mocked_bindings(fev_read_url = function(url, ...) {
    seen <<- url
    fixture("open_meteo_4pt.json")
  })
  out <- fev_open_meteo_year(grid4, as.Date("2021-08-16"),
                             as.Date("2021-08-16"), 12L)

  expect_match(seen, "start_date=2021-08-15")
  expect_match(seen, "end_date=2021-08-16")
  # And the extra day does not survive into the result.
  expect_equal(unique(out$day), 16L)
})

test_that("the cache key changes when the table's meaning changes", {
  # The stored table is derived, not raw: prec became a 24-hour sum while the
  # request that produced it stayed identical. Without the schema tag in the key,
  # every existing entry would be served as if still correct.
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.31, ymin = 43.31, xmax = 6.36, ymax = 43.36),
    crs = sf::st_crs(4326)
  )))
  pts <- fev_weather_grid(aoi, 0.1)
  args <- list(pts = pts, period = c("2021-01-01", "2021-12-31"),
               spacing = 0.1, hour = 12L)
  expect_false(identical(
    fev_cache_key("open_meteo", c(args, list(schema = "v2"))),
    fev_cache_key("open_meteo", c(args, list(schema = "v1")))
  ))
})

test_that("reset = annual restarts the codes and none does not", {
  # Two years at one point, dry throughout, so the Drought Code has nothing to
  # drain it: the continuous run must end higher than the restarted one.
  w <- expand.grid(day = 1:28, mon = 6:8, yr = 2020:2021, id = 1L)
  w$lat <- 43.3
  w$long <- 6.4
  w$temp <- 30
  w$rh <- 25
  w$ws <- 15
  w$prec <- 0
  w <- w[order(w$yr, w$mon, w$day), ]

  last <- function(reset) {
    r <- fev_data(suppressWarnings(
      fev_fwi_from_weather(w, index = "DC", reset = reset)
    ))
    max(terra::values(r[[terra::nlyr(r)]]), na.rm = TRUE)
  }
  expect_gt(last("none"), last("annual"))

  # The provenance has to say which was used: the two are not comparable.
  r <- suppressWarnings(fev_fwi_from_weather(w, index = "DC", reset = "annual"))
  step <- r$provenance$steps[[length(r$provenance$steps)]]
  expect_equal(step$params$reset, "annual")
})

test_that("a period ending in the future is truncated, not refused", {
  local_mocked_bindings(fev_read_url = function(...) fixture("open_meteo_4pt.json"))
  aoi <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
    c(xmin = 6.31, ymin = 43.31, xmax = 6.36, ymax = 43.36),
    crs = sf::st_crs(4326)
  )))
  # The archive ends today and answers HTTP 400 beyond it, so asking for the
  # current calendar year used to fail on the last chunk after downloading
  # every earlier one.
  expect_message(
    suppressWarnings(try(fev_fetch_weather(
      aoi, period = c(format(Sys.Date() - 1, "%Y-%m-%d"),
                      format(Sys.Date() + 400, "%Y-%m-%d")),
      cache = FALSE), silent = TRUE)),
    class = "fev_period_truncated"
  )

  # Entirely in the future is a mistake, not something to clamp.
  expect_error(
    fev_fetch_weather(aoi, period = c(format(Sys.Date() + 10, "%Y-%m-%d"),
                                      format(Sys.Date() + 20, "%Y-%m-%d")),
                      cache = FALSE),
    class = "fev_period_future"
  )
})

test_that("a rate-limited request is retried before it is given up on", {
  n <- 0L
  # HTTP 429 arrives as a warning from file() while the error only says the
  # connection could not be opened, so the status has to be read from the
  # warning to tell "wait" from "this request is wrong".
  local_mocked_bindings(
    readLines = function(...) {
      n <<- n + 1L
      warning("cannot open URL 'x': HTTP status was '429 Unknown Error'")
      stop("cannot open the connection")
    },
    .package = "base"
  )
  expect_error(
    suppressMessages(fev_read_url("https://example.invalid", tries = 3L,
                                  pause = 0)),
    class = "fev_weather_failed"
  )
  expect_equal(n, 3L)

  # A 400 is not retried: waiting cannot fix a malformed request.
  n <- 0L
  local_mocked_bindings(
    readLines = function(...) {
      n <<- n + 1L
      warning("cannot open URL 'x': HTTP status was '400 Bad Request'")
      stop("cannot open the connection")
    },
    .package = "base"
  )
  expect_error(suppressMessages(fev_read_url("https://example.invalid",
                                             tries = 3L, pause = 0)),
               class = "fev_weather_failed")
  expect_equal(n, 1L)
})
