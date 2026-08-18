# CLCplus Backbone import.
#
# Deliberately NOT a downloader. See the access-route section below: the
# Copernicus Land Monitoring Service serves this product behind EU Login and an
# OAuth2 token exchange, and the brief forbids this package from handling a
# personal token -- the same rule that sent phase 9 to Open-Meteo rather than to
# the CEMS historical product. So this function imports a file you fetched
# yourself, validates it, and records where it came from.
#
# The honest shape of a token-bound source is a good error message, not a
# credential helper.

#' Import CLCplus Backbone (10 m raster land cover)
#'
#' Reads a CLCplus Backbone raster, crops it to an area of interest, turns the
#' product's absence codes into `NA`, and records its provenance. CLCplus is a
#' 10 m raster derived from Sentinel-2 time series, with 11 land cover classes
#' and complete coverage of the EEA area.
#'
#' @section Access route, and why this is not a downloader:
#' The Copernicus Land Monitoring Service serves CLCplus behind EU Login, with
#' an OAuth2 token exchange for programmatic access. This package does not
#' handle personal tokens — the same rule that made [fev_fetch_weather()] use
#' Open-Meteo rather than the CEMS historical product. Download the raster for
#' your area from the CLMS portal or WEkEO, then pass the file here. The route
#' is recorded in the provenance as a manual import, which is what it is.
#'
#' @section What it gains over CORINE, and what it loses:
#' It **gains** the distinction CORINE cannot make. CORINE class 311 puts holm
#' oak and beech in one bucket; CLCplus separates broadleaved deciduous (class
#' 3) from broadleaved evergreen (class 4), and around the Mediterranean the
#' latter *is* the sclerophyll type. It also has no rasterisation slivers,
#' being a raster already, and a two-yearly vintage against CORINE's six.
#'
#' It **loses** the shrub layer. CORINE separates natural grassland (321),
#' moors and heathland (322), sclerophyllous vegetation (323) and transitional
#' woodland-shrub (324). CLCplus collapses the woody ones into class 5. Maquis,
#' heath and post-fire regeneration become one value.
#'
#' This is why it is offered as an auxiliary source beside CORINE rather than as
#' a replacement for it.
#'
#' @section The weak class is the one that burns:
#' Independent validation of the 2018 and 2021 rasters gave overall accuracies
#' of 85.2% and 85.3%, both within 0.5%. Producer's and user's accuracies meet
#' the per-class target of at least 85% for every class **except three**, stated
#' to be regionally lower: 5 (low-growing woody plants), 8 (lichens and mosses)
#' and 9 (non- and sparsely vegetated). The reasons given are fuzzy class
#' definition, limited spectral-temporal separability and sparse reference data.
#'
#' Class 5 is maquis and garrigue. The weakest class of the product is the one
#' that carries fire in the Var, so this function says so on import rather than
#' leaving it in a PDF. Validate it locally before relying on it —
#' [fev_fuel_profile()] is what that validation looks like.
#'
#' **By how much they fall short is not public.** The Algorithm Theoretical
#' Basis Document was read and carries no per-class figure; the validation
#' reports are announced as forthcoming. So the package records *which* classes
#' are weak, not *how* weak, which is the honest limit of what is known.
#'
#' @section Absence is not a class:
#' The raster carries three special values. 253 is the coastal seawater buffer,
#' a real if artificial surface, and it maps to non-fuel. **254 (outside the
#' product area) and 255 (no data) are turned into `NA`**, because they are the
#' absence of a class rather than a class. Giving them a fuel type would assert
#' that unknown ground is non-fuel, which the package refuses everywhere else.
#'
#' Note that these `NA` are *real* gaps, not rasterisation slivers, and
#' [fev_fuel_fill_gaps()] declines to fill them for exactly that reason.
#'
#' @param file Path to a CLCplus Backbone raster (any format GDAL reads).
#'   Required — see the access-route section.
#' @param aoi Optional area of interest to crop to: `sf`, `sfc`, `bbox`,
#'   `SpatVector` or `SpatRaster`. Must carry a CRS.
#' @param year Vintage. One of 2018, 2021, 2023. Recorded in the provenance and
#'   used to pick the source type.
#' @param crs_work EPSG code to return the raster in. Default `2154`. The
#'   product is distributed in EPSG:3035, so a reprojection is the normal case
#'   here; it uses nearest neighbour and is logged.
#' @param quiet Suppress the import report.
#'
#' @return A [fev_source] holding a `SpatRaster` of class codes.
#'
#' @seealso [fev_fuel_source()] to put it on a grid, [fev_fuel_lookup()] for the
#'   correspondence table, [fev_fetch_corine()] for the source it sits beside.
#'
#' @source
#' Codes, labels, resolution, CRS and vintages: European Environment Agency
#' catalogue record for CLCplus Backbone 2023,
#' \doi{10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2}, verified 2026-08-18.
#'
#' Accuracy figures and the three regionally weaker classes: Copernicus Land
#' Monitoring Service, CLCplus Backbone product documentation, read at summary
#' level 2026-08-18. The ATBD was read directly and carries no per-class figure;
#' the Product User Manual was not reachable, and the validation reports are
#' announced as forthcoming.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#' cpl <- fev_fetch_clcplus("CLMS_CLCplus_RASTER_2023_010m_eu.tif",
#'                          aoi = aoi, year = 2023)
#' fuel <- fev_fuel_source(cpl, type = "clcplus_2023", res = 10)
#' }
#'
#' @export
fev_fetch_clcplus <- function(file = NULL,
                              aoi = NULL,
                              year = 2023,
                              crs_work = 2154,
                              quiet = FALSE) {
  valid_years <- c(2018, 2021, 2023)
  if (!year %in% valid_years) {
    fev_abort(c(
      "{.arg year} must be one of {.val {valid_years}}, not {.val {year}}.",
      i = "CLCplus Backbone was three-yearly through 2021 and is two-yearly \\
           from 2023."
    ), .envir = environment())
  }

  if (is.null(file)) {
    fev_abort(c(
      "{.arg file} is required: this package does not download CLCplus.",
      i = "The Copernicus Land Monitoring Service serves it behind EU Login \\
           and an OAuth2 token exchange, and this package does not handle \\
           personal tokens.",
      i = "Download the {.val {year}} raster for your area from the CLMS \\
           portal or WEkEO, then pass its path as {.arg file}.",
      # Naming the tiles is the most useful thing a refusal can do when the
      # fetch has to be done by hand, and an AOI is all it takes.
      i = if (is.null(aoi)) {
        "Pass {.arg aoi} here and this message will name the tiles you need."
      } else {
        paste0("Tiles covering your area: ",
               "{.val {fev_clcplus_tiles(aoi)$tile}} (100 km, EPSG:3035).")
      },
      i = "The manual route is recorded in the provenance, so the analysis \\
           stays reproducible even though the fetch is not automated."
    ), class = "fev_clcplus_manual", .envir = environment())
  }
  if (!file.exists(file)) {
    fev_abort("CLCplus file {.file {file}} does not exist.")
  }

  r <- terra::rast(file)
  if (is.na(terra::crs(r)) || !nzchar(terra::crs(r))) {
    fev_abort(c(
      "The CLCplus raster carries no CRS.",
      i = "The product is distributed in EPSG:3035. A file without a CRS has \\
           been through something lossy; do not assume."
    ), class = "fev_crs_missing")
  }

  if (!is.null(aoi)) {
    r <- fev_clcplus_crop(r, aoi)
  }

  # Absence first, then reprojection: nearest neighbour on a layer that still
  # holds 254 could smear "outside the product area" into a neighbouring cell
  # and make it look like land cover.
  n_absent <- 0
  absent_mask <- terra::app(r, function(v) v %in% .FEV_CLCPLUS_NODATA)
  n_absent <- as.numeric(
    terra::global(absent_mask, "sum", na.rm = TRUE)[1, 1]
  )
  if (isTRUE(n_absent > 0)) {
    r <- terra::subst(r, from = .FEV_CLCPLUS_NODATA,
                      to = rep(NA_integer_, length(.FEV_CLCPLUS_NODATA)))
  }

  # Label BEFORE reprojecting, not after. terra::project() pads the rotated grid
  # with its own nodata sentinel, which surfaces from unique() as 2^32 and
  # overflows the coercion to integer -- so categorising afterwards tried to
  # associate a level with NA and failed. A categorical raster reprojected with
  # "near" carries its levels across untouched, so this order is also the one
  # that needs no repair.
  r <- fev_clcplus_categorise(r)

  reprojected <- FALSE
  target <- paste0("EPSG:", crs_work)
  if (!terra::same.crs(r, target)) {
    if (!quiet) {
      fev_inform(c(
        "Reprojecting CLCplus from its native CRS to {.val {target}}.",
        i = "Nearest neighbour, because the layer is categorical. This \\
             displaces class boundaries by up to half a cell and is logged."
      ), .envir = environment())
    }
    r <- terra::project(r, target, method = "near")
    reprojected <- TRUE
  }
  names(r) <- "code"

  if (!quiet) {
    fev_clcplus_report(r, year, n_absent)
  }

  new_fev_source(
    r,
    dataset      = paste0("clcplus_", year),
    provider     = "Copernicus Land Monitoring Service / EEA (local file)",
    endpoint     = normalizePath(file),
    query        = list(file = basename(file), year = year,
                        clipped_to_aoi = !is.null(aoi),
                        route = "manual download, EU Login required"),
    millesime    = year,
    version      = paste0("CLCplus Backbone ", year),
    import       = "local file",
    reprojected  = reprojected,
    n_absent     = n_absent,
    notes        = paste0(
      "CLMS serves this product behind EU Login and this package does not ",
      "handle personal tokens, so the fetch is manual and recorded as such. ",
      "Codes 254 and 255 converted to NA on import."
    )
  )
}

#' Crop a CLCplus raster to an AOI, in the raster's own CRS
#'
#' The AOI moves, not the raster: reprojecting a categorical layer twice — once
#' to crop, once to the working CRS — would displace boundaries twice.
#'
#' @noRd
fev_clcplus_crop <- function(r, aoi) {
  v <- terra::vect(fev_as_aoi(aoi))
  if (!terra::same.crs(v, r)) {
    v <- terra::project(v, terra::crs(r))
  }
  if (!fev_bbox_overlaps(fev_bbox(v), fev_bbox(r))) {
    fev_abort(c(
      "The area of interest does not overlap the CLCplus raster.",
      i = "Check that you downloaded the tile covering your area."
    ), class = "fev_no_overlap")
  }
  out <- terra::crop(r, terra::ext(v))
  if (terra::ncell(out) == 0) {
    fev_abort(c(
      "The area of interest does not overlap the CLCplus raster.",
      i = "Check that you downloaded the tile covering your area."
    ), class = "fev_no_overlap")
  }
  out
}

#' Attach the class vocabulary, so the raster arrives as what it is
#'
#' Without a level table terra reports these codes as plain numbers, and
#' `fev_fuel_source(register = "auto")` would file them in the CONTINUOUS
#' register — reading class 5 as a measurement of five of something. Labelling
#' at import is what makes the object self-describing.
#'
#' An unrecognised code is reported rather than dropped: if the producers add a
#' class, the package must not swallow it into `NA` in silence.
#'
#' @noRd
fev_clcplus_categorise <- function(r) {
  tab <- fev_fuel_lookup("clcplus")
  known <- as.integer(tab$code)

  present <- terra::unique(r)[[1]]
  # Keep only what can be a class code at all. A file that has been through a
  # lossy conversion can carry a nodata sentinel far outside the byte range, and
  # coercing that to integer overflows to NA -- which terra then refuses to
  # associate with a level, three calls further down.
  present <- present[is.finite(present) & present >= 0 & present <= 255]
  present <- as.integer(present)
  unknown <- setdiff(present, known)
  if (length(unknown)) {
    fev_warn(c(
      "CLCplus raster holds {length(unknown)} code{?s} the shipped lookup \\
       does not know: {.val {unknown}}.",
      i = "They are kept in the layer but no fuel type will match them, so \\
           they will read as {.val NA} downstream.",
      i = "If the producers have added a class, rebuild the table with \\
           {.file data-raw/build_fuel_lookups.R} rather than working around \\
           it here."
    ), class = "fev_clcplus_unknown_code", .envir = environment())
  }

  # The level label is the CODE, not the human name, because that is what the
  # correspondence tables join on -- CORINE rasters carry "311", not
  # "Broad-leaved forest". The readable label lives in the lookup, which is
  # where a reviewer reads it anyway.
  lv <- data.frame(
    id    = known,
    class = tab$code,
    stringsAsFactors = FALSE
  )
  if (length(unknown)) {
    lv <- rbind(lv, data.frame(id = sort(unknown),
                               class = as.character(sort(unknown)),
                               stringsAsFactors = FALSE))
  }
  levels(r) <- lv[order(lv$id), ]
  names(r) <- "code"
  r
}

#' Say what came in, and name the weak class before it is trusted
#' @noRd
fev_clcplus_report <- function(r, year, n_absent) {
  acc <- .FEV_CLCPLUS_ACCURACY
  # Only 2018 and 2021 have a published independent validation in what was read
  # for phase 10. A vintage without one says so rather than borrowing a figure
  # from a neighbouring year.
  key <- as.character(year)
  overall <- if (key %in% names(acc$overall)) acc$overall[[key]] else NULL
  msg <- c(
    "CLCplus Backbone {year}: {terra::ncell(r)} cells at \\
     {signif(terra::res(r)[1], 4)} m."
  )
  if (isTRUE(n_absent > 0)) {
    msg <- c(msg, i = "{n_absent} cell{?s} outside the product area or \\
                       without data, set to {.val NA}. These are real gaps, \\
                       and {.fn fev_fuel_fill_gaps} will not fill them.")
  }
  if (!is.null(overall)) {
    msg <- c(msg, i = "Validated overall accuracy {overall}% \\
                       (+/- {acc$margin_pct}%) for this vintage.")
  } else {
    msg <- c(msg, i = "No independent validation figure was recorded for the \\
                       {year} vintage; 2018 and 2021 came out at 85.2% and \\
                       85.3% overall.")
  }
  # What this file holds is about this file, so it prints every time. The
  # standing caveat below is about the product, so it prints once a session --
  # the same split fev_exposure() makes between its cost check and its radii
  # note. Folding them together would have hidden the cell counts of every
  # import after the first.
  fev_inform(msg, .envir = environment())

  weak <- .FEV_CLCPLUS_ACCURACY$weak_classes
  # Bound to a local first: cli reads a braced expression starting with a dot as
  # an inline style, so `{.FEV_...}` is a syntax error in the glue string.
  target <- .FEV_CLCPLUS_ACCURACY$target_per_class_pct
  fev_once("clcplus_weak_class", fev_warn(c(
    "{length(weak)} classes -- {.val {weak}} -- miss the {target}% per-class \
     accuracy target regionally, and class 5 is the maquis.",
    i = "Class 5 merges what CORINE splits across 322, 323 and 324. The \
         producers attribute the shortfall to fuzzy class definition, limited \
         spectral-temporal separability and sparse reference data.",
    i = "By how much is not public: the ATBD carries no per-class figure and \
         the validation reports are announced as forthcoming.",
    i = "Validate locally before relying on it; the shipped lookup marks every \
         CLCplus vegetation row {.val ambiguous}.",
    i = "Shown once per session; the caveat is in the lookup table every time."
  ), class = "fev_clcplus_weak_class", .envir = environment()))
}

#' Which CLCplus tiles cover an area
#'
#' CLCplus Backbone is distributed as 100 x 100 km cloud-optimised GeoTIFF tiles
#' on the EEA reference grid. Since the download is manual — the product sits
#' behind EU Login — the least this package can do is say exactly which tiles to
#' fetch, rather than leaving you to work it out from a map.
#'
#' @section How the tile code is built:
#' The EEA reference grid codes a cell as its size followed by its lower-left
#' coordinate expressed in units of that size, in EPSG:3035. A 100 km tile whose
#' corner sits at 4 000 000 m east and 2 200 000 m north is therefore `E40N22`.
#' The arithmetic is the documented coding system; **the exact filename prefix
#' CLMS puts in front of it was not verified**, so match on the `E..N..` part
#' when you browse the download list.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#'
#' @return A data frame with one row per tile: `tile`, and the tile's bounds in
#'   EPSG:3035 (`xmin`, `ymin`, `xmax`, `ymax`).
#'
#' @seealso [fev_fetch_clcplus()], which imports a tile once you have it.
#'
#' @source
#' EEA reference grid coding system: European Environment Agency, *About the
#' EEA reference grid*, ETRS89-LAEA (EPSG:3035), false easting 4 321 000 m,
#' false northing 3 210 000 m. Tiling of the product as 100 km cloud-optimised
#' GeoTIFF: CLMS product page for CLCplus Backbone 2023. Both read 2026-08-18.
#'
#' @examples
#' aoi <- sf::st_sf(
#'   geometry = sf::st_sfc(
#'     sf::st_polygon(list(cbind(c(970000, 975000, 975000, 970000, 970000),
#'                               c(6252000, 6252000, 6256000, 6256000, 6252000)))),
#'     crs = 2154
#'   )
#' )
#' fev_clcplus_tiles(aoi)
#'
#' @export
fev_clcplus_tiles <- function(aoi) {
  bb <- fev_bbox(sf::st_transform(fev_as_aoi(aoi), 3035))
  size <- .FEV_EEA_TILE_M

  # floor() on both corners, then every tile between them: an AOI that straddles
  # a tile boundary needs both, and Couchey does exactly that.
  ex <- seq(floor(bb[["xmin"]] / size), floor(bb[["xmax"]] / size))
  ny <- seq(floor(bb[["ymin"]] / size), floor(bb[["ymax"]] / size))
  grid <- expand.grid(e = ex, n = ny, KEEP.OUT.ATTRS = FALSE)

  out <- data.frame(
    tile = sprintf("E%02dN%02d", grid$e, grid$n),
    xmin = grid$e * size,
    ymin = grid$n * size,
    xmax = (grid$e + 1) * size,
    ymax = (grid$n + 1) * size,
    stringsAsFactors = FALSE
  )
  out[order(out$tile), ]
}
