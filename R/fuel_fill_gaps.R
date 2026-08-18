# Repairing rasterisation gaps, and why it is a repair rather than a guess.
#
# Rasterising a polygon coverage by cell-centre containment leaves holes: where
# two adjacent polygons share a boundary, floating-point geometry can put a cell
# centre in neither. On the shipped extracts that is 42 cells out of 469 989 at
# Couchey and 18 out of 677 846 in the Maures -- 0.009% and 0.003%.
#
# Left alone they are not harmless. fev_exposure() runs a focal window that
# propagates NA, so one isolated empty cell empties a disc of the window radius
# around it: measured amplification 626x, and 17.5% of the Couchey risk map.
#
# What licenses filling them is the minimum mapping unit. CORINE cannot represent
# anything under 25 ha, so a 0.25 ha hole inside CORINE's extent is not a land
# cover unit that happens to be unknown -- it is an artefact of the raster grid.
# Above the MMU the hole may be real and is left alone. See .FEV_FUEL_MMU.

#' Repair rasterisation gaps in a categorical fuel layer
#'
#' Fills small holes left by rasterising a polygon coverage, and **only** those:
#' a hole larger than the source's minimum mapping unit is left empty, because
#' it may be a genuine gap in the data rather than an artefact of the grid.
#'
#' @section Why this is a repair and not an interpolation:
#' A source cannot map an object smaller than its own minimum mapping unit.
#' CORINE Land Cover's is 25 ha; the smallest CORINE polygon in either shipped
#' extract measures 24.9 ha, so the specification is observed and not merely
#' claimed. A hole of 0.25 ha inside CORINE's extent therefore cannot be a real
#' land-cover unit — it is a sub-cell gap between polygons that share a boundary,
#' and the ground there is certainly one of the neighbours.
#'
#' That is why the threshold is a property of the data rather than a parameter to
#' tune, and why crossing it changes the answer from "repair" to "invent". Above
#' the minimum mapping unit this function refuses, reports, and moves on.
#'
#' @section Why it matters more than its size suggests:
#' 42 empty cells out of 469 989 sound negligible. They are not: [fev_exposure()]
#' propagates `NA` through its focal window, so each isolated empty cell empties a
#' disc of the window radius around it. Measured on the Couchey extract, 42 cells
#' emptied 26 303 — an amplification of 626 — and blanked 17.5% of the risk map
#' once the legitimate edge frame is counted.
#'
#' @section Sources that map only part of their extent:
#' BD Forêt v2 maps vegetation formations only, so its silence means "not forest",
#' which is information. Its minimum mapping unit is therefore never used to
#' justify a fill. Only a source flagged as complete coverage in `.FEV_FUEL_MMU`
#' can license one; if none of the merged components is, this function fills
#' nothing and says why.
#'
#' @param fuel An [fev_fuel_source], typically the result of [fev_fuel_merge()].
#' @param max_gap Largest hole to fill, in hectares. `NULL` (default) takes the
#'   minimum mapping unit of the complete-coverage component, which is the only
#'   value that makes this a repair. Passing a larger number is allowed and
#'   recorded, but it is then an assumption about unmapped ground.
#' @param quiet Suppress the report.
#'
#' @return The `fev_fuel_source`, with holes below `max_gap` filled in the
#'   categorical register and the operation recorded in the provenance.
#'
#' @seealso [fev_fuel_merge()], [fev_exposure()].
#'
#' @examples
#' r <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 500,
#'                  ymin = 0, ymax = 500, crs = "EPSG:2154")
#' terra::values(r) <- rep(1, terra::ncell(r))
#' levels(r) <- data.frame(id = 1, code_18 = "311")
#' r[5, 5] <- NA          # a one-cell rasterisation sliver
#' f <- fev_fuel_source(r, type = "clc_2018", millesime = 2018)
#' sum(is.na(terra::values(fev_fuel_categorical(f))))
#'
#' # 0.0625 ha is far below CORINE's 25 ha minimum mapping unit, so it cannot
#' # be a real land-cover unit and is repaired.
#' g <- fev_fuel_fill_gaps(f)
#' sum(is.na(terra::values(fev_fuel_categorical(g))))
#'
#' @export
fev_fuel_fill_gaps <- function(fuel, max_gap = NULL, quiet = FALSE) {
  if (!inherits(fuel, "fev_fuel_source")) {
    fev_abort(c(
      "{.arg fuel} must be an {.cls fev_fuel_source}.",
      x = "Got {.cls {class(fuel)[1]}}."
    ), .envir = environment())
  }
  cat_r <- fuel$categorical
  if (is.null(cat_r)) {
    fev_abort(c(
      "This source has no categorical register to repair.",
      i = "Gaps are a rasterisation artefact of the categorical path; the \\
           continuous register is derived from point clouds and has none."
    ), class = "fev_no_categorical")
  }

  components <- fev_fuel_components(fuel)
  mmu <- fev_fuel_mmu(components)
  # Whether the threshold was given or derived decides how the provenance reads:
  # a derived one is a property of the source, an explicit one is an assumption.
  explicit <- !is.null(max_gap)

  n_na <- as.numeric(terra::global(is.na(cat_r), "sum", na.rm = TRUE)[1, 1])
  if (n_na == 0) {
    if (!quiet) {
      fev_inform("No empty cell to repair.")
    }
    return(fuel)
  }

  if (is.null(max_gap)) {
    if (is.na(mmu$mmu_ha)) {
      # Not a refusal: nothing is filled, and the reason is that no component
      # claims to map its whole extent, so silence here may be information.
      fev_warn(c(
        "Nothing filled: no component maps its full extent.",
        i = "Components: {.val {components}}.",
        i = "In a partial-coverage source a gap may mean nothing of interest \\
             here rather than unknown, so its minimum mapping unit cannot \\
             license a repair.",
        i = "Pass {.arg max_gap} explicitly to fill anyway, as a stated \\
             assumption."
      ), class = "fev_no_complete_coverage", .envir = environment())
      return(fuel)
    }
    max_gap <- mmu$mmu_ha
  }
  if (!is.numeric(max_gap) || length(max_gap) != 1L || max_gap <= 0) {
    fev_abort("{.arg max_gap} must be a single positive number, in hectares.")
  }

  cell_ha <- prod(terra::res(cat_r)) / 1e4
  max_cells <- max_gap / cell_ha

  # A merged register carries two layers: `class`, the fuel code, and `source`,
  # which dataset supplied each pixel. Gaps are detected on the class layer;
  # doing it on the whole stack counted every patch twice, because both layers
  # share the same holes.
  class_idx <- match("class", names(cat_r))
  if (is.na(class_idx)) {
    class_idx <- 1L
  }
  class_r <- cat_r[[class_idx]]

  # patches() on the NA mask: contiguity is what distinguishes a sliver between
  # two polygons from a genuine unmapped region, and it has to be measured rather
  # than assumed from the total count.
  gaps <- terra::patches(terra::ifel(is.na(class_r), 1, NA), directions = 8,
                         zeroAsNA = TRUE)
  tally <- as.data.frame(terra::freq(gaps))
  small <- tally$value[tally$count <= max_cells]
  big <- tally[tally$count > max_cells, ]
  n_gaps <- nrow(tally)

  if (!length(small)) {
    if (!quiet) {
      fev_warn(c(
        "Nothing filled: every gap is larger than {max_gap} ha.",
        i = "{nrow(big)} gap{?s} left empty, the largest \\
             {round(max(big$count) * cell_ha, 2)} ha.",
        i = "Above the minimum mapping unit a hole may be a real gap in the \\
             data, so filling it would be an assumption, not a repair."
      ), class = "fev_gaps_too_large", .envir = environment())
    }
    return(fuel)
  }

  # subst() rather than `gaps %in% small`: on a SpatRaster `%in%` returns a plain
  # logical vector, not a layer, and the mask has to stay spatial.
  target <- terra::subst(gaps, from = small,
                         to = rep(1, length(small)), others = NA)
  n_fill <- as.numeric(terra::global(!is.na(target), "sum", na.rm = TRUE)[1, 1])

  # The modal neighbour, iterated: one pass closes a single cell, a wider sliver
  # needs several. `na.policy = "only"` is what confines the operation to empty
  # cells -- a value already present can never be overwritten by this.
  passes <- ceiling(sqrt(max(tally$count[tally$count <= max_cells]))) + 1L
  fill_layer <- function(layer) {
    out <- layer
    for (i in seq_len(passes)) {
      todo <- as.numeric(terra::global(is.na(out) & !is.na(target), "sum",
                                       na.rm = TRUE)[1, 1])
      if (!todo) {
        break
      }
      step <- terra::focal(out, w = 3, fun = "modal", na.policy = "only",
                           na.rm = TRUE)
      # Only where filling is allowed: elsewhere the original NA stands.
      out <- terra::ifel(is.na(out) & !is.na(target), step, out)
    }
    fev_restore_cat_levels(out, layer)
  }

  layers <- lapply(seq_len(terra::nlyr(cat_r)), function(i) {
    layer <- cat_r[[i]]
    if (identical(names(cat_r)[i], "source")) {
      # A repaired cell must NOT claim that CORINE mapped it. It gets its own
      # level instead, so the repair stays visible in the data rather than only
      # in the provenance, and a reader can map exactly where it happened.
      fev_stamp_filled(layer, target)
    } else {
      fill_layer(layer)
    }
  })
  filled <- terra::rast(layers)
  names(filled) <- names(cat_r)

  n_left <- as.numeric(terra::global(is.na(filled[[class_idx]]), "sum",
                                     na.rm = TRUE)[1, 1])

  if (!quiet) {
    biggest <- round(max(tally$count) * cell_ha, 2)
    fev_inform(c(
      "{n_na} empty cell{?s} in {n_gaps} gap{?s}.",
      v = "{n_fill} filled: below {max_gap} ha, so no component could have \\
           mapped them.",
      i = "Largest gap: {biggest} ha.",
      i = "Class from the modal 3x3 neighbour; the source layer records them \\
           as {.val gap_filled} rather than claiming a dataset mapped them."
    ), class = "fev_gaps_filled", .envir = environment())
    if (nrow(big)) {
      fev_warn(c(
        "{nrow(big)} gap{?s} left empty, above {max_gap} ha.",
        i = "Largest {round(max(big$count) * cell_ha, 2)} ha -- a hole that \\
             size may be a real gap in the source, not a grid artefact.",
        i = "{.fn fev_exposure} propagates each one across its whole window."
      ), class = "fev_gaps_kept", .envir = environment())
    }
  }

  fuel$categorical <- filled
  fuel$provenance <- fev_prov_add_step(
    fuel$provenance %||% fev_prov_new(crs_work = NA),
    fun = "fev_fuel_fill_gaps",
    params = list(max_gap_ha = max_gap,
                  threshold_source = if (explicit) "explicit" else mmu$from,
                  cells_empty = n_na, gaps = n_gaps,
                  cells_filled = n_fill, cells_left = n_left,
                  gaps_left = nrow(big),
                  method = "modal 3x3 neighbour, NA cells only"),
    notes = paste0("gaps below the minimum mapping unit are rasterisation ",
                   "artefacts, not unknown ground")
  )
  fuel
}

#' The minimum mapping unit that can license a fill
#'
#' Among the merged components, the one with complete coverage and the largest
#' minimum mapping unit: the larger the unit, the stronger the claim that a small
#' hole cannot be a real object. Partial-coverage sources are ignored, because
#' their silence is information.
#'
#' @noRd
fev_fuel_mmu <- function(components) {
  known <- components[components %in% names(.FEV_FUEL_MMU)]
  complete <- Filter(function(k) isTRUE(.FEV_FUEL_MMU[[k]]$complete), known)
  if (!length(complete)) {
    return(list(mmu_ha = NA_real_, from = NULL))
  }
  areas <- vapply(complete, function(k) .FEV_FUEL_MMU[[k]]$mmu_ha, numeric(1))
  pick <- complete[which.max(areas)]
  list(mmu_ha = unname(areas[which.max(areas)]),
       from = paste0(pick, " minimum mapping unit"))
}

#' Mark repaired cells in the source layer
#'
#' The `source` layer of a merged register says which dataset supplied each
#' pixel. A repaired cell was supplied by none of them, so it gets its own level
#' rather than borrowing a neighbour's -- otherwise the layer would assert that
#' CORINE mapped ground CORINE left empty.
#'
#' @noRd
fev_stamp_filled <- function(layer, target) {
  lv <- fev_cat_levels(layer)
  label_col <- if (!is.null(lv) && ncol(lv) >= 2L) names(lv)[2] else "class"
  new_id <- if (is.null(lv) || !nrow(lv)) 1L else max(lv[[1]]) + 1L

  out <- terra::ifel(!is.na(target) & is.na(layer), new_id, layer)
  if (!is.null(lv) && nrow(lv)) {
    add <- stats::setNames(
      data.frame(new_id, "gap_filled", stringsAsFactors = FALSE),
      c(names(lv)[1], label_col)
    )
    levels(out) <- rbind(lv[, c(1, 2)], add)
  }
  names(out) <- names(layer)
  out
}

#' Put categorical levels back after a focal pass
#'
#' terra::focal() drops the level table, and a categorical layer without it plots
#' and merges as bare integers.
#'
#' @noRd
fev_restore_cat_levels <- function(new, old) {
  lv <- fev_cat_levels(old)
  if (!is.null(lv) && nrow(lv)) {
    levels(new) <- lv
  }
  names(new) <- names(old)
  new
}
