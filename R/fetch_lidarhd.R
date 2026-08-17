# LiDAR HD: check coverage before trying to download anything.
#
# The brief is explicit that the availability check comes first, and the numbers
# say why: on 2026-08-17 the programme covered 505 294 tiles nationally, 1 016
# over the Maures, and none at all over Couchey. An absent tile is a normal
# answer, not an error condition, and the code has to be able to tell it from a
# malformed request -- which on this WFS also returns zero features with HTTP
# 200 when the BBOX axes are the wrong way round.

#' Is LiDAR HD available over an area, and which tiles
#'
#' Queries the IGN tile index and reports what exists over an area of interest,
#' without downloading anything.
#'
#' @section Why this comes first:
#' The LiDAR HD programme is still being flown. Metropolitan coverage was
#' announced for the end of 2026 and was not complete when this function was
#' written: the Var was covered, the Côte-d'Or was not. Attempting a download
#' before checking wastes time on the good case and produces a confusing failure
#' on the bad one, so the check is a function of its own and returns an empty
#' table rather than an error when there is nothing.
#'
#' @section What a tile is:
#' A 1 km square in Lambert-93, delivered as **COPC** — Cloud Optimized Point
#' Cloud. COPC is octree-indexed and readable by HTTP range request, so an
#' extent or a level of detail can be read without pulling the whole file. That
#' matters: a tile runs 120 to 260 MB — measured, not assumed — and a
#' Mediterranean massif needs several hundred of them.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param product Which tile index to query: `"points"` for the point clouds
#'   (the default), or `"mnh"`, `"mns"`, `"mnt"` for the derived height, surface
#'   and terrain rasters — far lighter when a canopy height model is all you
#'   need.
#' @param crs_work EPSG code to return the tile footprints in. Default `2154`,
#'   the tiles' native CRS.
#' @param cache Use the on-disk cache. See [fev_cache_dir()].
#'
#' @return An object of class `fev_lidarhd_index`: an `sf` of tile footprints
#'   with columns `name`, `url`, `format`, `timestamp`, `id_chantier`, plus a
#'   `coverage` attribute giving the share of the AOI the tiles cover. Zero rows
#'   when the area is not flown.
#'
#' @seealso [fev_fetch_lidarhd()] to retrieve the tiles,
#'   [fev_fuel_lidar()] to turn them into fuel metrics.
#'
#' @source
#' IGN Géoplateforme WFS, layers `IGNF_NUAGES-DE-POINTS-LIDAR-HD:dalle` and
#' `:bloc`, schema and values verified 2026-08-17. See
#' `specs/phase8-rapport-lidar.md`.
#'
#' @examples
#' \dontrun{
#' # The Maures: covered.
#' aoi <- sf::st_as_sfc(sf::st_bbox(
#'   c(xmin = 6.30, ymin = 43.20, xmax = 6.35, ymax = 43.25),
#'   crs = sf::st_crs(4326)
#' ))
#' idx <- fev_lidarhd_available(aoi)
#' nrow(idx)
#' attr(idx, "coverage")
#'
#' # Couchey: not flown, so an empty index rather than an error.
#' nrow(fev_lidarhd_available(sf::st_read("couchey.gpkg", "study_area")))
#' }
#'
#' @export
fev_lidarhd_available <- function(aoi,
                                  product = c("points", "mnh", "mns", "mnt"),
                                  crs_work = 2154,
                                  cache = TRUE) {
  product <- match.arg(product)
  layer <- .FEV_LIDARHD_LAYERS[[
    if (identical(product, "points")) "points_dalle" else paste0(product, "_dalle")
  ]]
  aoi <- fev_as_aoi(aoi, crs = crs_work)

  key <- fev_cache_key("lidarhd_index",
                       list(aoi = aoi, layer = layer, crs = crs_work))
  tiles <- if (isTRUE(cache) && fev_cache_hit(key)) {
    hit <- fev_cache_read(key)
    fev_inform("LiDAR HD tile index served from cache \\
                ({nrow(hit$data)} tile{?s}).")
    hit$data
  } else {
    got <- fev_lidarhd_query(aoi, layer, crs_work)
    if (isTRUE(cache) && nrow(got)) {
      fev_cache_write(key, got, list(dataset = "lidarhd_index",
                                     provider = "IGN", layer = layer))
    }
    got
  }

  coverage <- fev_lidarhd_coverage(tiles, aoi)
  out <- structure(tiles, class = c("fev_lidarhd_index", class(tiles)),
                   coverage = coverage, product = product, layer = layer)
  fev_report_lidarhd(out, coverage, product)
  out
}

#' @noRd
fev_lidarhd_query <- function(aoi, layer, crs_work) {
  fev_require("happign", "query the LiDAR HD tile index")
  endpoint <- .FEV_ENDPOINTS$ign_wfs
  fev_inform("Querying the LiDAR HD tile index at {.url {endpoint}} ...")

  got <- tryCatch(
    happign::get_wfs(x = aoi, layer = layer, verbose = FALSE),
    error = function(e) {
      fev_abort(c(
        "The LiDAR HD tile index request failed.",
        x = "{conditionMessage(e)}",
        i = "Check network egress to {.url data.geopf.fr}, then that the \\
             layer {.val {layer}} still exists."
      ), class = "fev_wfs_failed", .envir = environment())
    }
  )
  if (is.null(got) || !nrow(got)) {
    return(fev_lidarhd_empty(crs_work))
  }
  keep <- intersect(c("name", "url", "name_download", "format", "projection",
                      "timestamp", "id_chantier", "type_produit"), names(got))
  got <- sf::st_transform(got[, keep], crs_work)
  got[order(got$name), ]
}

#' @noRd
fev_lidarhd_empty <- function(crs_work) {
  sf::st_sf(
    name = character(), url = character(), name_download = character(),
    format = character(), projection = character(), timestamp = character(),
    id_chantier = character(),
    geometry = sf::st_sfc(crs = sf::st_crs(crs_work))
  )
}

#' Share of the AOI the tiles actually cover
#'
#' Reported because partial coverage is the common case at the edge of an
#' acquisition block, and a result computed on 60% of a study area is not a
#' result for that study area.
#'
#' @noRd
fev_lidarhd_coverage <- function(tiles, aoi) {
  if (!nrow(tiles)) {
    return(0)
  }
  inter <- suppressWarnings(
    sf::st_intersection(sf::st_union(sf::st_geometry(tiles)),
                        sf::st_union(sf::st_geometry(aoi)))
  )
  if (!length(inter)) {
    return(0)
  }
  round(100 * as.numeric(sum(sf::st_area(inter))) /
          as.numeric(sum(sf::st_area(aoi))), 1)
}

#' Say what was found, including when nothing was
#' @noRd
fev_report_lidarhd <- function(tiles, coverage, product) {
  if (!nrow(tiles)) {
    fev_warn(c(
      "No LiDAR HD {product} tile covers this area.",
      i = "The programme is still being flown -- metropolitan coverage was \\
           announced for the end of 2026 and was not complete when this was \\
           written.",
      i = "Fall back on the pan-European satellite canopy fuel maps (CBH and \\
           CBD at ~100 m for 2020). See {.fn fev_fuel_lidar} for what that \\
           costs in accuracy.",
      i = "If you expected coverage here, check the AOI: this WFS returns zero \\
           features for a lon/lat BBOX given latitude-first, which looks \\
           identical to an unflown area."
    ), class = "fev_no_lidar_coverage", .envir = environment())
    return(invisible(tiles))
  }

  vintages <- sort(unique(substr(as.character(tiles$timestamp), 1, 4)))
  chantiers <- sort(unique(as.character(tiles$id_chantier)))
  fev_inform(c(
    "{nrow(tiles)} LiDAR HD {product} tile{?s} found.",
    i = "They cover {coverage}% of the area.",
    i = "{length(chantiers)} acquisition block{?s}: {.val {chantiers}}.",
    i = "{length(vintages)} vintage{?s}: {.val {vintages}}.",
    if (coverage < 95)
      c("!" = "Partial coverage. A result computed on {coverage}% of a study \\
                area is not a result for that study area.")
  ), class = "fev_lidar_coverage", .envir = environment())
  invisible(tiles)
}

#' @export
print.fev_lidarhd_index <- function(x, ...) {
  cli::cli_h1("fev_lidarhd_index: {attr(x, 'product')}")
  if (!nrow(x)) {
    cli::cli_alert_warning("No tile: this area has not been flown.")
    return(invisible(x))
  }
  cli::cli_li("{nrow(x)} tile{?s}, {attr(x, 'coverage')}% of the AOI")
  cli::cli_li("Format: {.val {unique(x$format)}}, \\
               {.val {unique(x$projection)}}")
  chantiers <- unique(as.character(x$id_chantier))
  vintages <- sort(unique(substr(as.character(x$timestamp), 1, 10)))
  cli::cli_li("{length(chantiers)} acquisition block{?s}: {.val {chantiers}}")
  cli::cli_li("{length(vintages)} vintage{?s}: {.val {vintages}}")
  # 0.2 GB per tile: measured on two Maures tiles, 120 MB and 256 MB.
  size <- round(nrow(x) * 0.2)
  cli::cli_text("")
  cli::cli_alert_info(
    "Downloading all of these is roughly {size} GB. COPC is readable by HTTP \\
     range request -- see {.fn fev_fetch_lidarhd}."
  )
  invisible(x)
}

# --- retrieval ---------------------------------------------------------------

#' Retrieve LiDAR HD tiles
#'
#' Downloads the tiles covering an area, skipping those already present so an
#' interrupted run can be resumed.
#'
#' @section Volume, and resuming:
#' A tile runs 120 to 260 MB, measured on two Maures tiles on 2026-08-17 — the
#' burnt one is half the size of the unburnt one, because there is less
#' vegetation to return from. Five hundred tiles cover a massif, so a
#' departmental job is a hundred-gigabyte download that will be interrupted at
#' least once. Files already on disk with a plausible size are therefore skipped
#' rather than refetched, which makes re-running the same call the way to
#' resume.
#'
#' Nothing here parallelises the download on purpose: hammering a public service
#' with concurrent requests is how access gets withdrawn for everyone.
#'
#' @section Reading without downloading:
#' The tiles are COPC, so `lidR` can read an extent straight from the URL over
#' HTTP without a local copy. When you need metrics over a few hectares rather
#' than a department, that is the cheaper route — `fev_fetch_lidarhd()` is for
#' when you genuinely need the files.
#'
#' @param aoi Area of interest, or an index from [fev_lidarhd_available()].
#' @param dir Directory to download into. Defaults to a `lidarhd`
#'   subdirectory of the package cache.
#' @param max_tiles Refuse rather than start a job larger than this. There is no
#'   default that is right for everyone, so the default is deliberately small.
#' @param product Passed to [fev_lidarhd_available()] when `aoi` is not already
#'   an index.
#' @param crs_work EPSG code for the index.
#' @param quiet Suppress per-tile progress.
#'
#' @return A `fev_source` holding a data frame of local paths, with the
#'   provenance of the index it came from.
#'
#' @seealso [fev_lidarhd_available()], [fev_fuel_lidar()].
#'
#' @examples
#' \dontrun{
#' idx <- fev_lidarhd_available(aoi)
#' tiles <- fev_fetch_lidarhd(idx, max_tiles = 4)
#' fev_data(tiles)$path
#' }
#'
#' @export
fev_fetch_lidarhd <- function(aoi,
                              dir = NULL,
                              max_tiles = 10L,
                              product = "points",
                              crs_work = 2154,
                              quiet = FALSE) {
  idx <- if (inherits(aoi, "fev_lidarhd_index")) {
    aoi
  } else {
    fev_lidarhd_available(aoi, product = product, crs_work = crs_work)
  }

  if (!nrow(idx)) {
    fev_abort(c(
      "There is nothing to download: no tile covers this area.",
      i = "{.fn fev_lidarhd_available} said so already; check its result \\
           before calling this."
    ), class = "fev_no_lidar_coverage")
  }
  if (nrow(idx) > max_tiles) {
    fev_abort(c(
      "{nrow(idx)} tiles is more than {.arg max_tiles} = {max_tiles}.",
      i = "At 120 to 260 MB each that is roughly \\
           {round(nrow(idx) * 0.2)} GB.",
      i = "Raise {.arg max_tiles} deliberately, or read the COPC tiles over \\
           HTTP instead of downloading them -- see {.fn fev_fuel_lidar}."
    ), class = "fev_too_many_tiles", .envir = environment())
  }

  dir <- dir %||% file.path(fev_cache_dir(create = TRUE), "lidarhd")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  paths <- character(nrow(idx))
  skipped <- 0L
  for (i in seq_len(nrow(idx))) {
    file <- file.path(dir, basename(as.character(idx$url[i])))
    paths[i] <- file
    # Resume: a file already present and not obviously truncated is kept. The
    # threshold is deliberately crude -- a real LiDAR HD tile is never a few
    # kilobytes, and anything finer would need a checksum the service does not
    # publish.
    if (file.exists(file) && file.size(file) > 1e6) {
      skipped <- skipped + 1L
      next
    }
    if (!isTRUE(quiet)) {
      fev_inform("Downloading tile {i}/{nrow(idx)}: {.file {basename(file)}}",
                 .envir = environment())
    }
    ok <- tryCatch({
      utils::download.file(as.character(idx$url[i]), destfile = file,
                           mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(e) {
      fev_warn(c(
        "Tile {.file {basename(file)}} failed to download.",
        x = "{conditionMessage(e)}",
        i = "Re-run to resume: tiles already present are skipped."
      ), class = "fev_tile_failed", .envir = environment())
      FALSE
    })
    if (!ok) {
      unlink(file)
      paths[i] <- NA_character_
    }
  }

  if (skipped) {
    fev_inform("{skipped} tile{?s} already present and skipped.",
               .envir = environment())
  }
  got <- data.frame(name = as.character(idx$name), path = paths,
                    url = as.character(idx$url),
                    id_chantier = as.character(idx$id_chantier),
                    timestamp = as.character(idx$timestamp),
                    stringsAsFactors = FALSE)
  n_ok <- sum(!is.na(got$path))
  if (!n_ok) {
    fev_abort("No tile could be downloaded.", class = "fev_tile_failed")
  }

  new_fev_source(
    got,
    dataset   = "lidarhd",
    provider  = "IGN",
    endpoint  = .FEV_ENDPOINTS$ign_wfs,
    layer     = attr(idx, "layer"),
    query     = list(product = attr(idx, "product"), n_tiles = nrow(idx),
                     coverage_pct = attr(idx, "coverage")),
    millesime = sort(unique(substr(as.character(idx$timestamp), 1, 4))),
    chantier  = sort(unique(as.character(idx$id_chantier))),
    version   = "LiDAR HD, COPC",
    dir       = dir,
    n_downloaded = n_ok
  )
}
