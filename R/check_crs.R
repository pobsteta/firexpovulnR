# Front-of-chain CRS and extent validation.
#
# The rule this enforces is the brief's: work in the projection of the layer
# driving the finest computation -- the primary fuel source. That layer is
# categorical, so reprojecting it forces nearest-neighbour resampling, which
# shifts polygon boundaries and puts artefacts straight into the burnable
# mask that every exposure metric is built on. Auxiliary layers get
# reprojected instead, as late as possible.

#' Validate CRS and extents at the start of a chain
#'
#' Checks that every input carries a projected CRS (not lon/lat), that the
#' working CRS matches the primary fuel source's native CRS, and that the
#' extents actually overlap. Run this before building a [fev_stack()]: each of
#' these failures otherwise surfaces much later as an empty result, which
#' reads like a data problem rather than a CRS problem.
#'
#' @param ... Named spatial objects: `SpatRaster`, `SpatVector`, `sf` or
#'   `sfc`. Names appear in the messages, so use meaningful ones.
#' @param crs_work Integer EPSG code of the intended working CRS. Default
#'   `2154` (RGF93 / Lambert-93), matching BD Forêt v2.
#' @param primary Name of the input that is the primary fuel source, as a
#'   string matching one of `...`. When given, a mismatch between its native
#'   CRS and `crs_work` is reported prominently: reprojecting it is exactly
#'   what the working-CRS rule exists to avoid.
#' @param strict When `TRUE` (default), a missing or geographic CRS is an
#'   error. When `FALSE`, it is a warning and the check returns its findings
#'   so the caller can decide.
#'
#' @return Invisibly, an object of class `fev_crs_check`: a list with
#'   `inputs` (a data frame of one row per input: name, class, CRS label,
#'   projected flag), `crs_work`, `primary`, and `issues` (a character vector
#'   of problems found, empty when clean).
#'
#' @section Choosing `crs_work`:
#' Work in the projection of the layer driving your finest computation.
#'
#' - Primary source = BD Forêt v2 (IGN) → `crs_work = 2154`, the package
#'   default.
#' - Primary source = CORINE, or a multi-country study → `crs_work = 3035`
#'   (ETRS89-LAEA), which is equal-area and therefore comparable across
#'   regions.
#'
#' @examples
#' r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 250,
#'                  ymin = 0, ymax = 250, crs = "EPSG:2154")
#' terra::values(r) <- runif(100)
#' chk <- fev_check_crs(fuel = r, crs_work = 2154, primary = "fuel")
#' chk$issues
#'
#' @export
fev_check_crs <- function(..., crs_work = 2154, primary = NULL, strict = TRUE) {
  inputs <- list(...)
  nms <- names(inputs)

  if (!length(inputs)) {
    fev_abort("Pass at least one named spatial object to check.")
  }
  if (is.null(nms) || any(!nzchar(nms))) {
    fev_abort(c(
      "Every input must be named.",
      i = "Names are what the messages refer to, e.g. \\
           {.code fev_check_crs(fuel = bdforet, aoi = zone)}."
    ))
  }
  if (!is.null(primary) && !primary %in% nms) {
    fev_abort(c(
      "{.arg primary} is {.val {primary}}, which is not among the inputs.",
      i = "Inputs are {.val {nms}}."
    ))
  }

  bad_class <- !vapply(inputs, fev_has_crs_method, logical(1))
  if (any(bad_class)) {
    fev_abort(c(
      "Inputs must be spatial objects.",
      x = "{.val {nms[bad_class]}} {?is/are} \\
           {.cls {vapply(inputs[bad_class], function(z) class(z)[1], character(1))}}."
    ))
  }

  crs_labels <- vapply(inputs, fev_crs_label, character(1))
  projected  <- vapply(inputs, fev_is_projected, logical(1))

  info <- data.frame(
    name      = nms,
    class     = vapply(inputs, function(z) class(z)[1], character(1)),
    crs       = unname(crs_labels),
    projected = unname(projected),
    stringsAsFactors = FALSE
  )

  issues <- character()

  # 1. A missing CRS is unrecoverable: we will not guess one.
  missing_crs <- is.na(projected)
  if (any(missing_crs)) {
    msg <- c(
      "Input{?s} {.val {nms[missing_crs]}} carr{?ies/y} no CRS.",
      i = "Set it explicitly if you know it: \\
           {.code terra::crs(x) <- \"EPSG:2154\"} or \\
           {.code sf::st_crs(x) <- 2154}. The package will not infer one.",
      i = "EFFIS burnt-area shapefiles are a known case: their {.file .prj} \\
           declares {.val GCS_unknown} although the data are WGS84."
    )
    issues <- c(issues, sprintf("no CRS: %s", paste(nms[missing_crs], collapse = ", ")))
    if (strict) fev_abort(msg, class = "fev_crs_missing") else fev_warn(msg)
  }

  # 2. Geographic coordinates break every metric here: focal windows are in
  #    metres, and a degree is not a metre at any latitude we care about.
  geographic <- !is.na(projected) & !projected
  if (any(geographic)) {
    # Two pluralised vectors in one cli string raise "Multiple quantities for
    # pluralization" -- cli cannot tell which one governs {?s}. Keeping one
    # vector per line avoids the ambiguity entirely.
    msg <- c(
      "Input{?s} {.val {nms[geographic]}} {?is/are} in geographic coordinates.",
      x = "Exposure radii and resolutions are expressed in metres; \\
           a degree is not a metre.",
      i = "Found CRS {.val {unique(crs_labels[geographic])}}.",
      i = "Project to {.val {paste0('EPSG:', crs_work)}} first."
    )
    issues <- c(issues, sprintf("geographic CRS: %s",
                                paste(nms[geographic], collapse = ", ")))
    if (strict) fev_abort(msg, class = "fev_crs_geographic") else fev_warn(msg)
  }

  # 3. The one that matters most: crs_work must match the primary source, or
  #    the primary source gets reprojected somewhere downstream.
  if (!is.null(primary)) {
    prim_crs <- fev_crs(inputs[[primary]])
    if (!is.na(prim_crs) && !fev_crs_equal(prim_crs, sf::st_crs(crs_work))) {
      issues <- c(issues, sprintf("crs_work != primary CRS (%s vs %s)",
                                  crs_work, crs_labels[[primary]]))
      fev_warn(c(
        "{.arg crs_work} is {.val {crs_work}} but the primary source \\
         {.val {primary}} is in {.val {crs_labels[[primary]]}}.",
        x = "The primary fuel source is categorical: reprojecting it forces \\
             nearest-neighbour resampling, which shifts polygon boundaries \\
             and puts artefacts in the burnable mask.",
        i = "Either set {.code crs_work = {crs_labels[[primary]]}}, or accept \\
             the reprojection knowingly -- it will be logged in the provenance."
      ), class = "fev_crs_primary_mismatch")
    }
  }

  # 4. Disjoint extents. Compared in WGS84 so that inputs in different CRS can
  #    be compared at all; this is a test, not a data transform, and nothing
  #    reprojected here is returned.
  usable <- !is.na(projected)
  if (sum(usable) >= 2L) {
    boxes <- lapply(nms[usable], function(nm) {
      tryCatch({
        obj <- inputs[[nm]]
        g <- if (inherits(obj, c("SpatRaster", "SpatVector"))) {
          sf::st_as_sfc(sf::st_bbox(
            stats::setNames(as.numeric(fev_bbox(obj)),
                            c("xmin", "ymin", "xmax", "ymax")),
            crs = fev_crs(obj)
          ))
        } else {
          sf::st_as_sfc(sf::st_bbox(obj))
        }
        fev_bbox(sf::st_transform(g, 4326))
      }, error = function(e) NULL)
    })
    names(boxes) <- nms[usable]
    boxes <- boxes[!vapply(boxes, is.null, logical(1))]

    if (length(boxes) >= 2L) {
      pairs <- utils::combn(names(boxes), 2L, simplify = FALSE)
      disjoint <- Filter(function(p) !fev_bbox_overlaps(boxes[[p[1]]], boxes[[p[2]]]),
                         pairs)
      if (length(disjoint)) {
        lab <- vapply(disjoint, paste, character(1), collapse = " / ")
        issues <- c(issues, sprintf("disjoint extents: %s", paste(lab, collapse = "; ")))
        fev_warn(c(
          "Some extents do not overlap: {.val {lab}}.",
          i = "Every downstream intersection will be empty. Check the AOI \\
               and the fetched extents before going further."
        ), class = "fev_extent_disjoint")
      }
    }
  }

  if (!length(issues)) {
    fev_inform("CRS check passed: {length(inputs)} input{?s}, \\
                all projected in {.val {unique(crs_labels)}}.")
  }

  invisible(structure(
    list(inputs = info, crs_work = crs_work, primary = primary, issues = issues),
    class = "fev_crs_check"
  ))
}

#' @export
print.fev_crs_check <- function(x, ...) {
  cli::cli_h1("CRS check")
  cli::cli_text("Working CRS: {.val {x$crs_work}}")
  if (!is.null(x$primary)) {
    cli::cli_text("Primary source: {.val {x$primary}}")
  }
  cli::cli_text("")
  print(x$inputs, row.names = FALSE)
  cli::cli_text("")
  if (!length(x$issues)) {
    cli::cli_alert_success("No issues.")
  } else {
    cli::cli_alert_danger("{length(x$issues)} issue{?s}:")
    cli::cli_ul(x$issues)
  }
  invisible(x)
}
