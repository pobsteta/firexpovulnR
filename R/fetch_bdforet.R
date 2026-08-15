#' Fetch BD Forêt v2 (primary fuel source)
#'
#' Downloads vegetation formation polygons from the IGN Géoplateforme WFS for
#' an area of interest. BD Forêt v2 is the package's **primary fuel source**:
#' its 0.5 ha minimum mapping unit and 20 m minimum width are what make
#' hectometric focal exposure meaningful, where CORINE's 25 ha unit is not.
#'
#' @section Access route:
#' `geoservices.ign.fr` was retired in March 2026 and now redirects to
#' cartes.gouv.fr, which documents no programmatic route. This function uses
#' the Géoplateforme WFS instead — no authentication, filtered server-side by
#' AOI, so only the study area is transferred rather than whole departments.
#' Pagination and the IGN axis-order quirk are handled by `happign`.
#'
#' @section On the vintage:
#' **The WFS does not serve the vintage.** It is absent from the layer schema,
#' and no per-department table was found at IGN or in any related project. BD
#' Forêt v2 was built department by department between 2007 and 2018, so a
#' national assembly is not a snapshot: a stand mapped in 2008 may have burnt
#' in 2010 and be in a completely different state.
#'
#' `millesime` is therefore recorded as `NA` unless you supply it, and nothing
#' is inferred. Supply it when you know it — `fev_fuel_source()` requires it,
#' and the temporal-bias check in `fev_validate()` cannot run without it.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param millesime Vintage of the data, as a year, or a data frame with
#'   columns `dept` and `year` for a multi-department AOI. `NA` by default
#'   because the source does not provide it — supply it rather than let it
#'   default.
#' @param dept Optional department code(s) to record in provenance. Purely
#'   documentary: filtering is done by `aoi`.
#' @param crs_work EPSG code to return the data in. Default `2154`, BD Forêt's
#'   native CRS — leaving it there avoids reprojecting the categorical primary
#'   source.
#' @param cache Use the on-disk cache. See [fev_cache_dir()].
#' @param layer WFS layer name. Defaults to the verified BD Forêt v2 layer;
#'   override only if IGN moves it.
#'
#' @return A [fev_source] holding an `sf` of vegetation formations with
#'   columns `id`, `code_tfv`, `tfv`, `tfv_g11`, `essence`.
#'
#' @seealso [fev_fetch_corine()] for the auxiliary source,
#'   `fev_fuel_source()` to turn this into a fuel layer.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' bdf <- fev_fetch_bdforet(aoi, millesime = 2014, dept = "83")
#' bdf
#' table(fev_data(bdf)$code_tfv)
#' }
#'
#' @export
fev_fetch_bdforet <- function(aoi,
                              millesime = NA,
                              dept = NULL,
                              crs_work = 2154,
                              cache = TRUE,
                              layer = .FEV_LAYERS$bdforet_v2) {
  aoi <- fev_as_aoi(aoi, crs = crs_work)
  key <- fev_cache_key("bdforet_v2",
                       list(aoi = aoi, layer = layer, crs = crs_work))

  if (isTRUE(cache) && fev_cache_hit(key)) {
    hit <- fev_cache_read(key)
    fev_inform("BD For\u00eat v2 served from cache ({nrow(hit$data)} feature{?s}).")
    rec <- hit$source
    # The vintage is not part of the cache key: the same download can be
    # annotated with a vintage learned later. Honour the current call.
    if (!all(is.na(millesime))) {
      rec$millesime <- millesime
    }
    return(structure(list(data = hit$data, source = rec), class = "fev_source"))
  }

  fev_require("happign", "download BD For\u00eat v2 from the IGN WFS")

  # Bound to a dot-free local name because cli reads a leading dot inside {}
  # as a *style* (like {.url}), not as an expression, so {.FEV_ENDPOINTS$x}
  # fails to evaluate. Applies to every package-internal starting with a dot.
  endpoint <- .FEV_ENDPOINTS$ign_wfs
  fev_inform("Fetching BD For\u00eat v2 from {.url {endpoint}} ...")

  got <- tryCatch(
    happign::get_wfs(x = aoi, layer = layer, verbose = FALSE),
    error = function(e) {
      fev_abort(c(
        "The IGN WFS request failed.",
        x = "{conditionMessage(e)}",
        i = "Check network egress to {.url data.geopf.fr}, then that the \\
             layer {.val {layer}} still exists."
      ))
    }
  )

  if (is.null(got) || !nrow(got)) {
    fev_abort(c(
      "BD For\u00eat v2 returned no feature for this AOI.",
      i = "BD For\u00eat covers metropolitan France only. Check the AOI \\
           location and CRS.",
      i = "Some departments may be unmapped; {.fn fev_fetch_corine} can fill \\
           the gap as a secondary source."
    ), class = "fev_empty_result")
  }

  # happign returns the layer in its native CRS; only reproject if the caller
  # asked for something else, and say so, because reprojecting the primary
  # categorical source is what the working-CRS rule exists to avoid.
  if (!fev_crs_equal(got, sf::st_crs(crs_work))) {
    fev_warn(c(
      "Reprojecting the primary fuel source from {.val {fev_crs_label(got)}} \\
       to {.val {paste0('EPSG:', crs_work)}}.",
      i = "This is the reprojection {.arg crs_work} normally avoids. It is \\
           recorded in the provenance."
    ), class = "fev_primary_reprojected")
    got <- sf::st_transform(got, crs_work)
  }

  src <- new_fev_source(
    got,
    dataset   = "bdforet_v2",
    provider  = "IGN",
    endpoint  = .FEV_ENDPOINTS$ign_wfs,
    layer     = layer,
    query     = list(layer = layer, bbox = round(fev_bbox(aoi), 2),
                     crs = fev_crs_label(aoi)),
    millesime = millesime,
    dept      = dept,
    version   = "v2"
  )

  if (all(is.na(millesime))) {
    fev_warn(c(
      "BD For\u00eat v2 vintage is unknown: the WFS does not serve it.",
      i = "BD For\u00eat v2 was built department by department between 2007 \\
           and 2018, so a national assembly is not a snapshot.",
      i = "Supply {.arg millesime} to enable the temporal-bias check in \\
           {.fn fev_validate}."
    ), class = "fev_millesime_missing")
  }

  if (isTRUE(cache)) {
    fev_cache_write(key, got, src$source)
  }
  fev_inform("Got {nrow(got)} vegetation formation{?s}.")
  src
}

#' Fail with a useful message when an optional package is missing
#'
#' @noRd
fev_require <- function(pkg, what) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    fev_abort(c(
      "Package {.pkg {pkg}} is required to {what}.",
      i = "Install it with {.code install.packages(\"{pkg}\")}."
    ), class = "fev_missing_package")
  }
  invisible(TRUE)
}
