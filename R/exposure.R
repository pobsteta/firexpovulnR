# Fire exposure: how much burnable fuel surrounds a place, and from which
# direction it can reach it.
#
# Reimplemented rather than depended on -- fireexposuR stays in Suggests for
# the cross-check in tests/testthat/test-crosscheck-fireexposuR.R. The window
# geometry below reproduces theirs exactly (an annulus from one cell out to the
# transmission distance, focal cell excluded), because a cross-check that
# tolerated a different window would be checking nothing.

#' Fire exposure from surrounding fuel
#'
#' The proportion of burnable fuel within a transmission distance of each cell:
#' how much of the surrounding landscape could carry fire to it.
#'
#' @section What the window is:
#' An **annulus**, from one cell out to `radius`. The assessment cell itself is
#' excluded, because the metric asks what can reach a place, not what is
#' already there. A value of 0.5 means half the cells in that ring are
#' burnable. Values run 0 to 1.
#'
#' The grid must be at least three times finer than the radius — below that the
#' ring is a handful of cells and the proportion is quantised into a few
#' values. That constraint comes from `fireexposuR` and is enforced here too.
#'
#' @section The radii are Canadian, with one Mediterranean validation:
#' 30 m for radiant heat, 100 m for short-range embers, 500 m for long-range
#' embers, from Beverly et al. (2010, 2021) on Alberta fuels. Khan et al.
#' (2025) validated the metric over mainland Portugal — about 80% of burned
#' area fell where exposure was 80% or more — so it does transpose to an
#' Iberian context. It has not been calibrated on holm oak, garrigue or maquis,
#' and Portugal is not the Var. See [fev_exposure_radii()] for what exactly is
#' sourced. A message says this on first use in a session; the radius used is
#' recorded in the provenance every time.
#'
#' @section Cost, which is not linear in what you would expect:
#' The window is expressed in metres but materialised in cells, so it holds
#' about `(2 * radius / res)^2` weights and the whole pass costs on the order of
#' `1 / res^4`. Halving the cell size multiplies the work by sixteen.
#'
#' At 25 m with a 500 m radius the ring is about 1250 cells, and a French
#' department of 6000 km² is 15 million of them — some 2e10 weighted
#' operations. At 2 m the same radius gives a 501 x 501 window and the pass
#' stops being feasible. This function estimates the count before starting and
#' warns with the number and a suggested cell size, rather than appearing to
#' hang.
#'
#' For a departmental run, pass `filename` so `terra` streams to disk in blocks,
#' and `wopt = list(progress = 1)` to see it move. Measured timings are in the
#' package vignette.
#'
#' Note that a GeoTIFF written this way defaults to single precision, which
#' rounds the proportion at about the eighth decimal. That is far below
#' anything the metric means, but it does mean an on-disk result and an
#' in-memory one are not bit-identical; pass
#' `wopt = list(datatype = "FLT8S")` if you need them to be.
#'
#' @section Graded exposure:
#' Passing a [fev_fuel_availability()] layer instead of a binary mask gives a
#' weighted exposure: each surrounding cell contributes its availability rather
#' than a flat 1. That is a departure from the published metric, which is
#' binary, so it is not the default and the record says which was used.
#'
#' @section The edge frame, and how to be rid of it:
#' The outer ring of a focal result is not a measurement. It is the window
#' hanging off the edge of the data, and with `na_rm = FALSE` it comes back
#' empty — the white frame on every exposure map this package has ever drawn.
#'
#' `na_rm = TRUE` looks like the fix and is not: it computes each edge cell over
#' whatever part of the ring happens to have data, which understates exposure
#' there by about 30% on the Maures extract (0.32 against 0.46) and does so
#' invisibly. A white frame is more honest than a wrong number.
#'
#' The real fix has two halves, and the package used to supply only the first:
#' compute on more ground than you report on. Build the fuel source on an area
#' buffered by at least the radius, then pass the area you actually mean to
#' report as `trim`.
#'
#' ```r
#' fuel <- fev_fuel_source(bdforet, aoi = sf::st_buffer(study, 500), ...)
#' expo <- fev_exposure(fuel, radius = 500, trim = study)
#' ```
#'
#' Every reported cell then has a complete ring behind it. The frame is still
#' computed — it has to be, to make the inside correct — but it is cut away
#' instead of published.
#'
#' @param fuel A `fev_fuel_source` (reduced with [fev_fuel_binary()]), a
#'   `fev_fuel_layer`, or a `SpatRaster` with values in `[0, 1]`.
#' @param radius Transmission distance in CRS units. `NULL` takes it from
#'   `type`.
#' @param type `"ember"` (500 m, the default), `"ember_short"` (100 m) or
#'   `"radiant"` (30 m). Ignored when `radius` is given.
#' @param no_burn Optional `SpatRaster` of cells that cannot burn — water,
#'   rock, sealed surface — masked out of the **result**, not the window. Must
#'   contain only 1 and `NA`.
#' @param lookup Correspondence table, when `fuel` is a `fev_fuel_source`.
#' @param na_rm Ignore `NA` cells inside the window rather than propagating
#'   them. `FALSE` matches `fireexposuR`; `TRUE` is more forgiving at the edges
#'   of a study area, at the cost of computing a proportion over fewer cells
#'   than the ring contains.
#' @param trim Optional area to report on, smaller than the one computed. The
#'   focal pass runs on the full extent, then the result is cropped and masked
#'   to `trim`. This is what removes the edge frame rather than hiding it — see
#'   the section below.
#' @param filename Optional output path. Given one, `terra` streams the result
#'   to disk in blocks instead of holding it in memory — which is what makes a
#'   departmental run possible at all.
#' @param ... Passed to [terra::focal()], notably `wopt` (for
#'   `list(progress = 1)` or a compression setting) and `overwrite`.
#' @param quiet Suppress the first-use note about the radii and the cost
#'   estimate.
#'
#' @return A `fev_exposure_layer` holding a `SpatRaster` named `exposure`.
#'
#' @seealso [fev_directional()] for the same landscape seen from one point,
#'   [fev_exposure_radii()] for the sources.
#'
#' @source
#' Beverly, J.L., Bothwell, P., Conner, J.C.R., Herd, E.P.K. (2010).
#' \doi{10.1071/WF09071}. Beverly, J.L., McLoughlin, N., Chapman, E. (2021),
#' *Landscape Ecology* 36: 785-801. Khan, S.I. et al. (2025), *Natural Hazards*
#' 121: 16273-16295, \doi{10.1007/s11069-025-07424-8}. Window geometry checked
#' against `fireexposuR` 1.2.0 on 2026-08-16.
#'
#' @examples
#' fuel <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
#'                     ymin = 0, ymax = 1000, crs = "EPSG:2154")
#' terra::values(fuel) <- 0
#' fuel[10:30, 10:30] <- 1
#' e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
#' terra::global(fev_data(e), "max", na.rm = TRUE)
#'
#' @export
fev_exposure <- function(fuel,
                         radius = NULL,
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

  resolved <- fev_exposure_input(fuel, lookup)
  haz <- resolved$raster
  prov <- resolved$provenance %||% fev_prov_new(crs_work = NA)

  if (!is.numeric(radius) || length(radius) != 1L || is.na(radius) ||
      radius <= 0) {
    fev_abort("{.arg radius} must be a single positive number, in CRS units.")
  }

  res <- terra::res(haz)[1]
  if (res > radius / 3) {
    fev_abort(c(
      "Cell size {.val {signif(res, 6)}} is too coarse for a radius of \\
       {.val {radius}}.",
      i = "The ring would be a handful of cells and the proportion quantised \\
           into a few values.",
      i = "Needs {.code res <= radius / 3}: either a finer fuel grid, or a \\
           radius of at least {.val {signif(res * 3, 6)}}.",
      i = "Same constraint as {.pkg fireexposuR}."
    ), class = "fev_res_too_coarse", .envir = environment())
  }

  w <- fev_annulus_window(res, radius)
  n_ring <- sum(!is.na(w))
  if (terra::nrow(w) * 2 >= terra::nrow(haz) ||
      terra::ncol(w) * 2 >= terra::ncol(haz)) {
    fev_abort(c(
      "The fuel layer is too small for a radius of {.val {radius}}.",
      x = "Window is {nrow(w)} x {ncol(w)} cells; the layer is \\
           {terra::nrow(haz)} x {terra::ncol(haz)}.",
      i = "Most of the result would be edge effect. Fetch a larger AOI than \\
           the one you intend to report on -- a buffer of at least the radius."
    ), class = "fev_extent_too_small", .envir = environment())
  }

  fev_check_focal_cost(haz, n_ring, res, radius, quiet)
  fev_check_focal_gaps(haz, radius, res, na_rm, quiet)

  if (!isTRUE(quiet)) {
    fev_once("exposure_radii", fev_inform(c(
      "Exposure radii come from Canadian work (Beverly et al. 2010, 2021).",
      i = "The metric was validated over mainland Portugal by Khan et al. \\
           (2025), so it does transpose to an Iberian Mediterranean context.",
      i = "It has not been calibrated on holm oak, garrigue or maquis. Justify \\
           {.val {radius}} m for your fuels, or recalibrate against local \\
           burnt-area data.",
      i = "Shown once per session; the radius is in the provenance every time. \\
           See {.fn fev_exposure_radii}."
    ), class = "fev_unvalidated_radius", .envir = environment()))
  }

  weights <- w / n_ring
  exposure <- terra::focal(haz, w = weights, fun = "sum", na.rm = na_rm, ...)
  # A sum of n weights of 1/n does not land exactly on 1 in floating point: a
  # fully burnable window comes back as 1 + 7e-16. The result is a proportion
  # by construction, so the excess is noise -- but it is enough to trip the
  # 0-1 checks in fev_danger_index() and fev_directional() further down the
  # chain. fireexposuR hides the same thing by rounding to four decimals.
  #
  # `filename` is honoured here rather than on the focal call: clamping after
  # writing would pull the whole result back into memory and undo the point of
  # streaming it out.
  exposure <- terra::clamp(exposure, 0, 1, values = TRUE, filename = filename,
                           ...)
  names(exposure) <- "exposure"

  if (!is.null(no_burn)) {
    exposure <- fev_apply_no_burn(exposure, no_burn)
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_exposure",
    params = list(radius = radius, type = if (is.null(radius)) type else type,
                  res = signif(res, 6), window_cells = n_ring,
                  window_shape = "annulus, focal cell excluded",
                  input = resolved$role, graded = resolved$graded,
                  na_rm = na_rm, no_burn = !is.null(no_burn),
                  radius_source = radii$source[match(type, radii$type)]),
    notes = if (isTRUE(resolved$graded))
      "graded exposure: window cells contribute availability, not 0/1" else NULL
  )

  if (!is.null(trim)) {
    exposure <- fev_exposure_trim(exposure, trim, radius, quiet)
    prov <- fev_prov_add_step(
      prov, fun = "fev_exposure",
      params = list(trimmed_to_aoi = TRUE, radius = radius),
      notes = paste0("computed on the buffered extent, reported on the AOI: ",
                     "the edge frame is cut away rather than published")
    )
  }

  new_fev_layer(exposure, role = "exposure", provenance = prov,
                units = "proportion of surrounding fuel, 0-1",
                class = "fev_exposure_layer")
}

#' Cut the edge frame away instead of publishing it
#'
#' The outer ring of a focal result is not a value, it is the window hanging off
#' the edge of the data. `fev_exposure()` has always said so in the message
#' `fev_extent_too_small` -- fetch a buffered extent, report on the inner one --
#' and this is the second half of that advice, which until now had to be done by
#' hand and usually was not.
#'
#' The check refuses to trim to something the buffer never covered: if the
#' reporting area reaches within one radius of the computed extent, the frame is
#' inside it and cropping would only hide the artefact rather than remove it.
#'
#' @noRd
fev_exposure_trim <- function(exposure, trim, radius, quiet) {
  aoi <- fev_as_aoi(trim, crs = sf::st_crs(terra::crs(exposure)))
  v <- terra::vect(aoi)

  outer <- fev_bbox(exposure)
  inner <- fev_bbox(v)
  slack <- min(inner[["xmin"]] - outer[["xmin"]], outer[["xmax"]] - inner[["xmax"]],
               inner[["ymin"]] - outer[["ymin"]], outer[["ymax"]] - inner[["ymax"]])
  if (slack < radius) {
    fev_warn(c(
      "{.arg trim} leaves only {.val {round(slack)}} m of margin, against a \\
       radius of {.val {radius}} m.",
      i = "The edge frame reaches into the area you are reporting on, so \\
           cropping hides part of it rather than removing it.",
      i = "Build the fuel source on an area buffered by at least the radius, \\
           then trim back to the one you mean to report."
    ), class = "fev_trim_insufficient_buffer", .envir = environment())
  }

  out <- terra::mask(terra::crop(exposure, v), v)
  if (!quiet) {
    kept <- round(100 * terra::ncell(out) / terra::ncell(exposure), 1)
    fev_inform(c(
      "Trimmed to the reporting area: {kept}% of the computed cells kept.",
      i = "The rest was the {.val {radius}} m edge frame, where the window \\
           hung off the data. It was computed to make the inside correct, and \\
           is cut rather than published."
    ), .envir = environment())
  }
  names(out) <- names(exposure)
  out
}

#' Say what the empty cells are about to cost
#'
#' With `na_rm = FALSE` the focal window propagates `NA`, so one isolated empty
#' input cell empties a whole window around itself. On the Couchey extract 42
#' empty cells out of 469 989 -- 0.009% -- emptied 26 303, an amplification of
#' 626, and blanked 17.5% of the risk map once the legitimate edge frame is
#' counted. Nothing announced it.
#'
#' The count is announced rather than the behaviour changed, because propagating
#' is the right default: `na_rm = TRUE` computes truncated windows at the extent
#' edge instead, which understates exposure there by about 30% (measured 0.3165
#' against 0.4551 on the same data) and does so invisibly.
#'
#' @noRd
fev_check_focal_gaps <- function(haz, radius, res, na_rm, quiet) {
  if (isTRUE(quiet) || isTRUE(na_rm)) {
    return(invisible(TRUE))
  }
  n_na <- as.numeric(terra::global(is.na(haz[[1]]), "sum", na.rm = TRUE)[1, 1])
  if (!is.finite(n_na) || n_na == 0) {
    return(invisible(TRUE))
  }

  # Clusters, not cells: a hundred cells in one blob cost one window, a hundred
  # scattered singletons cost a hundred. The distinction is the whole point.
  gaps <- terra::patches(terra::ifel(is.na(haz[[1]]), 1, NA), directions = 8,
                         zeroAsNA = TRUE)
  n_gaps <- nrow(as.data.frame(terra::freq(gaps)))
  per_window <- ceiling(pi * (radius / res)^2)
  # An upper bound, and said to be one: scattered gaps whose windows overlap, or
  # gaps near the edge, cost less than the product.
  bound <- min(as.numeric(n_gaps) * per_window, terra::ncell(haz))

  fev_warn(c(
    "The fuel layer has {n_na} empty cell{?s}.",
    i = "They fall in {n_gaps} separate gap{?s}, and this window propagates \\
         every one of them.",
    i = "Up to {bound} cells of the result -- at most \\
         {round(100 * bound / terra::ncell(haz), 1)}% -- will come back empty.",
    i = "{.fn fev_fuel_fill_gaps} repairs gaps below the source\'s minimum \\
         mapping unit, which is what rasterisation slivers are.",
    i = "{.code na_rm = TRUE} ignores them instead, but then also computes \\
         truncated windows at the extent edge."
  ), class = "fev_focal_gaps", .envir = environment())
  invisible(TRUE)
}

#' Refuse to start a focal pass that will not finish today
#'
#' The window is expressed in metres but materialised in cells, so its weight
#' count grows as `(2 * radius / res)^2` and the total work as `1 / res^4`. That
#' is not a subtlety: on the nemeton project the same metric, run at 2 m with a
#' 500 m radius, sat at 51% of one core for over 75 minutes with no I/O and no
#' memory pressure -- a 501 x 501 window over five million cells. The fix there
#' was to bound the grid of the exposure step alone, leaving the finer grid to
#' the slope and topography indicators that have a linear cost.
#'
#' So the estimate is given before the pass rather than after it, and the advice
#' names the specific remedy rather than "this may be slow".
#'
#' @noRd
fev_check_focal_cost <- function(haz, n_ring, res, radius, quiet) {
  ops <- as.numeric(terra::ncell(haz)) * n_ring
  # Measured throughput when this was written is 180-210 million weighted
  # operations per second, so this threshold is about five minutes. A whole
  # department at 25 m costs 1.2e10 -- 83 seconds -- and stays quiet, because a
  # departmental run is the normal case and a warning on it would be noise.
  target <- 5e10
  if (ops < target || isTRUE(quiet)) {
    return(invisible(ops))
  }
  # The cell size at which the same extent would cost about `target`. Both
  # ncell and the window scale as res^-2, so the total goes as res^-4 and the
  # inversion is res * (ops / target)^(1/4).
  suggested <- signif(res * (ops / target)^(1 / 4), 2)
  fev_warn(c(
    "This focal pass is about {.val {signif(ops / 1e9, 3)}} billion weighted \\
     operations.",
    i = "The window is {n_ring} cells at {.val {signif(res, 6)}} m for a \\
         radius of {.val {radius}} m. Its cost grows as the fourth power of \\
         the inverse cell size, so halving {.arg res} multiplies this by 16.",
    i = "Consider running the exposure step on a grid of about \\
         {.val {suggested}} m and keeping the fine grid for the layers whose \\
         cost is linear in cells.",
    i = "Pass {.code quiet = TRUE} once you have decided."
  ), class = "fev_focal_cost", .envir = environment())
  invisible(ops)
}

#' An annulus weight matrix, matching fireexposuR cell for cell
#'
#' Reproduces `MultiscaleDTM::annulus_window(c(res, radius), "map", res)`: an
#' odd-sided matrix of distances from its centre, 1 where the distance falls in
#' `[res, radius]` and `NA` elsewhere. Rebuilt here rather than depended on, so
#' that `MultiscaleDTM` is not pulled into Imports for nine lines of geometry.
#'
#' @noRd
fev_annulus_window <- function(res, radius) {
  n <- floor((radius / res) * 2 + 1)
  if (n %% 2 == 0) {
    n <- n + 1
  }
  offsets <- (seq_len(n) - (n + 1) / 2) * res
  x <- matrix(offsets, nrow = n, ncol = n, byrow = TRUE)
  y <- matrix(offsets, nrow = n, ncol = n, byrow = FALSE)
  d <- sqrt(x^2 + y^2)
  w <- matrix(NA_real_, nrow = n, ncol = n)
  w[d >= res & d <= radius] <- 1
  w
}

#' Reduce whatever was passed to a 0-1 hazard raster
#' @noRd
fev_exposure_input <- function(fuel, lookup) {
  if (inherits(fuel, "fev_fuel_source")) {
    b <- fev_fuel_binary(fuel, lookup = lookup)
    return(list(raster = b$data, provenance = b$provenance,
                role = "fev_fuel_source -> binary", graded = FALSE))
  }
  if (inherits(fuel, "fev_layer")) {
    r <- fuel$data
    graded <- identical(fuel$role, "availability")
    fev_check_unit_range(r, "fuel")
    return(list(raster = r[[1]], provenance = fuel$provenance,
                role = fuel$role, graded = graded))
  }
  if (inherits(fuel, "fev_source")) {
    fuel <- fuel$data
  }
  if (!inherits(fuel, "SpatRaster")) {
    fev_abort(c(
      "{.arg fuel} must be a {.cls fev_fuel_source}, a {.cls fev_layer} or a \\
       {.cls SpatRaster}.",
      x = "Got {.cls {class(fuel)[1]}}.",
      i = "Build a mask with {.fn fev_fuel_binary}."
    ))
  }
  if (!is.null(fev_cat_levels(fuel))) {
    fev_abort(c(
      "{.arg fuel} is a categorical layer.",
      i = "Exposure is computed on a burnable mask, not on class codes. \\
           Reduce it with {.fn fev_fuel_binary} first."
    ), class = "fev_categorical_input")
  }
  fev_check_unit_range(fuel, "fuel")
  list(raster = fuel[[1]], provenance = NULL, role = "SpatRaster",
       graded = FALSE)
}

#' @noRd
fev_check_unit_range <- function(r, arg) {
  rng <- terra::global(r[[1]], fun = "range", na.rm = TRUE)
  lo <- as.numeric(rng[[1]][1])
  hi <- as.numeric(rng[[2]][1])
  if (!is.finite(lo)) {
    fev_abort(c(
      "{.arg {arg}} is entirely {.val NA}.",
      i = "Usually a disjoint AOI, or a lookup that matched nothing."
    ), class = "fev_all_na", .envir = environment())
  }
  if (lo < 0 || hi > 1) {
    fev_abort(c(
      "{.arg {arg}} must lie in {.val {c(0, 1)}}.",
      x = "Range is {.val {signif(c(lo, hi), 4)}}."
    ), class = "fev_bad_range", .envir = environment())
  }
  invisible(TRUE)
}

#' @noRd
fev_apply_no_burn <- function(exposure, no_burn) {
  if (!inherits(no_burn, "SpatRaster")) {
    fev_abort("{.arg no_burn} must be a {.cls SpatRaster}.")
  }
  vals <- unique(terra::values(no_burn[[1]]))
  if (!all(vals %in% c(1, NA, NaN))) {
    fev_abort(c(
      "{.arg no_burn} must contain only {.val 1} and {.val NA}.",
      i = "1 marks a cell that cannot burn; NA marks one that can."
    ), class = "fev_bad_no_burn")
  }
  if (!isTRUE(terra::compareGeom(exposure, no_burn, stopOnError = FALSE))) {
    fev_abort(c(
      "{.arg no_burn} is not on the fuel grid.",
      i = "Align it first with {.fn fev_align}."
    ), class = "fev_grid_mismatch")
  }
  terra::mask(exposure, no_burn[[1]], inverse = TRUE)
}

# --- directional vulnerability ----------------------------------------------

#' Directional vulnerability from a point
#'
#' Draws transects outward from a value in every direction and reports which
#' bearings offer a continuous high-exposure pathway to it. The answer to
#' "where would a fire come from" rather than "how much fuel is around".
#'
#' @section Method:
#' Follows Beverly and Forbes (2023). From the value, a transect is drawn at
#' every `interval` degrees. Each transect is cut into consecutive segments —
#' by default three of 5 km — and a segment counts as **viable** when at least
#' `thresh_viable` of the ground it crosses has exposure of at least
#' `thresh_exp`. A direction with all three segments viable is a continuous
#' corridor of hazardous fuel reaching the value from that bearing.
#'
#' Bearings are compass bearings: 0 and 360 are north, increasing clockwise.
#'
#' @section The two thresholds are measured, not conventional:
#' `thresh_exp = 0.6` because observed fires burned preferentially where
#' exposure exceeded 60%; `thresh_viable = 0.8` because observed burned
#' pathways intersected pre-fire high-exposure patches by 80% on average. Both
#' from Canadian landscapes — see [fev_directional_defaults()].
#'
#' @param exposure A `fev_exposure_layer` from [fev_exposure()], or a
#'   `SpatRaster` of exposure values in `[0, 1]`.
#' @param point The value at risk: an `sf`, `sfc`, `SpatVector` of one point,
#'   or a length-2 numeric `c(x, y)` in the exposure layer's CRS.
#' @param seg_lengths Segment lengths outward from the point, in CRS units.
#' @param interval Degrees between transects.
#' @param n_wedges Alternative to `interval`: number of evenly spaced
#'   directions, so `interval = 360 / n_wedges`.
#' @param max_dist Total transect length. When given, overrides `seg_lengths`
#'   by splitting it into three equal segments.
#' @param thresh_exp Exposure at or above which ground counts as hazardous.
#' @param thresh_viable Share of a segment that must be hazardous for it to be
#'   viable.
#' @param step Sampling interval along a transect. Defaults to the cell size.
#'
#' @return An object of class `fev_directional`: a list with `table` (one row
#'   per bearing, one logical column per segment plus `viable` for all
#'   segments), the parameters used, and a provenance record.
#'
#' @seealso [fev_exposure()], [fev_directional_defaults()].
#'
#' @source
#' Beverly, J.L., Forbes, A.M. (2023). Assessing directional vulnerability to
#' wildfire. *Natural Hazards* 117: 831-849. Parameters verified against the
#' `fireexposuR` 1.2.0 reference documentation on 2026-08-16.
#'
#' @examples
#' r <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 6000,
#'                  ymin = 0, ymax = 6000, crs = "EPSG:2154")
#' terra::values(r) <- 0
#' r[1:30, ] <- 0.9          # a high-exposure block to the north
#' d <- fev_directional(r, point = c(3000, 3000), seg_lengths = c(500, 500, 500),
#'                      interval = 45)
#' d$table
#'
#' @export
fev_directional <- function(exposure,
                            point,
                            seg_lengths = c(5000, 5000, 5000),
                            interval = 1,
                            n_wedges = NULL,
                            max_dist = NULL,
                            thresh_exp = 0.6,
                            thresh_viable = 0.8,
                            step = NULL) {
  prov <- fev_layer_prov(exposure)
  r <- fev_as_raster(exposure, "exposure")[[1]]
  fev_check_unit_range(r, "exposure")

  if (!is.null(n_wedges)) {
    if (!is.numeric(n_wedges) || length(n_wedges) != 1L || n_wedges < 1) {
      fev_abort("{.arg n_wedges} must be a single positive number.")
    }
    interval <- 360 / n_wedges
  }
  if (!is.null(max_dist)) {
    seg_lengths <- rep(max_dist / 3, 3)
  }
  if (any(seg_lengths <= 0)) {
    fev_abort("{.arg seg_lengths} must all be positive.")
  }
  for (nm in c("thresh_exp", "thresh_viable")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0 || v > 1) {
      fev_abort("{.arg {nm}} must be a single number in {.val {c(0, 1)}}.",
                .envir = environment())
    }
  }

  xy <- fev_directional_point(point, r)
  step <- step %||% terra::res(r)[1]
  bearings <- seq(interval, 360, by = interval)
  bounds <- c(0, cumsum(seg_lengths))
  n_seg <- length(seg_lengths)

  frac <- matrix(NA_real_, nrow = length(bearings), ncol = n_seg)
  off_grid <- 0L
  n_sampled <- 0L

  for (i in seq_along(bearings)) {
    theta <- bearings[i] * pi / 180
    for (k in seq_len(n_seg)) {
      d <- seq(bounds[k] + step / 2, bounds[k + 1], by = step)
      if (!length(d)) {
        next
      }
      # Compass bearings: 0 is north, clockwise, so x uses sin and y cos.
      px <- xy[1] + d * sin(theta)
      py <- xy[2] + d * cos(theta)
      vals <- terra::extract(r, cbind(px, py))[, 1]
      n_sampled <- n_sampled + length(vals)
      off_grid <- off_grid + sum(is.na(vals))
      frac[i, k] <- mean(vals >= thresh_exp, na.rm = TRUE)
    }
  }

  if (off_grid > 0) {
    fev_warn(c(
      "{round(100 * off_grid / n_sampled, 1)}% of transect samples fell \\
       outside the exposure layer.",
      i = "Those samples are dropped, so the affected segments are judged on \\
           the part of the transect that is mapped -- which biases them toward \\
           whatever the near field looks like.",
      i = "Use a layer extending at least {.val {sum(seg_lengths)}} beyond the \\
           point."
    ), class = "fev_transect_off_grid", .envir = environment())
  }

  viable <- frac >= thresh_viable
  viable[is.na(frac)] <- NA
  tab <- data.frame(bearing = bearings)
  for (k in seq_len(n_seg)) {
    tab[[paste0("seg", k)]] <- viable[, k]
    tab[[paste0("frac", k)]] <- round(frac[, k], 4)
  }
  tab$viable <- apply(viable, 1, function(v) isTRUE(all(v)))

  prov <- prov %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_directional",
    params = list(point = signif(xy, 8), seg_lengths = seg_lengths,
                  interval = interval, n_transects = length(bearings),
                  thresh_exp = thresh_exp, thresh_viable = thresh_viable,
                  step = step, n_viable = sum(tab$viable),
                  pct_off_grid = round(100 * off_grid / max(n_sampled, 1), 2),
                  source = "Beverly & Forbes 2023")
  )

  structure(
    list(table = tab, point = xy, crs = fev_crs_label(r),
         params = list(seg_lengths = seg_lengths, interval = interval,
                       thresh_exp = thresh_exp, thresh_viable = thresh_viable,
                       step = step),
         provenance = prov),
    class = "fev_directional"
  )
}

#' @noRd
fev_directional_point <- function(point, r) {
  xy <- if (is.numeric(point) && length(point) == 2L) {
    as.numeric(point)
  } else {
    p <- if (inherits(point, "SpatVector")) sf::st_as_sf(point) else point
    if (!inherits(p, c("sf", "sfc"))) {
      fev_abort(c(
        "{.arg point} must be an {.cls sf}, {.cls sfc}, {.cls SpatVector} or \\
         {.code c(x, y)}.",
        x = "Got {.cls {class(point)[1]}}."
      ))
    }
    g <- sf::st_geometry(p)
    if (length(g) != 1L) {
      fev_abort(c(
        "{.arg point} must be exactly one point.",
        x = "Got {length(g)}.",
        i = "Loop over your values, or use {.fn fev_exposure} for a map."
      ), .envir = environment())
    }
    if (fev_crs_usable(g) && !fev_crs_equal(g, r)) {
      g <- sf::st_transform(g, fev_crs(r))
    }
    as.numeric(sf::st_coordinates(sf::st_centroid(g))[1, 1:2])
  }

  e <- fev_bbox(r)
  if (xy[1] < e[["xmin"]] || xy[1] > e[["xmax"]] ||
      xy[2] < e[["ymin"]] || xy[2] > e[["ymax"]]) {
    fev_abort(c(
      "{.arg point} falls outside the exposure layer.",
      x = "Point {.val {signif(xy, 8)}}; extent {.val {signif(e, 8)}}.",
      i = "Both are read in {.val {fev_crs_label(r)}} -- if the point came \\
           from a lon/lat file, set its CRS rather than its numbers."
    ), class = "fev_disjoint_extent", .envir = environment())
  }
  xy
}

#' @export
print.fev_directional <- function(x, ...) {
  tab <- x$table
  n_seg <- sum(grepl("^seg", names(tab)))
  cli::cli_h1("fev_directional")
  cli::cli_li("Point: {.val {signif(x$point, 8)}} ({x$crs})")
  cli::cli_li("{nrow(tab)} transect{?s} every {x$params$interval} degree{?s}, \\
               {n_seg} segment{?s} of {.val {x$params$seg_lengths}}")
  cli::cli_li("Thresholds: exposure {.val {x$params$thresh_exp}}, viability \\
               {.val {x$params$thresh_viable}}")

  n_viable <- sum(tab$viable)
  if (!n_viable) {
    cli::cli_alert_success("No direction offers a continuous pathway.")
  } else {
    cli::cli_alert_warning(
      "{n_viable} of {nrow(tab)} bearing{?s} ({round(100 * n_viable / nrow(tab), 1)}%) \\
       offer a continuous high-exposure pathway."
    )
    cli::cli_li("Bearings: {.val {fev_bearing_ranges(tab$bearing[tab$viable])}}")
  }
  invisible(x)
}

#' Collapse a set of bearings into readable ranges
#' @noRd
fev_bearing_ranges <- function(b) {
  if (!length(b)) {
    return(character())
  }
  b <- sort(b)
  brk <- c(0, which(diff(b) > 1), length(b))
  vapply(seq_len(length(brk) - 1L), function(i) {
    seg <- b[(brk[i] + 1L):brk[i + 1L]]
    if (length(seg) == 1L) as.character(seg) else paste0(min(seg), "-", max(seg))
  }, character(1))
}

#' @export
plot.fev_directional <- function(x, ...) {
  tab <- x$table
  theta <- tab$bearing * pi / 180
  radius <- ifelse(tab$viable, 1, 0.35)
  px <- radius * sin(theta)
  py <- radius * cos(theta)
  graphics::plot(px, py, type = "n", asp = 1, axes = FALSE, xlab = "", ylab = "",
                 main = "Directional vulnerability", ...)
  graphics::symbols(0, 0, circles = 1, inches = FALSE, add = TRUE,
                    fg = "grey80")
  graphics::segments(0, 0, px, py,
                     col = ifelse(tab$viable, "firebrick", "grey85"))
  graphics::text(0, 1.12, "N")
  invisible(x)
}

#' What a focal exposure pass will cost, before committing to it
#'
#' Reports the size of the window and the weighted operation count for a fuel
#' grid, at its own resolution or at a hypothetical one. Exists because the cost
#' of this step grows as the **fourth power** of the inverse cell size — both the
#' cell count and the window area scale as `res^-2` — so the step from 25 m to
#' 10 m is not a 2.5-fold increase but roughly forty-fold, and that is worth
#' knowing before a run rather than during one.
#'
#' @section The other reason to ask:
#' `fev_exposure()` requires `res <= radius / 3`, so a coarse grid does not
#' merely cost less, it puts the short radii out of reach entirely. At 25 m the
#' 30 m radiant-heat radius is refused; at 10 m it passes, exactly, since
#' `10 = 30 / 3`. This function reports whether each radius is reachable at the
#' resolution asked about, which is the trade the cost has to be weighed against.
#'
#' @param x A fuel layer: `SpatRaster`, [fev_fuel_source] or `fev_layer`.
#' @param res Cell size to cost, in CRS units. `NULL` uses `x`'s own.
#' @param radius Radius in metres. `NULL` costs all three shipped radii.
#' @param rate Weighted operations per second, for the time estimate. The
#'   default was measured on the machine this package was developed on; yours
#'   will differ, which is why it is an argument and the result is called an
#'   estimate.
#'
#' @return A data frame with one row per radius: `radius`, `res`, `reachable`,
#'   `window_cells`, `ring_cells`, `ops` and `seconds`.
#'
#' @seealso [fev_exposure()], [fev_exposure_radii()].
#'
#' @examples
#' r <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 2500,
#'                  ymin = 0, ymax = 2500, crs = "EPSG:2154")
#' terra::values(r) <- 1
#'
#' # What the three scales cost on this grid, and which are out of reach.
#' fev_exposure_cost(r)
#'
#' # And what refining to 10 m would cost.
#' fev_exposure_cost(r, res = 10)
#'
#' @export
fev_exposure_cost <- function(x, res = NULL, radius = NULL, rate = 2e8) {
  r <- if (inherits(x, "fev_fuel_source")) {
    fev_fuel_categorical(x)
  } else if (inherits(x, "fev_layer")) {
    fev_data(x)
  } else {
    x
  }
  if (!inherits(r, "SpatRaster")) {
    fev_abort("{.arg x} must be a {.cls SpatRaster}, {.cls fev_fuel_source} \\
               or {.cls fev_layer}.")
  }

  native_res <- terra::res(r)[1]
  res <- res %||% native_res
  if (!is.numeric(res) || length(res) != 1L || is.na(res) || res <= 0) {
    fev_abort("{.arg res} must be a single positive number, in CRS units.")
  }

  radii <- fev_exposure_radii()
  radius <- radius %||% radii$max_m
  if (!is.numeric(radius) || anyNA(radius) || any(radius <= 0)) {
    fev_abort("{.arg radius} must be positive numbers, in CRS units.")
  }

  # The extent is fixed; only the cell size moves. Scaling the native cell count
  # rather than rebuilding a raster keeps this cheap enough to call casually.
  ncell <- as.numeric(terra::ncell(r)) * (native_res / res)^2

  rows <- lapply(radius, function(rad) {
    reachable <- res <= rad / 3
    if (!reachable) {
      return(data.frame(radius = rad, res = res, reachable = FALSE,
                        window_cells = NA_integer_, ring_cells = NA_integer_,
                        ops = NA_real_, seconds = NA_real_,
                        stringsAsFactors = FALSE))
    }
    # fev_annulus_window() returns a weight MATRIX, not a raster: terra's focal
    # takes it as such, and so does the arithmetic here.
    w <- fev_annulus_window(res, rad)
    ring <- sum(!is.na(w))
    ops <- ncell * ring
    data.frame(radius = rad, res = res, reachable = TRUE,
               window_cells = as.integer(length(w)),
               ring_cells = as.integer(ring),
               ops = ops, seconds = ops / rate,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
