# Copernicus DEM GLO-30 import: terrain, to make exposure anisotropic.
#
# Phase 11 step 3. The package had no terrain at all, which is why exposure
# weighted every direction alike on a massif where fire runs uphill.

.FEV_DEM_BUCKET <- "https://copernicus-dem-30m.s3.amazonaws.com"

#' Fetch Copernicus DEM GLO-30 (30 m elevation, worldwide, no account)
#'
#' Reads the one-degree tiles covering an area straight from the public bucket,
#' crops, reprojects, and records provenance. Feeds [fev_exposure()]'s slope
#' weighting.
#'
#' @section It is a surface model, not a terrain model:
#' GLO-30 is a **DSM**: it includes canopy and buildings. Over closed forest the
#' surface it describes is the top of the trees, so a slope computed from it is
#' the slope of the canopy, not of the ground beneath. At 30 m the canopy is
#' smoothed considerably and the large-scale slope survives; at the scale of a
#' single stand edge it does not.
#'
#' For the use this package puts it to — weighting exposure sectors by the
#' large-scale lie of the land — that is acceptable, and it is why the slope
#' weighting is deliberately coarse rather than pretending to a precision the
#' input has not got. If you need ground slope under canopy, use a LiDAR HD
#' terrain model where one has flown.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param crs_work EPSG code to return the raster in. Default `2154`. The
#'   product is in EPSG:4326, so a reprojection is the normal case; it uses
#'   bilinear interpolation, which is right for a continuous surface.
#' @param quiet Suppress the report.
#'
#' @return A [fev_source] holding a `SpatRaster` of elevation in metres.
#'
#' @seealso [fev_exposure()] for the slope weighting this feeds.
#'
#' @source
#' Copernicus DEM GLO-30, ESA, free and open under the Copernicus licence.
#' Distributed as cloud-optimised GeoTIFF on a public bucket.
#'
#' Verified 2026-08-19 from the product: one-degree tiles at one arc-second
#' (about 30 m), EPSG:4326, named by the south-west corner of the tile, header
#' read remotely in 5.9 s.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' dem <- fev_fetch_dem(aoi)
#' }
#'
#' @export
fev_fetch_dem <- function(aoi, crs_work = 2154, quiet = FALSE) {
  tiles <- fev_dem_tiles(aoi)
  urls <- sprintf("/vsicurl/%s/%s/%s.tif", .FEV_DEM_BUCKET, tiles, tiles)

  parts <- lapply(urls, function(u) {
    r <- try(terra::rast(u), silent = TRUE)
    if (inherits(r, "try-error")) NULL else r
  })
  missing <- tiles[vapply(parts, is.null, logical(1))]
  parts <- Filter(Negate(is.null), parts)

  if (!length(parts)) {
    fev_abort(c(
      "No Copernicus DEM tile could be read for this area.",
      x = "Expected {.val {tiles}}.",
      i = "Tiles that are entirely ocean are not published, which is not an \\
           error. If your area is on land, check network egress to \\
           {.url {.FEV_DEM_BUCKET}}."
    ), class = "fev_dem_unreachable", .envir = environment())
  }

  r <- if (length(parts) == 1L) parts[[1]] else do.call(terra::merge, unname(parts))
  v <- terra::vect(fev_as_aoi(aoi, crs = 4326))
  r <- terra::crop(r, terra::ext(v))
  if (terra::ncell(r) == 0) {
    fev_abort("The area of interest does not overlap the DEM tiles.",
              class = "fev_no_overlap")
  }

  reprojected <- FALSE
  target <- paste0("EPSG:", crs_work)
  if (!terra::same.crs(r, target)) {
    r <- terra::project(r, target, method = "bilinear")
    reprojected <- TRUE
  }
  names(r) <- "elevation"

  rng <- as.numeric(terra::global(r, range, na.rm = TRUE)[1, ])
  if (!quiet) {
    cli::cli_h1("Copernicus DEM GLO-30")
    cli::cli_li("{length(tiles)} tile{?s}\\
                {if (length(missing)) paste0(', ', length(missing), ' not published')}")
    cli::cli_li("Elevation {round(rng[1])} to {round(rng[2])} m")
    cli::cli_alert_warning(
      "A surface model: over closed forest this is the top of the canopy, not \\
       the ground."
    )
  }

  new_fev_source(
    r,
    dataset   = "copernicus_dem_glo30",
    provider  = "ESA Copernicus DEM (public bucket)",
    licence   = "Copernicus",
    licence_from = "licence Copernicus, annoncee par le producteur, lue 2026-08-19",
    endpoint  = .FEV_DEM_BUCKET,
    query     = list(tiles = tiles, res_arcsec = 1,
                     read = "/vsicurl/ window, no tile downloaded"),
    millesime = NA_integer_,
    version   = "GLO-30",
    reprojected = reprojected,
    notes = paste0(
      "Digital SURFACE model: includes canopy and buildings. Slope derived ",
      "from it under closed forest is canopy slope, not ground slope."
    )
  )
}

#' Which one-degree tiles cover an area
#'
#' Named by the south-west corner floored to the degree, latitude on two digits
#' and longitude on three, each followed by `_00` for the minutes that the
#' product's naming keeps even though every tile sits on a whole degree.
#'
#' @noRd
fev_dem_tiles <- function(aoi) {
  b <- sf::st_bbox(fev_as_aoi(aoi, crs = 4326))
  lats <- seq(floor(b[["ymin"]]), floor(b[["ymax"]]))
  lons <- seq(floor(b[["xmin"]]), floor(b[["xmax"]]))
  g <- expand.grid(lat = lats, lon = lons)
  sprintf("Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM",
          ifelse(g$lat < 0, "S", "N"), abs(g$lat),
          ifelse(g$lon < 0, "W", "E"), abs(g$lon))
}
