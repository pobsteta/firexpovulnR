# Burn severity from Sentinel-2, which is the layer the package never had.
#
# fev_validate() has only ever known burnt against unburnt. That is an outcome
# of the HAZARD: it says where fire went, not how hard it hit, so it can
# validate fuel, danger and exposure and can say nothing at all about the
# vulnerability half. A damage function needs a continuous measure INSIDE the
# perimeter, and dNBR is the only one available everywhere and retrospectively.
#
# Where the imagery comes from, and why not from the French portals. Both were
# enumerated on 2026-08-19 and both are rolling archives over the Maures: GEODES
# serves THEIA L2A only from 2025, L3A from 2024, PEPS L1C from 2023. Their
# collections ADVERTISE 2015 to 2026; that is the nominal product range, not
# what is held. Nothing reaches the 2021 Cannet-des-Maures fire.
#
# The Element 84 / AWS mirror of Sentinel-2 L2A does: complete since 2015, no
# account, and cloud-optimised, so a window costs a range request rather than a
# scene. Measured on the Maures: one tile's two bands read in about 8 seconds,
# and a full run over the 6 510 ha fire -- two tiles, three candidate passes --
# in about three minutes.

.FEV_STAC_EARTHSEARCH <- "https://earth-search.aws.element84.com/v1"

#' Burn severity (dNBR) from Sentinel-2
#'
#' Finds the least cloudy Sentinel-2 scene before and after a fire, computes the
#' Normalized Burn Ratio on each, and returns their difference — the standard
#' burn severity index — cropped to the area of interest.
#'
#' @section What dNBR is, and what it is not:
#' NBR contrasts near infrared against shortwave infrared: living foliage is
#' bright in the first and dark in the second, and fire reverses both. The
#' difference before minus after is therefore a **change in reflectance**, not a
#' measurement of damage. Mapping it to mortality, biomass loss or economic loss
#' takes a local calibration against field plots, and the published thresholds
#' below are indicative, not a substitute for one.
#'
#' The usual thresholds (USGS, after Key and Benson): below 0.10 unburnt, 0.10
#' to 0.27 low, 0.27 to 0.66 moderate, above 0.66 high. Measured over the 6 510
#' ha Cannet-des-Maures fire of 16 to 19 August 2021, from two tiles mosaicked
#' over 663 000 cells: median dNBR **0.576** inside the perimeter against
#' **0.000** outside, 41.9% of the burnt area above the high-severity threshold
#' and 4.9% below the unburnt one — the unburnt islands every large fire leaves.
#'
#' That 0.000 outside is the control worth insisting on: a dNBR that does not
#' come back to zero on ground that did not burn is measuring something else —
#' phenology between the two dates, haze, or a scene that does not reach.
#'
#' @section Choosing the two dates is most of the method:
#' An **initial assessment** compares the closest clear scenes either side of
#' the fire and captures the immediate effect, including the char that later
#' washes off. An **extended assessment** compares the same season a year apart
#' and captures what survived, which is closer to what an ecologist means by
#' severity. This function does the first, because it is what the arguments
#' describe and because the second needs a judgement about the growing season
#' that no default can make. Widen `post_window` to a year and you get the
#' second — the record says which dates were used either way.
#'
#' Phenology is the trap. A July pre-image against an October post-image over
#' Mediterranean vegetation puts summer senescence into the signal, and it will
#' look like low-severity burn across the whole scene. The out-of-perimeter
#' median is the check.
#'
#' @section Three ways to get a plausible map and a wrong number:
#' Each of these was found by running the function against a fire whose answer
#' was known, and none of them crashed. Each returned a severity map a reader
#' would have accepted.
#'
#' **The fire is still burning.** Counting the margin from the fire's *start*
#' picked a scene from 19 August 2021 — three days after ignition and, as EFFIS
#' records it, two hours before containment. Most of the perimeter had not
#' burned yet. The margin is therefore counted from the **end**: pass both
#' dates, or an `aoi` carrying EFFIS's `FIREDATE` and `FINALDATE`.
#'
#' **The scene does not reach.** The least cloudy candidate was an
#' edge-of-swath partial covering **1% of the area**, published at **0.0%
#' cloud**. Cloud cover does not report coverage, so `min_coverage` does.
#'
#' **The scene reaches, but the fire is bigger than the tile.** The
#' Cannet-des-Maures straddles the edge of 31TGH, which carries 46.6% of its
#' bounding box. A single-scene index described half the fire and said nothing
#' about it — worse, a coverage check on the *cropped* result reported 100%,
#' because it measured what came back rather than what was asked for. Every
#' tile of a pass is mosaicked, and coverage is measured against the area.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param fire_date When the fire burned. One date, or **two** — start and end.
#'   `NULL` reads `FIREDATE` and `FINALDATE` from `aoi` when they are there,
#'   which is what [fev_fetch_burnt()] returns.
#' @param pre_window,post_window Days to search before the start and after the
#'   end, outside a `buffer_days` margin.
#' @param buffer_days Days to exclude either side of the fire. Default 3.
#' @param max_cloud Maximum scene cloud cover in percent. Default 20.
#' @param n_candidates How many before-fire scenes to try. Each is differenced
#'   against the after scene and scored by how close its median comes to zero
#'   on ground outside the perimeter; the best wins. `1` takes the least cloudy
#'   and skips the check. Default 4.
#' @param min_coverage Fraction of the area a scene must actually carry data
#'   over. **Cloud cover does not report this**: an edge-of-swath scene covering
#'   1% of the area is published at 0% cloud. Default 0.95.
#' @param crs_work EPSG code to return the raster in. Default `2154`.
#' @param quiet Suppress the report.
#'
#' @return A [fev_source] holding a single-layer `SpatRaster` named `dNBR`, with
#'   the two scene identifiers and dates in its record.
#'
#' @seealso [fev_validate()], which today knows only burnt against unburnt.
#'
#' @source
#' Sentinel-2 L2A cloud-optimised mirror maintained by Element 84 on AWS Open
#' Data, from Copernicus Sentinel data — free and open under the Copernicus
#' licence. STAC API at <https://earth-search.aws.element84.com/v1>.
#'
#' Verified 2026-08-19 by computing the index rather than by reading about it:
#' see the figures in the section above.
#'
#' @examples
#' \dontrun{
#' feux <- sf::st_read("massif_maures.gpkg", "burnt_areas")
#' gros <- feux[which.max(feux$area_ha), ]
#' sev <- fev_fetch_severity(gros, fire_date = "2021-08-16")
#' terra::plot(fev_data(sev))
#' }
#'
#' @export
fev_fetch_severity <- function(aoi,
                               fire_date = NULL,
                               pre_window = 45,
                               post_window = 45,
                               buffer_days = 3,
                               max_cloud = 20,
                               n_candidates = 4,
                               min_coverage = 0.95,
                               crs_work = 2154,
                               quiet = FALSE) {
  span <- fev_fire_span(aoi, fire_date, quiet)
  fire_start <- span$start
  fire_end <- span$end
  for (nm in c("pre_window", "post_window", "buffer_days", "max_cloud")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0) {
      fev_abort("{.arg {nm}} must be a single non-negative number.",
                .envir = environment())
    }
  }

  b <- sf::st_bbox(fev_as_aoi(aoi, crs = 4326))
  cands <- fev_stac_candidates(b, fire_start - buffer_days - pre_window,
                               fire_start - buffer_days, max_cloud, "before")
  post <- fev_stac_candidates(b, fire_end + buffer_days,
                              fire_end + buffer_days + post_window, max_cloud,
                              "after")[[1]]

  v <- terra::vect(fev_as_aoi(aoi, crs = 4326))
  if (!quiet) {
    cli::cli_h3("Before-scene candidates")
  }
  chosen <- fev_pick_pre(cands, post, aoi, v, n_candidates, min_coverage,
                         crs_work, quiet)
  pre <- chosen$scene
  dnbr <- chosen$dnbr
  names(dnbr) <- "dNBR"
  reprojected <- TRUE

  if (!quiet) {
    fev_severity_report(dnbr, pre, post, fire_start, fire_end)
  }

  new_fev_source(
    dnbr,
    dataset   = "sentinel2_dnbr",
    provider  = "Copernicus Sentinel-2 L2A via Element 84 on AWS Open Data",
    licence   = "Copernicus",
    licence_from = "donnees Copernicus Sentinel, libres et ouvertes ; miroir AWS Open Data",
    endpoint  = .FEV_STAC_EARTHSEARCH,
    query     = list(scene_pre = pre$id, date_pre = as.character(pre$date),
                     cloud_pre = round(pre$cloud, 2),
                     pre_candidates = chosen$n_tried,
                     control_outside = chosen$control,
                     coverage = chosen$coverage,
                     min_coverage = min_coverage,
                     scene_post = post$id, date_post = as.character(post$date),
                     cloud_post = round(post$cloud, 2),
                     tiles_pre = paste(pre$tiles, collapse = ", "),
                     tiles_post = paste(post$tiles, collapse = ", "),
                     fire_start = as.character(fire_start),
                     fire_end = as.character(fire_end),
                     max_cloud = max_cloud,
                     read = "/vsicurl/ window, no scene downloaded"),
    millesime = as.integer(format(fire_start, "%Y")),
    version   = "dNBR = NBR(before) - NBR(after), bands nir and swir22",
    reprojected = reprojected,
    notes = paste0(
      "A change in reflectance, not a measurement of damage: mapping dNBR to ",
      "mortality or loss needs a local calibration against field plots. ",
      "Initial assessment (closest clear scenes either side), so char is ",
      "included and phenology between the two dates is a risk -- check the ",
      "median outside the perimeter comes back to zero."
    )
  )
}

#' When the fire burned: from the argument, or from the record already there
#'
#' EFFIS ships FIREDATE and FINALDATE, and `fev_fetch_burnt()` keeps them. Using
#' them is not a convenience: the difference between counting the margin from
#' the start and from the end was, on the Cannet-des-Maures, a dNBR of 0.254
#' against 0.754.
#'
#' @noRd
fev_fire_span <- function(aoi, fire_date, quiet) {
  as_day <- function(x) as.Date(substr(as.character(x), 1, 10))

  if (is.null(fire_date)) {
    tab <- if (inherits(aoi, "sf")) sf::st_drop_geometry(aoi) else NULL
    if (is.null(tab) || !all(c("FIREDATE", "FINALDATE") %in% names(tab))) {
      fev_abort(c(
        "{.arg fire_date} is required: {.arg aoi} carries no fire dates.",
        i = "Pass one date, or two -- start and end.",
        i = "{.fn fev_fetch_burnt} returns {.field FIREDATE} and \\
             {.field FINALDATE}, and those are used when they are present."
      ), class = "fev_no_fire_date")
    }
    st <- suppressWarnings(min(as_day(tab$FIREDATE), na.rm = TRUE))
    en <- suppressWarnings(max(as_day(tab$FINALDATE), na.rm = TRUE))
    if (!is.finite(st)) {
      fev_abort("The fire dates in {.arg aoi} are all missing.",
                class = "fev_no_fire_date")
    }
    if (!is.finite(en) || en < st) {
      en <- st
    }
    if (!quiet && en > st) {
      fev_inform("Fire dates read from the data: \\
                 {as.character(st)} to {as.character(en)} \\
                 ({as.numeric(en - st)} day{?s}).",
                 .envir = environment())
    }
    return(list(start = st, end = en))
  }

  d <- try(as.Date(fire_date), silent = TRUE)
  if (inherits(d, "try-error") || anyNA(d) || !length(d) || length(d) > 2L) {
    fev_abort(c(
      "{.arg fire_date} must be one date, or two -- start and end.",
      i = "Dates or strings {.val YYYY-MM-DD}."
    ))
  }
  if (length(d) == 2L) {
    return(list(start = min(d), end = max(d)))
  }

  # One date. Said out loud rather than assumed: a 6 510 ha fire burns for days,
  # and a scene taken inside that window photographs a fire still running.
  if (!quiet) {
    fev_once("severity_one_date", fev_inform(c(
      "One fire date given, so the margin after the fire is counted from it.",
      "!" = "A large fire burns for days. The Cannet-des-Maures ran for three, \\
             and a scene picked this way was taken two hours before \\
             containment -- it gave a third of the true severity.",
      i = "Pass the end date too, or an {.arg aoi} carrying EFFIS dates.",
      i = "Shown once per session."
    )))
  }
  list(start = d, end = d)
}

#' Candidate DATES in a window, least cloudy first
#'
#' Grouped by acquisition date rather than by scene: one date is one pass, and
#' the tiles it produced are what covers the area between them.
#'
#' @noRd
fev_stac_candidates <- function(bbox, from, to, max_cloud, side) {
  items <- fev_stac_search(bbox, from, to)
  if (!length(items)) {
    fev_abort(c(
      "No Sentinel-2 scene {side} the fire between {.val {as.character(from)}} \\
       and {.val {as.character(to)}}.",
      i = "Widen {.arg {if (side == 'before') 'pre_window' else 'post_window'}}.",
      i = "Sentinel-2 starts in 2015; before that there is nothing to find here."
    ), class = "fev_no_scene", .envir = environment())
  }
  flat <- lapply(items, function(f) {
    cl <- f$properties[["eo:cloud_cover"]]
    list(id = f$id, date = as.Date(substr(f$properties$datetime, 1, 10)),
         cloud = if (is.null(cl)) NA_real_ else as.numeric(cl),
         tile = f$properties[["grid:code"]],
         nir = f$assets$nir$href, swir = f$assets$swir22$href)
  })
  # One acquisition is republished under several processing suffixes; keep one
  # per date and tile so a mosaic does not stack three copies of a scene.
  key <- vapply(flat, function(x) paste(x$date, x$tile), character(1))
  flat <- flat[!duplicated(key)]

  by_date <- split(flat, vapply(flat, function(x) as.character(x$date),
                                character(1)))
  cloud <- vapply(by_date, function(g) {
    mean(vapply(g, function(x) x$cloud, numeric(1)), na.rm = TRUE)
  }, numeric(1))
  ok <- !is.na(cloud) & cloud <= max_cloud
  if (!any(ok)) {
    fev_abort(c(
      "Every pass {side} the fire is cloudier than {.val {max_cloud}}%.",
      x = "Least cloudy available: {.val {round(min(cloud, na.rm = TRUE), 1)}}%.",
      i = "Raise {.arg max_cloud}, or widen the window. A cloud over the \\
           perimeter makes the index meaningless there, so raising the \\
           threshold is not free."
    ), class = "fev_too_cloudy", .envir = environment())
  }
  by_date <- by_date[ok]
  cloud <- cloud[ok]
  ord <- order(cloud)
  lapply(ord, function(i) {
    list(date = as.Date(names(by_date)[i]), cloud = cloud[i],
         tiles = vapply(by_date[[i]], function(x) x$tile, character(1)),
         items = by_date[[i]])
  })
}

#' Choose the before-scene by the control that must hold, not by cloud cover
#'
#' A scene-level cloud percentage does not see haze, smoke or an anomalous
#' radiometry. Measured on the Maures: the 30 July 2021 scene is published at
#' **0.0% cloud** and its NBR median over the fire area is 0.177, against 0.536
#' on 18 July and 0.512 on 27 August -- lower than the image taken AFTER the
#' fire, which vegetation cannot do. Picking it gave a dNBR of 0.337 where the
#' right pair gives 0.754.
#'
#' So the choice is made on the property that must hold rather than on a proxy:
#' outside the perimeter, where nothing burned, the difference must come back to
#' zero. Each candidate is differenced against the after-scene and scored by
#' that median. It costs one windowed read per candidate -- about eight seconds
#' each -- and it replaces a silent coin-flip with a measurement.
#'
#' With an area that is not a polygon there is no outside, so the least cloudy
#' wins and the record says the check could not run.
#'
#' @noRd
fev_pick_pre <- function(cands, post, aoi, v, n_candidates, min_coverage,
                         crs_work, quiet) {
  nbr_post <- fev_nbr_date(post$items, v, crs_work)
  if (is.null(nbr_post) || fev_coverage(nbr_post) < min_coverage) {
    cov <- if (is.null(nbr_post)) 0 else fev_coverage(nbr_post)
    fev_abort(c(
      "The pass after the fire ({.val {as.character(post$date)}}) covers only \\
       {round(100 * cov)}% of the area.",
      i = "Cloud cover does not report this: an edge-of-swath scene is \\
           published at 0%.",
      i = "Widen {.arg post_window}, or lower {.arg min_coverage}."
    ), class = "fev_scene_partial", .envir = environment())
  }

  poly <- inherits(aoi, c("sf", "sfc")) &&
    any(sf::st_geometry_type(aoi) %in% c("POLYGON", "MULTIPOLYGON"))
  mask_v <- if (poly) {
    terra::project(terra::vect(sf::st_geometry(aoi)), terra::crs(nbr_post))
  } else {
    NULL
  }
  n <- max(1L, as.integer(n_candidates))

  tried <- list()
  for (i in seq_len(min(length(cands), n * 3L))) {
    d <- fev_nbr_date(cands[[i]]$items, v, crs_work)
    if (is.null(d)) next
    d <- terra::resample(d, nbr_post, method = "near") - nbr_post
    cov <- fev_coverage(d)
    if (cov < min_coverage) {
      if (!quiet) {
        cli::cli_li("{as.character(cands[[i]]$date)}: \\
                    {round(100 * cov)}% covered by \\
                    {length(cands[[i]]$tiles)} tile{?s} -- skipped")
      }
      next
    }
    ctrl <- if (is.null(mask_v)) NA_real_ else {
      out <- stats::na.omit(terra::values(
        terra::mask(d, mask_v, inverse = TRUE))[, 1])
      if (length(out)) stats::median(out) else NA_real_
    }
    tried[[length(tried) + 1L]] <- list(scene = cands[[i]], dnbr = d,
                                        coverage = cov, control = ctrl)
    if (length(tried) >= n) break
  }
  if (!length(tried)) {
    fev_abort(c(
      "No pass before the fire covers {round(100 * min_coverage)}% of the \\
       area.",
      i = "Every candidate leaves a gap, which cloud cover does not report.",
      i = "Widen {.arg pre_window}, or lower {.arg min_coverage}."
    ), class = "fev_scene_partial", .envir = environment())
  }

  score <- vapply(tried, function(x) abs(x$control), numeric(1))
  best <- if (all(is.na(score))) 1L else
    which.min(ifelse(is.na(score), Inf, score))

  if (!quiet) {
    for (i in seq_along(tried)) {
      cli::cli_li("{as.character(tried[[i]]$scene$date)} \\
                  ({round(tried[[i]]$scene$cloud, 1)}% cloud, \\
                  {round(100 * tried[[i]]$coverage)}% covered): \\
                  control {round(tried[[i]]$control, 3)}\\
                  {if (i == best) ' <- chosen' else ''}")
    }
  }
  list(scene = tried[[best]]$scene, dnbr = tried[[best]]$dnbr,
       n_tried = length(tried), control = round(tried[[best]]$control, 4),
       coverage = round(tried[[best]]$coverage, 4))
}

#' A STAC search over GET, parsed without a JSON package
#'
#' The response is JSON and `yaml` parses it, JSON being a subset of YAML. That
#' is not a trick played for cleverness: `yaml` is already an import and adding
#' `jsonlite` or `httr2` for one search would be a dependency the package does
#' not otherwise need.
#'
#' @noRd
fev_stac_search <- function(bbox, from, to, limit = 100) {
  u <- sprintf(
    "%s/search?collections=sentinel-2-l2a&bbox=%s&datetime=%sT00:00:00Z/%sT23:59:59Z&limit=%d",
    .FEV_STAC_EARTHSEARCH,
    paste(signif(as.numeric(bbox[c("xmin", "ymin", "xmax", "ymax")]), 8),
          collapse = ","),
    as.character(from), as.character(to), limit
  )
  txt <- tryCatch(
    paste(readLines(url(u), warn = FALSE), collapse = "\n"),
    error = function(e) NULL, warning = function(w) NULL
  )
  if (is.null(txt) || !nzchar(txt)) {
    fev_abort(c(
      "The Sentinel-2 catalogue could not be reached.",
      i = "Check network egress to {.url {.FEV_STAC_EARTHSEARCH}}."
    ), class = "fev_stac_unreachable")
  }
  parsed <- tryCatch(yaml::yaml.load(txt), error = function(e) NULL)
  parsed$features %||% list()
}

#' NBR for one date: every tile that touches the area, mosaicked
#'
#' A fire does not respect the Sentinel-2 grid. The Cannet-des-Maures straddles
#' the edge of 31TGH, which carries **46.6%** of its bounding box; a
#' single-scene index would have described half the fire and said nothing about
#' it. WorldCover and GHS-POP already mosaic for the same reason.
#'
#' Adjacent tiles can sit in different UTM zones -- 31T against 32T here -- so
#' the order of operations matters. The band arithmetic runs in each tile's own
#' grid, and only the resulting index is reprojected and merged. Reprojecting
#' the bands first and then differencing them would put an interpolation
#' between the two numbers the index is made of.
#'
#' @noRd
fev_nbr_date <- function(items, aoi_vect, crs_work, res_m = 10) {
  target <- paste0("EPSG:", crs_work)
  # The common grid is built FIRST, from the area, and every tile is projected
  # straight onto it. Merging rasters that merely happen to share a CRS makes
  # terra align them itself and say so in a warning -- an implicit alignment is
  # exactly what this package refuses everywhere else.
  grid <- terra::rast(terra::ext(terra::project(aoi_vect, target)),
                      resolution = res_m, crs = target)

  parts <- lapply(items, function(sc) {
    nir <- terra::rast(paste0("/vsicurl/", sc$nir))
    swir <- terra::rast(paste0("/vsicurl/", sc$swir))
    e <- terra::ext(terra::project(aoi_vect, terra::crs(nir)))
    nir <- try(terra::crop(nir, e), silent = TRUE)
    if (inherits(nir, "try-error") || terra::ncell(nir) == 0) {
      return(NULL)
    }
    swir <- terra::resample(terra::crop(swir, e), nir, method = "bilinear")
    n <- (nir - swir) / (nir + swir)
    names(n) <- "NBR"
    terra::project(n, grid, method = "bilinear")
  })
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts)) {
    return(NULL)
  }
  r <- if (length(parts) == 1L) parts[[1]] else do.call(terra::merge, parts)
  names(r) <- "NBR"
  r
}

#' Fraction of the area a scene actually carries data over
#'
#' NBR is NaN where both bands are zero, which is how a swath edge presents
#' itself, so the valid fraction of the index is the coverage.
#'
#' @noRd
fev_coverage <- function(r) {
  v <- terra::values(r)[, 1]
  if (!length(v)) 0 else mean(!is.na(v))
}

#' @noRd
fev_severity_report <- function(dnbr, pre, post, fire_start, fire_end) {
  v <- stats::na.omit(terra::values(dnbr)[, 1])
  cli::cli_h1("fev_fetch_severity: dNBR")
  cli::cli_li("Fire {as.character(fire_start)}\\
              {if (fire_end > fire_start) paste0(' to ', as.character(fire_end))}, \\
              {length(unique(c(pre$tiles, post$tiles)))} tile{?s}")
  cli::cli_li("Before: {as.character(pre$date)} \\
              ({round(pre$cloud, 1)}% cloud), \\
              {as.numeric(fire_start - pre$date)} day{?s} before it started")
  cli::cli_li("After: {as.character(post$date)} \\
              ({round(post$cloud, 1)}% cloud), \\
              {as.numeric(post$date - fire_end)} day{?s} after it ended")
  cli::cli_li("dNBR median {round(stats::median(v), 3)}, \\
              10th to 90th {round(stats::quantile(v, 0.1), 3)} to \\
              {round(stats::quantile(v, 0.9), 3)}")
  cli::cli_alert_info(
    "A change in reflectance, not damage. Check the median on ground that did \\
     not burn comes back to zero: if it does not, the two dates differ in \\
     phenology and the whole scene reads as lightly burnt."
  )
}
