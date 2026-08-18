# ESA WorldCover import.
#
# The package's 10 m land cover. A cloud-optimised GeoTIFF on a public bucket,
# so the window an analysis needs is read over HTTP through GDAL's /vsicurl/ --
# no account, and no 3 GB tile on disk to get a few hundred square kilometres.
#
# CLCplus Backbone was evaluated for this role and dropped: it sits behind EU
# Login, and the one thing it offered that WorldCover does not -- evergreen
# against deciduous broadleaf -- BD Foret already does in France, and by species
# rather than by leaf phenology. See NEWS for 0.21.0.

#' Fetch ESA WorldCover (10 m land cover, no account needed)
#'
#' Reads the WorldCover tiles covering an area of interest straight from the
#' public bucket, crops to the area, turns the product's nodata into `NA`, and
#' records provenance. Eleven classes at 10 m, derived from Sentinel-1 and
#' Sentinel-2.
#'
#' @section It does not download a tile: A WorldCover tile is 3° square — 36 000 by
#' 36 000 cells — and an analysis usually wants a fraction of one. GDAL reads
#' cloud-optimised GeoTIFFs by range request, so only the requested window
#' crosses the network.
#'
#' @section Where it sits in the hierarchy, and what that costs:
#' `fev_fuel_merge(hierarchy = "auto")`, the default, puts WorldCover **above**
#' BD Forêt: 10 m and a recent vintage everywhere beat 25 m and a 2008-2018
#' vintage.
#'
#' That trade is not free, and the cost was measured rather than guessed. On the
#' two Maures LiDAR plots, WorldCover's *Shrubland* class separates the measured
#' understorey only weakly — 0.688 at best on the 0–1 m load, 0.55 to 0.58
#' elsewhere, against 0.5 for no information — and its *Shrubland* and *Tree
#' cover* classes carry practically the same understorey (median bush height
#' 3.2 m against 2.8 m). It carries no species and no crown-cover reading, both
#' of which BD Forêt does.
#'
#' So this ranking buys resolution and recency and pays in thematic depth. Pass
#' `hierarchy = "primary_first"` with BD Forêt as primary to reverse it.
#'
#' @section The two vintages are not a time series:
#' 2020 is v100 and 2021 is v200, and the producers warn against differencing
#' them: the method changed between versions, and the change signal is dominated
#' by that rather than by the ground. Pick one vintage per analysis.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param year Vintage, 2020 or 2021. Default 2021, the more accurate.
#' @param crs_work EPSG code to return the raster in. Default `2154`. The
#'   product is in EPSG:4326, so a reprojection is the normal case; it uses
#'   nearest neighbour and is logged.
#' @param quiet Suppress the report.
#'
#' @return A [fev_source] holding a categorical `SpatRaster` of class codes.
#'
#' @seealso [fev_fuel_source()] to put it on a grid, [fev_fuel_profile()] to
#'   test its classes against a measurement before trusting them.
#'
#' @source
#' ESA WorldCover, CC-BY 4.0, <https://esa-worldcover.org>. Overall accuracy
#' 74.4% (2020, v100) and 76.7% (2021, v200).
#'
#' Verified 2026-08-18. Tile geometry, data type and nodata were read from the
#' product itself; the eleven class codes were confirmed against the colour
#' table embedded in the raster, all eleven RGB triplets matching the published
#' legend — verification from the data rather than from a document about it.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' wc <- fev_fetch_worldcover(aoi, year = 2021)
#' fuel <- fev_fuel_source(wc, type = "worldcover_2021", res = 10)
#' }
#'
#' @export
fev_fetch_worldcover <- function(aoi,
                                 year = 2021,
                                 crs_work = 2154,
                                 quiet = FALSE) {
  spec <- .FEV_WORLDCOVER_VERSIONS[[as.character(year)]]
  if (is.null(spec)) {
    fev_abort(c(
      "{.arg year} must be one of \\
       {.val {as.integer(names(.FEV_WORLDCOVER_VERSIONS))}}, not {.val {year}}.",
      i = "WorldCover has two maps, 2020 (v100) and 2021 (v200), and they are \\
           not a time series."
    ), .envir = environment())
  }

  tiles <- fev_worldcover_tiles(aoi)
  urls <- fev_worldcover_url(tiles$tile, spec$version, year)

  parts <- lapply(seq_along(urls), function(i) {
    r <- try(terra::rast(urls[i]), silent = TRUE)
    if (inherits(r, "try-error")) {
      # A tile that is entirely ocean is simply not published, which is not an
      # error -- but an unreachable bucket is, and the two must not look alike.
      return(NULL)
    }
    r
  })
  names(parts) <- tiles$tile
  missing <- tiles$tile[vapply(parts, is.null, logical(1))]
  parts <- Filter(Negate(is.null), parts)

  if (!length(parts)) {
    fev_abort(c(
      "No WorldCover tile could be read for this area.",
      x = "Expected {.val {tiles$tile}}.",
      i = "Tiles that are entirely ocean are not published. If your area is \\
           on land, check network egress to \\
           {.url {.FEV_WORLDCOVER_BUCKET}}."
    ), class = "fev_worldcover_unreachable", .envir = environment())
  }

  r <- if (length(parts) == 1L) {
    parts[[1]]
  } else {
    do.call(terra::merge, unname(parts))
  }

  # Crop in the product's own CRS, before reprojecting: reprojecting a whole
  # 3-degree tile to reach a few square kilometres is pure waste.
  v <- terra::vect(fev_as_aoi(aoi, crs = 4326))
  r <- terra::crop(r, terra::ext(v))
  if (terra::ncell(r) == 0) {
    fev_abort("The area of interest does not overlap the WorldCover tiles.",
              class = "fev_no_overlap")
  }

  n_absent <- as.numeric(terra::global(
    terra::app(r, function(x) x == .FEV_WORLDCOVER_NODATA), "sum",
    na.rm = TRUE
  )[1, 1])
  if (isTRUE(n_absent > 0)) {
    r <- terra::subst(r, from = .FEV_WORLDCOVER_NODATA, to = NA_integer_)
  }

  r <- fev_worldcover_categorise(r)

  reprojected <- FALSE
  target <- paste0("EPSG:", crs_work)
  if (!terra::same.crs(r, target)) {
    r <- terra::project(r, target, method = "near")
    reprojected <- TRUE
  }
  names(r) <- "code"

  if (!quiet) {
    fev_worldcover_report(r, year, spec, tiles$tile, missing, n_absent,
                          reprojected)
  }

  new_fev_source(
    r,
    dataset     = paste0("worldcover_", year),
    provider    = "ESA WorldCover (public bucket, CC-BY 4.0)",
    endpoint    = .FEV_WORLDCOVER_BUCKET,
    query       = list(tiles = tiles$tile, version = spec$version, year = year,
                       read = "/vsicurl/ window, no tile downloaded"),
    millesime   = as.integer(year),
    version     = paste("ESA WorldCover", spec$version),
    reprojected = reprojected,
    n_absent    = n_absent,
    notes       = paste0(
      "Overall accuracy ", spec$accuracy_pct, "% +/- ", spec$margin_pct,
      "%. The 2020 and 2021 maps are separate products, not a time series: ",
      "the producers warn against differencing them. Measured on the Maures ",
      "LiDAR plots, the Shrubland class separates understorey only weakly."
    )
  )
}

#' Which 3-degree tiles cover an area
#'
#' WorldCover tiles are named by their south-west corner, floored to a multiple
#' of three degrees: the tile holding 43.3 N 6.35 E is `N42E006`. Verified by
#' reading `N42E006`, whose extent is exactly 6-9 E and 42-45 N.
#'
#' @param aoi Area of interest. Must carry a CRS.
#'
#' @return A data frame with `tile` and the tile bounds in EPSG:4326.
#'
#' @seealso [fev_fetch_worldcover()].
#'
#' @examples
#' aoi <- sf::st_sf(geometry = sf::st_sfc(
#'   sf::st_point(c(6.35, 43.3)), crs = 4326
#' ))
#' fev_worldcover_tiles(sf::st_buffer(aoi, 0.05))
#'
#' @export
fev_worldcover_tiles <- function(aoi) {
  bb <- fev_bbox(sf::st_transform(fev_as_aoi(aoi), 4326))
  step <- .FEV_WORLDCOVER_TILE_DEG

  lon <- seq(floor(bb[["xmin"]] / step) * step,
             floor(bb[["xmax"]] / step) * step, by = step)
  lat <- seq(floor(bb[["ymin"]] / step) * step,
             floor(bb[["ymax"]] / step) * step, by = step)
  g <- expand.grid(lon = lon, lat = lat, KEEP.OUT.ATTRS = FALSE)

  out <- data.frame(
    tile = sprintf("%s%02d%s%03d",
                   ifelse(g$lat < 0, "S", "N"), abs(g$lat),
                   ifelse(g$lon < 0, "W", "E"), abs(g$lon)),
    xmin = g$lon, ymin = g$lat, xmax = g$lon + step, ymax = g$lat + step,
    stringsAsFactors = FALSE
  )
  out[order(out$tile), ]
}

#' @noRd
fev_worldcover_url <- function(tile, version, year) {
  sprintf("/vsicurl/%s/%s/%s/map/ESA_WorldCover_10m_%s_%s_%s_Map.tif",
          .FEV_WORLDCOVER_BUCKET, version, year, year, version, tile)
}

#' Attach the class vocabulary
#'
#' Without a level table, `fev_fuel_source()` files these codes in the
#' continuous register and reads class 20 as a measurement of twenty of
#' something.
#'
#' @noRd
fev_worldcover_categorise <- function(r) {
  tab <- fev_fuel_lookup("worldcover")
  known <- as.integer(tab$code)

  present <- terra::unique(r)[[1]]
  present <- present[is.finite(present) & present >= 0 & present <= 255]
  unknown <- setdiff(as.integer(present), known)
  if (length(unknown)) {
    fev_warn(c(
      "WorldCover raster holds {length(unknown)} code{?s} the shipped lookup \\
       does not know: {.val {unknown}}.",
      i = "They will read as {.val NA} downstream. Rebuild the table with \\
           {.file data-raw/build_fuel_lookups.R} rather than working around \\
           it here."
    ), class = "fev_worldcover_unknown_code", .envir = environment())
  }

  lv <- data.frame(id = known, class = tab$code, stringsAsFactors = FALSE)
  if (length(unknown)) {
    lv <- rbind(lv, data.frame(id = sort(unknown),
                               class = as.character(sort(unknown)),
                               stringsAsFactors = FALSE))
  }
  levels(r) <- lv[order(lv$id), ]
  names(r) <- "code"
  r
}

#' @noRd
fev_worldcover_report <- function(r, year, spec, tiles, missing, n_absent,
                                  reprojected) {
  msg <- c(
    "ESA WorldCover {year} ({spec$version}): {terra::ncell(r)} cells from \\
     {length(tiles)} tile{?s}, read as a window without downloading them."
  )
  if (length(missing)) {
    msg <- c(msg, i = "{length(missing)} tile{?s} not published (ocean): \\
                       {.val {missing}}.")
  }
  if (isTRUE(n_absent > 0)) {
    msg <- c(msg, i = "{n_absent} nodata cell{?s} set to {.val NA}.")
  }
  if (reprojected) {
    msg <- c(msg, i = "Reprojected from EPSG:4326 with nearest neighbour, \\
                       because the layer is categorical.")
  }
  msg <- c(msg, i = "Overall accuracy {spec$accuracy_pct}% \\
                     (+/- {spec$margin_pct}%).")
  fev_inform(msg, .envir = environment())

  fev_once("worldcover_shrubland", fev_warn(c(
    "{.val Shrubland} is the class this package needs most, and the one it \\
     trusts least.",
    i = "Measured on the two Maures LiDAR plots: it separates the understorey \\
         at 0.688 at best and 0.55 to 0.58 elsewhere, against 0.5 for no \\
         information -- and its {.val Shrubland} and {.val Tree cover} cells \\
         carry practically the same measured understorey.",
    i = "WorldCover also carries no species and no crown cover, both of which \\
         BD For\u00eat does.",
    i = "{.fn fev_fuel_profile} is how you check this on your own ground.",
    i = "Shown once per session."
  ), class = "fev_worldcover_shrubland"))
  invisible(TRUE)
}
