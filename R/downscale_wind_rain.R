# The two variables the first downscaling left alone.
#
# fev_downscale_weather() corrected temperature and humidity and passed wind and
# rain through, on the grounds that neither had a calibration this package could
# defend. That was right about the problem and wrong to stop there: what was
# missing was not a constant to import but a way to decide whether the data
# supports a correction at all.
#
# So both routes here refuse rather than invent:
#
#   rain   fitted from the reanalysis points' own elevation spread, and NOT
#          applied when the fit does not hold up. Measured on the Maures over
#          20 points spanning 464 m: R2 = 0.087, p = 0.21. There is no
#          orographic gradient to find in that reanalysis over that massif, and
#          fitting one would be fitting noise.
#
#   wind   the MicroMet terrain weighting (Liston & Elder 2006), CURVATURE ONLY.
#          Their slope term needs a wind direction and this package fetches
#          none, so it is off unless the direction is supplied. Ridges gain,
#          hollows lose, and the direction-free half of the published scheme is
#          the half that can be applied honestly.

#' Terrain curvature on the MicroMet scale
#'
#' Convex ground — ridges, spurs — accelerates wind; concave ground shelters it.
#' This computes the curvature that [fev_downscale_weather()] turns into a wind
#' multiplier, on the scale Liston and Elder define: divided by twice its own
#' maximum absolute value, so it lands in `[-0.5, 0.5]`.
#'
#' @section The length scale is the parameter that matters:
#' Curvature has no meaning without a distance over which to measure it. Liston
#' and Elder use roughly half the dominant topographic wavelength — the distance
#' from a valley floor to the ridge above it. Too short and the result is
#' surface roughness; too long and a whole massif reads as one gentle dome.
#' Several hundred metres suits a Mediterranean massif; the default is 500 m and
#' it is a choice, not a constant.
#'
#' @section It is scaled against the area processed:
#' Dividing by the observed maximum makes the result **extent-dependent**, like
#' `"minmax"` in [fev_vuln_layer()]: the same ridge scores differently under a
#' different area of interest. That is how the published scheme is defined, and
#' the consequence is the same one — a curvature layer is comparable within one
#' analysis and not between two.
#'
#' @param dem Elevation: a [fev_source] from [fev_fetch_dem()], a `fev_layer` or
#'   a `SpatRaster`.
#' @param length_scale Distance in CRS units over which curvature is measured.
#'   Default 500.
#' @param quiet Suppress the report.
#'
#' @return A `fev_layer` of role `"curvature"`, values in `[-0.5, 0.5]`.
#'
#' @seealso [fev_downscale_weather()], which consumes it.
#'
#' @source
#' Liston, G. E. and Elder, K. (2006). A meteorological distribution system for
#' high-resolution terrestrial modeling (MicroMet). *Journal of
#' Hydrometeorology* 7(2): 217-234.
#'
#' Formulation checked on 2026-08-19 against an independent implementation
#' rather than taken from memory: `windwt = 1 + slopewt * wind_slope + curvewt *
#' curvature`, with both terms divided by twice their maximum absolute value and
#' `slopewt + curvewt = 1` suggested. The publisher's own page is paywalled.
#'
#' @examples
#' g <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 3000,
#'                  ymin = 0, ymax = 3000, crs = "EPSG:2154")
#' # A ridge running north-south.
#' dem <- terra::init(g, "x")
#' dem <- 300 - abs(dem - 1500) / 5
#' cv <- fev_curvature(dem, length_scale = 300, quiet = TRUE)
#' range(terra::values(fev_data(cv)), na.rm = TRUE)
#'
#' @export
fev_curvature <- function(dem, length_scale = 500, quiet = FALSE) {
  prov <- fev_layer_prov(dem) %||% attr(dem, "provenance") %||%
    fev_prov_new(crs_work = NA)
  z <- fev_as_raster(dem, "dem")[[1]]
  res <- terra::res(z)[1]

  if (!is.numeric(length_scale) || length(length_scale) != 1L ||
      is.na(length_scale) || length_scale <= 0) {
    fev_abort("{.arg length_scale} must be a single positive distance.")
  }
  n <- max(1L, as.integer(round(length_scale / res)))
  if (n * 2L + 1L > min(terra::nrow(z), terra::ncol(z))) {
    fev_abort(c(
      "{.arg length_scale} = {.val {length_scale}} needs a window of \\
       {n * 2L + 1L} cells; the layer is \\
       {terra::nrow(z)} x {terra::ncol(z)}.",
      i = "Curvature over a distance larger than the map is not curvature."
    ), .envir = environment())
  }

  # MicroMet's curvature is the mean over four direction pairs of the height
  # above the midpoint of the two neighbours, divided by twice the length
  # scale. Collapsing that algebra gives one focal window: the centre against
  # the mean of the eight neighbours at the length scale.
  #
  #   0.25 * sum_pairs (z - (za + zb)/2) / (2L) = (z - mean(z_8)) / (2L)
  w <- matrix(NA_real_, nrow = 2L * n + 1L, ncol = 2L * n + 1L)
  mid <- n + 1L
  w[mid, mid] <- 1
  for (di in c(-n, 0L, n)) {
    for (dj in c(-n, 0L, n)) {
      if (di == 0L && dj == 0L) next
      w[mid + di, mid + dj] <- -1 / 8
    }
  }
  curv <- terra::focal(z, w = w, fun = "sum", na.rm = FALSE) /
    (2 * length_scale)

  mx <- as.numeric(terra::global(abs(curv), "max", na.rm = TRUE)[1, 1])
  # A millimetre floor, as the reference implementation has, so dead-flat ground
  # divides by something rather than returning NaN everywhere.
  scaled <- curv / (2 * max(mx, 1e-3))
  names(scaled) <- "curvature"

  if (!quiet) {
    cli::cli_h1("fev_curvature")
    cli::cli_li("Length scale {length_scale} ({n} cell{?s} at \\
                {signif(res, 4)})")
    cli::cli_li("Raw maximum |curvature|: {signif(mx, 3)}")
    cli::cli_alert_info(
      "Scaled against this extent's own maximum: comparable within one \\
       analysis, not between two."
    )
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_curvature",
    params = list(length_scale = length_scale, window_cells = 2L * n + 1L,
                  res = signif(res, 6), raw_max = signif(mx, 6)),
    notes = paste0("MicroMet curvature (Liston & Elder 2006), scaled to ",
                   "[-0.5, 0.5] against the processed extent")
  )
  new_fev_layer(scaled, role = "curvature", provenance = prov,
                units = "-0.5 to 0.5")
}

#' Is there an orographic rain gradient in these points at all?
#'
#' Regresses each point's mean precipitation on its elevation and reports
#' whether the result is worth using. Called by [fev_downscale_weather()] when
#' `rain = "fitted"`, and exported because the answer is worth knowing before
#' deciding.
#'
#' @section Why fit rather than import a coefficient:
#' Published orographic coefficients exist — MicroMet carries monthly ones from
#' the western United States. Importing them here would put a number in the
#' provenance derived from a different continent's topography and storm tracks.
#' The reanalysis points already sit at different elevations; if there is a
#' gradient in them, it is this analysis's own gradient.
#'
#' @section What it found on the Maures, and why that is the useful case:
#' Twenty points spanning 464 m of elevation: R² = 0.087, p = 0.21. **No usable
#' gradient.** That is not a disappointing result, it is the function working:
#' the reanalysis does not resolve orographic enhancement over a massif this
#' small, and a correction fitted anyway would have been fitted to noise and
#' would have travelled in the provenance looking like a measurement.
#'
#' @param weather A weather table, as [fev_fetch_weather()] returns.
#' @param p_max Significance the slope must reach to be considered usable.
#'   Default 0.05.
#'
#' @return A list with `slope` (mm per metre of elevation), `relative` (fraction
#'   of the mean per 1000 m), `r_squared`, `p_value`, `n_points`,
#'   `elev_range_m` and `usable`.
#'
#' @seealso [fev_downscale_weather()].
#'
#' @examples
#' w <- data.frame(id = rep(letters[1:6], each = 3),
#'                 elev_m = rep(c(10, 60, 110, 160, 210, 260), each = 3),
#'                 prec = rep(c(1, 1.2, 1.4, 1.6, 1.8, 2), each = 3))
#' fev_rain_gradient(w)$usable
#'
#' @export
fev_rain_gradient <- function(weather, p_max = 0.05) {
  tab <- if (inherits(weather, "fev_source")) weather$data else weather
  need <- c("id", "elev_m", "prec")
  if (!is.data.frame(tab) || length(setdiff(need, names(tab)))) {
    fev_abort(c(
      "{.arg weather} needs {.field id}, {.field elev_m} and {.field prec}.",
      i = "{.fn fev_fetch_weather} returns them."
    ))
  }
  agg <- stats::aggregate(prec ~ id + elev_m, data = tab, FUN = mean)
  if (nrow(agg) < 3L || diff(range(agg$elev_m)) == 0) {
    return(list(slope = NA_real_, relative = NA_real_, r_squared = NA_real_,
                p_value = NA_real_, n_points = nrow(agg),
                elev_range_m = diff(range(agg$elev_m)), usable = FALSE))
  }
  fit <- stats::lm(prec ~ elev_m, data = agg)
  co <- summary(fit)$coefficients
  p <- if (nrow(co) > 1L) co[2, 4] else NA_real_
  slope <- if (nrow(co) > 1L) co[2, 1] else NA_real_
  list(slope = slope,
       relative = 1000 * slope / mean(agg$prec),
       r_squared = summary(fit)$r.squared, p_value = p,
       n_points = nrow(agg), elev_range_m = diff(range(agg$elev_m)),
       usable = isTRUE(p <= p_max))
}

#' The per-zone wind multiplier, or a flat one
#'
#' Returns a vector of multipliers, one per zone. Flat ones when no curvature is
#' asked for, so the caller multiplies unconditionally and there is no branch in
#' the row builder to get wrong.
#'
#' @noRd
fev_zone_wind_weight <- function(wind, curvature, zr, zt, curve_weight) {
  if (identical(wind, "none")) {
    return(rep(1, nrow(zt)))
  }
  if (is.null(curvature)) {
    fev_abort(c(
      "{.arg wind} = {.val curvature} needs a {.arg curvature} layer.",
      i = "{.fn fev_curvature} builds one from the same elevation model the \\
           zones came from."
    ))
  }
  if (!is.numeric(curve_weight) || length(curve_weight) != 1L ||
      curve_weight < 0 || curve_weight > 1) {
    fev_abort("{.arg curve_weight} must be a single number in {.code [0, 1]}.")
  }
  cv <- fev_as_raster(curvature, "curvature")[[1]]
  if (!terra::compareGeom(cv, zr, stopOnError = FALSE)) {
    fev_abort(c(
      "The curvature and zone grids do not match.",
      i = "Build the curvature from the elevation model the zones came from."
    ), class = "fev_grid_mismatch")
  }
  v <- terra::values(cv)[, 1]
  zv <- terra::values(zr)[, 1]
  # The zone's mean curvature, not the value at a representative cell: a zone is
  # a band inside one reanalysis territory and spans many ridges and hollows.
  vapply(zt$zone, function(k) {
    m <- mean(v[zv == k], na.rm = TRUE)
    1 + curve_weight * (if (is.finite(m)) m else 0)
  }, numeric(1))
}

#' The rain gradient, applied only if the points support one
#'
#' Returns a list with a NULL slope when nothing is to be applied, so the caller
#' can test one thing.
#'
#' @noRd
fev_zone_rain_gradient <- function(rain, tab, quiet) {
  if (identical(rain, "none")) {
    return(list(slope = NULL))
  }
  g <- fev_rain_gradient(tab)
  if (!isTRUE(g$usable)) {
    # Requested and not applied: said out loud, and recorded, because a
    # correction that quietly did nothing is worse than one that was never
    # asked for -- the analysis would report a downscaled rain field it never
    # got.
    fev_warn(c(
      "No usable orographic rain gradient in these points: rain left \\
       uncorrected.",
      i = "R2 {signif(g$r_squared, 2)}, p {signif(g$p_value, 2)} over \\
           {g$n_points} point{?s} spanning {round(g$elev_range_m)} m.",
      i = "The reanalysis does not resolve orographic enhancement at this \\
           scale. Fitting anyway would fit noise and it would travel in the \\
           provenance looking like a measurement."
    ), class = "fev_no_rain_gradient", .envir = environment())
    return(list(slope = NULL))
  }
  g
}
