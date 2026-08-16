# What every fev_fetch_*() returns.
#
# The brief requires each fetch to carry its provenance metadata: dataset,
# version, vintage, download date, exact request. Attaching those as
# attributes on the sf/SpatRaster would lose them at the first terra
# operation (SpatRaster is S4 and does not carry user attributes through
# arithmetic), so the data and its record are held together in one S3 object
# instead.

#' Create a fetched-source object
#'
#' @param data An `sf` or `SpatRaster`.
#' @param dataset Short dataset identifier.
#' @param ... Fields passed to the source record.
#' @return An object of class `fev_source`.
#' @noRd
new_fev_source <- function(data, dataset, ...) {
  rec <- list(dataset = dataset, ...)
  rec$downloaded_at <- rec$downloaded_at %||% fev_now()
  rec$crs_native <- rec$crs_native %||% fev_crs_label(data)
  rec$n_features <- if (inherits(data, c("sf", "sfc"))) nrow(data) else NA_integer_
  structure(list(data = data, source = rec), class = "fev_source")
}

#' The `fev_source` class, and how to get at its contents
#'
#' `fev_fetch_*()` functions return a `fev_source`: the spatial data together
#' with the provenance record that says where it came from — dataset,
#' provider, endpoint, exact request, vintage and download time. These
#' accessors pull out one or the other.
#'
#' Data and record are held in one S3 object rather than as attributes on the
#' `sf`/`SpatRaster`, because `SpatRaster` is S4 and drops user attributes at
#' the first arithmetic operation — the record would vanish silently on first
#' use.
#'
#' @aliases fev_source
#'
#' @param x A `fev_source`, or — for `fev_data()` — any `fev_layer`: the
#'   objects returned by [fev_fuel_binary()], [fev_fuel_type()],
#'   [fev_fuel_availability()], [fev_fwi_percentile()] and
#'   [fev_danger_index()], which wrap their raster for the same reason.
#' @return `fev_data()` returns the underlying `sf` or `SpatRaster`.
#'   `fev_source_info()` returns the record as a named list.
#'
#' @examples
#' # Offline example: build a source object by hand.
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- seq_len(16)
#' s <- firexpovulnR:::new_fev_source(r, dataset = "demo", provider = "none")
#' fev_source_info(s)$dataset
#'
#' @export
fev_data <- function(x) {
  if (!inherits(x, c("fev_source", "fev_layer"))) {
    fev_abort(c(
      "{.arg x} must be a {.cls fev_source} or {.cls fev_layer}, not \\
       {.cls {class(x)[1]}}.",
      i = if (inherits(x, "fev_fuel_source"))
            "For a {.cls fev_fuel_source}, use {.fn fev_fuel_categorical} or \\
             {.fn fev_fuel_continuous}: it holds two registers, so there is no \\
             single {.field data} to return."
    ))
  }
  x$data
}

#' @rdname fev_data
#' @export
fev_source_info <- function(x) {
  if (!inherits(x, "fev_source")) {
    fev_abort("{.arg x} must be a {.cls fev_source}, not {.cls {class(x)[1]}}.")
  }
  x$source
}

#' @export
print.fev_source <- function(x, ...) {
  s <- x$source
  cli::cli_h1("fev_source: {s$dataset}")
  cli::cli_li("Provider: {s$provider %||% 'unknown'}")
  cli::cli_li("Endpoint: {s$endpoint %||% 'n/a'}")

  # The vintage is printed even when absent, and named as absent. BD Forêt v2
  # does not serve it, and a silently missing field is how a temporal-bias
  # check ends up never running.
  mil <- s$millesime
  if (is.null(mil) || all(is.na(mil))) {
    cli::cli_li(cli::col_yellow("Millesime: unknown (not served by this source)"))
  } else {
    cli::cli_li("Millesime: {.val {mil}}")
  }

  cli::cli_li("Downloaded: {s$downloaded_at}")
  cli::cli_li("Native CRS: {s$crs_native}")
  if (!is.na(s$n_features)) {
    cli::cli_li("Features: {.val {s$n_features}}")
  }
  if (!is.null(s$period_returned)) {
    cli::cli_li("Period returned: {.val {s$period_returned}}")
  }
  invisible(x)
}

#' @export
plot.fev_source <- function(x, ...) {
  d <- x$data
  if (inherits(d, "SpatRaster")) {
    terra::plot(d, main = x$source$dataset, ...)
  } else {
    plot(sf::st_geometry(d), main = x$source$dataset, ...)
  }
  invisible(x)
}

#' Normalise an AOI to an sf polygon in a given CRS
#'
#' Accepts the shapes users actually have: an sf/sfc, a SpatVector, a bbox, or
#' a raster to take the extent from. Everything else is refused with a message
#' naming what is accepted, rather than failing inside terra three calls down.
#'
#' @noRd
fev_as_aoi <- function(aoi, crs = NULL) {
  if (is.null(aoi)) {
    fev_abort("{.arg aoi} is required: it defines what to download.")
  }
  out <- if (inherits(aoi, "sf")) {
    sf::st_geometry(aoi)
  } else if (inherits(aoi, "sfc")) {
    aoi
  } else if (inherits(aoi, "bbox")) {
    sf::st_as_sfc(aoi)
  } else if (inherits(aoi, "SpatVector")) {
    sf::st_as_sfc(sf::st_as_sf(aoi))
  } else if (inherits(aoi, "SpatRaster")) {
    bb <- fev_bbox(aoi)
    sf::st_as_sfc(sf::st_bbox(bb, crs = sf::st_crs(terra::crs(aoi))))
  } else {
    fev_abort(c(
      "{.arg aoi} must be a spatial object.",
      x = "Got {.cls {class(aoi)[1]}}.",
      i = "Accepted: {.cls sf}, {.cls sfc}, {.cls bbox}, {.cls SpatVector}, \\
           {.cls SpatRaster}."
    ))
  }

  if (!fev_crs_usable(out)) {
    fev_abort(c(
      "{.arg aoi} carries no usable CRS.",
      i = "Set it explicitly, e.g. {.code sf::st_crs(aoi) <- 2154}. \\
           The package will not guess one."
    ))
  }
  if (!is.null(crs)) {
    out <- sf::st_transform(out, crs)
  }
  sf::st_as_sf(out)
}
