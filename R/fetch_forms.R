# FORMS import: canopy height for France, from Sentinel-1/2 trained on GEDI.
#
# Phase 10 step 4, and deliberately an IMPORT rather than a computation. The
# phase 10 report set out why: the GEDI x Sentinel-2 route to canopy height is a
# valid method, and Schwartz et al. already ran it for the whole of France at
# 10 m under CC-BY. Rebuilding it here would spend a phase to arrive at a free
# result, and we would then owe the validation ourselves.
#
# What it does NOT do is lift the package's central limitation. FORMS gives
# canopy height. The understorey stays with LiDAR HD, for the reasons in
# specs/phase10-rapport-sentinel.md section 5.3.

#' Import FORMS canopy height (France, 10 m)
#'
#' Reads a FORMS raster into the **continuous** register of a fuel source, so
#' that canopy height becomes available across France rather than only where
#' LiDAR HD has flown. FORMS is derived from Sentinel-1 and Sentinel-2 with a
#' U-Net trained on GEDI RH95, and is published under CC-BY 4.0.
#'
#' @section Why import and not compute:
#' Coupling GEDI with Sentinel-2 to obtain canopy height is a sound method —
#' including by regression kriging, with the anisotropy of GEDI's acquisition
#' modelled along track. But it has been done for the whole of France and
#' released freely. Recomputing it would cost a phase and produce a result we
#' would then have to validate ourselves.
#'
#' @section What it is good for, and what it is not:
#' Height is well restored: MAE 2.94 m and R² 0.69 against 2020 National Forest
#' Inventory plots. **Biomass is not**: R² 0.18 against Renecofor plots. Do not
#' treat FORMS-B as if it carried FORMS-H's reliability.
#'
#' Three caveats travel with the product, and this function repeats them rather
#' than assuming they were read:
#'
#' * the model was trained on a **2020** composite, and the authors state that
#'   deploying it on other years risks significant error;
#' * **Mediterranean forests are underrepresented in its validation** — which
#'   is precisely the Maures;
#' * accuracy degrades on steep slopes, and biomass saturates above
#'   400 Mg/ha.
#'
#' @section It does not reach the understorey:
#' Canopy height is not the package's missing quantity. The understorey is, and
#' no satellite product supplies it in Mediterranean evergreen vegetation: GEDI
#' does not resolve it below about 30 m of canopy height, which covers the whole
#' of the Maures. FORMS widens the *canopy* description beyond the LiDAR
#' footprint; it does not replace [fev_fuel_lidar()].
#'
#' Where it does help is [fev_fuel_profile()]: with FORMS as the reference, a
#' classification can be confronted with a measurement-derived height anywhere
#' in France, not only on the two shipped LiDAR plots.
#'
#' @param file Path to a FORMS raster. Required — the product is distributed
#'   through Zenodo, and this package does not download it for you.
#' @param aoi Optional area of interest to crop to.
#' @param variable Which FORMS product the file holds: `"height"` (FORMS-H,
#'   10 m), `"biomass"` (FORMS-B, 30 m) or `"volume"` (FORMS-V, 30 m). Recorded
#'   in the provenance and used to name the layer.
#' @param crs_work EPSG code to return the raster in. Default `2154`.
#' @param quiet Suppress the import report and the standing caveats.
#'
#' @return A [fev_source] holding a numeric `SpatRaster`, ready for
#'   `fev_fuel_source(register = "continuous")`.
#'
#' @seealso [fev_fuel_profile()] to use it as a reference, [fev_fuel_lidar()]
#'   for the understorey it does not reach.
#'
#' @source
#' Schwartz, M. et al. (2023), *FORMS: Forest Multiple Source height, wood
#' volume, and biomass maps in France at 10 to 30 m resolution based on
#' Sentinel-1, Sentinel-2, and Global Ecosystem Dynamics Investigation (GEDI)
#' data with a deep learning approach*, Earth System Science Data 15, 4927.
#' Data: \doi{10.5281/zenodo.7840108}, CC-BY 4.0. Read at article level
#' 2026-08-18; the raster itself has not been exercised by this package's tests.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' h <- fev_fetch_forms("FORMS_H_2020_10m.tif", aoi = aoi)
#'
#' # As a reference for profiling classes where no LiDAR has flown.
#' fev_fuel_profile(fuel, h, metrics = "height")
#' }
#'
#' @export
fev_fetch_forms <- function(file = NULL,
                            aoi = NULL,
                            variable = c("height", "biomass", "volume"),
                            crs_work = 2154,
                            quiet = FALSE) {
  variable <- match.arg(variable)

  if (is.null(file)) {
    fev_abort(c(
      "{.arg file} is required: this package does not download FORMS.",
      i = "The maps are published on Zenodo under CC-BY 4.0, \\
           {.url https://doi.org/10.5281/zenodo.7840108}.",
      i = "Download the {.val {variable}} raster, then pass its path as \\
           {.arg file}."
    ), class = "fev_forms_manual", .envir = environment())
  }
  if (!file.exists(file)) {
    fev_abort("FORMS file {.file {file}} does not exist.")
  }

  r <- terra::rast(file)
  if (is.na(terra::crs(r)) || !nzchar(terra::crs(r))) {
    fev_abort(c(
      "The FORMS raster carries no CRS.",
      i = "Do not assume one: a file that lost its CRS has been through \\
           something lossy."
    ), class = "fev_crs_missing")
  }
  if (!is.null(fev_cat_levels(r))) {
    fev_abort(c(
      "This raster is categorical, so it is not a FORMS product.",
      i = "FORMS holds a measured quantity per cell -- height in metres, \\
           biomass in Mg/ha, volume in m3/ha."
    ), class = "fev_forms_categorical")
  }

  if (!is.null(aoi)) {
    v <- terra::vect(fev_as_aoi(aoi))
    if (!terra::same.crs(v, r)) {
      v <- terra::project(v, terra::crs(r))
    }
    if (!fev_bbox_overlaps(fev_bbox(v), fev_bbox(r))) {
      fev_abort(c(
        "The area of interest does not overlap the FORMS raster.",
        i = "FORMS covers metropolitan France only."
      ), class = "fev_no_overlap")
    }
    r <- terra::crop(r, terra::ext(v))
  }

  reprojected <- FALSE
  target <- paste0("EPSG:", crs_work)
  if (!terra::same.crs(r, target)) {
    # Bilinear, not nearest: this is a measured continuous surface, and the
    # categorical rule that governs land cover does not apply to it.
    r <- terra::project(r, target, method = "bilinear")
    reprojected <- TRUE
  }
  names(r) <- variable

  if (!quiet) {
    fev_forms_report(r, variable, reprojected)
  }

  new_fev_source(
    r,
    dataset     = paste0("forms_", variable),
    provider    = "Schwartz et al. 2023, ESSD 15:4927 (local file, CC-BY 4.0)",
    endpoint    = normalizePath(file),
    query       = list(file = basename(file), variable = variable,
                       clipped_to_aoi = !is.null(aoi),
                       route = "manual download from Zenodo"),
    millesime   = 2020L,
    version     = "FORMS 2020",
    import      = "local file",
    reprojected = reprojected,
    units       = .FEV_FORMS_UNITS[[variable]],
    notes       = paste0(
      "FORMS was trained on a 2020 composite; the authors state that other ",
      "years risk significant error. Mediterranean forests are ",
      "underrepresented in its validation. Height MAE 2.94 m / R2 0.69 vs NFI; ",
      "biomass R2 0.18 vs Renecofor -- do not read the two as equally reliable."
    )
  )
}

# Units per FORMS variable, from the article. Kept here rather than inline so
# that the provenance and the printed report cannot drift apart.
.FEV_FORMS_UNITS <- list(
  height = "m",
  biomass = "Mg/ha",
  volume = "m3/ha"
)

# Reliability per variable, as published. The gap between height and biomass is
# large enough that reporting one figure for "FORMS" would mislead.
.FEV_FORMS_QUALITY <- list(
  height  = list(mae = 2.94, r2 = 0.69, against = "2020 NFI plots"),
  biomass = list(mae = 59.7, r2 = 0.18, against = "Renecofor plots"),
  volume  = list(mae = NA_real_, r2 = NA_real_, against = NA_character_)
)

#' Say what came in, and repeat the caveats the article states
#' @noRd
fev_forms_report <- function(r, variable, reprojected) {
  q <- .FEV_FORMS_QUALITY[[variable]]
  units <- .FEV_FORMS_UNITS[[variable]]
  msg <- c(
    "FORMS {variable} 2020: {terra::ncell(r)} cells at \\
     {signif(terra::res(r)[1], 4)} m, in {units}."
  )
  if (isTRUE(is.finite(q$r2))) {
    msg <- c(msg, i = "Published accuracy: MAE {q$mae} {units}, \\
                       R2 {q$r2}, against {q$against}.")
  }
  if (reprojected) {
    msg <- c(msg, i = "Reprojected to the working CRS with bilinear \\
                       interpolation -- it is a continuous surface, not a \\
                       class layer.")
  }
  fev_inform(msg, .envir = environment())

  fev_once("forms_caveats", fev_warn(c(
    "FORMS was trained on a {.strong 2020} composite only.",
    i = "The authors state that deploying it on other years risks significant \\
         error, so do not pair it with a 2015 or 2024 analysis without saying \\
         so.",
    i = "{.strong Mediterranean forests are underrepresented in its \\
         validation} -- which is exactly the Maures.",
    i = "It gives the CANOPY. The understorey is what this package lacks, and \\
         no satellite product supplies it in evergreen Mediterranean \\
         vegetation. See {.fn fev_fuel_lidar}.",
    i = "Shown once per session; the figures are in the provenance every time."
  ), class = "fev_forms_caveats"))
  invisible(TRUE)
}
