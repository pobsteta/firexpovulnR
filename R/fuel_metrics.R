# Layers derived from a fuel source: burnable mask, fuel type, availability.
#
# All three consume the CATEGORICAL register and say so, both in their
# documentation and at runtime through fev_fuel_require_register(). When the
# continuous register gains a producer in phase 8, availability grows a second
# path that reads measured load instead of a per-class weight; nothing here
# needs to change for that.
#
# They return a fev_fuel_layer rather than a bare SpatRaster so the provenance
# survives. A SpatRaster is S4 and drops user attributes at the first
# arithmetic operation, which is exactly what a caller does to one of these.

#' @noRd
new_fev_fuel_layer <- function(data, role, provenance = NULL, units = NA_character_) {
  structure(
    list(data = data, role = role, units = units, provenance = provenance),
    class = "fev_fuel_layer"
  )
}

#' Burnable / non-burnable mask
#'
#' Reduces a fuel source to the binary layer the exposure metrics operate on:
#' 1 where the class is fuel that can carry fire, 0 where it cannot, `NA` where
#' the source maps nothing or the lookup has no row for the class.
#'
#' @section Register consumed:
#' Categorical.
#'
#' @section Unmatched classes become NA, loudly:
#' A class present in the raster but absent from the lookup is not silently
#' non-burnable. It becomes `NA` and the function reports how many classes and
#' what share of mapped cells that is. Treating an unknown class as
#' non-burnable would understate exposure exactly where the data is weakest.
#'
#' @section What "burnable" means here, and what it does not:
#' It is a presence mask, not a flammability ranking: beech and Aleppo pine are
#' both 1. Grading between them is [fev_fuel_availability()]. And the shipped
#' lookups make debatable calls on agricultural classes — see
#' [fev_fuel_lookup()] before using this on a crop-forest interface.
#'
#' @param x A `fev_fuel_source`.
#' @param lookup Correspondence table. Defaults to the one carried by `x`.
#'
#' @return A `fev_fuel_layer` holding a 0/1 `SpatRaster` named `burnable`.
#'
#' @seealso [fev_fuel_lookup()] for the table that decides this,
#'   [fev_fuel_availability()] for the graded version.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- rep(1:2, 8)
#' levels(r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
#' fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
#' mask <- fev_fuel_binary(fuel)
#' terra::global(fev_data(mask), "mean", na.rm = TRUE)
#'
#' @export
fev_fuel_binary <- function(x, lookup = NULL) {
  fev_fuel_require_register(x, "categorical", "fev_fuel_binary")
  lookup <- fev_resolve_lookup(x, lookup)

  mapped <- fev_fuel_map(x, lookup, "burnable", "fev_fuel_binary")
  r <- mapped$raster
  names(r) <- "burnable"

  prov <- fev_prov_add_step(
    x$provenance,
    fun = "fev_fuel_binary",
    params = list(lookup_rows = nrow(lookup),
                  n_classes = mapped$n_classes,
                  unmatched_classes = mapped$unmatched,
                  pct_cells_unmatched = mapped$pct_unmatched,
                  pct_burnable = fev_pct_true(r))
  )
  new_fev_fuel_layer(r, role = "burnable", provenance = prov, units = "0/1")
}

#' Structural fuel type
#'
#' Maps class codes onto the package's shared fuel-type vocabulary, so that a
#' layer merged from two nomenclatures can be read as one thing.
#'
#' @section Register consumed:
#' Categorical.
#'
#' @section This is a relabelling, not a fuel model:
#' The types describe stand structure — closed conifer, open broadleaf,
#' shrubland — because structure is what BD Forêt and CORINE record. They are
#' not Anderson, Scott & Burgan or Prometheus fuel models, and no
#' correspondence to those is shipped: deriving one needs understorey and load
#' information neither database contains. That is the `medfate` extension
#' point, and the reason the continuous register exists.
#'
#' @param x A `fev_fuel_source`.
#' @param lookup Correspondence table. Defaults to the one carried by `x`.
#'
#' @return A `fev_fuel_layer` holding a categorical `SpatRaster` named
#'   `fuel_type`.
#'
#' @seealso [fev_fuel_types()] for the vocabulary.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- rep(1:2, 8)
#' levels(r) <- data.frame(id = 1:2, class = c("FF1G06-06", "LA4"))
#' fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
#' ft <- fev_fuel_type(fuel)
#' terra::levels(fev_data(ft))[[1]]
#'
#' @export
fev_fuel_type <- function(x, lookup = NULL) {
  fev_fuel_require_register(x, "categorical", "fev_fuel_type")
  lookup <- fev_resolve_lookup(x, lookup)

  cat_layer <- x$categorical[["class"]]
  lv <- terra::levels(cat_layer)[[1]]
  m <- match(lv$class, lookup$code)
  types <- lookup$fuel_type[m]

  present <- sort(unique(types[!is.na(types)]))
  if (!length(present)) {
    fev_abort(c(
      "No class in the layer has a fuel type in the lookup.",
      i = "Lookup covers {.val {utils::head(lookup$code, 5)}}...; the layer \\
           carries {.val {utils::head(lv$class, 5)}}...",
      i = "Usually the wrong lookup for the source, or a custom vocabulary \\
           with no table."
    ), class = "fev_no_match")
  }

  unmatched <- lv$class[is.na(types)]
  fev_report_unmatched(cat_layer, unmatched, "fev_fuel_type")

  plain <- cat_layer
  levels(plain) <- NULL
  r <- terra::classify(plain, rcl = cbind(lv$id, match(types, present)),
                       others = NA)
  levels(r) <- data.frame(id = seq_along(present), class = present)
  names(r) <- "fuel_type"

  prov <- fev_prov_add_step(
    x$provenance,
    fun = "fev_fuel_type",
    params = list(lookup_rows = nrow(lookup), n_types = length(present),
                  types = present, unmatched_classes = unmatched)
  )
  new_fev_fuel_layer(r, role = "fuel_type", provenance = prov)
}

#' Weighted fuel availability
#'
#' Grades the burnable mask: instead of 1 for every fuel, each pixel takes a
#' weight in `[0, 1]` for its fuel type, so that Mediterranean shrubland and a
#' beech stand are not treated as the same hazard.
#'
#' @section Register consumed:
#' Categorical. The continuous register is the phase 8 path: with LiDAR-derived
#' load and bulk density per stratum, availability can be measured rather than
#' assigned per class, and the per-class weights below become a fallback for
#' areas with no LiDAR coverage.
#'
#' @section The weights are conventional, not sourced:
#' Read [fev_fuel_weights()] before using the defaults. No published weighting
#' of BD Forêt or CORINE classes was verified during phase 2, so the numbers
#' are the package's own convention. They are written into the provenance
#' record with the result, whichever ones you use.
#'
#' @param x A `fev_fuel_source`.
#' @param weights Named numeric vector, one weight per fuel type. Defaults to
#'   [fev_fuel_weights()], which warns that it is conventional.
#' @param lookup Correspondence table. Defaults to the one carried by `x`.
#'
#' @return A `fev_fuel_layer` holding a `SpatRaster` named `availability` with
#'   values in `[0, 1]`.
#'
#' @seealso [fev_fuel_weights()], [fev_fuel_binary()].
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- rep(1:2, 8)
#' levels(r) <- data.frame(id = 1:2, class = c("FF1G09-09", "LA4"))
#' fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
#' av <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))
#' terra::global(fev_data(av), "max", na.rm = TRUE)
#'
#' @export
fev_fuel_availability <- function(x, weights = fev_fuel_weights(), lookup = NULL) {
  fev_fuel_require_register(x, "categorical", "fev_fuel_availability")
  lookup <- fev_resolve_lookup(x, lookup)

  unknown <- setdiff(unique(lookup$fuel_type), names(weights))
  if (length(unknown)) {
    fev_abort(c(
      "No weight for {length(unknown)} fuel type{?s}: {.val {unknown}}.",
      i = "The lookup uses {length(unknown)} type{?s} {.arg weights} does not \\
           cover, so those pixels would silently become {.val NA}.",
      i = "Start from {.fn fev_fuel_weights} and override what you need."
    ), class = "fev_missing_weight")
  }

  cat_layer <- x$categorical[["class"]]
  lv <- terra::levels(cat_layer)[[1]]
  m <- match(lv$class, lookup$code)
  vals <- unname(weights[lookup$fuel_type[m]])

  unmatched <- lv$class[is.na(m)]
  fev_report_unmatched(cat_layer, unmatched, "fev_fuel_availability")

  plain <- cat_layer
  levels(plain) <- NULL
  r <- terra::classify(plain, rcl = cbind(lv$id, vals), others = NA)
  names(r) <- "availability"

  prov <- fev_prov_add_step(
    x$provenance,
    fun = "fev_fuel_availability",
    params = list(weights = as.list(weights), lookup_rows = nrow(lookup),
                  unmatched_classes = unmatched,
                  weights_sourced = FALSE)
  )
  new_fev_fuel_layer(r, role = "availability", provenance = prov,
                     units = "dimensionless, 0-1")
}

# Shared machinery ------------------------------------------------------------

#' The lookup to use, and a clear refusal when there is none
#' @noRd
fev_resolve_lookup <- function(x, lookup) {
  lookup <- lookup %||% x$lookup
  if (is.null(lookup)) {
    fev_abort(c(
      "This fuel source carries no correspondence table.",
      i = "Sources of type {.val custom} have none by default.",
      i = "Pass {.arg lookup}, e.g. {.code fev_fuel_lookup(\"bdforet_v2\")} or \\
           your own table via {.code fev_fuel_lookup(file = ...)}."
    ), class = "fev_no_lookup")
  }
  fev_lookup_validate(lookup, origin = "<carried by the fuel source>")
}

#' Map class codes through one column of the lookup
#' @noRd
fev_fuel_map <- function(x, lookup, column, fn) {
  cat_layer <- x$categorical[["class"]]
  lv <- terra::levels(cat_layer)[[1]]
  m <- match(lv$class, lookup$code)
  vals <- lookup[[column]][m]
  if (is.logical(vals)) {
    vals <- as.numeric(vals)
  }

  unmatched <- lv$class[is.na(m)]
  pct <- fev_report_unmatched(cat_layer, unmatched, fn)

  plain <- cat_layer
  levels(plain) <- NULL
  r <- terra::classify(plain, rcl = cbind(lv$id, vals), others = NA)

  list(raster = r, n_classes = nrow(lv), unmatched = unmatched,
       pct_unmatched = pct)
}

#' Say, with numbers, how much of the layer the lookup does not cover
#' @noRd
fev_report_unmatched <- function(cat_layer, unmatched, fn) {
  if (!length(unmatched)) {
    return(0)
  }
  fr <- terra::freq(cat_layer)
  total <- sum(fr$count)
  lost <- sum(fr$count[as.character(fr$value) %in% unmatched])
  pct <- if (total > 0) round(100 * lost / total, 2) else 0
  fev_warn(c(
    "{length(unmatched)} class{?/es} {?is/are} absent from the lookup and \\
     become {.val NA} in {.fn {fn}}.",
    x = "{.val {unmatched}}",
    i = "That is {.val {pct}}% of mapped cells. They are not treated as \\
         non-burnable: an unknown class would then understate exposure exactly \\
         where the data is weakest.",
    i = "Add {length(unmatched)} row{?s} to your lookup, or pass a table that \\
         covers {?it/them}."
  ), class = "fev_unmatched_class", .envir = environment())
  pct
}

#' Share of a 0/1 layer that is 1, for the record
#' @noRd
fev_pct_true <- function(r) {
  n_ok <- terra::global(r, fun = "notNA")[[1]]
  if (!n_ok) {
    return(NA_real_)
  }
  round(100 * terra::global(r, fun = "sum", na.rm = TRUE)[[1]] / n_ok, 2)
}

#' @export
print.fev_fuel_layer <- function(x, ...) {
  r <- x$data
  cli::cli_h1("fev_fuel_layer: {x$role}")
  cli::cli_li("{terra::nrow(r)} x {terra::ncol(r)} cells at \\
               {.val {signif(terra::res(r)[1], 6)}}, {fev_crs_label(r)}")
  if (!is.na(x$units)) {
    cli::cli_li("Units: {.val {x$units}}")
  }
  lv <- fev_cat_levels(r)
  if (!is.null(lv)) {
    cli::cli_li("Classes: {.val {lv[[2]]}}")
  } else {
    mm <- terra::global(r, fun = "range", na.rm = TRUE)
    cli::cli_li("Range: {.val {signif(c(mm[[1]][1], mm[[2]][1]), 4)}}")
  }
  n_ok <- terra::global(r, fun = "notNA")[[1]]
  cli::cli_li("Mapped: {.val {round(100 * n_ok / terra::ncell(r), 1)}}% of cells")
  invisible(x)
}

#' @export
plot.fev_fuel_layer <- function(x, ...) {
  terra::plot(x$data, main = x$role, ...)
  invisible(x)
}
