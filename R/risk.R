# Composite risk: danger crossed with vulnerability.
#
# Three methods, and they are not three estimates of one quantity. Two of them
# come from the CLIMAAX wildfire workflow, whose notebook was read on
# 2026-08-16 rather than paraphrased: it normalises each component with min-max,
# averages the danger components with equal weights, and then combines danger
# with the vulnerability indicators through a Pareto analysis. The third,
# "weighted", is the ordinary weighted mean, which the package supports because
# people want it, not because anything validates it.

#' Composite fire risk
#'
#' Crosses composite danger with vulnerability, and optionally with further
#' dimensions, into one risk layer.
#'
#' @section The three methods answer different questions:
#' `"effis_mean"` normalises every component with min-max and takes their
#' unweighted arithmetic mean. This is the CLIMAAX danger-index step applied to
#' risk: simple, continuous, and it lets a very high score on one dimension be
#' bought back by a low score on another. That compensation is the whole
#' objection to it.
#'
#' `"pareto"` is what the CLIMAAX wildfire workflow actually does for risk. It
#' returns the **Pareto front**: the cells that cannot be improved on one
#' dimension without being worse on another, treating every dimension as
#' equally important with no weights at all. Note what this gives you — a
#' **set**, not a score. A cell is on the front or it is not, and the front says
#' nothing about how far from it the others are. Use `depth` to peel successive
#' fronts and get a graded layer instead.
#'
#' `"weighted"` is a weighted mean. It requires `weights` and writes them into
#' the record, because they are the analysis's judgement and nothing in the data
#' supplies them.
#'
#' @section Normalisation restretches layers that were already scaled:
#' `normalise = "minmax"` is the default because it is what CLIMAAX does. It
#' rescales each component on its own observed range, so a
#' [fev_vuln_stack()] layer that legitimately spans 0.3 to 0.6 comes out
#' spanning 0 to 1, and its lowest cell becomes a zero. When your components are
#' already on a meaningful common scale — which is what the rest of this package
#' produces — pass `normalise = "none"`.
#'
#' Min-max also makes the result depend on the extent processed: the same cell
#' scores differently under a different AOI.
#'
#' @section Grids must already match:
#' As everywhere outside [fev_align()], mismatched grids are an error.
#'
#' @param danger Composite danger: a `fev_layer` from [fev_danger_index()], or a
#'   `SpatRaster`.
#' @param vulnerability Vulnerability: a `fev_layer` from [fev_vuln_stack()], or
#'   a `SpatRaster`.
#' @param ... Further named dimensions to enter the combination, as CLIMAAX does
#'   with its wildland-urban interface, protected area, ecological
#'   irreplaceability and restoration cost indicators.
#' @param method `"effis_mean"`, `"pareto"` or `"weighted"`.
#' @param weights Required for `"weighted"`: one per dimension, summing to 1.
#' @param normalise `"minmax"` (default, as CLIMAAX) or `"none"`.
#' @param depth For `"pareto"`: how many successive fronts to peel. `1` gives
#'   the CLIMAAX boolean front; a larger number gives a graded layer where the
#'   first front scores 1 and deeper fronts score less; `Inf` peels until
#'   nothing is left.
#' @param digits For `"pareto"`: values are rounded to this many decimals before
#'   dominance is computed. A front computed on floating-point noise in the
#'   fifteenth decimal is not a front, and rounding is what keeps the problem
#'   tractable.
#' @param max_unique For `"pareto"`: refuse rather than run for hours when the
#'   rounded values yield more distinct combinations than this.
#'
#' @return A `fev_risk_layer` holding a `SpatRaster` named `risk`.
#'
#' @seealso [fev_validate()] to test the result against burnt areas,
#'   [fev_align()] to put the inputs on one grid.
#'
#' @source
#' CLIMAAX Climate Risk Assessment Handbook, FWI wildfire workflow, read
#' 2026-08-16:
#' <https://handbook.climaax.eu/notebooks/workflows/FIRE/02_wildfire_FWI/FWI_Risk_Assessment.html>.
#' The min-max-then-average step and the `paretoset(..., sense = [max, ...])`
#' call were read from the notebook's own code, not from its prose.
#'
#' @examples
#' g <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 150,
#'                  ymin = 0, ymax = 150, crs = "EPSG:2154")
#' danger <- terra::setValues(g, seq(0, 1, length.out = 36))
#' vuln <- terra::setValues(g, rev(seq(0, 1, length.out = 36)))
#'
#' mean_risk <- fev_risk(danger, vuln, normalise = "none")
#' terra::global(fev_data(mean_risk), "mean", na.rm = TRUE)
#'
#' front <- fev_risk(danger, vuln, method = "pareto", normalise = "none")
#' terra::global(fev_data(front), "sum", na.rm = TRUE)
#'
#' @export
fev_risk <- function(danger,
                     vulnerability,
                     ...,
                     method = c("effis_mean", "pareto", "weighted"),
                     weights = NULL,
                     normalise = c("minmax", "none"),
                     depth = 1,
                     digits = 3,
                     max_unique = 50000) {
  method <- match.arg(method)
  normalise <- match.arg(normalise)

  extra <- list(...)
  if (length(extra) && (is.null(names(extra)) || any(!nzchar(names(extra))))) {
    fev_abort(c(
      "Every extra dimension must be named.",
      i = "e.g. {.code fev_risk(danger, vuln, wui = interface, natura = n2000)}."
    ))
  }

  layers <- c(list(danger = danger, vulnerability = vulnerability), extra)
  nms <- names(layers)
  provs <- lapply(layers, fev_layer_prov)
  rasters <- Map(function(l, nm) fev_as_raster(l, nm)[[1]], layers, nms)

  ref <- rasters[[1]]
  for (i in seq_along(rasters)[-1]) {
    if (!isTRUE(terra::compareGeom(ref, rasters[[i]], stopOnError = FALSE))) {
      fev_abort(c(
        "{.val {nms[i]}} is not on the same grid as {.val {nms[1]}}.",
        x = "{.val {nms[1]}}: {terra::nrow(ref)} x {terra::ncol(ref)} at \\
             {.val {signif(terra::res(ref)[1], 6)}}.",
        x = "{.val {nms[i]}}: {terra::nrow(rasters[[i]])} x \\
             {terra::ncol(rasters[[i]])} at \\
             {.val {signif(terra::res(rasters[[i]])[1], 6)}}.",
        i = "Align them with {.fn fev_align} first."
      ), class = "fev_grid_mismatch", .envir = environment())
    }
  }

  ranges <- lapply(rasters, function(r) {
    g <- terra::global(r, fun = "range", na.rm = TRUE)
    c(as.numeric(g[[1]][1]), as.numeric(g[[2]][1]))
  })
  if (any(vapply(ranges, function(x) !is.finite(x[1]), logical(1)))) {
    fev_abort(c(
      "At least one dimension is entirely {.val NA}.",
      i = "Usually a disjoint AOI, or a lookup that matched nothing."
    ), class = "fev_all_na")
  }

  scaled <- if (identical(normalise, "minmax")) {
    fev_risk_minmax(rasters, ranges, nms)
  } else {
    for (i in seq_along(rasters)) {
      fev_check_unit_range(rasters[[i]], nms[i])
    }
    rasters
  }

  out <- switch(
    method,
    effis_mean = fev_risk_mean(scaled, rep(1 / length(scaled), length(scaled))),
    weighted   = fev_risk_mean(scaled, fev_risk_weights(weights, nms)),
    pareto     = fev_risk_pareto(scaled, nms, depth, digits, max_unique)
  )
  names(out) <- "risk"

  prov <- Reduce(fev_prov_merge, provs) %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_risk",
    params = list(
      method = method, dimensions = nms, n_dimensions = length(nms),
      normalise = normalise,
      weights = if (identical(method, "weighted"))
        stats::setNames(as.list(fev_risk_weights(weights, nms)), nms) else NULL,
      depth = if (identical(method, "pareto")) depth else NULL,
      digits = if (identical(method, "pareto")) digits else NULL,
      input_ranges = stats::setNames(
        lapply(ranges, function(x) signif(x, 6)), nms
      ),
      extent_dependent = identical(normalise, "minmax"),
      source = "CLIMAAX FWI wildfire workflow, read 2026-08-16"
    )
  )

  new_fev_layer(out, role = "risk", provenance = prov,
                units = if (identical(method, "pareto") && depth == 1)
                  "Pareto front membership, 0/1" else "dimensionless, 0-1",
                class = "fev_risk_layer")
}

#' @noRd
fev_risk_minmax <- function(rasters, ranges, nms) {
  flat <- vapply(ranges, function(x) x[2] == x[1], logical(1))
  if (any(flat)) {
    fev_abort(c(
      "Dimension{?s} {.val {nms[flat]}} {?is/are} constant.",
      i = "Min-max cannot rescale a layer with no range. Drop it, or pass \\
           {.code normalise = \"none\"}."
    ), class = "fev_bad_range", .envir = environment())
  }
  fev_once("risk_minmax", fev_warn(c(
    "Min-max normalisation rescales each dimension on its own observed range.",
    i = "A layer already scaled to {.val {c(0, 1)}} is restretched, so its \\
         lowest cell becomes a zero -- pass {.code normalise = \"none\"} when \\
         your components are already comparable.",
    i = "It also makes the result depend on the extent processed. Shown once \\
         per session; recorded in the provenance every time."
  ), class = "fev_extent_dependent"))

  Map(function(r, rg) (r - rg[1]) / (rg[2] - rg[1]), rasters, ranges)
}

#' @noRd
fev_risk_mean <- function(scaled, w) {
  Reduce(`+`, Map(function(r, wi) r * wi, scaled, w))
}

#' @noRd
fev_risk_weights <- function(weights, nms) {
  if (is.null(weights)) {
    fev_abort(c(
      "{.code method = \"weighted\"} requires {.arg weights}.",
      i = "One per dimension ({.val {nms}}), summing to 1.",
      i = "There is no data-driven default: the weights are the analysis's \\
           judgement, so they have to be typed and are recorded as typed.",
      i = "For equal weights, {.code method = \"effis_mean\"} already is that."
    ), .envir = environment())
  }
  if (length(weights) != length(nms) || !is.numeric(weights) ||
      anyNA(weights)) {
    fev_abort(c(
      "{.arg weights} must be one number per dimension.",
      x = "Got {length(weights)} for {length(nms)} dimension{?s}."
    ), .envir = environment())
  }
  if (any(weights < 0) || abs(sum(weights) - 1) > 1e-8) {
    fev_abort(c(
      "{.arg weights} must be non-negative and sum to 1.",
      x = "Got {.val {weights}}, summing to {.val {round(sum(weights), 6)}}."
    ), .envir = environment())
  }
  weights
}

#' Pareto front, and successive peels of it
#'
#' Dominance depends only on the value tuple, so the work is done on the
#' distinct rounded tuples and mapped back. Without that reduction the skyline
#' scan is quadratic in the number of cells, which on a departmental raster is
#' an afternoon rather than a second.
#'
#' @noRd
fev_risk_pareto <- function(scaled, nms, depth, digits, max_unique) {
  if (!is.numeric(depth) || length(depth) != 1L || depth < 1) {
    fev_abort("{.arg depth} must be a single number of at least 1.")
  }
  m <- do.call(cbind, lapply(scaled, function(r) terra::values(r)[, 1]))
  colnames(m) <- nms
  ok <- stats::complete.cases(m)
  if (!any(ok)) {
    fev_abort(c(
      "No cell has a value on every dimension.",
      i = "Pareto dominance is undefined where any dimension is {.val NA}."
    ), class = "fev_all_na")
  }

  vals <- round(m[ok, , drop = FALSE], digits)
  key <- do.call(paste, c(as.data.frame(vals), sep = "\r"))
  uniq_key <- unique(key)
  if (length(uniq_key) > max_unique) {
    fev_abort(c(
      "{length(uniq_key)} distinct value combinations at {digits} decimals.",
      i = "The dominance scan is quadratic in this number; above \\
           {max_unique} it would run for a very long time rather than fail.",
      i = "Lower {.arg digits}, coarsen the grid, or raise {.arg max_unique} \\
           if you are willing to wait."
    ), class = "fev_pareto_too_large", .envir = environment())
  }

  u <- vals[match(uniq_key, key), , drop = FALSE]
  rank_u <- rep(NA_real_, nrow(u))
  remaining <- seq_len(nrow(u))
  level <- 1L
  while (length(remaining) && level <= depth) {
    front <- fev_pareto_front(u[remaining, , drop = FALSE])
    rank_u[remaining[front]] <- level
    remaining <- remaining[!front]
    level <- level + 1L
  }
  n_levels <- level - 1L

  score_u <- if (is.finite(depth) && depth == 1) {
    ifelse(is.na(rank_u), 0, 1)
  } else {
    # Front 1 scores 1, the deepest scores just above 0, everything never
    # reached scores 0. A rank is an order, not a distance: two adjacent
    # fronts are not equally far apart everywhere.
    ifelse(is.na(rank_u), 0, (n_levels - rank_u + 1) / n_levels)
  }

  out <- terra::rast(scaled[[1]])
  v <- rep(NA_real_, terra::ncell(out))
  v[ok] <- score_u[match(key, uniq_key)]
  terra::values(out) <- v
  out
}

#' Non-dominated rows of a matrix, maximising every column
#'
#' Sorted by the first column descending so that a row can only be dominated by
#' one already accepted, which is what keeps the inner loop over the front
#' rather than over everything.
#'
#' @noRd
fev_pareto_front <- function(m) {
  n <- nrow(m)
  ord <- do.call(order, c(lapply(seq_len(ncol(m)), function(j) -m[, j])))
  sorted <- m[ord, , drop = FALSE]
  keep <- logical(n)
  front <- integer(0)
  for (i in seq_len(n)) {
    dominated <- FALSE
    for (f in front) {
      if (all(sorted[f, ] >= sorted[i, ]) && any(sorted[f, ] > sorted[i, ])) {
        dominated <- TRUE
        break
      }
    }
    if (!dominated) {
      keep[i] <- TRUE
      front <- c(front, i)
    }
  }
  out <- logical(n)
  out[ord] <- keep
  out
}
