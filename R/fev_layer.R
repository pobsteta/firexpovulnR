# A derived raster travelling with its provenance.
#
# Every fev_* function that produces a raster from another one returns one of
# these rather than a bare SpatRaster. The reason is mechanical: SpatRaster is
# S4 and drops user attributes at the first arithmetic operation, so a record
# attached as an attribute would vanish the first time a caller multiplied the
# layer by anything -- silently, and exactly when it started to matter.
#
# Subclasses (fev_fuel_layer, fev_danger_layer) exist so that a function can
# say what it accepts; the print, plot and fev_data() behaviour is shared.

#' @param data A `SpatRaster`.
#' @param role What the layer is, e.g. `"burnable"` or `"fwi_percentile"`.
#' @param provenance The record carried forward from the input.
#' @param units Free-text units, for the print method and the record.
#' @param class Optional subclass, prepended.
#' @noRd
new_fev_layer <- function(data, role, provenance = NULL, units = NA_character_,
                          class = character()) {
  structure(
    list(data = data, role = role, units = units, provenance = provenance),
    class = c(class, "fev_layer")
  )
}

#' @export
print.fev_layer <- function(x, ...) {
  r <- x$data
  cli::cli_h1("{class(x)[1]}: {x$role}")
  cli::cli_li("{terra::nrow(r)} x {terra::ncol(r)} cells at \\
               {.val {signif(terra::res(r)[1], 6)}}, {fev_crs_label(r)}")
  if (terra::nlyr(r) > 1L) {
    cli::cli_li("{terra::nlyr(r)} layers")
  }
  if (!is.na(x$units)) {
    cli::cli_li("Units: {.val {x$units}}")
  }
  lv <- fev_cat_levels(r)
  if (!is.null(lv)) {
    cli::cli_li("Classes: {.val {lv[[2]]}}")
  } else {
    mm <- terra::global(r[[1]], fun = "range", na.rm = TRUE)
    cli::cli_li("Range: {.val {signif(c(mm[[1]][1], mm[[2]][1]), 4)}}")
  }
  n_ok <- terra::global(r[[1]], fun = "notNA")[[1]]
  cli::cli_li("Mapped: {.val {round(100 * n_ok / terra::ncell(r), 1)}}% of cells")
  invisible(x)
}

#' @export
plot.fev_layer <- function(x, ...) {
  terra::plot(x$data, main = x$role, ...)
  invisible(x)
}
