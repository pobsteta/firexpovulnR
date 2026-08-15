#' Fetch CORINE Land Cover (auxiliary fuel source)
#'
#' Downloads CORINE Land Cover polygons for an area of interest. CORINE is the
#' package's **auxiliary** fuel source: it fills what BD Forêt v2 leaves
#' unmapped, in particular non-forest burnable vegetation (sclerophyllous
#' vegetation, moors, grassland) and unambiguously non-burnable classes
#' (urban, water, bare rock).
#'
#' @section Why auxiliary and not primary:
#' CORINE's minimum mapping unit is 25 ha, against 0.5 ha for BD Forêt v2. A
#' 500 m focal window covers 78 ha, so a single CORINE unit is a third of it;
#' at 100 m (3 ha of window) CORINE is smaller than its own mapping unit and
#' the resulting fraction is meaningless. This is the decisive argument for
#' the source hierarchy, and it is why `fev_fuel_merge()` tracks which source
#' each pixel came from.
#'
#' @section Access route:
#' For metropolitan France, CORINE is redistributed on the same IGN
#' Géoplateforme WFS as BD Forêt v2 — no Copernicus Land Monitoring Service
#' authentication needed. **For studies outside France this route does not
#' apply**: obtain the data from CLMS and pass the file through `file`. That
#' path is not verified by this package's tests.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param year CORINE vintage. One of 1990, 2000, 2006, 2012, 2018. Unlike BD
#'   Forêt, CORINE has a common European reference date, so this **is** the
#'   vintage and is recorded as such.
#' @param file Optional path to a local CORINE file (any format GDAL reads).
#'   Use this outside France, or when CLMS requires manual download. The file
#'   is validated and its provenance recorded as a local import.
#' @param code_col Name of the land cover code column. Defaults to the
#'   year-specific column served by the WFS (e.g. `code_18` for 2018).
#' @param crs_work EPSG code to return the data in. Default `2154`.
#' @param cache Use the on-disk cache.
#' @param layer WFS layer name. Defaults to the verified layer for `year`.
#'
#' @return A [fev_source] holding an `sf` of land cover polygons.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' clc <- fev_fetch_corine(aoi, year = 2018)
#'
#' # Outside France, or when CLMS needs a manual download:
#' clc <- fev_fetch_corine(aoi, year = 2018, file = "U2018_CLC2018_V2020_20u1.gpkg")
#' }
#'
#' @export
fev_fetch_corine <- function(aoi,
                             year = 2018,
                             file = NULL,
                             code_col = NULL,
                             crs_work = 2154,
                             cache = TRUE,
                             layer = NULL) {
  valid_years <- c(1990, 2000, 2006, 2012, 2018)
  if (!year %in% valid_years) {
    fev_abort(c(
      "{.arg year} must be one of {.val {valid_years}}, not {.val {year}}.",
      i = "These are the CORINE vintages served by the IGN G\u00e9oplateforme."
    ))
  }
  aoi <- fev_as_aoi(aoi, crs = crs_work)
  code_col <- code_col %||% paste0("code_", substr(as.character(year), 3, 4))

  # Local-file path: used outside France, and whenever CLMS requires a manual
  # download. Documented honestly as an import rather than a fetch.
  if (!is.null(file)) {
    return(fev_corine_from_file(file, aoi, year, code_col, crs_work))
  }

  layer <- layer %||% .FEV_LAYERS[[paste0("clc_", year)]]
  if (is.null(layer)) {
    fev_abort("No known WFS layer for CORINE {year}. Pass {.arg layer} or {.arg file}.")
  }

  key <- fev_cache_key("clc", list(aoi = aoi, layer = layer, crs = crs_work))
  if (isTRUE(cache) && fev_cache_hit(key)) {
    hit <- fev_cache_read(key)
    fev_inform("CORINE {year} served from cache ({nrow(hit$data)} feature{?s}).")
    return(structure(list(data = hit$data, source = hit$source),
                     class = "fev_source"))
  }

  fev_require("happign", "download CORINE from the IGN WFS")

  # Dot-free local name: cli reads a leading dot inside {} as a style, not an
  # expression. See the same note in fev_fetch_bdforet().
  endpoint <- .FEV_ENDPOINTS$ign_wfs
  fev_inform("Fetching CORINE {year} from {.url {endpoint}} ...")

  got <- tryCatch(
    happign::get_wfs(x = aoi, layer = layer, verbose = FALSE),
    error = function(e) {
      fev_abort(c(
        "The CORINE WFS request failed.",
        x = "{conditionMessage(e)}",
        i = "Outside France, pass a local file through {.arg file} instead."
      ))
    }
  )

  if (is.null(got) || !nrow(got)) {
    fev_abort(c(
      "CORINE {year} returned no feature for this AOI.",
      i = "The G\u00e9oplateforme layer covers France. Outside it, use {.arg file}."
    ), class = "fev_empty_result")
  }

  if (!fev_crs_equal(got, sf::st_crs(crs_work))) {
    got <- sf::st_transform(got, crs_work)
  }

  src <- new_fev_source(
    got,
    dataset   = "clc",
    provider  = "Copernicus CLMS, redistributed by IGN",
    endpoint  = .FEV_ENDPOINTS$ign_wfs,
    layer     = layer,
    query     = list(layer = layer, bbox = round(fev_bbox(aoi), 2)),
    # Unlike BD Forêt, CORINE has a single European reference date. This one
    # is real, not a placeholder.
    millesime = year,
    code_col  = code_col,
    version   = paste0("CLC", year),
    mmu_ha    = 25
  )

  if (isTRUE(cache)) {
    fev_cache_write(key, got, src$source)
  }
  fev_inform("Got {nrow(got)} land cover polygon{?s}.")
  src
}

#' Import CORINE from a local file
#' @noRd
fev_corine_from_file <- function(file, aoi, year, code_col, crs_work) {
  if (!file.exists(file)) {
    fev_abort(c(
      "{.file {file}} does not exist.",
      i = "Download CORINE from the Copernicus Land Monitoring Service and \\
           pass the path here."
    ))
  }
  fev_inform("Reading CORINE {year} from {.file {file}} ...")

  got <- tryCatch(
    sf::st_read(file, quiet = TRUE),
    error = function(e) {
      fev_abort(c("Could not read {.file {file}}.", x = "{conditionMessage(e)}"))
    }
  )

  # fev_crs_usable() rather than is.na(): a shapefile written without a CRS
  # comes back carrying GDAL's ENGCRS placeholder, which is not NA but cannot
  # be transformed.
  if (!fev_crs_usable(got)) {
    fev_abort(c(
      "{.file {file}} carries no usable CRS.",
      i = "Set it before passing it in. The package will not guess -- CORINE \\
           is normally EPSG:3035, but an unmarked file could be anything.",
      i = "A shapefile saved without a CRS reads back as \\
           {.val ENGCRS[\"Undefined Cartesian SRS\"]}, which looks set but \\
           cannot be reprojected."
    ), class = "fev_crs_missing")
  }
  if (!code_col %in% names(got)) {
    fev_abort(c(
      "Column {.val {code_col}} not found in {.file {file}}.",
      i = "Available: {.val {setdiff(names(got), attr(got, 'sf_column'))}}.",
      i = "Pass the right one through {.arg code_col}."
    ))
  }

  # Clip to the AOI before reprojecting: CLMS files are continental, and
  # reprojecting all of Europe to crop 50 km afterwards is minutes wasted.
  aoi_native <- sf::st_transform(aoi, sf::st_crs(got))
  got <- suppressWarnings(sf::st_intersection(got, sf::st_geometry(aoi_native)))

  if (!nrow(got)) {
    fev_abort(c(
      "No CORINE feature intersects the AOI.",
      i = "Check that the AOI and {.file {file}} cover the same place."
    ), class = "fev_empty_result")
  }

  got <- sf::st_transform(got, crs_work)

  new_fev_source(
    got,
    dataset   = "clc",
    provider  = "Copernicus CLMS (local file)",
    endpoint  = normalizePath(file),
    query     = list(file = basename(file), clipped_to_aoi = TRUE),
    millesime = year,
    code_col  = code_col,
    version   = paste0("CLC", year),
    mmu_ha    = 25,
    import    = "local file"
  )
}
