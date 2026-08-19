# GHS-POP import: resident population, 100 m, worldwide, no account.
#
# Phase 11 step 2. Until now every module had its own acquisition -- BD Foret,
# CORINE, WorldCover, FORMS, LiDAR HD, Open-Meteo, EFFIS -- and vulnerability
# had none: the user had to bring assets from somewhere, with no lookup, no
# vintage and no provenance. This is the asymmetry that made the second half of
# the package unusable by anyone who had not already assembled their own data.
#
# GHS-POP is the source CLIMAAX itself uses, which matters for fev_risk(): the
# comparison the method invites is then against the same input.

.FEV_GHSL_BASE <- paste0(
  "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_POP_GLOBE_R2023A/"
)

# World Mollweide, the projection GHSL distributes its 100 m product in.
.FEV_GHSL_CRS <- "ESRI:54009"

# Tile geometry, MEASURED rather than read off a datasheet: R4_C19 spans
# x [-41000, 959000] and y [5e6, 6e6]; R5_C19 spans the same x and y
# [4e6, 5e6]. So tiles are 1 000 000 m square, and the x origin carries a
# constant -41 000 m offset that no product sheet states. Re-verify if the
# release changes.
.FEV_GHSL_TILE_M <- 1e6
.FEV_GHSL_X0 <- -41000
.FEV_GHSL_C0 <- 19L
.FEV_GHSL_Y_TOP <- 1e7

#' Fetch GHS-POP resident population (100 m, worldwide, no account)
#'
#' Reads the Global Human Settlement population tiles covering an area straight
#' from the JRC open-data server, crops to the area, and records provenance.
#' Values are **residents per cell**, so a sum over an area is a headcount.
#'
#' @section Why this source:
#' It needs no account and no key, it is global, and it is what the CLIMAAX
#' wildfire workflow uses — so a risk layer built with it can be compared
#' against that method's own outputs rather than against a different population
#' product. It is modelled from census counts redistributed onto built-up
#' surface, which is the next section.
#'
#' @section What a population raster is and is not:
#' GHS-POP is **modelled**, not observed: census or register counts are
#' disaggregated onto the built-up surface GHSL detects from imagery. Two
#' consequences the package will not paper over.
#'
#' First, the spatial detail is the built-up layer's, while the totals are the
#' census's. A cell's value is an expectation, not a count of people who sleep
#' there.
#'
#' Second, and this is what matters for fire: it is **residential**. A campsite,
#' a hiking trail or a motorway carries no resident population and will read as
#' empty, when summer daytime exposure in a Mediterranean massif is exactly
#' where people burn. Do not read a low GHS-POP as a low human exposure in
#' August.
#'
#' @section It is exposure of assets, not vulnerability:
#' This function supplies *how much is exposed*. It says nothing about *how
#' badly it is harmed*, which is what vulnerability means in a risk assessment
#' and what this package still does not have — there is no damage function
#' anywhere in it. [fev_vuln_layer()] will happily normalise this raster onto
#' `[0, 1]` and the result will be a normalised asset density. A hospital and a
#' barn at the same population density come out identical, and no amount of
#' weighting in [fev_vuln_stack()] changes that.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param epoch Population epoch, one of the five-yearly GHSL epochs
#'   (1975 to 2030). Default 2020. Recorded as the vintage.
#' @param crs_work EPSG code to return the raster in. Default `2154`. `NULL`
#'   leaves it in the product's World Mollweide, which is what to pass when you
#'   want to measure what a reprojection costs. The
#'   product is in World Mollweide, so a reprojection is the normal case. It
#'   uses `"sum"` rather than an interpolation, because the values are people
#'   per cell and what must survive a change of projection is the **total**.
#'   The drift is reported, and warned about above 1%.
#' @param quiet Suppress the report.
#'
#' @return A [fev_source] holding a `SpatRaster` of residents per cell.
#'
#' @seealso [fev_vuln_layer()] to normalise it, [fev_wui()] for the interface
#'   where it matters most, [fev_risk()] to combine it.
#'
#' @source
#' GHS-POP R2023A, European Commission Joint Research Centre, CC-BY 4.0.
#' <https://human-settlement.emergency.copernicus.eu>
#'
#' Verified 2026-08-19 against the product itself, not a datasheet: two tiles
#' were read and their extents compared to establish the tiling, which is how
#' the 1 000 000 m tile size and the -41 000 m x-origin offset in this file
#' were obtained. A crop over the Maures returned 35 039 residents at 100 m.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' pop <- fev_fetch_ghsl(aoi, epoch = 2020)
#' human <- fev_vuln_layer(pop, method = "log")
#' }
#'
#' @export
fev_fetch_ghsl <- function(aoi,
                           epoch = 2020,
                           crs_work = 2154,
                           quiet = FALSE) {
  if (!is.numeric(epoch) || length(epoch) != 1L || epoch %% 5 != 0 ||
      epoch < 1975 || epoch > 2030) {
    fev_abort(c(
      "{.arg epoch} must be a five-yearly GHSL epoch between 1975 and 2030.",
      x = "Got {.val {epoch}}.",
      i = "The release publishes 1975, 1980, ... 2030."
    ), .envir = environment())
  }
  epoch <- as.integer(epoch)

  tiles <- fev_ghsl_tiles(aoi)
  urls <- fev_ghsl_url(tiles, epoch)

  parts <- lapply(urls, function(u) {
    r <- try(terra::rast(u), silent = TRUE)
    if (inherits(r, "try-error")) NULL else r
  })
  missing <- tiles[vapply(parts, is.null, logical(1))]
  parts <- Filter(Negate(is.null), parts)

  if (!length(parts)) {
    fev_abort(c(
      "No GHS-POP tile could be read for this area.",
      x = "Expected {.val {tiles}}.",
      i = "Tiles with no land are not published, which is not an error. If \\
           your area is on land, check network egress to \\
           {.url {.FEV_GHSL_BASE}}.",
      i = "The tiling was measured from the data, not from a document: if the \\
           release changed, the tile names computed here are wrong and this \\
           is how it shows."
    ), class = "fev_ghsl_unreachable", .envir = environment())
  }

  r <- if (length(parts) == 1L) parts[[1]] else do.call(terra::merge, unname(parts))

  # Crop in Mollweide first: reprojecting a 10 000 x 10 000 tile to reach a few
  # square kilometres is the waste WorldCover taught us to avoid.
  v <- terra::vect(fev_as_aoi(aoi, crs = .FEV_GHSL_CRS))
  r <- terra::crop(r, terra::ext(v))
  if (terra::ncell(r) == 0) {
    fev_abort("The area of interest does not overlap the GHS-POP tiles.",
              class = "fev_no_overlap")
  }

  before <- as.numeric(terra::global(r, "sum", na.rm = TRUE)[1, 1])

  reprojected <- FALSE
  # NULL leaves the raster in World Mollweide. That is not a convenience: it is
  # the only way to see what a reprojection costs, by comparing the headcount
  # before and after, which is how the bilinear drift was found.
  target <- if (is.null(crs_work)) terra::crs(r) else paste0("EPSG:", crs_work)
  if (!terra::same.crs(r, target)) {
    # "sum", not "bilinear". The values are people per cell, so the quantity to
    # preserve across a change of projection is the total, not the local
    # gradient. Bilinear gained 5% of the Maures population out of nowhere --
    # 35 039 residents became 36 783 -- which is the kind of error that never
    # gets caught downstream because it looks like a plausible number.
    r <- terra::project(r, target, method = "sum")
    reprojected <- TRUE
  }
  names(r) <- "population"
  after <- as.numeric(terra::global(r, "sum", na.rm = TRUE)[1, 1])

  if (!quiet) {
    fev_ghsl_report(r, epoch, tiles, missing, before, after, reprojected)
  }

  new_fev_source(
    r,
    dataset   = paste0("ghs_pop_", epoch),
    provider  = "European Commission JRC, GHSL (CC-BY 4.0)",
    endpoint  = .FEV_GHSL_BASE,
    query     = list(tiles = tiles, epoch = epoch, release = "R2023A",
                     res_m = 100, projection = .FEV_GHSL_CRS,
                     read = "/vsizip//vsicurl/ window, no tile downloaded"),
    millesime = epoch,
    version   = "GHS-POP R2023A V1-0, 100 m",
    reprojected = reprojected,
    notes = paste0(
      "Residents per cell, modelled: census counts disaggregated onto ",
      "built-up surface. Residential only -- campsites, trails and roads read ",
      "as empty, which understates summer daytime exposure in a ",
      "Mediterranean massif. This is exposure of assets, not vulnerability: ",
      "the package has no damage function."
    )
  )
}

#' Which GHS-POP tiles cover an area
#'
#' The grid was measured, not read: see the constants at the top of this file.
#' Row runs south as it increases, column runs east, which is why one formula
#' subtracts and the other adds.
#'
#' @noRd
fev_ghsl_tiles <- function(aoi) {
  b <- sf::st_bbox(fev_as_aoi(aoi, crs = .FEV_GHSL_CRS))
  cols <- seq(fev_ghsl_col(b[["xmin"]]), fev_ghsl_col(b[["xmax"]]))
  rows <- seq(fev_ghsl_row(b[["ymax"]]), fev_ghsl_row(b[["ymin"]]))
  g <- expand.grid(row = rows, col = cols)
  sprintf("R%d_C%d", g$row, g$col)
}

#' @noRd
fev_ghsl_col <- function(x) {
  as.integer(floor((x - .FEV_GHSL_X0) / .FEV_GHSL_TILE_M)) + .FEV_GHSL_C0
}

#' @noRd
fev_ghsl_row <- function(y) {
  as.integer(floor((.FEV_GHSL_Y_TOP - y) / .FEV_GHSL_TILE_M))
}

#' The zip, and the tif inside it
#'
#' GHSL ships each tile as a zip holding the raster plus two documents. GDAL
#' reads into it by range request, so nothing is downloaded whole -- the path
#' just has to name the member, and the member repeats the archive name.
#'
#' @noRd
fev_ghsl_url <- function(tiles, epoch) {
  stem <- sprintf("GHS_POP_E%d_GLOBE_R2023A_54009_100_V1_0_%s", epoch, tiles)
  sprintf("/vsizip//vsicurl/%sGHS_POP_E%d_GLOBE_R2023A_54009_100/V1-0/tiles/%s.zip/%s.tif",
          .FEV_GHSL_BASE, epoch, stem, stem)
}

#' @noRd
fev_ghsl_report <- function(r, epoch, tiles, missing, before, after,
                            reprojected) {
  cli::cli_h1("GHS-POP {epoch}")
  cli::cli_li("{length(tiles)} tile{?s} requested\\
              {if (length(missing)) paste0(', ', length(missing), ' not published')}")
  cli::cli_li("{round(after)} resident{?s} over the area")
  if (isTRUE(reprojected)) {
    drift <- 100 * (after - before) / max(before, 1)
    fn <- if (abs(drift) > 1) cli::cli_alert_warning else cli::cli_alert_info
    fn(
      "Reprojected with {.val sum}, which conserves the headcount. Total went \\
       from {round(before)} to {round(after)} ({sprintf('%+.2f%%', drift)})."
    )
  }
  cli::cli_alert_warning(
    "Residential population. Campsites, trails and roads read as empty."
  )
}
