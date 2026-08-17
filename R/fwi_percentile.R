# Percentile calibration: the methodological core of the danger module.
#
# Raw FWI breaks are not comparable between climates. An FWI of 25 is
# exceptional in Brittany and an ordinary July afternoon in the Var, so a map
# classified on absolute thresholds mostly draws the climate, not the anomaly.
# Ranking each value against a local reference climatology is what removes
# that, and it is the step the brief calls the heart of the method.
#
# caliver did this for ECMWF and was archived from CRAN in October 2021, so
# the method is reimplemented here rather than depended on. Its algorithm for
# deriving danger thresholds is reproduced in fev_fwi_thresholds() with the
# constants read from its source; the percentile RANK below is the package's
# own, simpler thing, and the two are deliberately not conflated -- caliver's
# own vignette makes the same distinction.

#' Percentile rank against a reference climatology
#'
#' Replaces each fire danger value by its rank within a local reference
#' distribution, expressed as a percentile from 0 to 100. A value of 95 means
#' the day is worse than 95% of the reference period at that place.
#'
#' @section Why this exists:
#' Absolute FWI thresholds are calibrated somewhere. Applied elsewhere they
#' mostly reproduce the climatology: a map of raw FWI over France in August is
#' close to a map of summer dryness, and classifying it on Canadian or even
#' European-mean breaks puts the whole Mediterranean in the top class every
#' year, which discriminates nothing. Percentile ranks are dimensionless and
#' local, so a 98th percentile day means the same thing in the Var and in
#' Brittany — an unusually dangerous day *there*.
#'
#' The cost is that they say nothing about absolute severity. A 98th percentile
#' day in Brittany may be an FWI a Var fire brigade would ignore. Report both,
#' or say which one you are mapping.
#'
#' @section Pixel or region:
#' `by = "pixel"` ranks each cell against its own history. It is the sharper
#' choice and needs no extra input, but at the ~25 km grid of the ERA5-driven
#' CEMS product a single cell mixes coast and ridge.
#'
#' `by = "region"` pools the reference values of every cell in a region and
#' ranks all of them against that one distribution, which is what caliver does
#' for administrative units. It needs `regions`, and it makes the result depend
#' on a zoning choice that should be reported.
#'
#' @section Length of the reference period:
#' The WMO climatological standard normal is a **30-year** period ending in a
#' year ending in 0 — 1991–2020 at present (WMO-No. 1203, 2017 edition). This
#' function warns below 10 years and informs below 30. Nothing stops you using
#' less; the record just says how much less.
#'
#' @param x A `SpatRaster` of daily fire danger, one layer per day, or a
#'   [fev_source] holding one. Layers must carry dates: without them there is
#'   no way to subset a reference period, and a climatology built on an unknown
#'   period is not a climatology.
#' @param ref_period Two-element vector bounding the reference: years
#'   (`c(1991, 2020)`) or dates. `NULL` uses every layer, and says so.
#' @param by `"pixel"` or `"region"`. See the section above.
#' @param regions Required for `by = "region"`: an `sf`, `SpatVector` or
#'   categorical `SpatRaster` of zones.
#' @param season Two `"MM-DD"` strings restricting the reference to a fire
#'   season, or `NULL` for the whole year. Defaults to 1 April – 31 October,
#'   the northern-hemisphere season caliver uses. Off-season days in a
#'   reference distribution drag every percentile up, because most of them are
#'   near zero.
#' @param time Dates of the layers, when `x` does not carry them.
#' @param min_ref Warn when a reference distribution has fewer than this many
#'   values. Defaults to 365 — one year of daily data.
#'
#' @return A `fev_danger_layer` holding a `SpatRaster` of percentile ranks in
#'   `[0, 100]`, one layer per input layer.
#'
#' @seealso [fev_fwi_thresholds()] for caliver's threshold derivation, which
#'   answers a different question, and [fev_danger_index()] to combine the
#'   result with fuel.
#'
#' @source
#' Method reimplemented rather than depended on: caliver (Vitolo, Di Giuseppe,
#' D'Andrea) was archived from CRAN in October 2021. Reference-period length
#' guidance: WMO, *Guidelines on the Calculation of Climate Normals*,
#' WMO-No. 1203, 2017 edition; the standard normal is 30 years, redefined in
#' 2015 as the most recent 30-year period ending in a year ending in 0.
#' Fire season default: 1 April – 31 October in the northern hemisphere, as
#' used by Vitolo et al. (2018), *PLoS ONE* 13(1): e0189419.
#'
#' @examples
#' # Three years of daily values on a tiny grid.
#' r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 50,
#'                  ymin = 0, ymax = 50, crs = "EPSG:2154", nlyr = 30)
#' terra::values(r) <- matrix(seq_len(120), nrow = 4)
#' terra::time(r) <- seq(as.Date("2020-06-01"), by = "day", length.out = 30)
#' p <- fev_fwi_percentile(r, season = NULL, min_ref = 10)
#' terra::global(fev_data(p), "max", na.rm = TRUE)
#'
#' @export
fev_fwi_percentile <- function(x,
                               ref_period = NULL,
                               by = c("pixel", "region"),
                               regions = NULL,
                               season = c("04-01", "10-31"),
                               time = NULL,
                               min_ref = 365) {
  by <- match.arg(by)
  prov <- if (inherits(x, "fev_source")) NULL else attr(x, "provenance")
  rec <- if (inherits(x, "fev_source")) x$source else NULL
  x <- if (inherits(x, "fev_source")) x$data else x

  if (!inherits(x, "SpatRaster")) {
    fev_abort(c(
      "{.arg x} must be a {.cls SpatRaster} or a {.cls fev_source} holding \\
       one.",
      x = "Got {.cls {class(x)[1]}}."
    ))
  }

  dates <- fev_layer_dates(x, time)
  ref_idx <- fev_ref_index(dates, ref_period, season)
  fev_check_ref_span(dates[ref_idx], ref_period, min_ref)

  ref <- x[[ref_idx]]
  out <- if (identical(by, "pixel")) {
    fev_percentile_pixel(x, ref)
  } else {
    fev_percentile_region(x, ref, regions, min_ref)
  }

  names(out) <- names(x)
  terra::time(out) <- dates

  prov <- prov %||% fev_prov_new(crs_work = NA)
  if (!is.null(rec)) {
    prov <- fev_prov_add_source(
      prov, dataset = rec$dataset %||% "fire_danger",
      provider = rec$provider %||% NA_character_,
      endpoint = rec$endpoint %||% NA_character_,
      millesime = rec$millesime %||% NA, query = rec$query,
      crs_native = rec$crs_native %||% NA_character_
    )
  }
  prov <- fev_prov_add_step(
    prov, fun = "fev_fwi_percentile",
    params = list(
      by = by, ref_period = fev_period_label(ref_period),
      season = season %||% "whole year",
      n_ref_layers = length(ref_idx), n_layers = terra::nlyr(x),
      ref_first = as.character(min(dates[ref_idx])),
      ref_last = as.character(max(dates[ref_idx])),
      ref_years = length(unique(format(dates[ref_idx], "%Y"))),
      regions = if (is.null(regions)) "none" else class(regions)[1],
      min_ref = min_ref
    )
  )

  new_fev_layer(out, role = "fwi_percentile", provenance = prov,
                units = "percentile rank, 0-100",
                class = "fev_danger_layer")
}

#' Rank every cell against its own history
#'
#' Written as a matrix-aware function passed to `terra::app()` so that large
#' stacks are chunked rather than read whole. The comparison `rf <= tgt[, j]`
#' recycles down columns, which is the per-cell comparison wanted.
#'
#' @noRd
fev_percentile_pixel <- function(x, ref) {
  n_t <- terra::nlyr(x)
  n_r <- terra::nlyr(ref)
  f <- function(v) {
    if (is.null(dim(v))) {
      v <- matrix(v, nrow = 1L)
    }
    tgt <- v[, seq_len(n_t), drop = FALSE]
    rf <- v[, n_t + seq_len(n_r), drop = FALSE]
    out <- matrix(NA_real_, nrow(v), n_t)
    for (j in seq_len(n_t)) {
      out[, j] <- 100 * rowMeans(rf <= tgt[, j], na.rm = TRUE)
    }
    out[!is.finite(out)] <- NA_real_
    out
  }
  terra::app(c(x, ref), fun = f)
}

#' Rank every cell against the pooled history of its region
#' @noRd
fev_percentile_region <- function(x, ref, regions, min_ref) {
  if (is.null(regions)) {
    fev_abort(c(
      "{.arg regions} is required when {.code by = \"region\"}.",
      i = "Pass an {.cls sf}, {.cls SpatVector} or categorical \\
           {.cls SpatRaster} of zones.",
      i = "Pooling over a region is what makes the result depend on a zoning \\
           choice, so it has to be yours."
    ), class = "fev_no_regions")
  }
  zones <- fev_zone_raster(regions, x)

  z <- terra::values(zones)[, 1]
  tgt <- terra::values(x)
  rf <- terra::values(ref)
  out <- matrix(NA_real_, nrow(tgt), ncol(tgt))

  ids <- sort(unique(stats::na.omit(z)))
  if (!length(ids)) {
    fev_abort(c(
      "No region covers the danger grid.",
      i = "Usually disjoint extents, or a zoning finer than the danger cell \\
           size."
    ), class = "fev_disjoint_extent")
  }

  thin <- integer()
  for (id in ids) {
    cells <- which(z == id)
    pool <- as.numeric(rf[cells, , drop = FALSE])
    pool <- pool[!is.na(pool)]
    if (!length(pool)) {
      next
    }
    if (length(pool) < min_ref) {
      thin <- c(thin, id)
    }
    pool <- sort(pool)
    for (j in seq_len(ncol(tgt))) {
      v <- tgt[cells, j]
      out[cells, j] <- 100 * findInterval(v, pool, rightmost.closed = FALSE) /
        length(pool)
    }
  }

  if (length(thin)) {
    fev_warn(c(
      "{length(thin)} region{?s} below the {min_ref}-value reference floor.",
      x = "Ids: {.val {thin}}.",
      i = "A percentile rank against a short pool is quantised: with 50 values \\
           the finest distinction available is 2 points."
    ), class = "fev_thin_reference", .envir = environment())
  }

  res <- terra::rast(x)
  terra::values(res) <- out
  res
}

#' Zones as an integer raster on the danger grid
#' @noRd
fev_zone_raster <- function(regions, x) {
  if (inherits(regions, "SpatRaster")) {
    if (!isTRUE(terra::compareGeom(regions, x, stopOnError = FALSE))) {
      fev_warn(c(
        "Resampling the region layer onto the danger grid with nearest \\
         neighbour.",
        i = "Zones are categorical; this moves their boundaries."
      ), class = "fev_categorical_resampled")
      regions <- terra::resample(regions, x, method = "near")
    }
    return(regions[[1]])
  }
  v <- if (inherits(regions, "SpatVector")) regions else terra::vect(regions)
  if (!fev_crs_equal(v, x)) {
    v <- terra::project(v, x)
  }
  terra::rasterize(v, x, field = seq_len(nrow(v)))
}

#' Dates of the layers, or a refusal
#' @noRd
fev_layer_dates <- function(x, time) {
  dates <- time %||% terra::time(x)
  if (is.null(dates) || all(is.na(dates))) {
    fev_abort(c(
      "The layers carry no dates.",
      i = "Set them with {.code terra::time(x) <- dates}, or pass \\
           {.arg time}.",
      i = "A reference period cannot be subset without them, and a \\
           climatology over an unknown period is not a climatology."
    ), class = "fev_no_time")
  }
  dates <- as.Date(dates)
  if (length(dates) != terra::nlyr(x)) {
    fev_abort(c(
      "{.arg time} must have one date per layer.",
      x = "Got {length(dates)} date{?s} for {terra::nlyr(x)} layer{?s}."
    ), .envir = environment())
  }
  dates
}

#' Which layers form the reference distribution
#' @noRd
fev_ref_index <- function(dates, ref_period, season) {
  keep <- rep(TRUE, length(dates))

  if (!is.null(ref_period)) {
    bounds <- fev_period_bounds(ref_period)
    keep <- keep & dates >= bounds[1] & dates <= bounds[2]
  }

  if (!is.null(season)) {
    if (length(season) != 2L) {
      fev_abort("{.arg season} must be two {.val MM-DD} strings, or NULL.")
    }
    md <- format(dates, "%m-%d")
    keep <- keep & md >= season[1] & md <= season[2]
  }

  idx <- which(keep)
  if (!length(idx)) {
    fev_abort(c(
      "No layer falls inside the reference period and season.",
      i = "Layers span {.val {as.character(range(dates))}}.",
      i = "Requested period {.val {fev_period_label(ref_period)}}, season \\
           {.val {season %||% 'whole year'}}."
    ), class = "fev_empty_reference", .envir = environment())
  }
  idx
}

#' @noRd
fev_period_bounds <- function(period) {
  if (length(period) != 2L) {
    fev_abort("{.arg ref_period} must have two elements.")
  }
  # Years, as numbers or as the strings the rest of the package passes around
  # ("2016", "2026" in fev_fetch_burnt), widen to the whole calendar year. Only
  # accepting numeric years meant c("2021", "2021") died inside as.Date() with
  # "character string is not in a standard unambiguous format".
  chr <- as.character(period)
  if (is.numeric(period) || all(grepl("^[0-9]{4}$", chr))) {
    return(c(as.Date(sprintf("%s-01-01", chr[1])),
             as.Date(sprintf("%s-12-31", chr[2]))))
  }
  out <- as.Date(chr, optional = TRUE)
  if (anyNA(out)) {
    bad <- chr[is.na(out)]
    fev_abort(c(
      "Cannot read {.val {bad}} as a date or a year.",
      i = "Give {.code c(\"2021-05-01\", \"2021-09-30\")} or \
           {.code c(2021, 2021)}."
    ), class = "fev_bad_period", .envir = environment())
  }
  out
}

#' @noRd
fev_period_label <- function(period) {
  if (is.null(period)) "all layers" else paste(as.character(period), collapse = "..")
}

#' Say how long the reference actually is, in years
#' @noRd
fev_check_ref_span <- function(ref_dates, ref_period, min_ref) {
  if (is.null(ref_period)) {
    fev_inform(c(
      "No {.arg ref_period} given: every layer is used as its own reference.",
      i = "Each value is then ranked against the record it belongs to, which \\
           is defensible only when that record is the climatology you mean."
    ), class = "fev_default_reference")
  }
  n_years <- length(unique(format(ref_dates, "%Y")))
  if (n_years < 10L) {
    fev_warn(c(
      "The reference period spans {n_years} year{?s}.",
      i = "The WMO climatological standard normal is 30 years (WMO-No. 1203). \\
           Below ten, a single hot summer moves every percentile in the map.",
      i = "It is recorded in the provenance either way."
    ), class = "fev_short_reference", .envir = environment())
  } else if (n_years < 30L) {
    fev_inform(
      "Reference period spans {n_years} years; the WMO standard normal is 30.",
      class = "fev_short_reference", .envir = environment()
    )
  }
  if (length(ref_dates) < min_ref) {
    fev_warn(c(
      "Only {length(ref_dates)} reference value{?s} per cell.",
      i = "Percentile ranks against a short reference are quantised and \\
           unstable at the tails, which is exactly where fire danger lives."
    ), class = "fev_thin_reference", .envir = environment())
  }
  invisible(TRUE)
}

#' Danger thresholds derived from a climatology
#'
#' Reimplements caliver's `get_fire_danger_levels()`: the five interior FWI
#' breaks separating six danger classes, derived from the record itself rather
#' than imported.
#'
#' @section The algorithm, and where its constants come from:
#' For each year, the `(1 - ndays/365)` quantile of the fire index is taken —
#' with the default `ndays = 4` that is the 98th percentile, read as "the level
#' exceeded on the four days a year a fire is expected". The **median across
#' years** of those yearly extremes is the extreme danger value. It is then
#' inverted through the Canadian system's intensity relation to a fire
#' intensity, and the six classes fall out of a geometric progression of that
#' intensity.
#'
#' The numeric constants (`0.289`, `0.980`, `1.546`, `1.013`, `0.647`) are
#' caliver's, read from its source. They belong to the Canadian FWI-intensity
#' relationships. This package has **not** verified them against Van Wagner's
#' original report — it reproduces a published implementation, and says so.
#'
#' @section What it is not:
#' This is not [fev_fwi_percentile()]. That one asks "how unusual is today
#' here"; this one asks "where should the class boundaries sit for this
#' record". caliver's own documentation insists on the distinction, and mixing
#' them produces a map that is neither.
#'
#' @param x A `SpatRaster` of daily fire danger, or a numeric vector with a
#'   `years` attribute, or a `fev_source`.
#' @param ndays Days per year on which a fire is expected. caliver's default is
#'   4, which yields the 98th percentile.
#' @param season Fire season, as in [fev_fwi_percentile()].
#' @param time Dates of the layers, when `x` does not carry them.
#'
#' @return A numeric vector of five breaks, with the derived extreme value in
#'   its `extreme` attribute. Feed it to [fev_fwi_classes()].
#'
#' @source
#' caliver, `R/get_fire_danger_levels.R`, ecmwf/caliver on GitHub, read
#' 2026-08-16. Method published as Vitolo, C., Di Giuseppe, F., D'Andrea, M.
#' (2018), *Caliver: An R package for CALIbration and VERification of forest
#' fire gridded model outputs*, PLoS ONE 13(1): e0189419.
#' \doi{10.1371/journal.pone.0189419}. Applied there to ERA-Interim 1980–2016
#' over the April–October season, the published European result is
#' `2, 5, 10, 19, 33`.
#'
#' @examples
#' r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 50,
#'                  ymin = 0, ymax = 50, crs = "EPSG:2154", nlyr = 40)
#' set.seed(1)
#' terra::values(r) <- runif(160, 0, 60)
#' terra::time(r) <- seq(as.Date("2019-06-01"), by = "day", length.out = 40)
#' fev_fwi_thresholds(r, season = NULL)
#'
#' @export
fev_fwi_thresholds <- function(x, ndays = 4, season = c("04-01", "10-31"),
                               time = NULL) {
  x <- if (inherits(x, "fev_source")) x$data else x
  if (!inherits(x, "SpatRaster")) {
    fev_abort("{.arg x} must be a {.cls SpatRaster} or a {.cls fev_source}.")
  }
  dates <- fev_layer_dates(x, time)
  idx <- fev_ref_index(dates, NULL, season)
  x <- x[[idx]]
  dates <- dates[idx]

  vals <- terra::values(x)
  if (all(is.na(vals))) {
    fev_warn("Every value is {.val NA}; no thresholds can be derived.",
             class = "fev_all_na")
    return(structure(rep(NA_real_, 5L), extreme = NA_real_))
  }

  # floor() then /100 reproduces caliver exactly: ndays = 4 gives 0.98, not
  # 0.98904. Rounding it differently moves every threshold.
  extreme_percentile <- floor((1 - ndays / 365) * 100) / 100
  years <- format(dates, "%Y")
  yearly <- vapply(unique(years), function(y) {
    v <- as.numeric(vals[, which(years == y), drop = FALSE])
    as.numeric(stats::quantile(v[!is.na(v)], extreme_percentile))
  }, numeric(1))

  extreme_danger <- stats::median(yearly)
  if (!is.finite(extreme_danger) || extreme_danger <= 0) {
    fev_warn(c(
      "The derived extreme danger value is {.val {extreme_danger}}.",
      i = "The intensity inversion needs a positive value; thresholds are NA."
    ), class = "fev_no_root", .envir = environment())
    return(structure(rep(NA_real_, 5L), extreme = extreme_danger))
  }

  f <- function(i_component_0) {
    log(0.289 * i_component_0) - 0.980 * (log(extreme_danger))^1.546
  }
  root <- try(stats::uniroot(f = f, interval = c(0.1, 1e14)), silent = TRUE)
  if (inherits(root, "try-error")) {
    fev_warn(c(
      "No root found for the intensity inversion; thresholds are NA.",
      i = "Happens when the extreme value is very small: {.val \\
           {round(extreme_danger, 3)}} here."
    ), class = "fev_no_root", .envir = environment())
    return(structure(rep(NA_real_, 5L), extreme = extreme_danger))
  }

  a <- root$root^(1 / 5)
  thresholds <- vapply(1:5, function(i) {
    v <- round(exp(1.013 * (log(0.289 * a^i))^0.647), 0)
    if (is.na(v)) 0 else v
  }, numeric(1))

  structure(thresholds, extreme = extreme_danger, n_years = length(yearly),
            percentile = extreme_percentile)
}
