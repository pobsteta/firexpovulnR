# Composite danger: weather danger tempered by what there is to burn.
#
# The scale gap is the whole difficulty. CEMS fire danger is on a ~25 km grid,
# fuel availability on a 25 m one -- a ratio of a thousand. This function does
# NOT resample. It refuses inputs that do not already share a grid and names
# fev_align(), because the brief allows exactly one place where resampling
# happens and this is not it. An implicit resample here would be invisible in
# the result and permanent in the conclusions.

#' Composite fire danger
#'
#' Combines meteorological fire danger with fuel availability into one
#' normalised index in `[0, 1]`. Weather that cannot reach fuel is not danger,
#' and fuel with no weather to dry it is not either.
#'
#' @section Both inputs must already share a grid:
#' This function does not resample. Fire danger from ERA5 is kilometric and
#' fuel is decametric; bringing them together is a deliberate, recorded
#' operation that belongs to `fev_align()`. Passing mismatched grids here is an
#' error, not a convenience to smooth over.
#'
#' `fev_align()` lands in phase 7. Until then, align the layers yourself and
#' say so in your methods — that is the same requirement, just manual.
#'
#' @section Normalising the danger side:
#' `method` combines two numbers in `[0, 1]`, so danger has to get there first.
#' A [fev_fwi_percentile()] result is already a percentile rank and is divided
#' by 100. Anything else needs `normalise` stated explicitly: the function will
#' not guess whether a layer of values between 0 and 60 is raw FWI, a
#' percentile, or something else entirely.
#'
#' @section Choosing a method:
#' `"product"` is the default because fire needs both: either factor at zero
#' gives zero, which is the behaviour a fuel break or a wet week should have.
#' It is also the most severe — the product of two numbers below 1 is below
#' both — so a landscape of moderate danger over moderate fuel scores low.
#'
#' `"min"` is the limiting-factor reading: danger is whatever is scarcest.
#' `"mean"` lets one factor compensate for the other, which is the EFFIS-style
#' additive logic and is the least defensible physically, though it is what
#' composite indices usually do. `"geometric"` sits between product and mean.
#'
#' None of these is validated against burnt-area data here. That is
#' `fev_validate()`, in phase 7.
#'
#' @param danger Meteorological fire danger: a `fev_danger_layer` from
#'   [fev_fwi_percentile()], a `SpatRaster`, or a [fev_source].
#' @param fuel_availability Fuel availability in `[0, 1]`: a `fev_fuel_layer`
#'   from [fev_fuel_availability()], or a `SpatRaster`.
#' @param method `"product"`, `"min"`, `"mean"` or `"geometric"`.
#' @param normalise How to bring `danger` into `[0, 1]`: `"auto"` (percentile
#'   ranks only), `"percentile"`, `"minmax"`, or `"none"` when it is already
#'   scaled.
#' @param weights Two weights for `method = "mean"`, danger then fuel. Must sum
#'   to 1.
#'
#' @return A `fev_danger_layer` holding a `SpatRaster` named `danger` with
#'   values in `[0, 1]`.
#'
#' @seealso [fev_fwi_percentile()], [fev_fuel_availability()].
#'
#' @examples
#' g <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' d <- terra::setValues(g, seq(0, 100, length.out = 16))
#' a <- terra::setValues(g, rep(c(0, 0.5, 0.95, 1), 4))
#' idx <- fev_danger_index(d, a, normalise = "percentile")
#' terra::global(fev_data(idx), "range", na.rm = TRUE)
#'
#' @export
fev_danger_index <- function(danger,
                             fuel_availability,
                             method = c("product", "min", "mean", "geometric"),
                             normalise = c("auto", "percentile", "minmax", "none"),
                             weights = c(0.5, 0.5)) {
  method <- match.arg(method)
  normalise <- match.arg(normalise)

  d_prov <- fev_layer_prov(danger)
  f_prov <- fev_layer_prov(fuel_availability)
  role <- if (inherits(danger, "fev_layer")) danger$role else NA_character_

  d <- fev_as_raster(danger, "danger")
  a <- fev_as_raster(fuel_availability, "fuel_availability")

  if (terra::nlyr(a) != 1L) {
    fev_abort(c(
      "{.arg fuel_availability} must be a single layer.",
      x = "Got {terra::nlyr(a)}."
    ), .envir = environment())
  }

  if (!isTRUE(terra::compareGeom(d, a, stopOnError = FALSE))) {
    fev_abort(c(
      "{.arg danger} and {.arg fuel_availability} are not on the same grid.",
      x = "Danger: {terra::nrow(d)} x {terra::ncol(d)} at \\
           {.val {signif(terra::res(d)[1], 6)}}, {fev_crs_label(d)}.",
      x = "Fuel: {terra::nrow(a)} x {terra::ncol(a)} at \\
           {.val {signif(terra::res(a)[1], 6)}}, {fev_crs_label(a)}.",
      i = "This function does not resample. Resampling between kilometric \\
           danger and decametric fuel is the single most consequential step \\
           in the chain, so it happens in one named place and is recorded \\
           there.",
      i = "Align them first -- {.code fev_align()} in phase 7, or by hand \\
           until then."
    ), class = "fev_grid_mismatch", .envir = environment())
  }

  a_rng <- terra::global(a, fun = "range", na.rm = TRUE)
  a_min <- as.numeric(a_rng[[1]][1])
  a_max <- as.numeric(a_rng[[2]][1])
  if (is.finite(a_min) && (a_min < 0 || a_max > 1)) {
    fev_abort(c(
      "{.arg fuel_availability} must lie in {.val {c(0, 1)}}.",
      x = "Range is {.val {signif(c(a_min, a_max), 4)}}.",
      i = "Build it with {.fn fev_fuel_availability}, which guarantees that."
    ), class = "fev_bad_range", .envir = environment())
  }

  norm <- fev_resolve_normalise(normalise, role)
  d01 <- fev_normalise_danger(d, norm)

  combined <- switch(
    method,
    product   = d01 * a,
    min       = terra::lapp(c(d01, a), fun = function(x, y) pmin(x, y)),
    mean      = fev_check_weights(weights)[1] * d01 +
                fev_check_weights(weights)[2] * a,
    geometric = sqrt(d01 * a)
  )
  names(combined) <- if (terra::nlyr(combined) > 1L) names(d) else "danger"

  prov <- fev_prov_merge(d_prov, f_prov) %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_danger_index",
    params = list(method = method, normalise = norm,
                  weights = if (identical(method, "mean")) weights else NULL,
                  danger_role = role, n_layers = terra::nlyr(d),
                  res = signif(terra::res(d)[1], 6),
                  crs = fev_crs_label(d))
  )

  new_fev_layer(combined, role = "danger_index", provenance = prov,
                units = "dimensionless, 0-1", class = "fev_danger_layer")
}

#' Decide how to scale the danger side, refusing to guess
#' @noRd
fev_resolve_normalise <- function(normalise, role) {
  if (!identical(normalise, "auto")) {
    return(normalise)
  }
  if (identical(role, "fwi_percentile")) {
    return("percentile")
  }
  fev_abort(c(
    "{.arg normalise} cannot be resolved automatically for this input.",
    i = "Automatic resolution only recognises a {.fn fev_fwi_percentile} \\
         result, which is a percentile rank by construction.",
    i = "State it: {.code normalise = \"percentile\"} for 0-100 ranks, \\
         {.val minmax} to rescale the layer's own range, {.val none} if it is \\
         already in 0-1.",
    x = "Guessing from the value range would silently turn raw FWI into a \\
         percentile, and the result would look perfectly plausible."
  ), class = "fev_normalise_ambiguous")
}

#' @noRd
fev_normalise_danger <- function(d, norm) {
  if (identical(norm, "none")) {
    rng <- terra::global(d, fun = "range", na.rm = TRUE)
    lo <- min(as.numeric(rng[[1]]), na.rm = TRUE)
    hi <- max(as.numeric(rng[[2]]), na.rm = TRUE)
    if (is.finite(lo) && (lo < 0 || hi > 1)) {
      fev_abort(c(
        "{.code normalise = \"none\"} but {.arg danger} is outside \\
         {.val {c(0, 1)}}.",
        x = "Range is {.val {signif(c(lo, hi), 4)}}."
      ), class = "fev_bad_range", .envir = environment())
    }
    return(d)
  }
  if (identical(norm, "percentile")) {
    rng <- terra::global(d, fun = "range", na.rm = TRUE)
    hi <- max(as.numeric(rng[[2]]), na.rm = TRUE)
    if (is.finite(hi) && hi > 100) {
      fev_abort(c(
        "{.code normalise = \"percentile\"} but {.arg danger} reaches \\
         {.val {signif(hi, 4)}}.",
        i = "Percentile ranks cannot exceed 100. This looks like raw FWI."
      ), class = "fev_bad_range", .envir = environment())
    }
    return(d / 100)
  }
  # minmax: rescaled on the layer's own range, which makes the result
  # dependent on the extent processed. Said out loud rather than buried.
  rng <- terra::global(d, fun = "range", na.rm = TRUE)
  lo <- min(as.numeric(rng[[1]]), na.rm = TRUE)
  hi <- max(as.numeric(rng[[2]]), na.rm = TRUE)
  if (!is.finite(lo) || !is.finite(hi) || hi == lo) {
    fev_abort(c(
      "Cannot min-max rescale: the layer has no range.",
      i = "It is constant, or entirely {.val NA}."
    ), class = "fev_bad_range")
  }
  fev_warn(c(
    "Min-max normalisation rescales on this extent's own range \\
     ({.val {signif(c(lo, hi), 4)}}).",
    i = "The same pixel scores differently under a different AOI, so results \\
         are not comparable between study areas. Percentile ranks against a \\
         fixed reference are."
  ), class = "fev_extent_dependent", .envir = environment())
  (d - lo) / (hi - lo)
}

#' @noRd
fev_check_weights <- function(weights) {
  if (length(weights) != 2L || !is.numeric(weights) || anyNA(weights)) {
    fev_abort("{.arg weights} must be two numbers: danger, then fuel.")
  }
  if (any(weights < 0) || abs(sum(weights) - 1) > 1e-8) {
    fev_abort(c(
      "{.arg weights} must be non-negative and sum to 1.",
      x = "Got {.val {weights}}, summing to {.val {sum(weights)}}."
    ), .envir = environment())
  }
  weights
}

#' Pull a raster out of whatever the caller passed
#' @noRd
fev_as_raster <- function(x, arg) {
  r <- if (inherits(x, c("fev_layer", "fev_source"))) x$data else x
  if (!inherits(r, "SpatRaster")) {
    fev_abort(c(
      "{.arg {arg}} must be a {.cls SpatRaster}, a {.cls fev_layer} or a \\
       {.cls fev_source}.",
      x = "Got {.cls {class(x)[1]}}."
    ), .envir = environment())
  }
  r
}

#' @noRd
fev_layer_prov <- function(x) {
  if (inherits(x, "fev_layer")) x$provenance else NULL
}
