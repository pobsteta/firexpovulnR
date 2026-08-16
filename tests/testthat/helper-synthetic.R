# Synthetic fixtures for the unit tests.
#
# The brief is explicit: no unit test may touch the network. Everything below
# builds miniature rasters and vectors in memory, deterministically, so tests
# are fast and give the same answer on every machine. Network-dependent
# integration tests live in their own files and are guarded by
# skip_if_offline().
#
# These helpers are also the fixtures for the fireexposuR cross-check in a
# later phase, so they are built to be shared rather than inlined per test.

#' A small raster with a known CRS and resolution
#'
#' @param nrow,ncol Grid size. Kept tiny by default: focal operations in tests
#'   should be verifiable by hand.
#' @param res Cell size in CRS units (metres for the projected defaults).
#' @param crs CRS string or EPSG code.
#' @param values Cell values. Recycled to `nrow * ncol`. `NULL` gives 1..n.
#' @param origin Coordinates of the lower-left corner.
synth_raster <- function(nrow = 10, ncol = 10, res = 25,
                         crs = "EPSG:2154", values = NULL,
                         origin = c(0, 0)) {
  r <- terra::rast(
    nrows = nrow, ncols = ncol,
    xmin = origin[1], xmax = origin[1] + ncol * res,
    ymin = origin[2], ymax = origin[2] + nrow * res,
    crs = crs
  )
  terra::values(r) <- if (is.null(values)) {
    seq_len(terra::ncell(r))
  } else {
    rep_len(values, terra::ncell(r))
  }
  r
}

#' A binary burnable / non-burnable mask with a solid central patch
#'
#' Deterministic on purpose: a focal fraction over a known rectangle can be
#' checked against an analytic value, which is what makes the exposure tests
#' meaningful rather than merely reproducible.
#'
#' @param nrow,ncol Grid size.
#' @param res Cell size in metres.
#' @param patch Integer vector `c(r1, r2, c1, c2)` bounding the burnable
#'   block, in row/column indices (inclusive).
#' @param crs CRS string or EPSG code.
synth_binary <- function(nrow = 20, ncol = 20, res = 25,
                         patch = c(6, 15, 6, 15), crs = "EPSG:2154") {
  r <- synth_raster(nrow, ncol, res, crs, values = 0)
  m <- matrix(0, nrow = nrow, ncol = ncol)
  m[patch[1]:patch[2], patch[3]:patch[4]] <- 1
  terra::values(r) <- as.vector(t(m))
  names(r) <- "burnable"
  r
}

#' A categorical fuel raster using real BD Forêt v2 TFV codes
#'
#' The codes are the ones actually served by the IGN WFS layer
#' `LANDCOVER.FORESTINVENTORY.V2:formation_vegetale`, so a test that maps them
#' exercises the same values production data will carry. They are stored as
#' integer indices with a levels table, which is how terra represents
#' categorical rasters.
#'
#' @param nrow,ncol Grid size.
#' @param res Cell size in metres.
#' @param crs CRS string or EPSG code.
#' @param seed Random seed, for a reproducible arrangement.
synth_fuel <- function(nrow = 20, ncol = 20, res = 25,
                       crs = "EPSG:2154", seed = 1L) {
  codes <- c(
    "FF1G06-06",  # forêt fermée de chênes sempervirents purs (chêne vert)
    "FF2-57-57",  # forêt fermée de pin d'Alep pur
    "FF1G01-01",  # forêt fermée de chênes décidus purs
    "LA4",        # lande ligneuse -- maquis / garrigue
    "LA6",        # formation herbacée
    "FO2"         # forêt ouverte de conifères purs
  )
  r <- synth_raster(nrow, ncol, res, crs, values = 0)
  withr::with_seed(seed, {
    terra::values(r) <- sample(seq_along(codes), terra::ncell(r), replace = TRUE)
  })
  levels(r) <- data.frame(id = seq_along(codes), code_tfv = codes)
  names(r) <- "code_tfv"
  r
}

#' An AOI polygon matching a synthetic raster's extent
#'
#' @param x A `SpatRaster` to take the extent and CRS from.
#' @param shrink Fraction to shrink the box by, so the AOI sits inside the
#'   raster rather than exactly on its edge.
synth_aoi <- function(x = synth_raster(), shrink = 0.1) {
  # as.vector() on a SpatExtent gives a clean unnamed numeric in
  # xmin/xmax/ymin/ymax order. Reading the slots individually would carry
  # names like "xmin.xmin", which st_bbox() does not recognise -- it returns
  # an all-NA bbox instead of erroring.
  v <- as.vector(terra::ext(x))
  dx <- (v[["xmax"]] - v[["xmin"]]) * shrink
  dy <- (v[["ymax"]] - v[["ymin"]]) * shrink
  bb <- sf::st_bbox(
    c(xmin = v[["xmin"]] + dx, ymin = v[["ymin"]] + dy,
      xmax = v[["xmax"]] - dx, ymax = v[["ymax"]] - dy),
    crs = sf::st_crs(terra::crs(x))
  )
  sf::st_as_sf(sf::st_as_sfc(bb))
}

#' A rectangle, as an sf polygon
#' @noRd
synth_rect <- function(xmin, xmax, ymin, ymax, crs = 2154) {
  sf::st_sfc(
    sf::st_polygon(list(cbind(
      c(xmin, xmax, xmax, xmin, xmin),
      c(ymin, ymin, ymax, ymax, ymin)
    ))),
    crs = crs
  )
}

#' A BD Forêt-style polygon layer covering only part of the study area
#'
#' The gap is the point: it is what the auxiliary source has to fill, and what
#' the per-pixel source layer has to attribute correctly. Real TFV codes, so
#' the shipped lookup is genuinely exercised.
#'
#' @param full When TRUE, covers the whole 0-200 square instead of its left
#'   half, for tests that need a primary with no gap.
synth_bdforet <- function(full = FALSE, crs = 2154) {
  if (full) {
    geom <- c(synth_rect(0, 100, 0, 200, crs), synth_rect(100, 200, 0, 200, crs))
  } else {
    geom <- c(synth_rect(0, 50, 0, 200, crs), synth_rect(50, 100, 0, 200, crs))
  }
  sf::st_sf(
    code_tfv = c("FF2-57-57", "FF1G06-06"),  # Aleppo pine, holm oak
    geometry = geom
  )
}

#' A CORINE-style polygon layer covering the whole study area
synth_clc <- function(crs = 2154) {
  sf::st_sf(
    code_18 = c("323", "512"),  # sclerophyllous vegetation, water bodies
    geometry = c(synth_rect(0, 200, 0, 100, crs),
                 synth_rect(0, 200, 100, 200, crs))
  )
}

#' The AOI both synthetic sources share, so their grids match
synth_fuel_aoi <- function(crs = 2154) {
  sf::st_as_sf(synth_rect(0, 200, 0, 200, crs))
}

#' A ready-made pair of fuel sources on a common grid
#'
#' @param res Cell size.
synth_fuel_pair <- function(res = 25) {
  aoi <- synth_fuel_aoi()
  list(
    primary = fev_fuel_source(synth_bdforet(), type = "bdforet_v2",
                              res = res, aoi = aoi, millesime = 2014),
    secondary = fev_fuel_source(synth_clc(), type = "clc_2018",
                                res = res, aoi = aoi, millesime = 2018)
  )
}

#' A categorical SpatRaster carrying given codes, for register tests
synth_class_raster <- function(codes = c("FF2-57-57", "LA4"), nrow = 4, ncol = 4,
                               crs = "EPSG:2154") {
  r <- synth_raster(nrow, ncol, res = 25, crs = crs,
                    values = rep_len(seq_along(codes), nrow * ncol))
  levels(r) <- data.frame(id = seq_along(codes), class = codes)
  names(r) <- "class"
  r
}

#' A dated daily series whose percentile ranks are known by hand
#'
#' Every cell carries the same values, `1..n` in layer order, so the percentile
#' rank of layer `j` against the whole record is exactly `100 * j / n`. That
#' makes the calibration testable against an analytic value rather than merely
#' reproducible — which is the difference between a test and a snapshot.
#'
#' @param n Number of daily layers.
#' @param start First date.
#' @param nrow,ncol Grid size.
#' @param values Optional matrix of values, cells by layers.
synth_danger_series <- function(n = 100, start = "2020-01-01",
                                nrow = 2, ncol = 2, values = NULL) {
  r <- terra::rast(nrows = nrow, ncols = ncol, xmin = 0, xmax = ncol * 25,
                   ymin = 0, ymax = nrow * 25, crs = "EPSG:2154", nlyr = n)
  terra::values(r) <- values %||% matrix(rep(seq_len(n), each = nrow * ncol),
                                         nrow = nrow * ncol)
  terra::time(r) <- seq(as.Date(start), by = "day", length.out = n)
  names(r) <- format(terra::time(r), "d%Y%m%d")
  r
}

#' A single-day weather grid with the layers cffdrs expects
synth_weather_grid <- function(temp = 25, rh = 40, ws = 10, prec = 0,
                               nrow = 3, ncol = 3) {
  r <- terra::rast(nrows = nrow, ncols = ncol, xmin = 0, xmax = ncol * 25,
                   ymin = 0, ymax = nrow * 25, crs = "EPSG:2154", nlyr = 4)
  n <- nrow * ncol
  terra::values(r) <- cbind(rep_len(temp, n), rep_len(rh, n),
                            rep_len(ws, n), rep_len(prec, n))
  names(r) <- c("temp", "rh", "ws", "prec")
  r
}

#' A station weather table with everything cffdrs needs, latitude included
synth_weather_table <- function(n = 5, lat = 43.3,
                                ws = c(10, 12, 15, 20, 11)) {
  data.frame(
    lat = lat, long = 6.4, yr = 2020, mon = 7, day = seq_len(n),
    temp = rep_len(c(25, 28, 30, 31, 29), n),
    rh = rep_len(c(40, 35, 30, 28, 33), n),
    ws = rep_len(ws, n),
    prec = rep_len(c(0, 0, 0, 0, 2), n)
  )
}

#' A minimal fev_stack, for testing methods that need one
synth_stack <- function(...) {
  args <- list(...)
  if (!length(args)) {
    args <- list(exposure = synth_raster(values = seq(0, 1, length.out = 100)))
  }
  do.call(fev_stack, c(args, list(crs_work = 2154)))
}

#' Collect the condition classes a call emits, without letting them escape
#'
#' Several package functions legitimately raise more than one warning at once
#' -- a short reference period is usually also a thin one -- and nested
#' `expect_warning()` cannot assert on two warnings of the same class. Every
#' package warning carries the `fev_warning` class, so they can be caught and
#' inspected as a set instead.
#'
#' @param expr Expression to evaluate.
#' @return Character vector of the first class of each warning raised.
warning_classes <- function(expr) {
  seen <- character()
  withCallingHandlers(
    suppressMessages(force(expr)),
    fev_warning = function(w) {
      seen <<- c(seen, class(w)[1])
      invokeRestart("muffleWarning")
    }
  )
  seen
}
