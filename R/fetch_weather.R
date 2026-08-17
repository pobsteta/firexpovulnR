# Fire weather without a token.
#
# fev_fetch_fwi() serves the authoritative CEMS product, and needs a personal
# Copernicus key the package refuses to handle beyond passing it through. That
# is a hard barrier for anyone without an account, and it is why both shipped
# articles ran on an invented series -- which is a poor advertisement for a
# package whose first requirement is traceability.
#
# The Open-Meteo archive re-serves ERA5 and ERA5-Land over an open API with no
# authentication at all. It gives the four variables the Canadian system needs,
# hourly, so the noon observation the system is defined on is available rather
# than approximated. Verified 2026-08-17; see specs/phase9-rapport-meteo.md.
#
# What it costs: one more link in the provenance chain -- a third party between
# ECMWF and us -- and the indices become cffdrs-on-Open-Meteo rather than the
# CEMS product. Comparable, not identical, and said so in the docs.

#' Fire weather from the open Open-Meteo archive
#'
#' Retrieves the four variables the Canadian Fire Weather Index System needs —
#' noon temperature, relative humidity, wind speed and 24-hour precipitation —
#' over a grid of points, **without any API key**.
#'
#' @section Rain is summed, the rest is read:
#' Three of the four inputs are the noon observation. The fourth is not:
#' the system takes the rainfall **accumulated over the 24 hours ending at
#' noon**. So hourly precipitation is summed over that window, and one extra day
#' is fetched at the start of each chunk to fill it. Reading the noon hour's rain
#' instead throws away 23 hours a day and inflates the drought codes without
#' making the FWI look wrong — see the note on saturation in
#' [fev_fwi_from_weather()].
#'
#' @section Why this exists next to fev_fetch_fwi():
#' [fev_fetch_fwi()] downloads indices already computed by the CEMS, which is
#' the authoritative product and needs a personal Copernicus token. This route
#' needs none, reaches back to 1940, and comes at roughly 0.1° — about 11 km,
#' two and a half times finer than the 0.25° CEMS grid. The trade is that the
#' indices are then computed here by `cffdrs` rather than by ECMWF, and that a
#' third-party service sits between the reanalysis and you.
#'
#' Use CEMS when you have a token and want the reference product. Use this when
#' you do not, or when you want a finer grid, and say which you used.
#'
#' @section Noon, not daily aggregates:
#' The FWI system is defined on **noon local standard time** observations. This
#' function requests hourly data and keeps the noon hour, rather than
#' substituting daily maximum temperature and minimum humidity as operational
#' implementations often do. That is exact but wasteful: 24 hours are
#' transferred for each one kept. A 30-year record over nine points is of the
#' order of 90 MB of transfer, which is why the result is cached and the request
#' is chunked by year.
#'
#' @section Wind is already in km/h:
#' Open-Meteo serves `wind_speed_10m` in kilometres per hour, which is what the
#' system wants — unlike E-OBS, whose `FG` is in metres per second and is the
#' classic way to get FWI wrong by a factor of 3.6.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param period Two dates or years bounding the record, e.g.
#'   `c("1991-01-01", "2020-12-31")`.
#' @param spacing Point spacing in degrees. Defaults to `0.1`, the native
#'   resolution of ERA5-Land; asking for less does not add information.
#' @param hour Hour to keep, UTC. Defaults to 12.
#' @param max_points Refuse rather than start a job larger than this. Each point
#'   is a separate series in the response.
#' @param cache Use the on-disk cache. See [fev_cache_dir()].
#' @param crs_work EPSG code recorded for the point grid.
#'
#' @return A [fev_source] holding a data frame with one row per point and day —
#'   columns `id`, `lat`, `long`, `yr`, `mon`, `day`, `temp`, `rh`, `ws`,
#'   `prec` — which is exactly the shape [fev_fwi_calc()] consumes. The point
#'   grid travels in the `points` field of the source record.
#'
#' @seealso [fev_fwi_from_weather()] to turn this into a dated FWI raster,
#'   [fev_fetch_fwi()] for the CEMS product.
#'
#' @source
#' Open-Meteo historical weather archive, <https://open-meteo.com/>, which
#' re-serves ERA5 and ERA5-Land. Endpoint, variable names, units and the
#' availability of 1991 verified by real calls on 2026-08-17. Multi-point
#' requests return a JSON array, one object per point — also verified.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' w <- fev_fetch_weather(aoi, period = c("2021-01-01", "2021-12-31"))
#' head(fev_data(w))
#' }
#'
#' @export
fev_fetch_weather <- function(aoi,
                              period,
                              spacing = 0.1,
                              hour = 12L,
                              max_points = 25L,
                              cache = TRUE,
                              crs_work = 2154) {
  fev_require("jsonlite", "read the Open-Meteo response")

  bounds <- fev_period_bounds(period)

  # The archive stops at today and refuses anything beyond it with HTTP 400, so
  # asking for the current year -- c("2026-01-01", "2026-12-31") -- fails on the
  # last chunk after every earlier one has been downloaded. Clamped rather than
  # refused, because a period given as a year is a reasonable request; said out
  # loud rather than silently, because the record is then shorter than asked for.
  #
  # There is no reanalysis latency to allow for: verified 2026-08-17 that the
  # endpoint serves 24 valid hours for today itself, Open-Meteo filling recent
  # days from a forecast model. Those last days are therefore not ERA5.
  today <- Sys.Date()
  if (bounds[2] > today) {
    asked <- format(bounds[2], "%Y-%m-%d")
    if (bounds[1] > today) {
      fev_abort(c(
        "The whole period {asked} onwards is in the future.",
        i = "The archive ends at {format(today, '%Y-%m-%d')}."
      ), class = "fev_period_future", .envir = environment())
    }
    fev_inform(c(
      "Period truncated at {format(today, '%Y-%m-%d')}, from {asked}.",
      i = "The archive ends today and refuses later dates.",
      i = "The most recent days come from a forecast model rather than \
           from ERA5, so treat the tail of the record as provisional."
    ), class = "fev_period_truncated", .envir = environment())
    bounds[2] <- today
  }

  years <- fev_period_years(bounds)
  aoi <- fev_as_aoi(aoi, crs = crs_work)
  pts <- fev_weather_grid(aoi, spacing)

  if (nrow(pts) > max_points) {
    fev_abort(c(
      "{nrow(pts)} grid points is more than {.arg max_points} = \\
       {max_points}.",
      i = "Each point is a separate series in the response, and a 30-year \\
           hourly record is about 10 MB per point.",
      i = "Coarsen {.arg spacing}, shrink the AOI, or raise \\
           {.arg max_points} deliberately."
    ), class = "fev_too_many_points", .envir = environment())
  }

  # The schema tag is part of the key on purpose. The stored table is a derived
  # product -- noon observations plus a 24-hour rain sum -- so a change in how it
  # is derived makes every existing entry wrong while the request that produced
  # it is unchanged. Bump this whenever the columns or their meaning change.
  key <- fev_cache_key("open_meteo",
                       list(pts = pts, period = as.character(bounds),
                            spacing = spacing, hour = hour,
                            schema = .FEV_OPEN_METEO_SCHEMA))
  if (isTRUE(cache) && fev_cache_hit(key, ext = "rds")) {
    hit <- fev_cache_read(key, ext = "rds")
    fev_inform("Weather served from cache ({nrow(hit$data)} point-day{?s}).")
    return(structure(list(data = hit$data, source = hit$source),
                     class = "fev_source"))
  }

  n_years <- years[2] - years[1] + 1L
  fev_inform(c(
    "Fetching {n_years} year{?s} at {nrow(pts)} point{?s} from the \\
     Open-Meteo archive.",
    i = "Hourly data is transferred and the {hour}:00 hour kept, so this \\
         moves about {round(nrow(pts) * n_years * 0.33)} MB.",
    i = "No API key is used or needed."
  ), class = "fev_weather_fetch", .envir = environment())

  # Chunked by year rather than one huge request: courteous to a free service,
  # and it keeps peak memory to one year of hourly data instead of thirty.
  chunks <- seq(years[1], years[2])
  parts <- lapply(seq_along(chunks), function(i) {
    y <- chunks[i]
    from <- max(bounds[1], as.Date(sprintf("%d-01-01", y)))
    to <- min(bounds[2], as.Date(sprintf("%d-12-31", y)))
    # A short pause between chunks rather than a burst: it costs seconds on a
    # job that moves tens of megabytes, and it is what keeps a multi-decade
    # request from being throttled in the first place.
    if (i > 1L) {
      Sys.sleep(2)
    }
    fev_open_meteo_year(pts, from, to, hour)
  })
  served <- attr(parts[[1]], "served")
  out <- do.call(rbind, parts)
  if (!is.null(out) && nrow(out)) {
    out <- out[order(out$id, out$yr, out$mon, out$day), ]
    rownames(out) <- NULL
  }

  if (is.null(out) || !nrow(out)) {
    fev_abort(c(
      "The archive returned no usable observation.",
      i = "Check the period and that the AOI is on land -- ERA5-Land is \\
           undefined over sea."
    ), class = "fev_empty_result")
  }

  fev_check_weather_ranges(out)

  src <- new_fev_source(
    out,
    dataset   = "open_meteo_archive",
    provider  = "Open-Meteo (re-serving ERA5 / ERA5-Land)",
    endpoint  = .FEV_ENDPOINTS$open_meteo,
    query     = list(period = as.character(bounds), spacing = spacing,
                     hour = hour, n_points = nrow(pts),
                     variables = unname(.FEV_OPEN_METEO_VARS)),
    millesime = paste(years, collapse = "-"),
    version   = "archive API v1",
    third_party = TRUE,
    points    = merge(pts, served, by = "id", all.x = TRUE),
    crs_native = "EPSG:4326"
  )
  src$source$n_features <- nrow(out)

  fev_once("weather_third_party", fev_warn(c(
    "These observations come from a third party re-serving ERA5, not from \\
     Copernicus directly.",
    i = "The indices you derive will be {.pkg cffdrs} on Open-Meteo inputs, \\
         not the CEMS product -- comparable, not identical.",
    i = "With a Copernicus token, {.fn fev_fetch_fwi} gives the reference \\
         product instead. Say which one your results used.",
    i = "Shown once per session; recorded in the provenance every time."
  ), class = "fev_third_party_source"))

  if (isTRUE(cache)) {
    fev_cache_write(key, out, src$source, ext = "rds")
  }
  fev_inform("Got {nrow(out)} point-day{?s} at {nrow(pts)} point{?s}.",
             .envir = environment())
  src
}

# Open-Meteo variable names, verified 2026-08-17 with their units. Wind is
# already km/h, which is the unit the FWI system wants -- the one thing this
# source gets right that E-OBS does not.
# Bumped when the derived table changes meaning, so cached entries from an
# earlier definition are misses rather than silently wrong answers.
#   v2: prec became the 24-hour sum ending at `hour`, not that hour's rainfall.
.FEV_OPEN_METEO_SCHEMA <- "v2"

.FEV_OPEN_METEO_VARS <- c(
  temp = "temperature_2m",        # degrees C
  rh   = "relative_humidity_2m",  # percent
  ws   = "wind_speed_10m",        # km/h
  prec = "precipitation"          # mm
)

#' A regular lon/lat point grid over an AOI
#'
#' One point per reanalysis cell rather than one per output pixel: the series is
#' a property of the cell, and interpolating between cell centres would invent
#' variation the reanalysis never resolved -- the same argument fev_align()
#' makes about downscaling.
#'
#' @noRd
fev_weather_grid <- function(aoi, spacing) {
  if (!is.numeric(spacing) || length(spacing) != 1L || spacing <= 0) {
    fev_abort("{.arg spacing} must be a single positive number, in degrees.")
  }
  bb <- fev_bbox(sf::st_transform(aoi, 4326))
  lon <- seq(floor(bb[["xmin"]] / spacing) * spacing,
             ceiling(bb[["xmax"]] / spacing) * spacing, by = spacing)
  lat <- seq(floor(bb[["ymin"]] / spacing) * spacing,
             ceiling(bb[["ymax"]] / spacing) * spacing, by = spacing)
  g <- expand.grid(long = lon, lat = lat)
  # Ordered north to south, west to east, so the row order maps onto a raster
  # read the same way.
  g <- g[order(-g$lat, g$long), ]
  data.frame(id = seq_len(nrow(g)), lat = g$lat, long = g$long,
             stringsAsFactors = FALSE)
}

#' Read a URL as one string, retrying when the service says slow down
#'
#' A named function rather than an inline `readLines()` for two reasons. The
#' response parsing can be exercised offline against a recorded fixture -- the
#' multi-point shape is where this file's only real bug lived, and it is not
#' reachable by a test that needs the network. And Open-Meteo is free and
#' rate-limited: a multi-year request over twenty points earns an HTTP 429 part
#' way through, which is a reason to wait rather than to fail.
#'
#' The status code arrives in a warning from `file()` while the error itself only
#' says "cannot open the connection", so the warning is captured to tell 429
#' (wait) from 400 (the request is wrong and waiting will not help).
#'
#' @noRd
fev_read_url <- function(url, year = NA_character_, tries = 4L, pause = 15) {
  status <- NA_character_
  for (attempt in seq_len(tries)) {
    res <- withCallingHandlers(
      tryCatch(paste(readLines(url, warn = FALSE), collapse = ""),
               error = function(e) {
                 structure(conditionMessage(e), class = "fev_url_failed")
               }),
      warning = function(w) {
        msg <- conditionMessage(w)
        if (grepl("HTTP status", msg)) {
          hit <- regmatches(msg, regexpr("[0-9]{3}", msg))
          if (length(hit)) status <<- hit
        }
        invokeRestart("muffleWarning")
      }
    )
    if (!inherits(res, "fev_url_failed")) {
      return(res)
    }
    if (!identical(status, "429") || attempt == tries) {
      break
    }
    # Linear backoff: the limit is per minute as well as per day, so waiting a
    # few tens of seconds is usually enough, and hammering a free service is not
    # something this package should do on the user's behalf.
    wait <- pause * attempt
    fev_inform(c(
      "Rate-limited by Open-Meteo. Waiting {wait} second{?s} and retrying.",
      i = "Attempt {attempt} of {tries}."
    ), class = "fev_rate_limited", .envir = environment())
    Sys.sleep(wait)
  }

  msg <- as.character(res)
  hint <- if (identical(status, "429")) {
    "Rate-limited after {tries} attempt{?s}. Open-Meteo is free and capped \\
     per minute and per day: fetch fewer years at a time, coarsen \\
     {.arg spacing}, or come back later. Whole years already downloaded are \\
     in the cache."
  } else if (identical(status, "400")) {
    "The request was refused as malformed. The usual cause is a date the \\
     archive does not have, or a period ending in the future."
  } else {
    "Check network egress to {.url open-meteo.com}."
  }
  fev_abort(c(
    "The Open-Meteo request failed for {year}{if (is.na(status)) '' else paste0(' (HTTP ', status, ')')}.",
    x = "{msg}",
    i = hint
  ), class = "fev_weather_failed", .envir = environment())
}

#' One year, every point, keeping a single hour
#'
#' @section Why the requested point, not the served one, is the identity:
#' The response echoes the coordinates of the reanalysis cell it read, and
#' several requested points can share one cell. They do not share a series:
#' Open-Meteo adjusts temperature to the elevation of the requested location.
#' Three points inside cell 43.40949 / 6.341829, at 274, 221 and 77 m, came back
#' at 34.8, 34.8 and 35.4 degrees for noon on 2021-08-16 -- verified 2026-08-17.
#' So the station id follows the requested grid, and the served cell with its
#' elevation travels in the provenance as a diagnostic.
#'
#' The consequence worth stating: this is not a raw reanalysis extraction. The
#' elevation adjustment helps in relief and is a departure from the CEMS
#' product, which reads its cell and stops.
#'
#' @noRd
fev_open_meteo_year <- function(pts, from, to, hour) {
  url <- paste0(
    .FEV_ENDPOINTS$open_meteo, "?",
    "latitude=", paste(pts$lat, collapse = ","),
    "&longitude=", paste(pts$long, collapse = ","),
    # One day earlier than asked: the 24-hour rainfall ending at noon on the
    # first day reaches back into the previous evening, and a chunk boundary
    # must not silently zero it. The extra day is dropped below.
    "&start_date=", format(from - 1L, "%Y-%m-%d"),
    "&end_date=", format(to, "%Y-%m-%d"),
    "&hourly=", paste(.FEV_OPEN_METEO_VARS, collapse = ","),
    "&timezone=UTC"
  )

  txt <- fev_read_url(url, year = format(from, "%Y"))
  parsed <- jsonlite::fromJSON(txt, simplifyVector = TRUE)

  if (isTRUE(parsed$error)) {
    reason <- parsed$reason %||% "no reason given"
    fev_abort(c(
      "Open-Meteo refused the request.",
      x = "{reason}"
    ), class = "fev_weather_failed", .envir = environment())
  }

  # A single point returns a JSON object, several return an array -- which
  # jsonlite turns into a data frame whose `hourly` column is itself a data
  # frame of lists. Branching on is.data.frame() rather than on the presence of
  # `hourly`, which is non-NULL in both shapes and was this function's first bug.
  multi <- is.data.frame(parsed)
  n_got <- if (multi) nrow(parsed) else 1L

  # Series come back in request order and nothing in the response keys one to
  # its point, so that ordering is load-bearing and the count is the only thing
  # that can be checked. A silent mismatch would attribute weather to the wrong
  # place, which is worse than failing.
  if (n_got != nrow(pts)) {
    n_asked <- nrow(pts)
    fev_abort(c(
      "Asked for {n_asked} point{?s} and got {n_got} series back.",
      i = "Points are matched to series by position, so a mismatch would \\
           attribute weather to the wrong place."
    ), class = "fev_weather_mismatch", .envir = environment())
  }

  series <- lapply(seq_len(n_got), function(i) {
    if (multi) {
      list(cell_lat = parsed$latitude[i], cell_long = parsed$longitude[i],
           elev = parsed$elevation[i],
           hourly = lapply(parsed$hourly, function(col) col[[i]]))
    } else {
      list(cell_lat = parsed$latitude, cell_long = parsed$longitude,
           elev = parsed$elevation, hourly = parsed$hourly)
    }
  })

  rows <- lapply(seq_along(series), function(i) {
    h <- series[[i]]$hourly
    if (is.null(h) || !length(h$time)) {
      return(NULL)
    }
    stamp <- as.character(h$time)
    at <- which(substr(stamp, 12, 13) == sprintf("%02d", hour))
    if (!length(at)) {
      return(NULL)
    }
    d <- as.Date(substr(stamp[at], 1, 10))

    # Temperature, humidity and wind are the noon OBSERVATION. Rainfall is not:
    # the system's input is the rain ACCUMULATED over the 24 hours ending at
    # noon. Taking the hourly value at noon instead -- which this function did
    # first -- discards 23 hours of every day's rain, and the moisture codes
    # notice. Measured over three years in the Maures: rain on 10% of days
    # instead of 39%, and DC at 1 949 on 2021-08-16 instead of 619.
    #
    # It also looked like a different bug. The inflated DC reads as a missing
    # seasonal reset, and it is not: with the rain right, winter precipitation
    # drains the DC on its own, which is what it is designed to do.
    hourly_prec <- as.numeric(h[[.FEV_OPEN_METEO_VARS[["prec"]]]])
    prec24 <- vapply(at, function(k) {
      sum(hourly_prec[max(1L, k - 23L):k], na.rm = TRUE)
    }, numeric(1))

    out <- data.frame(
      id = pts$id[i], lat = pts$lat[i], long = pts$long[i],
      yr = as.integer(format(d, "%Y")),
      mon = as.integer(format(d, "%m")),
      day = as.integer(format(d, "%d")),
      temp = as.numeric(h[[.FEV_OPEN_METEO_VARS[["temp"]]]])[at],
      rh   = as.numeric(h[[.FEV_OPEN_METEO_VARS[["rh"]]]])[at],
      ws   = as.numeric(h[[.FEV_OPEN_METEO_VARS[["ws"]]]])[at],
      prec = prec24,
      stringsAsFactors = FALSE
    )
    # Drop the extra leading day, which was fetched only to fill that window.
    out[d >= from, , drop = FALSE]
  })

  out <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  if (is.null(out)) {
    return(NULL)
  }
  num1 <- function(x) if (length(x) && !is.null(x)) as.numeric(x) else NA_real_
  attr(out, "served") <- data.frame(
    id        = pts$id,
    cell_lat  = vapply(series, function(p) num1(p$cell_lat), numeric(1)),
    cell_long = vapply(series, function(p) num1(p$cell_long), numeric(1)),
    elev_m    = vapply(series, function(p) num1(p$elev), numeric(1)),
    stringsAsFactors = FALSE
  )
  out
}

# --- from weather to a dated FWI raster --------------------------------------

#' Fire Weather Index from open weather, as a dated raster
#'
#' Runs the FWI system on a weather table point by point and assembles the
#' result into a dated `SpatRaster`, ready for [fev_fwi_percentile()].
#'
#' @section Why point by point:
#' The moisture codes are cumulative: each day's FFMC, DMC and DC depend on the
#' previous day's at the same place. `cffdrs::fwi(batch = TRUE)` accumulates them
#' independently per station id — verified: two stations given identical startup
#' values but different weather diverge correctly. So going through the tabular
#' path gives **per-cell integration**, which the gridded path of
#' [fev_fwi_calc()] cannot: `cffdrs::fwiRaster()` takes scalar startup codes, so
#' that route carries them forward as spatial means and smooths the drought
#' signal.
#'
#' That is the main reason to prefer this function over rasterising first.
#'
#' @section Startup values, and whether to restart each year:
#' Every point starts from the same `init`, and `cffdrs` warns about it. The first
#' weeks of any record are therefore a spin-up rather than a result. Start the
#' record earlier than the period you intend to analyse.
#'
#' By default the codes are integrated **continuously** over the whole record,
#' because that is what the Drought Code is built to do: winter rain drains it,
#' and a genuinely dry winter should carry over into spring. Measured over three
#' years in the Maures, the difference on 16 August 2021 is DC 643 continuous
#' against 619 restarted each January, and FWI 84.3 against 84.2.
#'
#' `reset = "annual"` restarts from `init` at the beginning of each year, which is
#' what operational implementations do at fire-season onset. It is worth having
#' for a record that begins mid-season, or to reproduce an implementation that
#' does it — not as a routine correction.
#'
#' A warning about diagnosing this from the FWI: the duration factor saturates.
#' `1000 / (25 + 108.64 * exp(-0.023 * BUI))` is 38.3 at BUI 200 and 39.8 at BUI
#' 300, against an asymptote of 40. Above roughly BUI 250 the FWI is nearly blind
#' to further drought, so a Drought Code that has drifted to twice its physical
#' value does not make the FWI look wrong. Check DC and BUI directly.
#'
#' @param weather A [fev_source] from [fev_fetch_weather()], or a data frame in
#'   the same shape.
#' @param index Which index to return as the raster: `"FWI"` by default, or any
#'   column `cffdrs` produces — `"DC"`, `"ISI"`, `"BUI"`, `"DSR"` and so on.
#' @param crs_work EPSG code for the output raster. `NULL` keeps lon/lat, which
#'   avoids a reprojection the values do not need.
#' @param init Startup codes, passed through to [fev_fwi_calc()].
#' @param reset `"none"` (default) integrates the whole record continuously;
#'   `"annual"` restarts the moisture codes from `init` at the start of each year.
#' @param reset_month Month the annual restart happens in. Defaults to January.
#'
#' @return A `fev_danger_layer` holding a `SpatRaster` with one dated layer per
#'   day.
#'
#' @seealso [fev_fetch_weather()], [fev_fwi_percentile()], [fev_fwi_calc()].
#'
#' @examples
#' # A two-point, three-day table in the shape fev_fetch_weather() returns.
#' w <- expand.grid(id = 1:2, day = 1:3)
#' w$lat <- c(43.2, 43.3)[w$id]
#' w$long <- c(6.3, 6.4)[w$id]
#' w$yr <- 2021
#' w$mon <- 8
#' w$temp <- c(30, 22)[w$id]
#' w$rh <- c(25, 55)[w$id]
#' w$ws <- c(20, 8)[w$id]
#' w$prec <- 0
#' r <- fev_fwi_from_weather(w)
#' terra::nlyr(fev_data(r))
#'
#' @export
fev_fwi_from_weather <- function(weather,
                                 index = "FWI",
                                 crs_work = NULL,
                                 init = c(ffmc = 85, dmc = 6, dc = 15),
                                 reset = c("none", "annual"),
                                 reset_month = 1L) {
  reset <- match.arg(reset)
  rec <- if (inherits(weather, "fev_source")) weather$source else NULL
  tab <- if (inherits(weather, "fev_source")) weather$data else weather

  if (!is.data.frame(tab)) {
    fev_abort(c(
      "{.arg weather} must be a {.cls fev_source} or a {.cls data.frame}.",
      x = "Got {.cls {class(weather)[1]}}."
    ))
  }
  needed <- c("id", "lat", "long", "yr", "mon", "day", "temp", "rh", "ws",
              "prec")
  missing <- setdiff(needed, names(tab))
  if (length(missing)) {
    fev_abort(c(
      "{.arg weather} is missing column{?s} {.field {missing}}.",
      i = "{.fn fev_fetch_weather} returns exactly this shape."
    ), class = "fev_bad_weather", .envir = environment())
  }

  tab <- tab[order(tab$id, tab$yr, tab$mon, tab$day), ]

  # batch = TRUE is what makes the codes accumulate per id rather than across the
  # whole table. Dropping it would silently mix every point's drought.
  #
  # The annual restart is one cffdrs call per season rather than a distinct
  # station id per point-year: cffdrs refuses a batch whose stations do not all
  # span the same dates ("Multiple stations have to start and end at the same
  # dates"), and a truncated final year never does.
  if (identical(reset, "annual")) {
    season <- tab$yr - (tab$mon < reset_month)
    fwi <- do.call(rbind, lapply(split(tab, season), function(chunk) {
      fev_fwi_calc(chunk[order(chunk$id, chunk$yr, chunk$mon, chunk$day), ],
                   init = init)
    }))
    rownames(fwi) <- NULL
  } else {
    fwi <- fev_fwi_calc(tab, init = init)
  }
  if (!index %in% names(fwi)) {
    fev_abort(c(
      "No index {.val {index}} in the result.",
      i = "Available: {.val {setdiff(names(fwi), c('ID','LAT','LONG','YR','MON','DAY'))}}."
    ), .envir = environment())
  }

  out <- fev_fwi_assemble(fwi, tab, index, crs_work)

  prov <- fev_prov_new(crs_work = crs_work)
  if (!is.null(rec)) {
    prov <- fev_prov_add_source(
      prov, dataset = rec$dataset %||% "weather",
      provider = rec$provider %||% NA_character_,
      endpoint = rec$endpoint %||% NA_character_,
      query = rec$query, millesime = rec$millesime %||% NA,
      version = rec$version %||% NA_character_,
      crs_native = rec$crs_native %||% NA_character_,
      third_party = isTRUE(rec$third_party)
    )
  }
  prov <- fev_prov_add_step(
    prov, fun = "fev_fwi_from_weather",
    params = list(index = index, n_points = length(unique(tab$id)),
                  n_days = terra::nlyr(out), init = as.list(init),
                  reset = reset, reset_month = reset_month,
                  engine = "cffdrs::fwi (batch, per-point accumulation)",
                  crs_work = crs_work %||% "EPSG:4326"),
    notes = if (identical(reset, "annual")) {
      "codes accumulated per point, restarted each year"
    } else {
      "codes accumulated per point, one continuous integration"
    }
  )

  new_fev_layer(out, role = "fwi", provenance = prov,
                units = "FWI system, dimensionless",
                class = "fev_danger_layer")
}

#' Assemble a point-day table into a dated raster
#'
#' Built from the regular lon/lat grid directly rather than by rasterising
#' points day by day: 30 years is 10 958 days, and one rasterize call per day
#' would take longer than the download.
#'
#' @noRd
fev_fwi_assemble <- function(fwi, tab, index, crs_work) {
  pts <- unique(tab[, c("id", "lat", "long")])
  lons <- sort(unique(pts$long))
  lats <- sort(unique(pts$lat), decreasing = TRUE)

  dates <- as.Date(sprintf("%d-%02d-%02d", fwi$YR, fwi$MON, fwi$DAY))
  udates <- sort(unique(dates))
  # The cell index is arithmetic on the row and column of the lon/lat grid, not
  # the rank of the point in a sorted table: an AOI whose grid is not a full
  # rectangle -- a coastal strip, say -- would shift every row after the gap.
  cell <- (match(fwi$LAT, lats) - 1L) * length(lons) + match(fwi$LONG, lons)
  layer <- match(dates, udates)
  if (anyNA(cell)) {
    fev_abort(c(
      "{sum(is.na(cell))} row{?s} could not be placed on the lon/lat grid.",
      i = "The coordinates in the index table must be the ones in \\
           {.arg weather}, unrounded."
    ), class = "fev_ungriddable", .envir = environment())
  }

  m <- matrix(NA_real_, nrow = length(lats) * length(lons),
              ncol = length(udates))
  m[cbind(cell, layer)] <- fwi[[index]]

  half <- if (length(lons) > 1L) diff(lons)[1] / 2 else 0.05
  halfy <- if (length(lats) > 1L) abs(diff(lats)[1]) / 2 else 0.05
  r <- terra::rast(
    nrows = length(lats), ncols = length(lons),
    xmin = min(lons) - half, xmax = max(lons) + half,
    ymin = min(lats) - halfy, ymax = max(lats) + halfy,
    crs = "EPSG:4326", nlyr = length(udates)
  )
  terra::values(r) <- m
  terra::time(r) <- udates
  names(r) <- format(udates, "d%Y%m%d")

  if (!is.null(crs_work)) {
    # Nearest neighbour: these are cell values, and interpolating between
    # reanalysis cell centres invents variation the model never resolved.
    r <- terra::project(r, paste0("EPSG:", crs_work), method = "near")
  }
  r
}
