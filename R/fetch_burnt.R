#' Fetch EFFIS burnt area perimeters
#'
#' Downloads burnt area polygons from the EFFIS/GWIS service, for validating a
#' risk surface against what actually burnt.
#'
#' @section Coverage is shorter than you may expect:
#' The public EFFIS endpoint serves roughly **2016 onward** — not 2006. EFFIS
#' states that historic data, database extracts and raw perimeters go through
#' their data request form instead. This function therefore compares the
#' period you asked for against the period actually returned, and warns with
#' numbers rather than a vague caveat: silently validating on ten years while
#' believing you validated on eighteen is the failure mode worth preventing.
#'
#' Use `file` to bring in an extract obtained through the EFFIS request form.
#'
#' @section The CRS is forced, deliberately:
#' EFFIS ships a `.prj` declaring `GCS_unknown` although the coordinates are
#' plain WGS84, so `sf::st_crs()` reads `unknown`. The package sets EPSG:4326
#' explicitly and records the override in provenance. It is never applied
#' silently, because "the provider mislabels its CRS" is exactly the kind of
#' assumption that must be visible in a methods section.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param period Two-element character or numeric vector giving the first and
#'   last year (or dates) to keep, e.g. `c("2016", "2025")`. `NULL` keeps
#'   everything returned.
#' @param file Optional path to a local burnt-area file, for extracts obtained
#'   through the EFFIS data request form.
#' @param crs_work EPSG code to return the data in. Default `2154`.
#' @param cache Use the on-disk cache.
#' @param layer WFS type name. Defaults to the verified `ms:modis.ba.poly`.
#'
#' @return A [fev_source] holding an `sf` of burnt area polygons, with at
#'   least `FIREDATE`, `AREA_HA` and `COUNTRY`. A `fire_year` column is added
#'   for convenience.
#'
#' @seealso `fev_validate()`, which uses these to score a risk surface and
#'   runs the temporal-bias check against the fuel vintage.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' ba <- fev_fetch_burnt(aoi, period = c("2016", "2025"))
#' fev_source_info(ba)$period_returned
#' }
#'
#' @export
fev_fetch_burnt <- function(aoi,
                            period = NULL,
                            file = NULL,
                            crs_work = 2154,
                            cache = TRUE,
                            layer = .FEV_LAYERS$effis_ba) {
  aoi <- fev_as_aoi(aoi, crs = crs_work)

  got <- if (!is.null(file)) {
    fev_burnt_from_file(file)
  } else {
    fev_burnt_from_effis(aoi, layer, cache)
  }

  ba <- got$data
  ba <- fev_burnt_prepare(ba, crs_work)
  n_all <- nrow(ba)

  # Compare requested against available BEFORE filtering, so the message can
  # quantify what is missing rather than just report an empty result.
  avail <- range(ba$fire_year, na.rm = TRUE)
  if (!is.null(period)) {
    want <- fev_period_years(period)
    if (want[1] < avail[1]) {
      # Bound to a plain local name first: cli evaluates {} expressions in the
      # caller's frame, and a dotted package-internal object is not reliably
      # visible there.
      min_year <- .FEV_EFFIS_MIN_YEAR
      gap_end <- min(avail[1] - 1L, want[2])
      fev_warn(c(
        "Requested period starts in {want[1]}, but the earliest burnt area \\
         available here is {avail[1]}.",
        x = "{want[1]}-{gap_end} is missing from this source.",
        i = "The public EFFIS endpoint serves roughly {min_year} onward. \\
             Earlier data goes through the EFFIS data request form; pass the \\
             extract through {.arg file}."
      ), class = "fev_period_truncated")
    }
    keep <- !is.na(ba$fire_year) &
      ba$fire_year >= want[1] & ba$fire_year <= want[2]
    ba <- ba[keep, , drop = FALSE]
  }

  if (!nrow(ba)) {
    fev_abort(c(
      "No burnt area left after filtering.",
      i = "{n_all} feature{?s} were returned, covering {avail[1]}-{avail[2]}.",
      i = "Widen {.arg period}, or check the AOI."
    ), class = "fev_empty_result")
  }

  returned <- range(ba$fire_year, na.rm = TRUE)
  src <- got$source
  src$period_requested <- if (is.null(period)) NA_character_ else paste(fev_period_years(period), collapse = "-")
  src$period_returned  <- paste(returned, collapse = "-")
  src$n_features       <- nrow(ba)
  src$crs_override     <- sprintf(
    "forced to EPSG:%d (provider .prj declares GCS_unknown)", .FEV_EFFIS_CRS
  )

  fev_inform("Got {nrow(ba)} burnt area{?s}, {returned[1]}-{returned[2]}, \\
              {round(sum(ba$area_ha, na.rm = TRUE))} ha total.")
  structure(list(data = ba, source = src), class = "fev_source")
}

#' Download the EFFIS shapefile bundle
#'
#' SHAPEZIP rather than GeoJSON: the JSON output of this server returns HTTP
#' 502 intermittently, while the zipped shapefile is the format EFFIS
#' documents and it downloaded reliably in testing.
#'
#' @noRd
fev_burnt_from_effis <- function(aoi, layer, cache) {
  bb <- fev_bbox(sf::st_transform(aoi, .FEV_EFFIS_CRS))
  key <- fev_cache_key("effis_ba", list(bbox = round(bb, 4), layer = layer))

  if (isTRUE(cache) && fev_cache_hit(key)) {
    hit <- fev_cache_read(key)
    fev_inform("EFFIS burnt areas served from cache.")
    return(list(data = hit$data, source = hit$source))
  }

  fev_require("httr2", "download EFFIS burnt areas")
  url <- .FEV_ENDPOINTS$effis_wfs
  query <- list(
    service      = "WFS",
    version      = "1.1.0",
    request      = "getfeature",
    typename     = layer,
    outputformat = "SHAPEZIP",
    bbox         = paste(round(bb, 6), collapse = ",")
  )

  fev_inform("Fetching EFFIS burnt areas from {.url {url}} ...")
  tmp <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp), add = TRUE)

  resp <- tryCatch({
    req <- httr2::request(url)
    req <- httr2::req_url_query(req, !!!query)
    req <- httr2::req_timeout(req, 180)
    httr2::req_perform(req, path = tmp)
  }, error = function(e) {
    fev_abort(c(
      "The EFFIS request failed.",
      x = "{conditionMessage(e)}",
      i = "Check network egress to {.url maps.effis.emergency.copernicus.eu}."
    ))
  })

  if (httr2::resp_status(resp) != 200L) {
    fev_abort("EFFIS returned HTTP {httr2::resp_status(resp)}.")
  }

  exdir <- tempfile()
  dir.create(exdir)
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  utils::unzip(tmp, exdir = exdir)

  shp <- list.files(exdir, pattern = "\\.shp$", full.names = TRUE)
  if (!length(shp)) {
    fev_abort(c(
      "The EFFIS response contained no shapefile.",
      i = "The service may be returning an error document. Retry, then \\
           check the layer name {.val {layer}}."
    ))
  }

  ba <- sf::st_read(shp[1], quiet = TRUE)
  src <- list(
    dataset       = "effis_burnt_areas",
    provider      = "EFFIS / Copernicus EMS",
    endpoint      = url,
    layer         = layer,
    query         = query,
    millesime     = NA,
    downloaded_at = fev_now(),
    crs_native    = "GCS_unknown (declared)",
    n_features    = nrow(ba)
  )

  if (isTRUE(cache)) {
    # Cache before forcing the CRS, so the sidecar records what arrived.
    forced <- ba
    sf::st_crs(forced) <- .FEV_EFFIS_CRS
    fev_cache_write(key, forced, src)
  }
  list(data = ba, source = src)
}

#' @noRd
fev_burnt_from_file <- function(file) {
  if (!file.exists(file)) {
    fev_abort(c(
      "{.file {file}} does not exist.",
      i = "Request historic EFFIS data through their data request form, \\
           then pass the extract here."
    ))
  }
  fev_inform("Reading burnt areas from {.file {file}} ...")
  ba <- tryCatch(
    sf::st_read(file, quiet = TRUE),
    error = function(e) {
      fev_abort(c("Could not read {.file {file}}.", x = "{conditionMessage(e)}"))
    }
  )
  list(
    data = ba,
    source = list(
      dataset       = "effis_burnt_areas",
      provider      = "EFFIS / Copernicus EMS (local extract)",
      endpoint      = normalizePath(file),
      query         = list(file = basename(file)),
      millesime     = NA,
      downloaded_at = fev_now(),
      crs_native    = fev_crs_label(ba),
      n_features    = nrow(ba),
      import        = "local file"
    )
  )
}

#' Normalise burnt-area columns and CRS
#'
#' EFFIS delivers every attribute as a string, including AREA_HA and the
#' land-cover shares. Converting here rather than at each use keeps the
#' coercion in one place where it can be checked.
#'
#' @noRd
fev_burnt_prepare <- function(ba, crs_work) {
  nms <- toupper(names(ba))

  if (!"FIREDATE" %in% nms) {
    fev_abort(c(
      "The burnt area data has no {.field FIREDATE} column.",
      i = "Available: {.val {names(ba)}}.",
      i = "{.fn fev_validate} needs a fire date to compare against the fuel \\
           vintage."
    ))
  }
  names(ba)[nms == "FIREDATE"] <- "FIREDATE"

  if (!fev_crs_usable(ba)) {
    # EFFIS declares GCS_unknown for what is plain WGS84. Forced, never
    # silent: this is recorded in the source record too.
    forced <- paste0("EPSG:", .FEV_EFFIS_CRS)
    fev_inform("Burnt areas carry no usable CRS; forcing {.val {forced}} \\
                (EFFIS declares {.val GCS_unknown} for WGS84 data).")
    sf::st_crs(ba) <- .FEV_EFFIS_CRS
  }

  # An explicit format is required, not optional: as.Date() without one throws
  # ("character string is not in a standard unambiguous format") on unparseable
  # input rather than returning NA, so a malformed extract would crash here
  # instead of reaching the diagnostic below. EFFIS serves
  # "2016-07-18 00:00:00"; the slash variant covers hand-edited extracts.
  raw <- substr(as.character(ba$FIREDATE), 1, 10)
  d <- as.Date(raw, format = "%Y-%m-%d")
  if (anyNA(d)) {
    alt <- as.Date(raw, format = "%Y/%m/%d")
    d[is.na(d)] <- alt[is.na(d)]
  }
  ba$fire_date <- d
  ba$fire_year <- as.integer(format(d, "%Y"))

  if (all(is.na(ba$fire_year))) {
    bad <- utils::head(as.character(ba$FIREDATE), 3)
    fev_abort(c(
      "No {.field FIREDATE} value could be parsed as a date.",
      i = "First values: {.val {bad}}.",
      i = "Expected {.val YYYY-MM-DD} at the start of the field."
    ))
  }

  area_col <- names(ba)[toupper(names(ba)) == "AREA_HA"]
  ba$area_ha <- if (length(area_col)) {
    suppressWarnings(as.numeric(as.character(ba[[area_col[1]]])))
  } else {
    as.numeric(sf::st_area(sf::st_transform(ba, crs_work))) / 10000
  }

  sf::st_transform(ba, crs_work)
}

#' Coerce a period argument to a pair of years
#' @noRd
fev_period_years <- function(period) {
  if (length(period) != 2L) {
    fev_abort("{.arg period} must have exactly two elements (start, end).")
  }
  y <- suppressWarnings(as.integer(substr(as.character(period), 1, 4)))
  if (any(is.na(y))) {
    fev_abort(c(
      "Could not read years from {.arg period}.",
      i = "Use {.code c(\"2016\", \"2025\")} or {.code c(2016, 2025)}."
    ))
  }
  if (y[1] > y[2]) {
    fev_abort("{.arg period} starts in {y[1]} but ends in {y[2]}.")
  }
  y
}
