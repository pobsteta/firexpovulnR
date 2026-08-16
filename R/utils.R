# Internal helpers. Nothing here is exported.

#' Default value for `NULL`
#'
#' Defined locally rather than imported: base R gained `%||%` in 4.4, and
#' importing rlang's version on top of it produces a "replacing previous
#' import" note on some R versions. `DESCRIPTION` allows R >= 4.2, so we
#' cannot rely on the base one being present either.
#'
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Abort with a firexpovulnR condition class
#'
#' Every user-facing failure in the package goes through one of these three
#' helpers, so that (a) messages are formatted by cli consistently and
#' (b) callers can catch package errors by class instead of by message text.
#'
#' `.envir` must default to the *caller's* frame, not to this function's own.
#' cli interpolates `{}` expressions in `.envir`, and its default is
#' `parent.frame()` — evaluated inside cli_abort, that is the body of this
#' wrapper, where none of the caller's variables exist. Without forwarding it
#' explicitly, every interpolated message here fails with "Could not evaluate
#' cli {} expression".
#'
#' @param message A cli-formatted message (character vector).
#' @param class Extra condition subclass, appended after `"fev_error"`.
#' @param ... Passed to the corresponding cli function.
#' @noRd
fev_abort <- function(message, class = NULL, ..., call = rlang::caller_env(),
                      .envir = parent.frame()) {
  cli::cli_abort(message, class = c(class, "fev_error"), ...,
                 call = call, .envir = .envir)
}

#' @noRd
fev_warn <- function(message, class = NULL, ..., .envir = parent.frame()) {
  cli::cli_warn(message, class = c(class, "fev_warning"), ..., .envir = .envir)
}

#' @noRd
fev_inform <- function(message, class = NULL, ..., .envir = parent.frame()) {
  cli::cli_inform(message, class = c(class, "fev_message"), ..., .envir = .envir)
}

#' UTC timestamp in ISO 8601
#'
#' Provenance records must be comparable across machines and time zones, so
#' every timestamp the package writes is UTC and explicitly suffixed `Z`.
#'
#' @noRd
fev_now <- function() {
  format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
}

#' Is this object something we can read a CRS from?
#' @noRd
fev_has_crs_method <- function(x) {
  inherits(x, c("SpatRaster", "SpatVector", "sf", "sfc", "crs", "character"))
}

#' Extract a `sf::crs` object from anything the package accepts
#'
#' `terra` and `sf` do not share a CRS class, and the package accepts inputs
#' from both. Everything is normalised to `sf::st_crs()` because it is the
#' only one of the two that reliably round-trips an EPSG code.
#'
#' @param x A SpatRaster, SpatVector, sf, sfc, crs object, or a CRS string.
#' @return An `sf::crs` object. Its `$input` is `NA` when `x` carries no CRS.
#' @noRd
fev_crs <- function(x) {
  if (inherits(x, "crs")) {
    return(x)
  }
  if (inherits(x, c("SpatRaster", "SpatVector"))) {
    wkt <- terra::crs(x)
    if (!nzchar(wkt)) {
      return(sf::NA_crs_)
    }
    return(sf::st_crs(wkt))
  }
  if (inherits(x, c("sf", "sfc"))) {
    return(sf::st_crs(x))
  }
  if (is.character(x) || is.numeric(x)) {
    return(sf::st_crs(x))
  }
  fev_abort(c(
    "Cannot read a CRS from an object of class {.cls {class(x)}}.",
    i = "Supported: {.cls SpatRaster}, {.cls SpatVector}, {.cls sf}, \\
         {.cls sfc}, {.cls crs}, or an EPSG code."
  ))
}

#' Is this CRS actually usable for reprojection?
#'
#' `is.na(sf::st_crs(x))` is not enough. Writing an object with no CRS to a
#' shapefile makes GDAL substitute
#' `ENGCRS["Undefined Cartesian SRS with unknown unit"]`, so reading it back
#' gives a CRS that is *not* NA but cannot be transformed — `st_transform()`
#' fails with "OGRCreateCoordinateTransformation(): transformation not
#' available". Any file that has been through a shapefile round trip can carry
#' one, which makes this a realistic input, not a corner case.
#'
#' The reliable discriminant is `proj4string`: `NA` for such engineering CRS,
#' populated for real geographic and projected ones.
#'
#' @noRd
fev_crs_usable <- function(x) {
  crs <- fev_crs(x)
  if (is.na(crs)) {
    return(FALSE)
  }
  p4 <- suppressWarnings(crs$proj4string)
  !is.null(p4) && !is.na(p4)
}

#' Does this CRS exist, and is it projected (i.e. not lon/lat)?
#'
#' Returns `NA` when the CRS is missing, so callers can tell "absent" from
#' "present but geographic" — the two cases need different messages.
#'
#' @noRd
fev_is_projected <- function(x) {
  if (!fev_crs_usable(x)) {
    return(NA)
  }
  isTRUE(!sf::st_is_longlat(fev_crs(x)))
}

#' Short human label for a CRS, for messages and provenance
#'
#' Prefers `EPSG:xxxx` when an EPSG code is resolvable, because that is what
#' a reader can act on. Falls back to the CRS name, then to `"unknown"`.
#'
#' @noRd
fev_crs_label <- function(x) {
  crs <- fev_crs(x)
  if (is.na(crs)) {
    return("unknown")
  }
  epsg <- suppressWarnings(crs$epsg)
  if (!is.null(epsg) && !is.na(epsg)) {
    return(paste0("EPSG:", epsg))
  }
  nm <- crs$Name
  if (!is.null(nm) && !is.na(nm) && nzchar(nm)) {
    return(nm)
  }
  "unknown"
}

#' Are two CRS the same?
#'
#' `sf::st_crs()` comparison already handles WKT-vs-EPSG differences; this is
#' a thin wrapper that treats a missing CRS as "not equal to anything",
#' including to another missing CRS. Two objects that both lack a CRS are not
#' known to agree — they are both unknown, which is a different thing.
#'
#' @noRd
fev_crs_equal <- function(x, y) {
  cx <- fev_crs(x)
  cy <- fev_crs(y)
  if (is.na(cx) || is.na(cy)) {
    return(FALSE)
  }
  isTRUE(cx == cy)
}

#' Bounding box as a plain named numeric, in the object's own CRS
#'
#' `SpatExtent$xmin` returns a *named* scalar (`xmin.xmin`), so building the
#' vector naively yields names like `xmin.xmin` that `sf::st_bbox()` does not
#' recognise — it silently returns an all-NA bbox rather than erroring. Going
#' through `as.vector()` and indexing by name avoids that. Note its order is
#' xmin/xmax/ymin/ymax, not the xmin/ymin/xmax/ymax that sf uses.
#'
#' @noRd
fev_bbox <- function(x) {
  if (inherits(x, c("SpatRaster", "SpatVector"))) {
    v <- as.vector(terra::ext(x))
    return(c(xmin = v[["xmin"]], ymin = v[["ymin"]],
             xmax = v[["xmax"]], ymax = v[["ymax"]]))
  }
  bb <- sf::st_bbox(x)
  c(xmin = bb[["xmin"]], ymin = bb[["ymin"]],
    xmax = bb[["xmax"]], ymax = bb[["ymax"]])
}

#' Do two bounding boxes overlap at all?
#'
#' Assumes both are already expressed in the same CRS; the caller is
#' responsible for that, because reprojecting to compare would hide exactly
#' the mistake this check exists to catch.
#'
#' @noRd
fev_bbox_overlaps <- function(a, b) {
  a[["xmin"]] < b[["xmax"]] && b[["xmin"]] < a[["xmax"]] &&
    a[["ymin"]] < b[["ymax"]] && b[["ymin"]] < a[["ymax"]]
}

#' Is this raster entirely NA?
#'
#' Degenerate inputs must produce an explicit package message rather than a
#' cryptic terra failure three calls deeper.
#'
#' @noRd
fev_all_na <- function(x) {
  if (!inherits(x, "SpatRaster")) {
    return(FALSE)
  }
  cnt <- terra::global(x, fun = "notNA")
  all(as.numeric(cnt[[1]]) == 0)
}

#' Level table of a categorical layer, or NULL
#'
#' `terra::levels()` returns a list whose element is `""` — an empty character
#' string, not `NULL` — for a layer that has no categories. Testing it with
#' `is.null()` therefore passes, and the next `nrow()` returns `NULL` rather
#' than erroring, so the mistake surfaces later as an unrelated `&&` failure.
#' Everything in the package that reads categories goes through here.
#'
#' @noRd
fev_cat_levels <- function(r) {
  lv <- terra::levels(r[[1]])[[1]]
  if (!is.data.frame(lv) || !nrow(lv)) {
    return(NULL)
  }
  lv
}

#' Versions of the geospatial stack, for the provenance record
#'
#' A result is only reproducible if you know what produced it. GDAL/GEOS/PROJ
#' versions change resampling and reprojection behaviour, so they belong in
#' the record next to the R package versions.
#'
#' @noRd
fev_session_info <- function() {
  gdal <- tryCatch(as.character(terra::gdal()), error = function(e) NA_character_)
  geos <- tryCatch(as.character(terra::gdal(lib = "geos")), error = function(e) NA_character_)
  proj <- tryCatch(as.character(terra::gdal(lib = "proj")), error = function(e) NA_character_)
  list(
    r_version     = paste(R.version$major, R.version$minor, sep = "."),
    platform      = R.version$platform,
    firexpovulnR  = as.character(utils::packageVersion("firexpovulnR")),
    terra         = as.character(utils::packageVersion("terra")),
    sf            = as.character(utils::packageVersion("sf")),
    gdal          = gdal,
    geos          = geos,
    proj          = proj
  )
}
