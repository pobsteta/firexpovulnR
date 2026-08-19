# Exposure that knows which way the wind blows and which way the ground tilts.
#
# Phase 11 step 3. fev_exposure() weights every direction alike; the Maures burn
# on the mistral and uphill. fev_directional() looked like it addressed this and
# does not: it reads the isotropic field around a point asset, describing
# approach corridors after the fact.
#
# The construction here is a decomposition, not a new metric:
#
#     exposure(c) = sum_k alpha_k(c) * e_k(c),    sum_k alpha_k(c) = 1
#
# e_k is the burnable fraction in angular sector k of the annulus -- one focal
# pass per sector, over the same ring cells the isotropic version uses once.
# alpha_k is where wind and slope enter.
#
# The invariant that keeps this honest, and that the tests enforce: with
# alpha_k proportional to each sector's cell count, the sum must reproduce
# fev_exposure() to numerical tolerance. Anything that breaks it has stopped
# being a decomposition of the published metric and become a different one.

#' Exposure weighted by wind and slope
#'
#' The same annulus as [fev_exposure()], split into angular sectors and
#' recombined with weights that make approach from some directions count more
#' than others: from where the wind blows, and from downslope.
#'
#' @section This is not the published metric:
#' Beverly et al. define exposure isotropically and Khan et al. validated it
#' isotropically. Directional weighting is a **departure**, it has no validation
#' of its own, and both concentration parameters are judgements of the analysis
#' rather than properties of the data — exactly like the weights of
#' [fev_vuln_stack()]. They are written into the provenance for that reason. Set
#' both to zero and you get the published metric back, which is the default and
#' the thing to compare against.
#'
#' @section How the two weights are built:
#' Each sector `k` has a mean bearing. Its weight is the product of two von
#' Mises-like factors, `exp(kappa * cos(delta))`, normalised over sectors so
#' they sum to one:
#'
#' * **Wind.** `delta` is the angle between the sector bearing and the direction
#'   the wind comes **from** — fire arrives from upwind, so that is the
#'   direction that must weigh more. `kappa_wind` is constant over the map.
#' * **Slope.** `delta` is the angle between the sector bearing and the
#'   direction of steepest descent at the assessed cell, which is what
#'   `terra::terrain(v = "aspect")` returns. Fire runs uphill, so a cell is
#'   exposed from below. `kappa` here is **not** constant: it is
#'   `kappa_slope * tan(slope)`, so flat ground gets no anisotropy at all and
#'   steep ground gets a lot. That is the behaviour you want and it falls out
#'   of the physics rather than being imposed.
#'
#' @section What it costs:
#' `n_sectors` focal passes, each over roughly `1 / n_sectors` of the ring, so
#' the weighted-operation count is about the same as the isotropic version. What
#' is not the same is memory: `n_sectors` intermediate layers are held at once.
#' Eight sectors on a departmental grid is the point where `filename` stops
#' being optional.
#'
#' Eight is the default because 45 degrees is about the angular precision a
#' wind direction deserves; more sectors buy resolution the input does not have.
#'
#' @section On wind direction:
#' `wind` is a **meteorological** direction in degrees: the direction the wind
#' blows *from*, clockwise from north, as [fev_fetch_weather()] returns it and
#' as every anemometer reports it. A north wind is 0 and pushes fire southwards,
#' so the exposure it raises is on the northern side of a cell. Passing a vector
#' direction here — the way the wind goes — inverts the whole result, and there
#' is no way for the function to detect it.
#'
#' @param fuel As [fev_exposure()] takes it.
#' @param radius Annulus radius in CRS units.
#' @param wind Wind direction in degrees, meteorological convention (from). A
#'   single number, or `NULL` for no wind weighting.
#' @param kappa_wind Concentration of the wind weight. `0` is isotropic; 1 to 2
#'   is a moderate bias; above 4 the upwind sectors carry nearly everything.
#' @param dem Elevation for the slope weight: a [fev_source] from
#'   [fev_fetch_dem()], a `fev_layer` or a `SpatRaster`, on the fuel grid.
#'   `NULL` for no slope weighting.
#' @param kappa_slope Concentration of the slope weight, multiplied by
#'   `tan(slope)`. `0` disables it.
#' @param n_sectors Number of angular sectors. Default 8.
#' @param type,no_burn,lookup,na_rm,trim,filename,quiet,... As
#'   [fev_exposure()].
#'
#' @return A `fev_layer` of role `"exposure"`, values in `[0, 1]`.
#'
#' @seealso [fev_exposure()] for the isotropic metric this decomposes,
#'   [fev_fetch_dem()] for the terrain, [fev_exposure_calibrate()] for the
#'   radius.
#'
#' @examples
#' g <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 400,
#'                  ymin = 0, ymax = 400, crs = "EPSG:2154")
#' fuel <- terra::setValues(g, rep(rep(c(1, 0), each = 20), 40))
#' # With no wind and no terrain this is fev_exposure(), by construction.
#' e <- fev_exposure_aniso(fuel, radius = 60, quiet = TRUE)
#' terra::global(fev_data(e), "mean", na.rm = TRUE)
#'
#' @export
fev_exposure_aniso <- function(fuel,
                               radius = NULL,
                               wind = NULL,
                               kappa_wind = 0,
                               dem = NULL,
                               kappa_slope = 0,
                               n_sectors = 8L,
                               type = c("ember", "ember_short", "radiant"),
                               no_burn = NULL,
                               lookup = NULL,
                               na_rm = FALSE,
                               trim = NULL,
                               filename = "",
                               ...,
                               quiet = FALSE) {
  type <- match.arg(type)
  radii <- fev_exposure_radii()
  radius <- radius %||% radii$max_m[match(type, radii$type)]

  n_sectors <- as.integer(n_sectors)
  if (is.na(n_sectors) || n_sectors < 2L) {
    fev_abort("{.arg n_sectors} must be at least 2.")
  }
  if (!is.numeric(kappa_wind) || length(kappa_wind) != 1L || kappa_wind < 0 ||
      !is.numeric(kappa_slope) || length(kappa_slope) != 1L || kappa_slope < 0) {
    fev_abort("{.arg kappa_wind} and {.arg kappa_slope} must be single \\
               non-negative numbers.")
  }
  if (!is.null(wind) &&
      (!is.numeric(wind) || length(wind) != 1L || is.na(wind))) {
    fev_abort("{.arg wind} must be a single direction in degrees, or NULL.")
  }

  resolved <- fev_exposure_input(fuel, lookup)
  haz <- resolved$raster
  prov <- resolved$provenance %||% fev_prov_new(crs_work = NA)
  res <- terra::res(haz)[1]

  if (res > radius / 3) {
    fev_abort(c(
      "Cell size {.val {signif(res, 6)}} is too coarse for a radius of \\
       {.val {radius}}.",
      i = "Needs {.code res <= radius / 3}, same constraint as \\
           {.fn fev_exposure}."
    ), class = "fev_res_too_coarse", .envir = environment())
  }

  sectors <- fev_sector_windows(res, radius, n_sectors)
  n_ring <- sum(vapply(sectors$windows, function(w) sum(!is.na(w)), numeric(1)))
  if (!n_ring) {
    fev_abort("The annulus holds no cell at this resolution and radius.")
  }

  fev_check_focal_cost(haz, n_ring, res, radius, quiet)

  # Each sector's own burnable fraction: divide by that sector's cell count, so
  # e_k is a proportion in its own right and the recombination is a weighted
  # mean of proportions rather than of counts.
  parts <- lapply(seq_along(sectors$windows), function(k) {
    w <- sectors$windows[[k]]
    nk <- sum(!is.na(w))
    if (!nk) return(NULL)
    terra::focal(haz, w = w / nk, fun = "sum", na.rm = na_rm)
  })
  keep <- !vapply(parts, is.null, logical(1))
  parts <- parts[keep]
  counts <- sectors$counts[keep]
  bearings <- sectors$bearings[keep]

  alpha <- fev_sector_weights(counts, bearings, wind, kappa_wind,
                              dem, kappa_slope, haz, quiet)

  exposure <- fev_sector_combine(parts, alpha)
  exposure <- terra::clamp(exposure, 0, 1, values = TRUE, filename = filename,
                           ...)
  names(exposure) <- "exposure"

  if (!is.null(no_burn)) {
    exposure <- fev_apply_no_burn(exposure, no_burn)
  }

  isotropic <- is.null(wind) || kappa_wind == 0
  isotropic <- isotropic && (is.null(dem) || kappa_slope == 0)

  if (!quiet && !isotropic) {
    fev_once("exposure_aniso", fev_inform(c(
      "Directional exposure is a departure from the published metric.",
      i = "Beverly et al. define it isotropically and Khan et al. validated it \\
           isotropically. This weighting has no validation of its own.",
      i = "The concentrations are judgements of the analysis, like the weights \\
           of {.fn fev_vuln_stack}. They are in the provenance.",
      i = "Shown once per session."
    ), class = "fev_unvalidated_anisotropy"))
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_exposure_aniso",
    params = list(radius = radius, res = signif(res, 6),
                  n_sectors = length(parts), window_cells = n_ring,
                  wind_from_deg = wind %||% NA, kappa_wind = kappa_wind,
                  slope_used = !is.null(dem) && kappa_slope > 0,
                  kappa_slope = kappa_slope,
                  isotropic_equivalent = isotropic,
                  input = resolved$role, graded = resolved$graded,
                  na_rm = na_rm),
    notes = if (isotropic) {
      "no directional weighting applied: equivalent to fev_exposure()"
    } else {
      paste0("directional weighting, NOT the published metric; ",
             "concentrations are analysis judgements, not measurements")
    }
  )

  if (!is.null(trim)) {
    exposure <- fev_exposure_trim(exposure, trim, radius, quiet)
    prov <- fev_prov_add_step(
      prov, fun = "fev_exposure_aniso",
      params = list(trimmed_to_aoi = TRUE, radius = radius),
      notes = "computed on the buffered extent, reported on the AOI"
    )
  }

  new_fev_layer(exposure, role = "exposure", provenance = prov,
                units = "fraction of burnable neighbourhood, direction-weighted")
}

#' Cut the annulus into angular sectors
#'
#' Bearings are compass bearings: clockwise from north, which is the convention
#' wind directions come in. That is why the arctangent takes (x, y) in that
#' order rather than the mathematical (y, x).
#'
#' @noRd
fev_sector_windows <- function(res, radius, n_sectors) {
  base <- fev_annulus_window(res, radius)
  n <- nrow(base)
  offsets <- (seq_len(n) - (n + 1) / 2) * res
  x <- matrix(offsets, nrow = n, ncol = n, byrow = TRUE)
  # Row 1 of a matrix is the northern edge, so the y offset runs the other way.
  y <- -matrix(offsets, nrow = n, ncol = n, byrow = FALSE)
  bearing <- (atan2(x, y) * 180 / pi) %% 360

  width <- 360 / n_sectors
  # Sectors are centred on their nominal bearing, so sector 1 straddles north
  # rather than starting at it: a north wind then falls in the middle of a
  # sector instead of on the seam between two.
  edges <- (seq_len(n_sectors) - 1) * width - width / 2
  windows <- lapply(seq_len(n_sectors), function(k) {
    lo <- edges[k] %% 360
    hi <- (lo + width) %% 360
    inside <- if (lo < hi) bearing >= lo & bearing < hi else
      bearing >= lo | bearing < hi
    w <- base
    w[!inside] <- NA_real_
    w
  })
  list(windows = windows,
       counts = vapply(windows, function(w) sum(!is.na(w)), numeric(1)),
       bearings = (seq_len(n_sectors) - 1) * width)
}

#' Sector weights, from cell counts, wind and slope
#'
#' Returns either a numeric vector -- one weight per sector, constant over the
#' map -- or a list of SpatRasters when the slope makes the weights vary by
#' cell. The two cases are kept apart deliberately: the constant one is much
#' cheaper and it is the common one.
#'
#' @noRd
fev_sector_weights <- function(counts, bearings, wind, kappa_wind,
                               dem, kappa_slope, haz, quiet) {
  # The isotropic baseline: proportional to how many cells each sector holds.
  # This is what makes the decomposition reproduce fev_exposure() exactly when
  # nothing else weighs in -- sectors do not hold equal numbers of cells, and
  # weighting them equally would be a different metric.
  base <- counts / sum(counts)

  if (!is.null(wind) && kappa_wind > 0) {
    d <- (bearings - wind) * pi / 180
    base <- base * exp(kappa_wind * cos(d))
    base <- base / sum(base)
  }

  if (is.null(dem) || kappa_slope <= 0) {
    return(base)
  }

  elev <- fev_as_raster(dem, "dem")[[1]]
  if (!terra::compareGeom(elev, haz, stopOnError = FALSE)) {
    fev_abort(c(
      "The elevation and fuel grids do not match.",
      i = "As everywhere outside {.fn fev_align}, mismatched grids are an \\
           error rather than a silent resample."
    ), class = "fev_grid_mismatch")
  }

  terr <- terra::terrain(elev, v = c("slope", "aspect"), unit = "degrees",
                         neighbors = 8)
  # tan of the slope, so flat ground gets no anisotropy and the strength grows
  # the way the physics does rather than linearly in degrees.
  k <- kappa_slope * tan(terr[["slope"]] * pi / 180)
  # A flat cell has no defined aspect; terra returns 90 there by convention.
  # With k = 0 that choice cannot matter, which is the point of scaling by
  # tan(slope) rather than adding a separate flat-ground rule.
  asp <- terr[["aspect"]]

  ws <- lapply(seq_along(bearings), function(i) {
    d <- (bearings[i] - asp) * pi / 180
    base[i] * exp(k * cos(d))
  })
  total <- Reduce(`+`, ws)
  lapply(ws, function(w) w / total)
}

#' Recombine the sectors
#' @noRd
fev_sector_combine <- function(parts, alpha) {
  out <- NULL
  for (k in seq_along(parts)) {
    a <- if (is.list(alpha)) alpha[[k]] else alpha[k]
    term <- parts[[k]] * a
    out <- if (is.null(out)) term else out + term
  }
  out
}
