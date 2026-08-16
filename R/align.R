# The one place in the package where grids are allowed to change.
#
# Brought forward from phase 7 because fev_danger_index() refuses mismatched
# grids and points here, and without it the target workflow cannot run at all.
# Everything else in the package refuses to resample precisely so that this
# function is the only thing anyone has to audit.

#' Put layers on a common grid, explicitly
#'
#' Resamples a set of layers onto one grid and records exactly what was done.
#' This is the **only** function in the package that changes a layer's grid;
#' every other one refuses mismatched inputs and sends you here.
#'
#' @section Why it is a function of its own:
#' Fire danger from the ERA5-driven CEMS product is on a 0.25° grid — 20 to
#' 30 km at French latitudes. Fuel-derived exposure is at 20 to 100 m. Bringing
#' them together spans three orders of magnitude, and whichever direction you
#' go, something is lost or invented:
#'
#' - **to the finest grid** (the default, because it is what a risk map is
#'   for): one danger value is copied across roughly a million fuel pixels. The
#'   map looks decametric and the weather in it is not. Nothing is added by
#'   this step except resolution that no data supports.
#' - **to the coarsest grid**: exposure is averaged over a 25 km cell, which
#'   destroys exactly the spatial contrast the fuel module exists to produce,
#'   but invents nothing.
#'
#' Neither is right. The point of naming the operation is that the ratio ends
#' up in the provenance record and in a warning you cannot miss, rather than
#' in an implicit `resample()` three functions deep.
#'
#' @section Method:
#' Categorical layers are always resampled with nearest neighbour, whatever you
#' ask for — anything else averages class codes into meaningless numbers.
#'
#' For continuous layers going to a **finer** grid the default is also nearest
#' neighbour, deliberately: bilinear interpolation between the centres of two
#' 25 km cells draws a smooth gradient across the intervening landscape that
#' the reanalysis never resolved, and it is very convincing. Going to a
#' **coarser** grid the default is `"average"`, which is the honest summary of
#' many fine cells.
#'
#' @param ... Named layers: `SpatRaster`, `fev_layer` or [fev_source]. Names
#'   become the layer names of the result.
#' @param to Optional target: a `SpatRaster` whose grid to adopt, or the name
#'   of one of the layers in `...`.
#' @param direction Which grid to align onto when `to` is not given:
#'   `"finest"` (default) or `"coarsest"`.
#' @param method Resampling method, or `NULL` to let each layer take the
#'   default described above. Passed to [terra::resample()].
#' @param crs_work EPSG code recorded as the working CRS of the result.
#' @param quiet Suppress the scale-ratio warning. It exists to be read; use
#'   this only in loops where you have already reported the ratio.
#'
#' @return A [fev_stack()] holding the aligned layers, whose provenance records
#'   the target grid, the method used for each layer, and the scale ratio.
#'
#' @seealso [fev_danger_index()], which refuses to do this itself.
#'
#' @examples
#' danger <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 1000,
#'                       ymin = 0, ymax = 1000, crs = "EPSG:2154")
#' terra::values(danger) <- c(10, 20, 30, 40)
#' expo <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
#'                     ymin = 0, ymax = 1000, crs = "EPSG:2154")
#' terra::values(expo) <- runif(1600)
#' s <- fev_align(danger = danger, exposure = expo, quiet = TRUE)
#' vapply(s, function(r) terra::res(r)[1], numeric(1))
#'
#' @export
fev_align <- function(..., to = NULL, direction = c("finest", "coarsest"),
                      method = NULL, crs_work = NULL, quiet = FALSE) {
  direction <- match.arg(direction)
  layers <- list(...)
  nms <- names(layers)

  if (length(layers) < 1L) {
    fev_abort("{.fn fev_align} needs at least one layer.")
  }
  if (is.null(nms) || any(!nzchar(nms))) {
    fev_abort(c(
      "Every layer must be named.",
      i = "Names become the layer names of the returned {.cls fev_stack}, \\
           e.g. {.code fev_align(danger = d, exposure = e)}."
    ))
  }

  provs <- lapply(layers, fev_layer_prov)
  rasters <- Map(fev_as_raster, layers, nms)

  crs_labels <- vapply(rasters, fev_crs_label, character(1))
  if (length(unique(crs_labels)) > 1L) {
    fev_inform(c(
      "Layers arrive in different CRS: {.val {unique(crs_labels)}}.",
      i = "They are reprojected onto the target grid's CRS as part of the \\
           alignment, and the change is recorded."
    ), class = "fev_align_reproject", .envir = environment())
  }

  target <- fev_align_target(rasters, to, direction)
  res <- vapply(rasters, function(r) terra::res(r)[1], numeric(1))
  ratio <- max(res) / min(res)

  if (!isTRUE(quiet) && length(rasters) > 1L && ratio > 1) {
    finest <- nms[which.min(res)]
    coarsest <- nms[which.max(res)]
    fev_warn(c(
      "Aligning layers whose cell sizes differ by a factor of \\
       {.val {signif(ratio, 4)}}.",
      i = "Finest {.val {finest}} at {.val {signif(min(res), 6)}}; coarsest \\
           {.val {coarsest}} at {.val {signif(max(res), 6)}}.",
      i = "Target grid: {.val {signif(terra::res(target)[1], 6)}} \\
           ({direction}).",
      i = if (identical(direction, "finest"))
            "Each coarse cell is copied across about \\
             {.val {signif(ratio^2, 3)}} fine cells. That adds resolution, \\
             not information."
          else
            "Each coarse cell now summarises about {.val {signif(ratio^2, 3)}} \\
             fine cells. That loses the contrast the fuel module produced.",
      i = "The ratio is recorded in the provenance."
    ), class = "fev_scale_gap", .envir = environment())
  }

  methods <- character(length(rasters))
  aligned <- vector("list", length(rasters))
  for (i in seq_along(rasters)) {
    r <- rasters[[i]]
    # A layer already on the target grid is not touched, and the record says
    # "none" rather than naming a method that was never applied -- the whole
    # point of logging this is that a reader can tell what happened to which
    # layer.
    if (isTRUE(terra::compareGeom(r, target, stopOnError = FALSE))) {
      methods[i] <- "none"
      aligned[[i]] <- r
      next
    }
    m <- fev_align_method(r, method, terra::res(r)[1], terra::res(target)[1],
                          nms[i])
    methods[i] <- m
    aligned[[i]] <- if (!fev_crs_equal(r, target)) {
      terra::project(r, target, method = m)
    } else {
      terra::resample(r, target, method = m)
    }
  }
  names(aligned) <- nms

  prov <- Reduce(fev_prov_merge, provs)
  prov <- prov %||% fev_prov_new(crs_work = crs_work)
  prov <- fev_prov_add_step(
    prov, fun = "fev_align",
    params = list(
      direction = direction, target = to %||% direction,
      target_res = signif(terra::res(target)[1], 6),
      target_crs = fev_crs_label(target),
      layers = nms,
      native_res = signif(unname(res), 6),
      methods = stats::setNames(as.list(methods), nms),
      scale_ratio = signif(ratio, 6),
      cells_per_coarse_cell = signif(ratio^2, 6)
    ),
    notes = "the only grid change in the package happens here"
  )

  do.call(fev_stack, c(aligned,
                       list(crs_work = crs_work %||% fev_align_epsg(target),
                            provenance = prov)))
}

#' Which grid everything lands on
#' @noRd
fev_align_target <- function(rasters, to, direction) {
  if (!is.null(to)) {
    if (is.character(to)) {
      if (!to %in% names(rasters)) {
        fev_abort(c(
          "{.arg to} names no layer in {.arg ...}.",
          x = "Got {.val {to}}; available: {.val {names(rasters)}}."
        ), .envir = environment())
      }
      return(rasters[[to]][[1]])
    }
    if (inherits(to, "SpatRaster")) {
      return(to[[1]])
    }
    fev_abort("{.arg to} must be a {.cls SpatRaster} or a layer name.")
  }
  res <- vapply(rasters, function(r) terra::res(r)[1], numeric(1))
  idx <- if (identical(direction, "finest")) which.min(res) else which.max(res)
  rasters[[idx]][[1]]
}

#' Method per layer, with categorical layers overriding the caller
#' @noRd
fev_align_method <- function(r, method, from_res, to_res, nm) {
  if (!is.null(fev_cat_levels(r))) {
    if (!is.null(method) && !identical(method, "near")) {
      fev_warn(c(
        "Layer {.val {nm}} is categorical; using {.val near} rather than \\
         {.val {method}}.",
        i = "Averaging class codes produces numbers that are not classes."
      ), class = "fev_categorical_resampled", .envir = environment())
    }
    return("near")
  }
  if (!is.null(method)) {
    return(method)
  }
  # Downscaling: nearest neighbour, on purpose. Bilinear between the centres
  # of two 25 km cells draws a gradient the reanalysis never resolved, and it
  # looks entirely credible on a map.
  if (to_res < from_res) "near" else "average"
}

#' EPSG code of a grid, for the stack's working CRS
#' @noRd
fev_align_epsg <- function(r) {
  crs <- fev_crs(r)
  epsg <- suppressWarnings(crs$epsg)
  if (!is.null(epsg) && !is.na(epsg)) epsg else fev_crs_label(r)
}
