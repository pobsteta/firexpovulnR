# Recovering the BD Forêt v2 vintage from the imagery it was drawn on.
#
# Phase 2 recorded this as a blocker: the WFS does not serve the vintage, its
# schema has no date field at all, and no per-department table was found at
# IGN. Without it the temporal-bias check in fev_validate() cannot run, which
# is the one thing the brief singles out as needing code rather than a caveat.
#
# The way round it is not a table but a definition. IGN's own content
# description (DC_BDFORET_v2.pdf, September 2014, §2.3 "Actualité et mise à
# jour") says:
#
#   « La date de validation est celle de la prise de vues de la BD ORTHO®
#     servant à la production des données. »
#
# The vintage IS the aerial survey date. And that date is published, per
# polygon, in the BD ORTHO mosaicking graph -- which IGN archives in
# period-sliced layers that span the whole BD Forêt v2 construction window.
#
# What this does not settle is which campaign fed a given department: a
# department is reflown about every five years, so 2007-2018 usually holds two.
# This function therefore returns the candidates with the share of the area each
# covers, and refuses to invent a choice between them.

#' BD Forêt v2 vintage, from the imagery it was photo-interpreted on
#'
#' Retrieves the aerial survey dates of the BD ORTHO campaigns covering an area
#' of interest, which is what IGN defines the BD Forêt v2 validity date to be.
#'
#' @section Why this is the vintage, not a proxy for it:
#' The BD Forêt v2 content description states it directly: *« La date de
#' validation est celle de la prise de vues de la BD ORTHO® servant à la
#' production des données. »* The database describes the stand as the
#' photo-interpreter saw it on the infrared imagery, so the survey date is the
#' date of the landscape state it records — which is exactly what a temporal
#' bias check needs, and arguably better than a publication date would be.
#'
#' The WFS serving BD Forêt v2 carries no date field of any kind (schema
#' verified 2026-08-16: `id`, `code_tfv`, `tfv`, `tfv_g11`, `essence`,
#' `geom`), so this is the only route to it that does not involve guessing.
#'
#' @section It usually returns more than one candidate:
#' BD ORTHO reflies a department roughly every five years, and BD Forêt v2 was
#' built between 2007 and 2018. Most departments therefore have two campaigns
#' inside that window — the Var has 2008 and 2014 — and **IGN does not publish
#' which one fed which department's production**. This function will not choose
#' for you.
#'
#' Two things narrow it. Full metropolitan coverage was planned for early 2016,
#' so a survey flown after that fed an update rather than an initial
#' production. And `strategy = "oldest"` is the conservative reading: assuming
#' the older campaign maximises the lag the validation reports, which errs
#' toward flagging temporal bias rather than hiding it.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param period Two years bounding the search. Defaults to the BD Forêt v2
#'   construction window, 2007 to 2018.
#' @param strategy `NULL` (default) returns every candidate. `"oldest"` and
#'   `"newest"` collapse to a single year, and say which rule produced it.
#' @param crs_work EPSG code to work in. Default `2154`.
#' @param cache Use the on-disk cache. See [fev_cache_dir()].
#'
#' @return With `strategy = NULL`, a data frame of class `fev_millesime` with
#'   one row per campaign: `dep`, `pva`, `date_vol`, `year`, `n_polygons` and
#'   `pct_area` — the share of the mosaic area over the AOI that campaign
#'   covers. With a strategy, a single integer year carrying the table as its
#'   `candidates` attribute.
#'
#' @seealso [fev_fetch_bdforet()], which accepts `millesime = "auto"` to call
#'   this, and [fev_validate()], which is what needs the answer.
#'
#' @source
#' IGN, *BD Forêt® Version 2 — Descriptif de contenu*, September 2014, §2.3,
#' <https://inventaire-forestier.ign.fr/IMG/pdf/DC_BDFORET_v2.pdf>, read
#' 2026-08-16. Mosaicking graph layers and their `date_vol` field verified by
#' `DescribeFeatureType` and by real `GetFeature` requests over the Var on the
#' same day.
#'
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("massif_maures.gpkg")
#'
#' # Every campaign that could have fed the BD Forêt v2 of this area:
#' fev_bdforet_millesime(aoi)
#'
#' # Collapsed conservatively, for an automated pipeline:
#' millesime <- fev_bdforet_millesime(aoi, strategy = "oldest")
#' bdf <- fev_fetch_bdforet(aoi, millesime = millesime)
#' }
#'
#' @export
fev_bdforet_millesime <- function(aoi,
                                  period = .FEV_BDFORET_V2_WINDOW,
                                  strategy = NULL,
                                  crs_work = 2154,
                                  cache = TRUE) {
  if (!is.null(strategy)) {
    strategy <- match.arg(strategy, c("oldest", "newest"))
  }
  years <- fev_period_years(period)
  aoi <- fev_as_aoi(aoi, crs = crs_work)

  layers <- fev_ortho_graphs_for(years)
  if (!length(layers)) {
    fev_abort(c(
      "No archived BD ORTHO mosaicking graph covers {.val {years}}.",
      i = "Available slices: {.val {names(.FEV_ORTHO_GRAPHS)}}.",
      i = "Widen {.arg period}, or query the current graph directly."
    ), class = "fev_no_graph", .envir = environment())
  }

  key <- fev_cache_key("ortho_graphe",
                       list(aoi = aoi, layers = layers, crs = crs_work))
  graph <- if (isTRUE(cache) && fev_cache_hit(key)) {
    hit <- fev_cache_read(key)
    fev_inform("BD ORTHO mosaicking graph served from cache \\
                ({nrow(hit$data)} polygon{?s}).")
    hit$data
  } else {
    got <- fev_fetch_ortho_graph(aoi, layers, crs_work)
    if (isTRUE(cache)) {
      fev_cache_write(key, got, list(dataset = "ortho_graphe",
                                     provider = "IGN", layers = layers))
    }
    got
  }

  tab <- fev_millesime_table(graph, years, crs_work)

  if (!nrow(tab)) {
    fev_abort(c(
      "No BD ORTHO survey covers this AOI between {years[1]} and {years[2]}.",
      i = "BD For\u00eat v2 covers metropolitan France only. Check the AOI \\
           location and CRS.",
      i = "Outside that window there may still be coverage: widen \\
           {.arg period}."
    ), class = "fev_empty_result", .envir = environment())
  }

  fev_report_millesime(tab, years)

  if (is.null(strategy)) {
    return(tab)
  }
  chosen <- if (identical(strategy, "oldest")) min(tab$year) else max(tab$year)
  structure(as.integer(chosen), candidates = tab, strategy = strategy,
            class = c("fev_millesime_year", "integer"))
}

#' Which archived graphs overlap the requested window
#' @noRd
fev_ortho_graphs_for <- function(years) {
  bounds <- lapply(names(.FEV_ORTHO_GRAPHS), function(n) {
    as.integer(strsplit(n, "-", fixed = TRUE)[[1]])
  })
  keep <- vapply(bounds, function(b) {
    b[1] <= years[2] && b[2] >= years[1]
  }, logical(1))
  unlist(.FEV_ORTHO_GRAPHS[keep], use.names = TRUE)
}

#' Fetch and stack the mosaicking graphs
#'
#' Kept apart from the tabulation so the logic downstream can be tested without
#' a network, which is the rule the brief sets for the whole suite.
#'
#' @noRd
fev_fetch_ortho_graph <- function(aoi, layers, crs_work) {
  fev_require("happign", "download the BD ORTHO mosaicking graph")
  endpoint <- .FEV_ENDPOINTS$ign_wfs
  fev_inform("Fetching {length(layers)} BD ORTHO mosaicking graph{?s} from \\
              {.url {endpoint}} ...")

  parts <- lapply(names(layers), function(slice) {
    got <- tryCatch(
      happign::get_wfs(x = aoi, layer = layers[[slice]], verbose = FALSE),
      error = function(e) {
        fev_warn(c(
          "The {.val {slice}} mosaicking graph could not be fetched.",
          x = "{conditionMessage(e)}",
          i = "The other slices are still used; the result is incomplete."
        ), class = "fev_graph_partial", .envir = environment())
        NULL
      }
    )
    if (is.null(got) || !nrow(got)) {
      return(NULL)
    }
    got$slice <- slice
    got[, intersect(c("dep", "pva", "date_vol", "slice", "geometry"),
                    names(got))]
  })

  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) {
    fev_abort(c(
      "No mosaicking graph returned a feature for this AOI.",
      i = "Check network egress to {.url data.geopf.fr}, then the AOI \\
           location -- these layers cover France only."
    ), class = "fev_empty_result")
  }
  out <- do.call(rbind, parts)
  sf::st_transform(out, crs_work)
}

#' Campaigns over an AOI, with the share of area each covers
#'
#' Area share matters because an AOI straddling two departments, or a
#' department reflown in two passes, gets more than one campaign and the row
#' covering 3% of it is not the vintage of the analysis.
#'
#' @noRd
fev_millesime_table <- function(graph, years, crs_work) {
  if (!nrow(graph)) {
    return(fev_millesime_empty())
  }
  d <- as.Date(graph$date_vol)
  graph$year <- as.integer(format(d, "%Y"))
  graph <- graph[!is.na(graph$year) &
                   graph$year >= years[1] & graph$year <= years[2], ]
  if (!nrow(graph)) {
    return(fev_millesime_empty())
  }

  graph$area <- as.numeric(sf::st_area(graph))
  total <- sum(graph$area, na.rm = TRUE)
  key <- paste(graph$dep, graph$year, sep = "|")

  rows <- lapply(unique(key), function(k) {
    sel <- key == k
    parts <- strsplit(k, "|", fixed = TRUE)[[1]]
    data.frame(
      dep = parts[1],
      pva = suppressWarnings(max(as.integer(graph$pva[sel]), na.rm = TRUE)),
      date_vol = as.character(min(as.Date(graph$date_vol[sel]), na.rm = TRUE)),
      year = as.integer(parts[2]),
      n_polygons = sum(sel),
      pct_area = if (total > 0) round(100 * sum(graph$area[sel]) / total, 1)
                 else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(out$dep, out$year), ]
  rownames(out) <- NULL
  structure(out, class = c("fev_millesime", "data.frame"))
}

#' @noRd
fev_millesime_empty <- function() {
  structure(
    data.frame(dep = character(), pva = integer(), date_vol = character(),
               year = integer(), n_polygons = integer(), pct_area = numeric(),
               stringsAsFactors = FALSE),
    class = c("fev_millesime", "data.frame")
  )
}

#' Say what was found, and whether it settles the question
#' @noRd
fev_report_millesime <- function(tab, years) {
  n_years <- length(unique(tab$year))
  if (n_years == 1L) {
    fev_inform(c(
      "One BD ORTHO campaign covers this AOI between {years[1]} and \\
       {years[2]}: {.val {unique(tab$year)}}.",
      i = "IGN defines the BD For\u00eat v2 validity date as the survey date, so \\
           this is the vintage."
    ), class = "fev_millesime_found", .envir = environment())
    return(invisible(tab))
  }
  fev_warn(c(
    "{n_years} BD ORTHO campaigns cover this AOI between {years[1]} and \\
     {years[2]}: {.val {sort(unique(tab$year))}}.",
    i = "IGN does not publish which one fed a given department's BD For\u00eat \\
         v2, so the vintage is not settled by the data alone.",
    i = "Read {.field pct_area} to see which dominates, then pass the year to \\
         {.fn fev_fuel_source} yourself.",
    i = "{.code strategy = \"oldest\"} takes the conservative one: it \\
         maximises the lag {.fn fev_validate} reports, which errs toward \\
         flagging temporal bias rather than hiding it."
  ), class = "fev_millesime_ambiguous", .envir = environment())
  invisible(tab)
}

#' @export
print.fev_millesime <- function(x, ...) {
  cli::cli_h1("BD For\u00eat v2 vintage candidates")
  if (!nrow(x)) {
    cli::cli_alert_warning("No campaign found.")
    return(invisible(x))
  }
  print(as.data.frame(unclass(x)[seq_along(x)]), row.names = FALSE)
  cli::cli_text("")
  cli::cli_alert_info(
    "Vintage = BD ORTHO survey date (IGN, DC_BDFORET_v2.pdf, section 2.3)."
  )
  invisible(x)
}

#' @export
print.fev_millesime_year <- function(x, ...) {
  cli::cli_text("BD For\u00eat v2 vintage: {.strong {as.integer(x)}} \\
                 ({attr(x, 'strategy')} of {nrow(attr(x, 'candidates'))} \\
                 candidate{?s})")
  invisible(x)
}
