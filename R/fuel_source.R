# The fuel source abstraction.
#
# Deliberately NOT built around a nomenclature of classes. A fuel source holds
# two coexisting registers:
#
#   categorical -- a class code per pixel (BD Forêt TFV, CORINE level 3, or a
#                  user vocabulary), plus optionally the per-pixel record of
#                  which dataset that code came from;
#   continuous  -- named numeric metrics per pixel (fuel load by stratum,
#                  bulk density, crown base height, fuel strata gap).
#
# Today only the categorical register has producers, because BD Forêt and
# CORINE are categorical. LiDAR HD is continuous, and if this object assumed
# categories the whole module would have to be rewritten to accept it. Every
# downstream function declares which register it consumes and refuses politely
# when that register is empty, rather than failing inside terra.

#' Build a fuel source
#'
#' Turns a fetched land cover dataset into a fuel source on a defined grid: a
#' categorical class layer, the correspondence table that gives those classes
#' fire meaning, and the provenance to say where they came from and for which
#' vintage.
#'
#' @section The two registers:
#' A fuel source carries a **categorical** register (a class code per pixel)
#' and a **continuous** register (named numeric metrics per pixel). BD Forêt
#' and CORINE populate the first. The second exists so that continuous fuel
#' descriptions — LiDAR-derived load, bulk density, crown base height — can be
#' carried by the same object without the abstraction assuming everything is a
#' class. Use [fev_fuel_registers()] to see which are populated.
#'
#' @section On the target resolution:
#' `res` defaults to 25 m, and the floor below which it buys nothing is a
#' property of the source, not a constant: BD Forêt v2's minimum mapped width is
#' 20 m, ESA WorldCover's is 10 m. Below its source's own width a grid
#' resolves boundaries the data never had. At 100 m the advantage over CORINE —
#' whose native raster is 100 m — disappears entirely. Between those, the cost
#' is quadratic in memory and in focal-window time.
#'
#' One resolution earns its cost for a reason unrelated to detail. `fev_exposure()`
#' requires `res <= radius / 3`, so the 30 m radiant-heat radius is **refused**
#' at 25 m and becomes computable at 10 m — exactly, since 10 = 30 / 3. A 10 m
#' source is therefore the only way to reach that scale at all, and it costs
#' about 39 times the focal work of 25 m: 6.25 times the cells, each with 6.25
#' times the window.
#'
#' @section On the vintage:
#' For `type = "bdforet_v2"` the vintage is **required**. BD Forêt v2 was built
#' department by department between 2007 and 2018, so a stand mapped in 2008
#' may have burnt in 2010 and be in another state entirely; without the vintage
#' the temporal-bias check in `fev_validate()` cannot run at all. The WFS does
#' not serve it and no per-department table was found (phase 2 report, section
#' 2 bis), so it has to come from you. Passing `millesime = NA` explicitly is
#' accepted — it records "we looked and do not know", which is honest — but it
#' is not the default, so that the check is never skipped by accident.
#'
#' @section Rasterising polygons:
#' `touches = FALSE` (the default) assigns a cell to a polygon only when the
#' cell centre falls inside it, which is the standard convention and keeps
#' burnable area unbiased. It does drop polygons narrower than the cell — at
#' 25 m that means some of BD Forêt's 20 m minimum-width features. `touches =
#' TRUE` keeps them, at the cost of inflating every class's area and letting
#' thin non-burnable features (a road strip) claim whole cells. Neither is
#' free; the choice is recorded in the provenance.
#'
#' @param x A [fev_source] from [fev_fetch_bdforet()] or [fev_fetch_corine()],
#'   or a plain `sf`, `SpatVector` or `SpatRaster`.
#' @param type Source type: `"bdforet_v2"`, `"clc_2018"` (and the other CORINE
#'   vintages), `"worldcover_2021"` (and 2020), `"lidarhd"` (phase 8, not
#'   implemented) or `"custom"`.
#' @param res Target cell size in CRS units, metres for the projected
#'   defaults. See the resolution section.
#' @param crs_work EPSG code of the working CRS. Default `2154`, BD Forêt's
#'   native CRS. A categorical source is **not** reprojected silently: when
#'   `crs_work` differs from the data's CRS the reprojection is warned about
#'   and logged, because nearest-neighbour on a class layer displaces
#'   boundaries.
#' @param field Name of the class column. Defaults to `code_tfv` for BD Forêt
#'   and to the `code_XX` column CORINE serves for its vintage.
#' @param lookup Correspondence table. Defaults to the shipped one for `type`;
#'   pass your own from [fev_fuel_lookup()] to override it.
#' @param millesime Vintage of the data. See the vintage section. `NULL` takes
#'   it from `x`'s provenance record when there is one.
#' @param aoi Optional area of interest to crop the grid to.
#' @param touches Rasterisation rule for polygons. See the section above.
#' @param register For `type = "custom"` with a `SpatRaster`: which register
#'   the layers populate. `"auto"` reads a categorical raster as categorical
#'   and a plain numeric one as continuous.
#' @param units Named character vector of units for continuous layers, e.g.
#'   `c(cbd = "kg/m3")`. Recorded in the provenance and printed.
#' @param provenance Provenance record to carry forward. Taken from `x` when
#'   `NULL`.
#'
#' @return An object of class `fev_fuel_source`.
#'
#' @seealso [fev_fuel_merge()] to combine a primary and an auxiliary source,
#'   [fev_fuel_binary()], [fev_fuel_type()] and [fev_fuel_availability()] for
#'   the layers derived from one.
#'
#' @examples
#' # A miniature BD Forêt-style polygon layer.
#' poly <- sf::st_sf(
#'   code_tfv = c("FF2-57-57", "LA4"),
#'   geometry = sf::st_sfc(
#'     sf::st_polygon(list(cbind(c(0, 100, 100, 0, 0), c(0, 0, 100, 100, 0)))),
#'     sf::st_polygon(list(cbind(c(100, 200, 200, 100, 100), c(0, 0, 100, 100, 0)))),
#'     crs = 2154
#'   )
#' )
#' fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 25, millesime = 2014)
#' fuel
#'
#' @export
fev_fuel_source <- function(x,
                            type = c("bdforet_v2", "clc_2018",
                                     "worldcover_2021", "lidarhd", "custom"),
                            res = 25,
                            crs_work = 2154,
                            field = NULL,
                            lookup = NULL,
                            millesime = NULL,
                            aoi = NULL,
                            touches = FALSE,
                            register = c("auto", "categorical", "continuous"),
                            units = NULL,
                            provenance = NULL) {
  type <- fev_fuel_match_type(type)
  register <- match.arg(register)

  if (identical(type, "lidarhd")) {
    fev_abort(c(
      "{.val lidarhd} is a phase 8 source and is not implemented.",
      i = "It will populate the {.strong continuous} register -- fuel load by \\
           stratum, bulk density, crown base height -- through \\
           {.code fev_fetch_lidarhd()} and {.code fev_fuel_lidar()}.",
      i = "The register already exists on this object, so nothing here will \\
           need rewriting when it lands."
    ), class = "fev_not_implemented")
  }

  fev_check_res(res, type)

  # Provenance and vintage may both travel with a fetched source. Read them
  # before unwrapping, and let explicit arguments win.
  rec <- if (inherits(x, "fev_source")) x$source else NULL
  data <- if (inherits(x, "fev_source")) x$data else x
  millesime_explicit <- !is.null(millesime)
  millesime <- millesime %||% rec$millesime %||% NA
  fev_check_millesime(type, millesime, millesime_explicit)

  prov <- provenance %||% fev_prov_new(crs_work = crs_work)
  if (!is.null(rec)) {
    prov <- fev_prov_add_source(
      prov,
      dataset    = rec$dataset %||% type,
      provider   = rec$provider %||% NA_character_,
      endpoint   = rec$endpoint %||% NA_character_,
      query      = rec$query,
      millesime  = millesime,
      version    = rec$version %||% NA_character_,
      crs_native = rec$crs_native %||% NA_character_
    )
  } else {
    prov <- fev_prov_add_source(
      prov, dataset = type, provider = "user",
      millesime = millesime, crs_native = fev_crs_label(data)
    )
  }

  lookup <- lookup %||% fev_fuel_default_lookup(type)

  built <- if (inherits(data, "SpatRaster")) {
    fev_fuel_from_raster(data, type, register, crs_work, aoi, units)
  } else {
    fev_fuel_from_vector(data, type, field, res, crs_work, aoi, touches)
  }

  prov <- fev_prov_add_step(
    prov,
    fun = "fev_fuel_source",
    params = list(type = type, res = res, crs_work = crs_work,
                  field = built$field, touches = touches,
                  millesime = millesime, register = built$register,
                  n_classes = built$n_classes,
                  lookup_rows = if (is.null(lookup)) 0L else nrow(lookup)),
    notes = built$notes
  )

  new_fev_fuel_source(
    categorical = built$categorical,
    continuous  = built$continuous,
    units       = units,
    lookup      = lookup,
    type        = type,
    millesime   = millesime,
    provenance  = prov
  )
}

#' @noRd
new_fev_fuel_source <- function(categorical = NULL, continuous = NULL,
                                units = NULL, lookup = NULL, type = "custom",
                                millesime = NA, provenance = NULL) {
  structure(
    list(
      categorical = categorical,
      continuous  = continuous,
      units       = units,
      lookup      = lookup,
      type        = type,
      millesime   = millesime,
      provenance  = provenance
    ),
    class = "fev_fuel_source"
  )
}

# Accepted type strings. CORINE's fuel semantics do not change with the
# vintage, so every clc_* year is a valid type and they all read the same
# lookup.
.FEV_FUEL_TYPES <- c("bdforet_v2",
                     "clc", paste0("clc_", c(1990, 2000, 2006, 2012, 2018)),
                     paste0("worldcover_", c(2020, 2021)),
                     "lidarhd", "custom")

#' @noRd
fev_fuel_match_type <- function(type) {
  type <- type[1]
  if (!type %in% .FEV_FUEL_TYPES) {
    known <- .FEV_FUEL_TYPES
    fev_abort(c(
      "Unknown fuel source type {.val {type}}.",
      i = "Accepted: {.val {known}}."
    ))
  }
  type
}

#' @noRd
fev_fuel_default_lookup <- function(type) {
  if (identical(type, "custom")) {
    return(NULL)
  }
  fev_fuel_lookup(type)
}

#' Refuse a resolution that makes no sense, and say why for the ones that do
#'
#' The floor is not a constant: it is the minimum mapped width of the source in
#' hand, read from `.FEV_FUEL_MMU`. BD For\u00eat v2 resolves 20 m, ESA WorldCover
#' 10 m, and telling a WorldCover user that 10 m is finer than BD For\u00eat's
#' detail would be both wrong and confusing.
#'
#' @noRd
fev_check_res <- function(res, type = "bdforet_v2") {
  if (!is.numeric(res) || length(res) != 1L || is.na(res) || res <= 0) {
    fev_abort("{.arg res} must be a single positive number, in CRS units.")
  }
  spec <- .FEV_FUEL_MMU[[type]]
  floor_m <- if (is.null(spec)) NA_real_ else spec$min_width_m
  # Only for a source the grid is chosen for. An auxiliary source has to be
  # rasterised onto whatever grid the primary picked, so a cell finer than its
  # own width is required of it, not wasted on it.
  drives <- !is.null(spec) && isTRUE(spec$grid_driver)

  if (drives && !is.na(floor_m) && res < floor_m) {
    fev_inform(c(
      "{.arg res} = {.val {res}} m is finer than {.val {type}}'s own detail.",
      i = "Its minimum mapped width is {.val {floor_m}} m, so a finer grid \\
           resolves boundaries the data never had. Cost is quadratic."
    ), class = "fev_res_too_fine", .envir = environment())
  }
  if (res >= 100) {
    fev_warn(c(
      "{.arg res} = {.val {res}} m cancels the advantage of a fine source \\
       over CORINE.",
      i = "CORINE's native raster is 100 m. At this cell size the finer \\
           minimum mapping unit buys nothing."
    ), class = "fev_res_too_coarse")
  }
  invisible(TRUE)
}

#' Enforce the vintage rule, which differs by source
#' @noRd
fev_check_millesime <- function(type, millesime, explicit) {
  if (!identical(type, "bdforet_v2")) {
    return(invisible(TRUE))
  }
  if (!all(is.na(millesime))) {
    return(invisible(TRUE))
  }
  if (explicit) {
    fev_warn(c(
      "BD For\u00eat v2 vintage recorded as unknown, on your explicit request.",
      i = "The temporal-bias check in {.code fev_validate()} will not be able \\
           to run: burnt areas cannot be compared to a vintage that is not \\
           there.",
      i = "This is recorded in the provenance as an absent value, not a \\
           guessed one."
    ), class = "fev_millesime_missing")
    return(invisible(TRUE))
  }
  fev_abort(c(
    "The BD For\u00eat v2 vintage is required and was not supplied.",
    i = "BD For\u00eat v2 was built department by department between 2007 and \\
         2018, so a national assembly is not a snapshot. Without the vintage, \\
         a stand that burnt after it was mapped cannot be detected.",
    i = "Pass {.code millesime = 2014} (the year for your department), or \\
         {.code millesime = NA} to state explicitly that it is unknown.",
    i = "{.fn fev_bdforet_millesime} derives it from the BD ORTHO survey \\
         dates, which is how IGN defines the validity date of BD For\\u00eat v2."
  ), class = "fev_millesime_required")
}

#' Rasterise a polygon layer onto an aligned grid
#' @noRd
fev_fuel_from_vector <- function(data, type, field, res, crs_work, aoi, touches) {
  if (inherits(data, "SpatVector")) {
    data <- sf::st_as_sf(data)
  }
  if (!inherits(data, "sf")) {
    fev_abort(c(
      "Cannot build a fuel source from {.cls {class(data)[1]}}.",
      i = "Accepted: {.cls fev_source}, {.cls sf}, {.cls SpatVector}, \\
           {.cls SpatRaster}."
    ))
  }
  if (!nrow(data)) {
    fev_abort(c(
      "The source has no features.",
      i = "Usually an AOI outside the dataset's coverage -- BD For\u00eat is \\
           metropolitan France only."
    ), class = "fev_empty_result")
  }
  if (!fev_crs_usable(data)) {
    fev_abort(c(
      "The source carries no usable CRS.",
      i = "Set it explicitly, e.g. {.code sf::st_crs(x) <- 2154}. The package \\
           will not guess one."
    ))
  }

  field <- field %||% fev_fuel_default_field(data, type)
  if (!field %in% names(data)) {
    fev_abort(c(
      "No column {.field {field}} in the source.",
      i = "Available: {.field {setdiff(names(data), attr(data, 'sf_column'))}}.",
      i = "Pass {.arg field} to name the class column."
    ))
  }

  notes <- NULL
  if (!fev_crs_equal(data, sf::st_crs(crs_work))) {
    fev_warn(c(
      "Reprojecting a categorical source from {.val {fev_crs_label(data)}} to \\
       {.val {paste0('EPSG:', crs_work)}}.",
      i = "Reprojecting before rasterising avoids nearest-neighbour on the \\
           class grid, but it does move polygon boundaries. Prefer setting \\
           {.arg crs_work} to the primary source's native CRS."
    ), class = "fev_categorical_reprojected")
    data <- sf::st_transform(data, crs_work)
    notes <- sprintf("reprojected to EPSG:%s before rasterising", crs_work)
  }

  if (!is.null(aoi)) {
    aoi <- fev_as_aoi(aoi, crs = crs_work)
    if (!fev_bbox_overlaps(fev_bbox(data), fev_bbox(aoi))) {
      fev_abort(c(
        "The AOI and the source do not overlap.",
        i = "Source bbox: {.val {round(fev_bbox(data))}}.",
        i = "AOI bbox: {.val {round(fev_bbox(aoi))}}.",
        i = "Both are in {.val {paste0('EPSG:', crs_work)}}, so this is a \\
             location mismatch, not a CRS one."
      ), class = "fev_disjoint_extent")
    }
  }

  template <- fev_fuel_template(aoi %||% data, res, crs_work)
  v <- terra::vect(data[, field])
  r <- terra::rasterize(v, template, field = field, touches = touches)
  r <- fev_normalise_categorical(r)

  if (fev_all_na(r)) {
    fev_warn(c(
      "The rasterised fuel layer is entirely {.val NA}.",
      i = "At {.val {res}} m with {.code touches = FALSE}, features narrower \\
           than one cell fall between cell centres. Try a finer {.arg res} or \\
           {.code touches = TRUE}."
    ), class = "fev_all_na")
  }

  list(categorical = r, continuous = NULL, field = field,
       register = "categorical", notes = notes,
       n_classes = nrow(fev_cat_levels(r)))
}

#' Take a raster as-is into one of the two registers
#' @noRd
fev_fuel_from_raster <- function(data, type, register, crs_work, aoi, units) {
  if (!fev_crs_usable(data)) {
    fev_abort("The raster carries no usable CRS. Set one; the package will \\
               not guess.")
  }
  is_cat <- !is.null(fev_cat_levels(data))
  register <- if (identical(register, "auto")) {
    if (is_cat) "categorical" else "continuous"
  } else {
    register
  }

  if (!fev_crs_equal(data, sf::st_crs(crs_work))) {
    method <- if (identical(register, "categorical")) "near" else "bilinear"
    fev_warn(c(
      "Reprojecting the fuel raster from {.val {fev_crs_label(data)}} to \\
       {.val {paste0('EPSG:', crs_work)}} with {.val {method}}.",
      i = "On a categorical layer this displaces class boundaries. It is \\
           recorded in the provenance."
    ), class = "fev_categorical_reprojected")
    data <- terra::project(data, paste0("EPSG:", crs_work), method = method)
  }

  if (!is.null(aoi)) {
    aoi <- fev_as_aoi(aoi, crs = crs_work)
    data <- terra::crop(data, terra::vect(aoi), mask = TRUE)
  }

  if (identical(register, "categorical")) {
    data <- fev_normalise_categorical(data)
    return(list(categorical = data, continuous = NULL, field = names(data)[1],
                register = register, notes = NULL,
                n_classes = nrow(fev_cat_levels(data))))
  }

  if (!is.null(units) && !all(names(data) %in% names(units))) {
    fev_warn(c(
      "{.arg units} does not cover every continuous layer.",
      i = "Missing for {.val {setdiff(names(data), names(units))}}. An \\
           unlabelled metric is not reproducible."
    ))
  }
  list(categorical = NULL, continuous = data, field = NA_character_,
       register = register, notes = NULL, n_classes = NA_integer_)
}

#' Which class column does this source normally carry?
#' @noRd
fev_fuel_default_field <- function(data, type) {
  if (identical(type, "bdforet_v2")) {
    return("code_tfv")
  }
  if (startsWith(type, "clc")) {
    # CORINE's class column is vintage-specific (code_18, code_12, ...). Read
    # it off the data rather than deriving it from the type, so a layer fetched
    # for one vintage and labelled another still works.
    hit <- grep("^code_[0-9]{2}$", names(data), value = TRUE)
    if (length(hit)) {
      return(hit[1])
    }
    return("code_18")
  }
  fev_abort(c(
    "No default class column for type {.val {type}}.",
    i = "Pass {.arg field} to name it."
  ))
}

#' One shape for every categorical layer: values are ids, levels are `class`
#'
#' terra names the level column after the rasterised field, so the same layer
#' arrives as `code_tfv` from BD Forêt and `code_18` from CORINE. Downstream
#' code would then have to know its source to read its own levels. Normalising
#' here means it does not.
#'
#' @noRd
fev_normalise_categorical <- function(r) {
  r <- r[[1]]
  lv <- fev_cat_levels(r)
  if (is.null(lv)) {
    fev_abort(c(
      "The layer is not categorical: it carries no class table.",
      i = "Rasterise with a character field, or set \\
           {.code levels(x) <- data.frame(id = , class = )}."
    ))
  }
  names(lv) <- c("id", "class")
  lv$class <- as.character(lv$class)
  levels(r) <- lv
  names(r) <- "class"
  r
}

#' A grid aligned on multiples of `res`
#'
#' Snapping the extent outward to multiples of the cell size means two AOIs
#' processed separately land on the same grid, so their outputs can be compared
#' or mosaicked without resampling. An unaligned grid is a resampling step
#' waiting to happen.
#'
#' @noRd
fev_fuel_template <- function(x, res, crs_work) {
  bb <- fev_bbox(x)
  terra::rast(
    xmin = floor(bb[["xmin"]] / res) * res,
    xmax = ceiling(bb[["xmax"]] / res) * res,
    ymin = floor(bb[["ymin"]] / res) * res,
    ymax = ceiling(bb[["ymax"]] / res) * res,
    resolution = res,
    crs = paste0("EPSG:", crs_work)
  )
}

#' Which registers of a fuel source are populated
#'
#' A fuel source carries a categorical register (class codes) and a continuous
#' register (numeric metrics per pixel). Downstream functions declare which one
#' they consume: [fev_fuel_binary()], [fev_fuel_type()] and
#' [fev_fuel_availability()] all read the categorical register.
#'
#' @param x A `fev_fuel_source`.
#' @return `fev_fuel_registers()` returns a character vector of the populated
#'   registers. `fev_fuel_categorical()` and `fev_fuel_continuous()` return the
#'   corresponding `SpatRaster`, or `NULL`.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- rep(1:2, 8)
#' levels(r) <- data.frame(id = 1:2, class = c("LA4", "LA6"))
#' f <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
#' fev_fuel_registers(f)
#'
#' @export
fev_fuel_registers <- function(x) {
  fev_check_fuel_source(x)
  c(if (!is.null(x$categorical)) "categorical",
    if (!is.null(x$continuous)) "continuous")
}

#' @rdname fev_fuel_registers
#' @export
fev_fuel_categorical <- function(x) {
  fev_check_fuel_source(x)
  x$categorical
}

#' @rdname fev_fuel_registers
#' @export
fev_fuel_continuous <- function(x) {
  fev_check_fuel_source(x)
  x$continuous
}

#' @noRd
fev_check_fuel_source <- function(x, arg = "x") {
  if (!inherits(x, "fev_fuel_source")) {
    fev_abort(c(
      "{.arg {arg}} must be a {.cls fev_fuel_source}, not \\
       {.cls {class(x)[1]}}.",
      i = "Build one with {.fn fev_fuel_source}."
    ), .envir = environment())
  }
  invisible(TRUE)
}

#' Refuse politely when the register a function needs is empty
#' @noRd
fev_fuel_require_register <- function(x, register, fn) {
  fev_check_fuel_source(x)
  if (!is.null(x[[register]])) {
    return(invisible(TRUE))
  }
  have <- fev_fuel_registers(x)
  fev_abort(c(
    "{.fn {fn}} consumes the {.strong {register}} register, which is empty.",
    x = if (length(have)) "This source populates: {.val {have}}."
        else "This source populates no register at all.",
    i = if (identical(register, "continuous"))
          "Continuous metrics come from LiDAR (phase 8) or from a custom \\
           raster built with {.code register = \"continuous\"}."
        else
          "Build a categorical source from BD For\u00eat or CORINE with \\
           {.fn fev_fuel_source}."
  ), class = "fev_missing_register", .envir = environment())
}

#' One-line vintage, whether there is one of them or one per component
#'
#' A merged source has a vintage per component by construction — CORINE has a
#' common European date, BD Forêt does not — and collapsing them to "2014 and
#' 2018" loses which is which, which is precisely what the temporal-bias check
#' needs.
#'
#' @noRd
fev_format_millesime <- function(mil) {
  if (is.null(mil) || all(is.na(unlist(mil)))) {
    return(NA_character_)
  }
  if (is.null(names(mil))) {
    return(paste(unlist(mil), collapse = ", "))
  }
  parts <- vapply(names(mil), function(n) {
    v <- mil[[n]]
    paste0(n, " ", if (all(is.na(v))) "unknown" else paste(v, collapse = "/"))
  }, character(1))
  paste(parts, collapse = ", ")
}

#' @export
print.fev_fuel_source <- function(x, ...) {
  cli::cli_h1("fev_fuel_source: {x$type}")

  mil <- fev_format_millesime(x$millesime)
  if (is.na(mil)) {
    cli::cli_li(cli::col_yellow("Millesime: unknown (recorded as absent)"))
  } else {
    cli::cli_li("Millesime: {mil}")
  }

  regs <- fev_fuel_registers(x)
  cli::cli_li("Registers: {.val {if (length(regs)) regs else 'none'}}")

  if (!is.null(x$categorical)) {
    r <- x$categorical
    lv <- terra::levels(r[[1]])[[1]]
    cli::cli_li("Categorical: {terra::nrow(r)} x {terra::ncol(r)} cells at \\
                 {.val {signif(terra::res(r)[1], 6)}} {.field {fev_crs_label(r)}}, \\
                 {nrow(lv)} class{?/es}")
    if ("source" %in% names(r)) {
      slv <- terra::levels(r[["source"]])[[1]]
      cli::cli_li("Per-pixel source: {.val {slv[[2]]}}")
    }
  }
  if (!is.null(x$continuous)) {
    u <- x$units
    lab <- vapply(names(x$continuous), function(n) {
      if (!is.null(u) && n %in% names(u)) paste0(n, " (", u[[n]], ")") else n
    }, character(1))
    cli::cli_li("Continuous: {.val {unname(lab)}}")
  }

  if (!is.null(x$lookup)) {
    amb <- sum(x$lookup$confidence %in% "ambiguous", na.rm = TRUE)
    cli::cli_li("Lookup: {nrow(x$lookup)} row{?s}, {amb} flagged ambiguous")
  }

  prov <- x$provenance
  if (!is.null(prov)) {
    cli::cli_text("")
    cli::cli_text("{.field Provenance}: {length(prov$sources)} source{?s}, \\
                   {length(prov$steps)} step{?s}.")
  }
  invisible(x)
}

#' @export
summary.fev_fuel_source <- function(object, ...) {
  fev_check_fuel_source(object)
  if (is.null(object$categorical)) {
    return(structure(list(type = object$type, classes = NULL),
                     class = "summary.fev_fuel_source"))
  }
  r <- object$categorical[[1]]
  lv <- terra::levels(r)[[1]]
  freq <- terra::freq(r)
  # terra::freq() on a categorical layer returns the label in `value`, so join
  # on the label rather than on the id.
  counts <- stats::setNames(freq$count, as.character(freq$value))
  n <- sum(freq$count)
  out <- data.frame(
    class = lv$class,
    cells = as.integer(counts[lv$class]),
    stringsAsFactors = FALSE
  )
  out$cells[is.na(out$cells)] <- 0L
  out$pct <- round(100 * out$cells / n, 2)
  if (!is.null(object$lookup)) {
    m <- match(out$class, object$lookup$code)
    out$fuel_type <- object$lookup$fuel_type[m]
    out$burnable <- object$lookup$burnable[m]
  }
  out <- out[order(-out$cells), ]
  structure(
    list(type = object$type, millesime = object$millesime,
         classes = out, unmatched = sum(is.na(out$fuel_type))),
    class = "summary.fev_fuel_source"
  )
}

#' @export
print.summary.fev_fuel_source <- function(x, ...) {
  cli::cli_h1("fev_fuel_source summary: {x$type}")
  if (is.null(x$classes)) {
    cli::cli_alert_info("No categorical register to summarise.")
    return(invisible(x))
  }
  print(x$classes, row.names = FALSE)
  if (isTRUE(x$unmatched > 0)) {
    cli::cli_alert_warning(
      "{x$unmatched} class{?/es} {?is/are} absent from the lookup table and \\
       will become {.val NA} downstream."
    )
  }
  invisible(x)
}

#' @export
plot.fev_fuel_source <- function(x, register = NULL, ...) {
  fev_check_fuel_source(x)
  regs <- fev_fuel_registers(x)
  if (!length(regs)) {
    fev_abort("Nothing to plot: this fuel source populates no register.")
  }
  register <- register %||% regs[1]
  r <- x[[register]]
  if (is.null(r)) {
    fev_abort(c("Register {.val {register}} is empty.",
                i = "Populated: {.val {regs}}."))
  }
  terra::plot(r, main = paste0(x$type, " (", register, ")"), ...)
  invisible(x)
}
