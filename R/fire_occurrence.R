# Turning declared fires into an ignition layer, and refusing to pretend it is
# sharper than it is.
#
# fev_fetch_bdiff() brought in the records. They are counts attached to a
# COMMUNE, and a commune in France has a median area of about 15 km2 -- an
# equivalent diameter of some 4 km. The working grid of this package is
# decametric. Rasterising a commune count onto a 25 m grid therefore produces
# an image with 25 m cells and 4 km of information, which is the same trade the
# package already refuses to hide when it drops a 25 km FWI onto a 25 m grid.
#
# So this function does the rasterising, because the downstream combination
# needs a grid, and it says the ratio out loud with numbers every time, and it
# writes it into the provenance. What it will NOT do is smooth, interpolate or
# kernel-weight the result: those would manufacture sub-communal structure out
# of a communal observation, and the map would then carry a precision no one
# could trace back to a source.
#
# The second thing it will not do quietly is confuse an ABSENT commune with a
# ZERO one. `fires` only holds communes that recorded something. Without the
# full commune layer, everything else is unobserved, not fire-free -- and that
# is precisely the failure BDIFF's own exhaustivity caveat warns about. The
# `communes` argument is what turns unobserved into zero, and passing it is a
# claim about the extract's coverage that the record then carries.

#' Fire occurrence from declared records
#'
#' Turns the fire records of [fev_fetch_bdiff()] into an occurrence layer on a
#' working grid: how often a fire is declared to start per unit area and per
#' year. This is the **ignition** term of the hazard, which the rest of the
#' package does not otherwise carry.
#'
#' @section What this is, in the hazard:
#' Hazard is usually defined as the probability that a fire **starts** and that
#' it **spreads**. [fev_exposure()], [fev_fuel_availability()] and
#' [fev_danger_index()] describe spread — fuel, terrain, weather. None of them
#' says anything about where fires begin, which is an empirical question and
#' mostly an anthropogenic one: roads, field edges, tips, power lines.
#'
#' Pass the result into [fev_danger_index()] or [fev_risk()] as one more named
#' dimension and it enters the combination like any other.
#'
#' @section The resolution is communal, whatever the cell size says:
#' BDIFF geolocates a fire to its **commune of departure**. Every cell inside a
#' commune therefore gets the same value, and the map has the cell size of
#' `template` with the information content of a commune. The function reports
#' the ratio between the two on every call and records it, because a 25 m map
#' of a 4 km observation is exactly the kind of thing that reads as precision
#' to someone who did not build it.
#'
#' There is deliberately **no smoothing or kernel option**. Spreading a commune
#' count over a distance decay would invent sub-communal structure that no
#' source supports. If you want a smoother map, aggregate the grid, do not
#' interpolate the values.
#'
#' @section Absent is not zero, and only you can say which:
#' `fires` holds the communes that recorded a fire. Nothing in it distinguishes
#' a commune that never burnt from one that never filed.
#'
#' Without `communes`, only the communes present get a value and the rest of the
#' grid is `NA` — honest, and usually not what a risk combination wants.
#' With `communes`, every commune in that layer and outside `fires` becomes
#' **0**. That is a claim: that the extract covered those communes, so silence
#' there means no declared fire. It is written into the record as
#' `zeros_assumed_from`, because BDIFF's own exhaustivity caveat means a zero is
#' "nothing was filed", never "nothing burnt".
#'
#' @section The denominator, which decides what the numbers mean:
#' A rate needs a period. It must be the period **observed**, not the span of
#' the fires that happen to be in the extract: a commune with one fire in 2010
#' inside a 2006–2025 request has a rate of 1/20 per year, not 1/1.
#'
#' So `period` is read, in order, from the argument, then from the
#' `period_requested` of the [fev_source] record, then — with a warning — from
#' the range of the fire dates themselves, which is a lower bound on the true
#' observation window and therefore inflates every rate.
#'
#' @param fires Fire records **carrying geometry**: a [fev_source] from
#'   [fev_fetch_bdiff()] called with `communes`, or the `sf` itself. Records
#'   without geometry are refused, with the reason.
#' @param template The working grid: a `SpatRaster`, or a `fev_layer` holding
#'   one. Defines cell size, extent and CRS of the result.
#' @param communes Optional `sf` of every commune in scope, to turn unrecorded
#'   communes into zeros rather than `NA`. See the section above.
#' @param communes_key Name of the INSEE code column in `communes`. `NULL`
#'   auto-detects, as [fev_fetch_bdiff()] does.
#' @param period Two-element vector of years bounding the observation window,
#'   used as the denominator. `NULL` reads it from the source record, then
#'   falls back to the data with a warning.
#' @param measure `"rate"` (default) fires per 100 km2 per year; `"count"` the
#'   raw number over the whole period; `"burnt_rate"` hectares burnt per 100 km2
#'   per year, which weights by size rather than counting equally.
#' @param min_area_ha Drop fires smaller than this before counting. `0` keeps
#'   everything, which is the point of BDIFF over EFFIS; raise it to ask how
#'   often a fire of consequence starts here.
#' @param output `"raster"` (default) for the gridded layer, or `"communes"`
#'   for the `sf` with the computed columns, which is what a communal
#'   choropleth wants and what carries the information without the false
#'   sharpness.
#' @param quiet Suppress the report.
#'
#' @return For `output = "raster"`, a `fev_layer` of role `"occurrence"`
#'   holding a `SpatRaster`. For `output = "communes"`, an `sf` with `insee`,
#'   `n_fires`, `burnt_ha`, `area_km2` and `occurrence`.
#'
#' @seealso [fev_fetch_bdiff()] for the records, [fev_danger_index()] and
#'   [fev_risk()] to combine this with the spread terms.
#'
#' @examples
#' # A commune layer and two fires in it, entirely offline.
#' poly <- function(x0) sf::st_polygon(list(cbind(
#'   c(x0, x0 + 2000, x0 + 2000, x0, x0), c(0, 0, 2000, 2000, 0))))
#' com <- sf::st_sf(
#'   INSEE_COM = c("21001", "21002"),
#'   geometry = sf::st_sfc(poly(0), poly(2000), crs = 2154)
#' )
#' fires <- sf::st_sf(
#'   insee = c("21001", "21001"),
#'   fire_year = c(2010L, 2015L),
#'   area_ha = c(3, 12),
#'   geometry = sf::st_geometry(com)[c(1, 1)]
#' )
#' grid <- terra::rast(terra::ext(0, 4000, 0, 2000), resolution = 500,
#'                     crs = "EPSG:2154")
#'
#' occ <- fev_fire_occurrence(fires, grid, communes = com,
#'                            period = c(2006, 2025), quiet = TRUE)
#' terra::unique(fev_data(occ))
#'
#' @export
fev_fire_occurrence <- function(fires,
                                template,
                                communes = NULL,
                                communes_key = NULL,
                                period = NULL,
                                measure = c("rate", "count", "burnt_rate"),
                                min_area_ha = 0,
                                output = c("raster", "communes"),
                                quiet = FALSE) {
  measure <- match.arg(measure)
  output <- match.arg(output)

  grid <- fev_as_raster(template, "template")
  if (!fev_crs_usable(grid)) {
    fev_abort(c(
      "{.arg template} carries no usable CRS.",
      i = "The commune polygons have to be reprojected onto it; the package \\
           will not guess one."
    ))
  }
  crs_work <- fev_crs_label(grid)

  src <- if (inherits(fires, "fev_source")) fires$source else NULL
  tab <- fev_occ_records(fires)
  prov <- fev_occ_provenance(fires, crs_work)

  if (!is.numeric(min_area_ha) || length(min_area_ha) != 1L || min_area_ha < 0) {
    fev_abort("{.arg min_area_ha} must be a single non-negative number.")
  }
  if (min_area_ha > 0) {
    keep <- !is.na(tab$area_ha) & tab$area_ha >= min_area_ha
    n_drop <- sum(!keep)
    tab <- tab[keep, , drop = FALSE]
    if (!nrow(tab)) {
      fev_abort(c(
        "No fire is at least {min_area_ha} ha.",
        i = "{n_drop} record{?s} were dropped by {.arg min_area_ha}."
      ), class = "fev_empty_result")
    }
    if (!quiet) {
      fev_inform("Dropped {n_drop} fire{?s} below {min_area_ha} ha.")
    }
  }

  years <- fev_occ_period(period, src, tab, quiet)
  n_years <- years[2] - years[1] + 1L

  by_com <- fev_occ_aggregate(tab)
  by_com <- fev_occ_attach_geometry(by_com, tab, communes, communes_key,
                                    grid, quiet)

  by_com$area_km2 <- as.numeric(sf::st_area(by_com)) / 1e6
  if (any(by_com$area_km2 <= 0)) {
    fev_abort(c(
      "{sum(by_com$area_km2 <= 0)} commune{?s} ha{?s/ve} zero area in \\
       {.val {crs_work}}.",
      i = "A rate cannot be divided by it. Check the commune geometries."
    ))
  }

  by_com$occurrence <- switch(
    measure,
    count      = by_com$n_fires,
    rate       = by_com$n_fires / by_com$area_km2 / n_years * 100,
    burnt_rate = by_com$burnt_ha / by_com$area_km2 / n_years * 100
  )
  units <- switch(
    measure,
    count      = sprintf("fires over %d-%d", years[1], years[2]),
    rate       = "fires per 100 km2 per year",
    burnt_rate = "ha burnt per 100 km2 per year"
  )

  mismatch <- fev_occ_scale_report(by_com, grid, quiet)

  prov <- fev_prov_add_step(
    prov, fun = "fev_fire_occurrence",
    params = list(
      measure = measure,
      units = units,
      period = paste(years, collapse = "-"),
      period_source = attr(years, "from"),
      n_years = n_years,
      min_area_ha = min_area_ha,
      n_fires = nrow(tab),
      n_communes = nrow(by_com),
      n_communes_zero = sum(by_com$n_fires == 0),
      zeros_assumed_from = if (is.null(communes)) NA_character_ else
        "communes layer: absent from the records was read as no declared fire",
      cell_m = signif(terra::res(grid)[1], 6),
      median_commune_km2 = signif(stats::median(by_com$area_km2), 4),
      commune_equivalent_diameter_m = signif(mismatch$diameter, 4),
      information_is_communal = TRUE,
      smoothing = "none, deliberately: a kernel would invent sub-communal structure"
    ),
    notes = paste(
      "Occurrence is observed per commune of departure. A zero is 'nothing was",
      "declared', never 'nothing burnt': BDIFF entry is declarative and its",
      "exhaustivity is not guaranteed."
    )
  )

  if (output == "communes") {
    attr(by_com, "provenance") <- prov
    return(by_com)
  }

  r <- terra::rasterize(terra::vect(by_com), grid, field = "occurrence")
  names(r) <- "occurrence"
  new_fev_layer(r, role = "occurrence", provenance = prov, units = units)
}


# Inputs ----------------------------------------------------------------------

#' Pull the record table out of whatever was passed, and insist on geometry
#' @noRd
fev_occ_records <- function(fires) {
  x <- if (inherits(fires, "fev_source")) fires$data else fires

  if (!inherits(x, "sf")) {
    fev_abort(c(
      "{.arg fires} carries no geometry.",
      x = "Got {.cls {class(x)[1]}}.",
      i = "BDIFF records hold a commune code, not a shape. Call \\
           {.code fev_fetch_bdiff(..., communes = <sf>)} so the commune \\
           polygons are attached, then pass the result here."
    ), class = "fev_occ_no_geometry")
  }

  need <- c("insee", "fire_year")
  missing_cols <- setdiff(need, names(x))
  if (length(missing_cols)) {
    fev_abort(c(
      "{.arg fires} has no {.field {missing_cols}} column{?s}.",
      i = "Columns present: {.val {setdiff(names(x), attr(x, 'sf_column'))}}.",
      i = "This function consumes the output of {.fn fev_fetch_bdiff}."
    ), class = "fev_occ_missing_column")
  }
  if (!"area_ha" %in% names(x)) {
    x$area_ha <- NA_real_
  }
  if (!nrow(x)) {
    fev_abort("{.arg fires} holds no record.", class = "fev_empty_result")
  }
  x
}

#' @noRd
fev_occ_provenance <- function(fires, crs_work) {
  if (inherits(fires, "fev_source")) {
    prov <- fev_prov_new(crs_work = crs_work)
    return(fev_prov_add_source(
      prov,
      dataset   = fires$source$dataset %||% "fire_records",
      provider  = fires$source$provider,
      endpoint  = fires$source$endpoint,
      query     = fires$source$query,
      millesime = fires$source$millesime,
      licence   = fires$source$licence
    ))
  }
  fev_layer_prov(fires) %||% attr(fires, "provenance") %||%
    fev_prov_new(crs_work = crs_work)
}

#' Decide the denominator, and say where it came from
#'
#' The order matters. The argument is a statement by the analyst. The source
#' record's `period_requested` is what was actually asked of BDIFF, which is the
#' observation window. The range of the fire dates is neither: it is a lower
#' bound on that window, so using it makes every rate too high, and it warns.
#'
#' @noRd
fev_occ_period <- function(period, src, tab, quiet) {
  if (!is.null(period)) {
    y <- fev_period_years(period)
    attr(y, "from") <- "argument"
    return(y)
  }

  requested <- src$period_requested
  if (!is.null(requested) && !all(is.na(requested)) &&
        grepl("^[0-9]{4}-[0-9]{4}$", requested)) {
    y <- as.integer(strsplit(requested, "-", fixed = TRUE)[[1]])
    attr(y, "from") <- "fev_source record (period_requested)"
    if (!quiet) {
      fev_inform("Denominator {y[1]}-{y[2]}, read from the source record.")
    }
    return(y)
  }

  y <- range(tab$fire_year, na.rm = TRUE)
  attr(y, "from") <- "range of the records themselves (lower bound)"
  fev_warn(c(
    "No observation period given, so the denominator is the span of the \\
     records themselves, {y[1]}-{y[2]}.",
    x = "That is a LOWER bound on the window actually observed, so every rate \\
         here is too high.",
    i = "Pass {.arg period} with the years you asked BDIFF for."
  ), class = "fev_occ_period_inferred")
  y
}


# Aggregation and geometry ----------------------------------------------------

#' One row per commune: how many fires, how many hectares
#' @noRd
fev_occ_aggregate <- function(tab) {
  d <- sf::st_drop_geometry(tab)
  split_by <- d$insee
  n <- tapply(rep(1L, nrow(d)), split_by, sum)
  burnt <- tapply(d$area_ha, split_by, function(v) sum(v, na.rm = TRUE))
  data.frame(
    insee = names(n),
    n_fires = as.integer(n),
    burnt_ha = as.numeric(burnt[names(n)]),
    stringsAsFactors = FALSE
  )
}

#' Give every commune a polygon, and decide what the unrecorded ones are
#' @noRd
fev_occ_attach_geometry <- function(by_com, tab, communes, communes_key,
                                    grid, quiet) {
  if (is.null(communes)) {
    # Only the communes that recorded something. Everything else is unobserved,
    # and the map will be NA there rather than zero.
    geom <- sf::st_geometry(tab)[match(by_com$insee, tab$insee)]
    out <- sf::st_sf(by_com, geometry = geom)
    out <- sf::st_transform(out, terra::crs(grid))
    fev_warn(c(
      "No {.arg communes} layer, so only the {nrow(out)} commune{?s} with a \\
       record get a value.",
      x = "Every other cell is {.val NA} -- unobserved, not fire-free.",
      i = "Pass the full commune layer through {.arg communes} to read \\
           silence as zero, which is a claim about the extract's coverage."
    ), class = "fev_occ_no_zero_communes")
    return(out)
  }

  if (!inherits(communes, "sf")) {
    fev_abort(c(
      "{.arg communes} must be an {.cls sf}, not {.cls {class(communes)[1]}}."
    ))
  }
  key <- fev_bdiff_commune_key(communes, communes_key, quiet = quiet)
  communes <- sf::st_transform(communes, terra::crs(grid))
  codes <- fev_bdiff_pad5(trimws(as.character(communes[[key]])))
  keep <- !duplicated(codes)
  communes <- communes[keep, , drop = FALSE]
  codes <- codes[keep]

  idx <- match(codes, by_com$insee)
  orphan <- setdiff(by_com$insee, codes)
  if (length(orphan)) {
    fev_warn(c(
      "{length(orphan)} commune{?s} with records {?is/are} absent from \\
       {.arg communes} and {?is/are} dropped.",
      i = "e.g. {.val {utils::head(sort(orphan), 5)}}.",
      i = "The commune layer is probably more recent than the fires."
    ), class = "fev_occ_unmatched_communes")
  }

  out <- sf::st_sf(
    insee = codes,
    n_fires = ifelse(is.na(idx), 0L, by_com$n_fires[idx]),
    burnt_ha = ifelse(is.na(idx), 0, by_com$burnt_ha[idx]),
    geometry = sf::st_geometry(communes),
    stringsAsFactors = FALSE
  )
  if (!quiet) {
    n_zero <- sum(out$n_fires == 0)
    fev_inform("{nrow(out)} commune{?s}, of which {n_zero} with no declared \\
                fire, read as zero.")
  }
  out
}

#' Say how much finer the grid is than the observation, with numbers
#'
#' The equivalent diameter of the median commune, against the cell size. A
#' ratio of one means the grid matches what was observed; a ratio of 160 -- a
#' 25 m cell inside a 15 km2 commune -- means the map is 160 times finer than
#' anything in the data.
#'
#' @noRd
fev_occ_scale_report <- function(by_com, grid, quiet) {
  med_km2 <- stats::median(by_com$area_km2)
  diameter <- 2 * sqrt(med_km2 * 1e6 / pi)
  cell <- terra::res(grid)[1]
  ratio <- diameter / cell

  if (!quiet) {
    fev_inform("Median commune {signif(med_km2, 3)} km2 \\
                (~{signif(diameter, 3)} m across) on {signif(cell, 3)} m cells.")
  }
  if (ratio > .FEV_OCC_SCALE_WARN) {
    fev_warn(c(
      "The grid is {round(ratio)} times finer than the observation.",
      x = "Every cell in a commune carries the same value: this map has \\
           {signif(cell, 3)} m cells and ~{signif(diameter, 3)} m of \\
           information.",
      i = "Recorded in the provenance. Do not read sub-communal structure \\
           into it, and consider {.code output = \"communes\"} for anything \\
           a reader will look at directly."
    ), class = "fev_occ_scale_mismatch")
  }
  list(median_km2 = med_km2, diameter = diameter, ratio = ratio)
}
