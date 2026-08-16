# Wrapper around cffdrs for user-supplied weather forcings.
#
# The package's own danger layers come from CEMS through fev_fetch_fwi(), which
# serves indices already computed. This is the other route: someone with their
# own station or gridded weather who wants the same indices from it. cffdrs
# does the physics; everything here is about refusing inputs that would give a
# plausible wrong answer.

#' Fire Weather Index from weather forcings
#'
#' Computes the Canadian Fire Weather Index System codes and indices — FFMC,
#' DMC, DC, ISI, BUI, FWI and DSR — from daily noon weather, wrapping
#' [cffdrs::fwi()] for tabular input and [cffdrs::fwiRaster()] for gridded
#' input.
#'
#' @section Units, which are where this goes wrong:
#' The system expects **noon local standard time** observations, in
#' `temp` degrees Celsius, `rh` percent, `ws` **kilometres per hour** and
#' `prec` millimetres accumulated over the preceding 24 hours. Wind in metres
#' per second is the classic mistake and produces indices that look entirely
#' reasonable; this function warns when the wind distribution suggests it, but
#' it cannot know. Check your source.
#'
#' @section Latitude is required, and why, exactly:
#' `cffdrs` defaults a missing latitude to 55°N and a missing longitude to
#' 120°W — central British Columbia — with a warning that is easy to miss in a
#' loop. Latitude drives the day-length adjustment in DMC and DC.
#'
#' Measured on the installed package (2026-08-16), that adjustment is
#' **banded**, not continuous: 43.3°N, 51°N and 55°N give bit-identical codes,
#' because metropolitan France and central British Columbia sit in the same
#' ≥ 30°N band. So for a study in metropolitan France the substitution happens
#' to be harmless.
#'
#' It is not harmless anywhere else. At 20°N — Guadeloupe, Martinique — ten
#' rainless days give a DMC 16% lower and a DC 26% lower than the substituted
#' 55°N would; in the southern hemisphere, Réunion at 21°S, the gap is larger
#' again. A default that is correct in the place you wrote the script and wrong
#' in the place you copy it to is worse than no default, so this function
#' **refuses** input without `lat` instead of substituting one.
#'
#' @section Startup values:
#' `init` defaults to `ffmc = 85`, `dmc = 6`, `dc = 15` — the spring startup
#' values `cffdrs` ships, read from the installed package. They originate in
#' the Canadian system's specification (Van Wagner 1987) and assume a snow-melt
#' spring startup, which much of Mediterranean France does not have. If your
#' series starts mid-season, or in a climate without a defined startup, carry
#' the codes over from a spin-up period instead of accepting these.
#'
#' @section On a sequence of grids:
#' The moisture codes are cumulative: each day's FFMC, DMC and DC depend on the
#' previous day's. [cffdrs::fwiRaster()] computes **one day**. Pass a list of
#' daily `SpatRaster` and this function iterates, feeding each day's codes into
#' the next, which is the part callers usually get wrong by re-initialising
#' every day.
#'
#' @param weather Daily noon weather. Either a `data.frame` with columns
#'   `temp`, `rh`, `ws`, `prec`, `lat` (and optionally `long`, `yr`, `mon`,
#'   `day`, `id`), a `SpatRaster` with layers named `temp`, `rh`, `ws`, `prec`
#'   for a single day, or a list of such `SpatRaster` for consecutive days.
#' @param init Startup values. See the section above.
#' @param months Month of each gridded step, `1`-`12`, used for the day-length
#'   adjustment. Length 1 or one per element of `weather`.
#' @param lat_adjust Apply the latitude day-length adjustment. Leave `TRUE`
#'   unless you have a reason.
#' @param out Passed to `cffdrs`: `"all"` keeps the inputs alongside the
#'   indices, `"fwi"` returns the indices only.
#'
#' @return A `fev_danger_layer` for gridded input, or a `data.frame` for
#'   tabular input, in both cases carrying the parameters in its provenance.
#'
#' @seealso [fev_fwi_percentile()], which is what makes these numbers
#'   comparable between climates, and [fev_fetch_fwi()] for the CEMS indices.
#'
#' @source
#' `cffdrs` 1.9.2, Wang, Cantin, Parisien, Wotton, Anderson and Flannigan.
#' Startup values and argument defaults read from the installed package on
#' 2026-08-16. The underlying system is Van Wagner, C.E. (1987), *Development
#' and structure of the Canadian Forest Fire Weather Index System*, Forestry
#' Technical Report 35, Canadian Forestry Service — cited as the origin of the
#' method, not read for this implementation.
#'
#' @examples
#' w <- data.frame(
#'   lat = 43.3, long = 6.4, yr = 2020, mon = 7, day = 1:5,
#'   temp = c(25, 28, 30, 31, 29), rh = c(40, 35, 30, 28, 33),
#'   ws = c(10, 12, 15, 20, 11), prec = c(0, 0, 0, 0, 2)
#' )
#' out <- fev_fwi_calc(w)
#' out$FWI
#'
#' @export
fev_fwi_calc <- function(weather,
                         init = c(ffmc = 85, dmc = 6, dc = 15),
                         months = NULL,
                         lat_adjust = TRUE,
                         out = "all") {
  fev_require("cffdrs", "compute Fire Weather Index codes")

  if (is.data.frame(weather)) {
    return(fev_fwi_calc_table(weather, init, lat_adjust, out))
  }
  if (inherits(weather, "SpatRaster")) {
    weather <- list(weather)
  }
  if (!is.list(weather) ||
      !all(vapply(weather, inherits, logical(1), what = "SpatRaster"))) {
    fev_abort(c(
      "{.arg weather} must be a {.cls data.frame}, a {.cls SpatRaster}, or a \\
       list of {.cls SpatRaster}.",
      x = "Got {.cls {class(weather)[1]}}."
    ))
  }
  fev_fwi_calc_grid(weather, init, months, lat_adjust, out)
}

.FEV_FWI_INPUTS <- c("temp", "rh", "ws", "prec")

#' @noRd
fev_fwi_calc_table <- function(weather, init, lat_adjust, out) {
  # Bound to a dot-free local name: cli reads a leading dot inside {} as a
  # style, not an expression. Same trap as in fev_fetch_bdforet().
  required <- .FEV_FWI_INPUTS
  missing <- setdiff(required, tolower(names(weather)))
  if (length(missing)) {
    fev_abort(c(
      "{.arg weather} is missing column{?s} {.field {missing}}.",
      i = "Required: {.field {required}}, at noon local standard time.",
      i = "Units: temp {.val C}, rh {.val %}, ws {.val km/h}, prec \\
           {.val mm/24h}."
    ), class = "fev_bad_weather", .envir = environment())
  }
  if (!"lat" %in% tolower(names(weather))) {
    fev_abort(c(
      "{.arg weather} has no {.field lat} column.",
      i = "{.pkg cffdrs} would silently assume 55 degrees North -- central \\
           British Columbia -- and warn only in passing.",
      i = "Latitude drives the day-length adjustment in DMC and DC. The \\
           adjustment is banded, so 55 N happens to give the same answer as \\
           metropolitan France; below 30 N and in the southern hemisphere it \\
           does not, and the error would travel with the script.",
      i = "Add {.field lat}, or pass {.code lat_adjust = FALSE} if you \\
           genuinely want no adjustment and can justify it."
    ), class = "fev_no_latitude")
  }

  fev_check_weather_ranges(weather)

  # cffdrs reads its own init$lat for the very first step, and its default is
  # 55. Take the caller's first latitude instead, so the startup matches the
  # data rather than Canada.
  init_df <- data.frame(
    ffmc = unname(init[["ffmc"]]), dmc = unname(init[["dmc"]]),
    dc = unname(init[["dc"]]),
    lat = stats::median(weather[[grep("^lat$", names(weather),
                                      ignore.case = TRUE)[1]]], na.rm = TRUE)
  )

  res <- cffdrs::fwi(weather, init = init_df, lat.adjust = lat_adjust,
                     out = out)
  attr(res, "fev_params") <- list(init = as.list(init_df),
                                  lat_adjust = lat_adjust, out = out,
                                  n_rows = nrow(weather))
  res
}

#' @noRd
fev_fwi_calc_grid <- function(weather, init, months, lat_adjust, out) {
  required <- .FEV_FWI_INPUTS
  for (i in seq_along(weather)) {
    have <- tolower(names(weather[[i]]))
    missing <- setdiff(required, have)
    if (length(missing)) {
      fev_abort(c(
        "Step {i} of {.arg weather} is missing layer{?s} {.field {missing}}.",
        i = "Each step needs layers named {.field {required}}.",
        i = "Found: {.field {have}}."
      ), class = "fev_bad_weather", .envir = environment())
    }
  }

  months <- months %||% 7L
  if (length(months) == 1L) {
    months <- rep(months, length(weather))
  }
  if (length(months) != length(weather)) {
    fev_abort(c(
      "{.arg months} must have length 1 or {length(weather)}.",
      x = "Got {length(months)}."
    ), .envir = environment())
  }

  fev_check_weather_ranges_grid(weather)

  codes <- init
  outputs <- vector("list", length(weather))
  for (i in seq_along(weather)) {
    step <- weather[[i]][[.FEV_FWI_INPUTS]]
    names(step) <- toupper(.FEV_FWI_INPUTS)
    res <- cffdrs::fwiRaster(step, init = codes, mon = months[i],
                             out = out, lat.adjust = lat_adjust)
    outputs[[i]] <- res
    # The moisture codes are cumulative: each day starts from the previous
    # day's. Re-initialising every step is the error this loop exists to
    # prevent, and it produces a series with no memory of drought at all.
    codes <- c(
      ffmc = as.numeric(terra::global(res[["FFMC"]], "mean", na.rm = TRUE)[[1]]),
      dmc  = as.numeric(terra::global(res[["DMC"]], "mean", na.rm = TRUE)[[1]]),
      dc   = as.numeric(terra::global(res[["DC"]], "mean", na.rm = TRUE)[[1]])
    )
  }

  if (length(outputs) > 1L) {
    fev_warn(c(
      "Carrying the moisture codes forward as {.strong spatial means}.",
      i = "{.fn cffdrs::fwiRaster} takes scalar startup codes, so a per-pixel \\
           carry-over is not possible through it. Over {length(outputs)} steps \\
           this smooths spatial contrast in DMC and DC.",
      i = "For long series prefer the CEMS product from {.fn fev_fetch_fwi}, \\
           which is integrated per grid cell."
    ), class = "fev_scalar_carryover", .envir = environment())
  }

  stack <- if (length(outputs) == 1L) outputs[[1]] else terra::rast(outputs)
  prov <- fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_fwi_calc",
    params = list(init = as.list(init), months = months,
                  lat_adjust = lat_adjust, out = out,
                  n_steps = length(weather), engine = "cffdrs::fwiRaster"),
    notes = if (length(outputs) > 1L)
      "moisture codes carried forward as spatial means" else NULL
  )
  new_fev_layer(stack, role = "fwi", provenance = prov,
                units = "FWI system, dimensionless",
                class = "fev_danger_layer")
}

#' Refuse impossible values, and flag the plausible-but-suspicious ones
#'
#' Relative humidity outside 0-100 and negative wind or rain are impossible and
#' abort. A wind series whose maximum sits below 30 km/h over a whole record is
#' not impossible, but it is what metres per second look like, so it warns with
#' the number rather than deciding.
#'
#' @noRd
fev_check_weather_ranges <- function(w) {
  get <- function(nm) w[[grep(paste0("^", nm, "$"), names(w),
                              ignore.case = TRUE)[1]]]
  rh <- get("rh")
  ws <- get("ws")
  prec <- get("prec")
  temp <- get("temp")
  fev_check_ranges(temp, rh, ws, prec, n = nrow(w))
}

#' @noRd
fev_check_weather_ranges_grid <- function(weather) {
  rng <- function(nm) {
    vals <- vapply(weather, function(r) {
      g <- terra::global(r[[grep(paste0("^", nm, "$"), names(r),
                                 ignore.case = TRUE)[1]]],
                         fun = "range", na.rm = TRUE)
      c(as.numeric(g[[1]][1]), as.numeric(g[[2]][1]))
    }, numeric(2))
    c(min(rng_or_na(vals[1, ])), max(rng_or_na(vals[2, ])))
  }
  fev_check_ranges(rng("temp"), rng("rh"), rng("ws"), rng("prec"),
                   n = length(weather))
}

#' @noRd
rng_or_na <- function(x) if (all(is.na(x))) NA_real_ else x[!is.na(x)]

#' @noRd
fev_check_ranges <- function(temp, rh, ws, prec, n) {
  if (any(rh < 0 | rh > 100, na.rm = TRUE)) {
    fev_abort(c(
      "{.field rh} must be a percentage in {.val {c(0, 100)}}.",
      i = "Values outside it usually mean a fraction (0-1) rather than a \\
           percentage."
    ), class = "fev_bad_weather")
  }
  if (any(ws < 0, na.rm = TRUE) || any(prec < 0, na.rm = TRUE)) {
    fev_abort("{.field ws} and {.field prec} cannot be negative.",
              class = "fev_bad_weather")
  }
  if (any(temp < -60 | temp > 60, na.rm = TRUE)) {
    fev_warn("{.field temp} leaves {.val {c(-60, 60)}} degrees Celsius. \\
              Check the unit.", class = "fev_suspicious_weather")
  }
  max_ws <- suppressWarnings(max(ws, na.rm = TRUE))
  if (is.finite(max_ws) && max_ws < 30 && n >= 30) {
    fev_warn(c(
      "Maximum wind speed over the record is {.val {round(max_ws, 1)}}.",
      i = "The FWI system expects {.strong km/h}. A record that never exceeds \\
           30 is what metres per second look like, and would understate ISI \\
           and FWI throughout.",
      i = "If the unit is right, ignore this."
    ), class = "fev_suspicious_units", .envir = environment())
  }
  invisible(TRUE)
}
