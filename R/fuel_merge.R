# Hierarchical merge of two categorical fuel sources.
#
# Scope note: this is deliberately an INTRA-REGISTER operation. Primary and
# secondary compete for the same pixel, so the merge needs an arbiter and a
# record of which one won -- that is what the per-pixel source layer is. A
# continuous source such as LiDAR competes for nothing: it carries metrics
# neither categorical source has, on the same grid. Folding that into this
# function would give one name two incompatible behaviours, so it will be a
# separate `fev_fuel_attach()` in phase 8, writing to the continuous register.

#' Merge a primary and an auxiliary fuel source
#'
#' Fills the gaps of a primary fuel source with an auxiliary one, and records
#' for every pixel which dataset its class came from.
#'
#' In France the primary is BD Forêt v2 and the auxiliary is CORINE. BD Forêt
#' wins wherever it maps something; CORINE fills the rest — chiefly the
#' non-forest burnable vegetation it maps and BD Forêt does not (sclerophyllous
#' vegetation, moors, natural grassland) and the unambiguously non-burnable
#' classes (urban, water, bare rock).
#'
#' @section The per-pixel source layer:
#' The result carries a `source` layer alongside `class`. Without it the merged
#' layer is uninterpretable: a 25 m pixel from BD Forêt and a 25 m pixel
#' resampled from a 25 ha CORINE unit look identical and mean entirely
#' different things. Any statistic computed on the merged layer should be
#' reported per source, or at least alongside the source proportions that
#' `summary()` prints.
#'
#' Merging is **idempotent** on that layer: re-merging an already-merged source
#' with the same auxiliary changes no pixel and no attribution, because pixels
#' already attributed keep their original source.
#'
#' @section What gets reprojected:
#' The primary is never touched. When the auxiliary sits on a different CRS or
#' a different grid it is reprojected or resampled onto the primary's grid with
#' nearest neighbour — the only correct method for a class layer, and one that
#' does displace boundaries. Both operations warn and are logged.
#'
#' The result therefore adopts the primary's grid **and its extent**: auxiliary
#' coverage outside the primary's footprint is dropped, not appended. Pass the
#' same `aoi` to both [fev_fuel_source()] calls and the question does not
#' arise. Where BD Forêt covers a smaller area than the study needs — a
#' department it does not map — build the primary on the full AOI, so the
#' unmapped part is `NA` inside the extent and CORINE can fill it.
#'
#' @param primary The primary fuel source, a `fev_fuel_source` with a
#'   categorical register.
#' @param secondary The auxiliary fuel source.
#' @param hierarchy `"primary_first"` (default) or `"secondary_first"`, which
#'   swaps the two roles — including which grid the result lands on.
#'
#' @return A `fev_fuel_source` whose categorical register has two layers,
#'   `class` and `source`, and whose lookup is the union of both tables.
#'
#' @seealso [fev_fuel_source()] to build the inputs.
#'
#' @examples
#' mk <- function(codes, type, millesime) {
#'   r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                    ymin = 0, ymax = 100, crs = "EPSG:2154")
#'   terra::values(r) <- codes
#'   levels(r) <- data.frame(id = sort(unique(stats::na.omit(codes))),
#'                           class = attr(codes, "labels"))
#'   fev_fuel_source(r, type = type, millesime = millesime)
#' }
#' bdf <- structure(c(1, 1, NA, NA, 1, 1, NA, NA, rep(NA, 8)),
#'                  labels = "FF2-57-57")
#' clc <- structure(rep(1, 16), labels = "323")
#' merged <- fev_fuel_merge(mk(bdf, "bdforet_v2", 2014),
#'                          mk(clc, "clc_2018", 2018))
#' merged
#'
#' @export
fev_fuel_merge <- function(primary, secondary,
                           hierarchy = c("primary_first", "secondary_first")) {
  hierarchy <- match.arg(hierarchy)
  fev_check_fuel_source(primary, "primary")
  fev_check_fuel_source(secondary, "secondary")
  fev_fuel_require_register(primary, "categorical", "fev_fuel_merge")
  fev_fuel_require_register(secondary, "categorical", "fev_fuel_merge")

  if (identical(hierarchy, "secondary_first")) {
    tmp <- primary
    primary <- secondary
    secondary <- tmp
  }

  p_cat <- primary$categorical
  s_cat <- secondary$categorical[["class"]]
  p_class <- p_cat[["class"]]

  notes <- character()

  # The auxiliary is the only thing that moves. Reprojection first, then grid
  # alignment: doing it the other way round resamples twice.
  if (!fev_crs_equal(s_cat, p_class)) {
    fev_warn(c(
      "Reprojecting the auxiliary fuel source from \\
       {.val {fev_crs_label(s_cat)}} to {.val {fev_crs_label(p_class)}} with \\
       nearest neighbour.",
      i = "Nearest neighbour is the only correct method on a class layer, and \\
           it does move class boundaries. The primary is not touched."
    ), class = "fev_categorical_reprojected")
    s_cat <- terra::project(s_cat, p_class, method = "near")
    notes <- c(notes, "auxiliary reprojected onto the primary CRS (near)")
  } else if (!isTRUE(terra::compareGeom(p_class, s_cat, stopOnError = FALSE))) {
    s_res <- signif(terra::res(s_cat)[1], 6)
    p_res <- signif(terra::res(p_class)[1], 6)
    fev_warn(c(
      "Resampling the auxiliary fuel source onto the primary grid with \\
       nearest neighbour.",
      i = "Auxiliary cell size {.val {s_res}}, primary {.val {p_res}}.",
      if (s_res > p_res)
        c(i = "Upsampling a coarse class layer does not add detail; it only \\
               makes the mapping unit invisible.")
      else
        c(i = "Same cell size, different extent or origin: the result takes \\
               the primary's grid, so auxiliary cells outside it are dropped."),
      i = "Pass the same {.arg aoi} to both {.fn fev_fuel_source} calls to \\
           avoid this."
    ), class = "fev_categorical_resampled", .envir = environment())
    s_cat <- terra::resample(s_cat, p_class, method = "near")
    notes <- c(notes, "auxiliary resampled onto the primary grid (near)")
  }

  p_lv <- terra::levels(p_class)[[1]]
  s_lv <- terra::levels(s_cat)[[1]]
  fev_check_code_collision(p_lv$class, s_lv$class, primary$lookup, secondary$lookup)

  codes <- unique(c(p_lv$class, s_lv$class))
  p_i <- fev_cat_recode(p_class, p_lv, codes)
  s_i <- fev_cat_recode(s_cat, s_lv, codes)

  filled <- terra::global(is.na(p_i) & !is.na(s_i), fun = "sum", na.rm = TRUE)[[1]]
  n_cell <- terra::ncell(p_i)

  merged <- terra::cover(p_i, s_i)
  levels(merged) <- data.frame(id = seq_along(codes), class = codes)
  names(merged) <- "class"

  # Source attribution. A primary that is itself a merge already carries one,
  # and it is kept: a pixel attributed to BD Forêt in the first merge must not
  # be relabelled by the second. That is what makes the operation idempotent.
  p_label <- fev_fuel_label(primary)
  s_label <- fev_fuel_label(secondary)
  if (identical(p_label, s_label)) {
    p_label <- paste0(p_label, ":primary")
    s_label <- paste0(s_label, ":secondary")
  }

  if ("source" %in% names(p_cat)) {
    p_src <- p_cat[["source"]]
    p_src_lv <- terra::levels(p_src)[[1]]
    src_labels <- unique(c(p_src_lv$class, s_label))
    p_src_i <- fev_cat_recode(p_src, p_src_lv, src_labels)
  } else {
    src_labels <- unique(c(p_label, s_label))
    p_src_i <- terra::ifel(is.na(p_i), NA, match(p_label, src_labels))
  }
  s_src_i <- terra::ifel(is.na(s_i), NA, match(s_label, src_labels))

  src <- terra::cover(p_src_i, s_src_i)
  levels(src) <- data.frame(id = seq_along(src_labels), class = src_labels)
  names(src) <- "source"

  out_cat <- c(merged, src)

  lookup <- fev_merge_lookups(primary$lookup, secondary$lookup)

  components <- unique(c(fev_fuel_components(primary),
                         fev_fuel_components(secondary)))
  millesime <- fev_merge_millesime(primary, secondary)

  prov <- fev_prov_merge(primary$provenance, secondary$provenance)
  prov <- fev_prov_add_step(
    prov,
    fun = "fev_fuel_merge",
    params = list(hierarchy = hierarchy, primary = p_label,
                  secondary = s_label, components = components,
                  n_classes = length(codes),
                  cells_filled_by_secondary = as.integer(filled),
                  pct_filled_by_secondary = round(100 * filled / n_cell, 2)),
    notes = if (length(notes)) notes else NULL
  )

  fev_inform(
    "{.val {s_label}} filled {.val {as.integer(filled)}} cell{?s} \\
     ({round(100 * filled / n_cell, 1)}%) that {.val {p_label}} left unmapped."
  )

  new_fev_fuel_source(
    categorical = out_cat,
    continuous  = primary$continuous %||% secondary$continuous,
    units       = primary$units %||% secondary$units,
    lookup      = lookup,
    type        = paste(components, collapse = "+"),
    millesime   = millesime,
    provenance  = prov
  )
}

#' Remap a categorical layer onto a shared code vocabulary
#'
#' Levels are stripped before reclassifying: `terra::classify()` on a
#' categorical layer reclassifies labels, not ids, which is not what is wanted
#' here.
#'
#' @noRd
fev_cat_recode <- function(r, lv, codes) {
  plain <- r
  levels(plain) <- NULL
  terra::classify(plain, rcl = cbind(lv$id, match(lv$class, codes)),
                  others = NA)
}

#' Which dataset labels this source's pixels
#' @noRd
fev_fuel_label <- function(x) {
  x$type
}

#' @noRd
fev_fuel_components <- function(x) {
  if (grepl("+", x$type, fixed = TRUE)) {
    strsplit(x$type, "+", fixed = TRUE)[[1]]
  } else {
    x$type
  }
}

#' Refuse to merge two vocabularies that use one code for two things
#'
#' Both nomenclatures shipped here are disjoint by construction — TFV codes are
#' alphanumeric, CORINE codes are three digits — but a custom vocabulary need
#' not be. A silent collision would attribute pixels to the wrong fuel type
#' with no visible symptom.
#'
#' @noRd
fev_check_code_collision <- function(p_codes, s_codes, p_lookup, s_lookup) {
  shared <- intersect(p_codes, s_codes)
  if (!length(shared) || is.null(p_lookup) || is.null(s_lookup)) {
    return(invisible(TRUE))
  }
  pm <- p_lookup[match(shared, p_lookup$code), c("fuel_type", "burnable")]
  sm <- s_lookup[match(shared, s_lookup$code), c("fuel_type", "burnable")]
  disagree <- shared[
    !is.na(pm$fuel_type) & !is.na(sm$fuel_type) &
      (pm$fuel_type != sm$fuel_type | pm$burnable != sm$burnable)
  ]
  if (length(disagree)) {
    fev_abort(c(
      "The two sources use the same code{?s} {.val {disagree}} for different \\
       fuel.",
      i = "A merged layer would attribute those pixels to whichever table was \\
           consulted first, with no visible symptom.",
      i = "Rename the codes in one vocabulary, or reconcile the lookups."
    ), class = "fev_code_collision")
  }
  invisible(TRUE)
}

#' Union of two lookups, primary's row winning on a shared code
#' @noRd
fev_merge_lookups <- function(p, s) {
  if (is.null(p)) return(s)
  if (is.null(s)) return(p)
  out <- rbind(p, s)
  out[!duplicated(out$code), , drop = FALSE]
}

#' Vintages of a merged source, one per component
#'
#' Kept as a named vector rather than collapsed: the components have different
#' vintages by construction (CORINE has a common European date, BD Forêt does
#' not), and the temporal-bias check needs to know which pixel follows which.
#'
#' @noRd
fev_merge_millesime <- function(primary, secondary) {
  as_named <- function(x) {
    m <- x$millesime
    if (is.null(m)) m <- NA
    if (is.null(names(m))) {
      stats::setNames(rep(list(m), length(fev_fuel_components(x))),
                      fev_fuel_components(x))
    } else {
      as.list(m)
    }
  }
  out <- c(as_named(primary), as_named(secondary))
  out[!duplicated(names(out))]
}
