#' Fetch CEMS fire danger indices
#'
#' Downloads Canadian Fire Weather Index System indices from the Copernicus
#' Emergency Management Service historical reconstruction, hosted on the Early
#' Warning Data Store (EWDS) and driven by ERA5 reanalysis.
#'
#' @section Credentials:
#' The EWDS needs a personal Copernicus API token. The package never handles
#' it: it reads `ECMWF_KEY` from the environment (set it in `~/.Renviron`), or
#' falls back to whatever `ecmwfr` already has in its keyring. **Never put a
#' token in a script or commit one.**
#'
#' ```
#' # in ~/.Renviron
#' ECMWF_KEY=your-token-here
#' ```
#'
#' @section Resolution, and why it matters here more than elsewhere:
#' The reanalysis is on a 0.25° grid — roughly 20-30 km at French latitudes.
#' Fuel-derived exposure is at 20-100 m. **That is a ratio of several hundred**,
#' and it is the central methodological difficulty of the whole chain. Nothing
#' in this function hides it: combining these layers with anything else goes
#' through `fev_align()`, which warns and records the ratio.
#'
#' Note also that the EWDS request examples use `grid = "0.5/0.5"` while the
#' dataset overview announces 0.25° for the reanalysis. The discrepancy is
#' unresolved upstream, so `grid` is an explicit argument here rather than a
#' hidden default.
#'
#' @section Verification status:
#' The dataset identifier, service name and variable names were read from the
#' EWDS documentation and from the `ecmwfr` source on 2026-08-15. **No live
#' request has been made from this package**, because that requires a personal
#' token. Treat the first real call as part of your own validation, and check
#' that what comes back matches what you asked for.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS. Converted to a lon/lat bounding box for
#'   the request.
#' @param period Two-element vector of dates or years bounding the request,
#'   e.g. `c("1991-01-01", "2020-12-31")`.
#' @param product Character vector of indices to retrieve. Defaults to the
#'   Canadian FWI system set.
#' @param grid Request grid as `"lat/lon"` degrees. Explicit on purpose.
#' @param dataset EWDS dataset identifier.
#' @param user `ecmwfr` user id.
#' @param path Directory for the downloaded file. Defaults to the package
#'   cache.
#' @param transfer Perform the download. `FALSE` builds and returns the
#'   request without contacting the service — useful to inspect exactly what
#'   would be sent.
#'
#' @return A [fev_source] holding a `SpatRaster` of the requested indices.
#'   When `transfer = FALSE`, the request list is returned instead.
#'
#' @seealso `fev_fwi_percentile()` to turn raw indices into regional
#'   percentile ranks, which is what makes them comparable across climates.
#'
#' @examples
#' # Inspect the request that would be sent, without any credentials:
#' aoi <- sf::st_as_sfc(sf::st_bbox(
#'   c(xmin = 6.2, ymin = 43.1, xmax = 6.6, ymax = 43.4), crs = sf::st_crs(4326)
#' ))
#' req <- fev_fetch_fwi(aoi, period = c("2020-01-01", "2020-12-31"),
#'                      transfer = FALSE)
#' req$dataset_short_name
#' req$variable
#'
#' @export
fev_fetch_fwi <- function(aoi,
                          period,
                          product = c("fire_weather_index",
                                      "fine_fuel_moisture_code",
                                      "duff_moisture_code",
                                      "drought_code",
                                      "initial_spread_index",
                                      "build_up_index",
                                      "fire_daily_severity_index"),
                          grid = "0.25/0.25",
                          dataset = "cems-fire-historical-v1",
                          user = "ecmwfr",
                          path = NULL,
                          transfer = TRUE) {
  aoi <- fev_as_aoi(aoi)
  bb <- fev_bbox(sf::st_transform(aoi, 4326))
  years <- fev_period_years(period)

  # EWDS area order is North/West/South/East, not the xmin/ymin/xmax/ymax that
  # everything else in this package uses. Getting it wrong returns a valid
  # raster for the wrong place, which is the worst kind of failure.
  area <- c(round(bb[["ymax"]], 3), round(bb[["xmin"]], 3),
            round(bb[["ymin"]], 3), round(bb[["xmax"]], 3))

  request <- list(
    dataset_short_name = dataset,
    product_type       = "reanalysis",
    dataset_type       = "consolidated_dataset",
    system_version     = "4_1",
    variable           = product,
    year               = as.character(seq(years[1], years[2])),
    month              = sprintf("%02d", 1:12),
    day                = sprintf("%02d", 1:31),
    grid               = grid,
    area               = area,
    data_format        = "grib",
    target             = sprintf("cems_fwi_%d_%d.grib", years[1], years[2])
  )

  if (!isTRUE(transfer)) {
    return(request)
  }

  fev_require("ecmwfr", "download CEMS fire danger indices from the EWDS")
  fev_fwi_credentials(user)

  path <- path %||% fev_cache_dir(create = TRUE)
  n_years <- years[2] - years[1] + 1L
  if (n_years > 5L) {
    fev_inform("Requesting {n_years} years of daily {length(product)}-variable \\
                data. EWDS queues large requests; this can take a while.")
  }

  fev_inform("Submitting request to the EWDS ({.val {dataset}}) ...")
  file <- tryCatch(
    ecmwfr::wf_request(request = request, user = user, transfer = TRUE,
                       path = path, verbose = FALSE),
    error = function(e) {
      fev_abort(c(
        "The EWDS request failed.",
        x = "{conditionMessage(e)}",
        i = "Check that your token is valid and that you accepted the \\
             dataset licence on the EWDS website -- licence acceptance is \\
             per dataset and is a common cause of rejected requests."
      ), class = "fev_ewds_failed")
    }
  )

  r <- tryCatch(
    terra::rast(file),
    error = function(e) {
      fev_abort(c(
        "Downloaded {.file {file}} but {.pkg terra} could not read it.",
        x = "{conditionMessage(e)}",
        i = "Reading GRIB needs GDAL built with GRIB support."
      ))
    }
  )

  src <- new_fev_source(
    r,
    dataset   = "cems_fire_historical",
    provider  = "Copernicus EMS / ECMWF (EWDS)",
    endpoint  = .FEV_ENDPOINTS$ewds_api,
    query     = request,
    millesime = paste(years, collapse = "-"),
    version   = "system 4_1",
    variables = product,
    grid      = grid,
    file      = file
  )

  fev_warn(c(
    "Fire danger is on a {grid} degree grid, roughly 20-30 km at French \\
     latitudes.",
    i = "Fuel-based exposure is at 20-100 m. Combine the two only through \\
         {.code fev_align()}, which records the scale ratio."
  ), class = "fev_scale_gap")

  src
}

#' Resolve EWDS credentials without ever handling the token in the open
#'
#' Reads ECMWF_KEY from the environment and hands it straight to ecmwfr's
#' keyring. The value is never printed, logged, or written to provenance.
#'
#' @noRd
fev_fwi_credentials <- function(user = "ecmwfr") {
  key <- Sys.getenv("ECMWF_KEY", unset = "")
  if (nzchar(key)) {
    ecmwfr::wf_set_key(key = key, user = user)
    return(invisible(TRUE))
  }
  existing <- tryCatch(ecmwfr::wf_get_key(user = user), error = function(e) NULL)
  if (!is.null(existing) && nzchar(existing)) {
    return(invisible(TRUE))
  }
  fev_abort(c(
    "No EWDS credentials found.",
    i = "Set {.envvar ECMWF_KEY} in {.file ~/.Renviron} and restart R.",
    i = "Get a token from {.url https://ewds.climate.copernicus.eu/} \\
         (profile page), and accept the dataset licence there.",
    x = "Never put the token in a script or commit it."
  ), class = "fev_no_credentials")
}
