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

#' A minimal fev_stack, for testing methods that need one
synth_stack <- function(...) {
  args <- list(...)
  if (!length(args)) {
    args <- list(exposure = synth_raster(values = seq(0, 1, length.out = 100)))
  }
  do.call(fev_stack, c(args, list(crs_work = 2154)))
}
