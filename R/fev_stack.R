# The fev_stack class.
#
# Deliberately NOT a terra::SpatRaster with many layers. The chain combines
# layers whose native grids differ by three orders of magnitude -- ERA5 fire
# danger at ~9-31 km against fuel-derived exposure at 20-100 m. A SpatRaster
# forces a single grid, so putting danger and exposure in one would mean
# resampling at construction time, silently, which is precisely what the brief
# forbids. A named list of SpatRaster lets layers keep their native grid until
# fev_align() is called explicitly.

#' Create a `fev_stack`
#'
#' A `fev_stack` bundles the raster layers of an analysis with the provenance
#' record that makes it replayable: sources and their vintages, the working
#' CRS and resolution, and an ordered log of every operation with the
#' parameters it used.
#'
#' Layers are **not** required to share a grid. Fire danger from ERA5 is
#' kilometric while fuel-derived exposure is decametric, and forcing them onto
#' one grid at construction time would hide a resampling step that has to be
#' explicit. Use [fev_align()] when layers must be combined.
#'
#' All layers must, however, share a CRS. Mixing CRS in one object makes every
#' downstream extent comparison wrong in a way that is hard to see.
#'
#' @param ... Named `SpatRaster` objects, one per layer. Names become layer
#'   names and must be unique and non-empty.
#' @param crs_work Integer EPSG code of the working CRS. Defaults to `2154`
#'   (RGF93 / Lambert-93), the CRS of BD Forêt v2, the primary fuel source.
#'   Use `3035` (ETRS89-LAEA) for CORINE-driven or multi-country studies.
#' @param provenance An existing provenance record to carry forward. When
#'   `NULL` a fresh one is created.
#'
#' @return An object of class `fev_stack`: a named list of `SpatRaster` with a
#'   `provenance` attribute.
#'
#' @seealso [fev_provenance()] to export the record, [fev_check_crs()] to
#'   validate inputs before building one.
#'
#' @examples
#' r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 250,
#'                  ymin = 0, ymax = 250, crs = "EPSG:2154")
#' terra::values(r) <- runif(100)
#' s <- fev_stack(exposure = r, crs_work = 2154)
#' s
#'
#' @export
fev_stack <- function(..., crs_work = 2154, provenance = NULL) {
  layers <- list(...)

  if (!length(layers)) {
    fev_abort(c(
      "A {.cls fev_stack} needs at least one layer.",
      i = "Pass named {.cls SpatRaster} objects, e.g. \\
           {.code fev_stack(danger = r1, exposure = r2)}."
    ))
  }

  nms <- names(layers)
  if (is.null(nms) || any(!nzchar(nms))) {
    fev_abort(c(
      "Every layer must be named.",
      x = "Layer{?s} {.val {which(is.null(nms) | !nzchar(nms))}} \\
           {?has/have} no name.",
      i = "Names are how layers are referred to throughout the chain."
    ))
  }
  if (anyDuplicated(nms)) {
    dup <- unique(nms[duplicated(nms)])
    fev_abort("Layer names must be unique. Duplicated: {.val {dup}}.")
  }

  not_rast <- !vapply(layers, inherits, logical(1), what = "SpatRaster")
  if (any(not_rast)) {
    bad <- nms[not_rast]
    cls <- vapply(layers[not_rast], function(x) class(x)[1], character(1))
    fev_abort(c(
      "Every layer must be a {.cls SpatRaster}.",
      x = "{.val {bad}} {?is/are} {.cls {cls}}.",
      i = "Convert vectors with {.fn terra::rasterize} first, or use \\
           {.fn fev_fuel_source} which does it for you."
    ))
  }

  # One CRS for the whole stack. Checked here rather than at use time because
  # a mismatch surfaces later as an empty intersection, which reads like an
  # AOI problem rather than a CRS problem.
  crs_labels <- vapply(layers, fev_crs_label, character(1))
  if (length(unique(crs_labels)) > 1L) {
    fev_abort(c(
      "All layers of a {.cls fev_stack} must share one CRS.",
      x = "Found: {.val {unique(crs_labels)}}.",
      i = "Reproject the auxiliary layers before stacking -- never the \\
           primary fuel source. See {.fn fev_check_crs}."
    ))
  }
  if (identical(crs_labels[[1]], "unknown")) {
    fev_abort(c(
      "The layers carry no CRS.",
      i = "Set one with {.code terra::crs(x) <- \"EPSG:2154\"} if you know \\
           what it is. Do not guess."
    ))
  }

  empty <- vapply(layers, fev_all_na, logical(1))
  if (any(empty)) {
    fev_warn(c(
      "Layer{?s} {.val {nms[empty]}} {?is/are} entirely {.val NA}.",
      i = "Usually a disjoint AOI, or a fetch that matched nothing."
    ))
  }

  prov <- provenance %||% fev_prov_new(crs_work = crs_work)
  prov$crs_work <- crs_work
  prov <- fev_prov_add_step(
    prov,
    fun = "fev_stack",
    params = list(layers = nms, crs_work = crs_work,
                  crs_layers = unname(crs_labels[[1]]))
  )

  structure(layers, class = "fev_stack", provenance = prov)
}

#' Coerce to a `fev_stack`
#'
#' @param x An object to coerce.
#' @param ... Passed to [fev_stack()].
#' @return A `fev_stack`.
#' @export
as_fev_stack <- function(x, ...) {
  if (inherits(x, "fev_stack")) {
    return(x)
  }
  if (inherits(x, "SpatRaster")) {
    nms <- names(x)
    layers <- stats::setNames(
      lapply(seq_len(terra::nlyr(x)), function(i) x[[i]]),
      if (all(nzchar(nms))) nms else paste0("layer", seq_len(terra::nlyr(x)))
    )
    return(do.call(fev_stack, c(layers, list(...))))
  }
  fev_abort("Cannot coerce {.cls {class(x)[1]}} to a {.cls fev_stack}.")
}

#' @export
print.fev_stack <- function(x, ...) {
  prov <- attr(x, "provenance")
  cli::cli_h1("fev_stack")
  cli::cli_text("{length(x)} layer{?s}, working CRS {.val {prov$crs_work}}")

  for (nm in names(x)) {
    r <- x[[nm]]
    res <- signif(terra::res(r), 6)
    cli::cli_li("{.strong {nm}}: {terra::nrow(r)} x {terra::ncol(r)} cells, \\
                 res {.val {paste(res, collapse = ' x ')}}")
  }

  # A stack whose layers sit on different grids is legal and expected, but the
  # reader must see it: it is the scale gap the whole chain has to manage.
  resolutions <- vapply(x, function(r) terra::res(r)[1], numeric(1))
  if (length(unique(signif(resolutions, 6))) > 1L) {
    ratio <- max(resolutions) / min(resolutions)
    cli::cli_alert_warning(
      "Layers sit on different grids (coarsest/finest = {.val {signif(ratio, 4)}}). \\
       Combine them only through {.fn fev_align}."
    )
  }

  cli::cli_text("")
  cli::cli_text("{.field Provenance}: {length(prov$sources)} source{?s}, \\
                 {length(prov$steps)} step{?s}. See {.fn fev_provenance}.")
  invisible(x)
}

#' @export
summary.fev_stack <- function(object, ...) {
  prov <- attr(object, "provenance")
  rows <- lapply(names(object), function(nm) {
    r <- object[[nm]]
    mm <- terra::global(r, fun = "range", na.rm = TRUE)
    n_ok <- terra::global(r, fun = "notNA")[[1]]
    data.frame(
      layer   = nm,
      nrow    = terra::nrow(r),
      ncol    = terra::ncol(r),
      res     = terra::res(r)[1],
      min     = as.numeric(mm[[1]][1]),
      max     = as.numeric(mm[[2]][1]),
      pct_na  = round(100 * (1 - n_ok / terra::ncell(r)), 2),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  structure(
    list(layers = out, crs_work = prov$crs_work,
         n_sources = length(prov$sources), n_steps = length(prov$steps)),
    class = "summary.fev_stack"
  )
}

#' @export
print.summary.fev_stack <- function(x, ...) {
  cli::cli_h1("fev_stack summary")
  cli::cli_text("Working CRS {.val {x$crs_work}} - \\
                 {x$n_sources} source{?s}, {x$n_steps} step{?s}")
  cli::cli_text("")
  print(x$layers, row.names = FALSE)
  invisible(x)
}

#' Plot the layers of a `fev_stack`
#'
#' @param x A `fev_stack`.
#' @param layer Optional layer name or index. When `NULL`, all layers are
#'   drawn on a common panel layout.
#' @param ... Passed to [terra::plot()].
#' @return `x`, invisibly.
#' @export
plot.fev_stack <- function(x, layer = NULL, ...) {
  if (!is.null(layer)) {
    if (is.character(layer) && !layer %in% names(x)) {
      fev_abort(c("No layer named {.val {layer}}.",
                  i = "Available: {.val {names(x)}}."))
    }
    terra::plot(x[[layer]], main = if (is.character(layer)) layer else names(x)[layer], ...)
    return(invisible(x))
  }
  n <- length(x)
  op <- graphics::par(mfrow = grDevices::n2mfrow(n))
  on.exit(graphics::par(op), add = TRUE)
  for (nm in names(x)) {
    terra::plot(x[[nm]], main = nm, ...)
  }
  invisible(x)
}

#' @export
`[.fev_stack` <- function(x, i, ...) {
  out <- NextMethod()
  structure(out, class = "fev_stack", provenance = attr(x, "provenance"))
}

#' Add or replace a layer, keeping provenance
#'
#' @param x A `fev_stack`.
#' @param name Layer name.
#' @param value A `SpatRaster`.
#' @param step Name of the function performing the addition, for the log.
#' @param params Parameters to record alongside.
#' @return The stack, with the layer added and a step appended.
#' @noRd
fev_stack_set <- function(x, name, value, step = NULL, params = list()) {
  if (!inherits(value, "SpatRaster")) {
    fev_abort("Layer {.val {name}} must be a {.cls SpatRaster}.")
  }
  prov <- attr(x, "provenance")
  layers <- unclass(x)
  layers[[name]] <- value
  if (!is.null(step)) {
    prov <- fev_prov_add_step(prov, fun = step, params = params)
  }
  structure(layers, class = "fev_stack", provenance = prov)
}

#' Save and reload a `fev_stack`
#'
#' `terra` rasters hold a C++ pointer, so a plain [saveRDS()] of a `fev_stack`
#' writes an object whose layers are unusable when reloaded. These two
#' functions wrap the layers with [terra::wrap()] first, so the object -- and
#' the provenance record travelling with it -- survives a round trip to disk.
#'
#' Large in-memory rasters are materialised by wrapping. For heavy layers,
#' write the rasters to GeoTIFF separately and keep only the provenance here.
#'
#' @param x A `fev_stack`.
#' @param file Path to an `.rds` file.
#' @return `fev_stack_save()` returns `file` invisibly;
#'   `fev_stack_read()` returns a `fev_stack`.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- seq_len(16)
#' s <- fev_stack(fuel = r, crs_work = 2154)
#' f <- tempfile(fileext = ".rds")
#' fev_stack_save(s, f)
#' s2 <- fev_stack_read(f)
#' names(s2)
#'
#' @export
fev_stack_save <- function(x, file) {
  if (!inherits(x, "fev_stack")) {
    fev_abort("{.arg x} must be a {.cls fev_stack}.")
  }
  payload <- list(
    layers     = lapply(unclass(x), terra::wrap),
    provenance = attr(x, "provenance")
  )
  saveRDS(payload, file)
  invisible(file)
}

#' @rdname fev_stack_save
#' @export
fev_stack_read <- function(file) {
  payload <- readRDS(file)
  if (!all(c("layers", "provenance") %in% names(payload))) {
    fev_abort(c(
      "{.file {file}} is not a saved {.cls fev_stack}.",
      i = "Write it with {.fn fev_stack_save}, not {.fn saveRDS}."
    ))
  }
  structure(
    lapply(payload$layers, terra::unwrap),
    class = "fev_stack",
    provenance = payload$provenance
  )
}
