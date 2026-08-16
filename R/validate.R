# Validation against observed burnt area, with the temporal bias treated as
# code rather than as a caveat.
#
# The brief is specific about the last point: BD Forêt v2 was built department
# by department across a decade, so a stand mapped in 2008 may have burnt in
# 2010 and be in another state entirely. Comparing a risk map built on that
# fuel to fires that postdate it validates the map against a landscape that no
# longer existed. This function measures how much of the sample is in that
# situation and says so with a number, before reporting any skill statistic.

#' Validate a risk map against observed burnt areas
#'
#' Tests whether observed fires fell where the map said risk was high: an
#' AUC, a ROC curve, and the observed-versus-expected distribution across risk
#' classes. Runs the temporal bias check first, because a good AUC computed
#' against fires that postdate the fuel data is not evidence of anything.
#'
#' @section The temporal bias check:
#' Every fire's year is compared to the vintage of the fuel layer the risk map
#' was built on, read from the provenance record. The function reports how many
#' fires and what share of burnt **area** postdate that vintage by more than
#' `max_lag_years`, and — when `max_lag_years` is given — drops them from the
#' sample.
#'
#' If the vintage is unknown the check cannot run. That is the recorded
#' consequence of BD Forêt v2 not serving it (see [fev_fuel_source()]): the
#' function then refuses if you asked for filtering, and warns loudly if you
#' did not.
#'
#' @section What AUC does and does not say:
#' The AUC here is the probability that a randomly chosen burnt cell scores
#' higher than a randomly chosen unburnt one. 0.5 is a coin toss.
#'
#' It is computed over **cells**, which are not independent observations: fires
#' are spatially contiguous, so the effective sample size is far smaller than
#' the cell count and any confidence interval built on that count would be far
#' too narrow. None is reported for that reason. Treat the AUC as a descriptive
#' comparison of two distributions, not as a test.
#'
#' The class table alongside it is the more readable statement, and is the form
#' `fireexposuR::fire_exp_validate()` uses: the share of burnt area in each risk
#' class against the share of the study area in that class. A map with skill
#' concentrates burnt area in classes that occupy little ground.
#'
#' @param risk A `fev_risk_layer` from [fev_risk()], a `fev_layer`, or a
#'   `SpatRaster`.
#' @param burnt_areas Observed fires: a [fev_source] from [fev_fetch_burnt()],
#'   an `sf` or a `SpatVector`, carrying a fire date.
#' @param max_lag_years Drop fires whose year exceeds the fuel vintage by more
#'   than this. `NULL` keeps everything and only reports.
#' @param millesime Fuel vintage, when it is not in `risk`'s provenance or you
#'   want to override it.
#' @param class_breaks Upper bounds of the risk classes for the
#'   observed-versus-expected table. The default matches
#'   `fireexposuR::fire_exp_validate()`.
#' @param n_thresholds Number of thresholds along the ROC curve.
#'
#' @return An object of class `fev_validation`, with `auc`, `roc`, `classes`,
#'   `temporal` and the provenance record.
#'
#' @seealso [fev_risk()], [fev_fetch_burnt()].
#'
#' @source
#' Class-table form after `fireexposuR::fire_exp_validate()` 1.2.0, whose
#' default `class_breaks = c(0.2, 0.4, 0.6, 0.8, 1)` is reused here. Read from
#' the installed package on 2026-08-16.
#'
#' @examples
#' # Risk rising towards the south: row 1 of a SpatRaster is its northern edge,
#' # so values run 0 at the top to 1 at the bottom.
#' g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 2000,
#'                  ymin = 0, ymax = 2000, crs = "EPSG:2154")
#' terra::values(g) <- rep(seq(0, 1, length.out = 20), each = 20)
#'
#' # A fire in the south, where the map said risk was highest.
#' fires <- sf::st_sf(
#'   FIREDATE = "2016-07-18",
#'   geometry = sf::st_sfc(sf::st_polygon(list(cbind(
#'     c(0, 2000, 2000, 0, 0), c(0, 0, 500, 500, 0)
#'   ))), crs = 2154)
#' )
#' v <- fev_validate(g, fires, millesime = 2014)
#' v$auc
#' v$classes
#'
#' @export
fev_validate <- function(risk,
                         burnt_areas,
                         max_lag_years = NULL,
                         millesime = NULL,
                         class_breaks = c(0.2, 0.4, 0.6, 0.8, 1),
                         n_thresholds = 200) {
  prov <- fev_layer_prov(risk) %||% attr(risk, "provenance")
  r <- fev_as_raster(risk, "risk")[[1]]

  if (fev_all_na(r)) {
    fev_abort(c(
      "The risk layer is entirely {.val NA}.",
      i = "Nothing to validate."
    ), class = "fev_all_na")
  }

  fires <- fev_validate_fires(burnt_areas, r)
  millesime <- millesime %||% fev_provenance_millesime(prov)
  temporal <- fev_temporal_bias(fires, millesime, max_lag_years)
  fires <- temporal$fires

  if (!nrow(fires)) {
    fev_abort(c(
      "No fire is left after the temporal filter.",
      i = "{.arg max_lag_years} = {max_lag_years} against a vintage of \\
           {.val {millesime}} removed all {temporal$n_total} of them.",
      i = "Either the fuel data long predates the fire record, or the vintage \\
           is wrong."
    ), class = "fev_empty_sample", .envir = environment())
  }

  observed <- terra::rasterize(terra::vect(fires), r, background = 0)
  observed <- terra::mask(observed, r)

  vals <- terra::values(r)[, 1]
  burnt <- terra::values(observed)[, 1]
  ok <- !is.na(vals) & !is.na(burnt)
  vals <- vals[ok]
  burnt <- burnt[ok] > 0

  if (!any(burnt)) {
    fev_abort(c(
      "No fire overlaps the risk layer.",
      i = "{nrow(fires)} fire{?s} were supplied but none intersect its \\
           extent.",
      i = "Both are in {.val {fev_crs_label(r)}}, so this is a location \\
           mismatch, not a CRS one."
    ), class = "fev_disjoint_extent", .envir = environment())
  }
  if (all(burnt)) {
    fev_abort(c(
      "Every cell of the risk layer burnt.",
      i = "With no unburnt cells there is nothing to discriminate against, \\
           and an AUC is undefined.",
      i = "Validate on an extent wider than the fires."
    ), class = "fev_degenerate_sample")
  }

  auc <- fev_auc(vals, burnt)
  roc <- fev_roc(vals, burnt, n_thresholds)
  classes <- fev_class_table(vals, burnt, class_breaks)

  prov <- prov %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_validate",
    params = list(
      auc = round(auc, 4),
      n_cells = length(vals), n_burnt_cells = sum(burnt),
      n_fires = nrow(fires), n_fires_supplied = temporal$n_total,
      millesime = millesime %||% NA,
      max_lag_years = max_lag_years,
      pct_area_beyond_lag = temporal$pct_area,
      class_breaks = class_breaks
    ),
    notes = temporal$note
  )

  structure(
    list(auc = auc, roc = roc, classes = classes, temporal = temporal,
         n_cells = length(vals), n_burnt = sum(burnt),
         provenance = prov),
    class = "fev_validation"
  )
}

#' Fires as an sf on the risk layer's CRS, with dates and areas parsed
#' @noRd
fev_validate_fires <- function(burnt_areas, r) {
  fires <- if (inherits(burnt_areas, "fev_source")) burnt_areas$data else burnt_areas
  if (inherits(fires, "SpatVector")) {
    fires <- sf::st_as_sf(fires)
  }
  if (!inherits(fires, "sf")) {
    fev_abort(c(
      "{.arg burnt_areas} must be a {.cls fev_source}, {.cls sf} or \\
       {.cls SpatVector}.",
      x = "Got {.cls {class(burnt_areas)[1]}}.",
      i = "{.fn fev_fetch_burnt} returns one."
    ))
  }
  if (!nrow(fires)) {
    fev_abort("{.arg burnt_areas} has no features.", class = "fev_empty_result")
  }

  crs_work <- fev_crs(r)
  if (!all(c("fire_year", "area_ha") %in% names(fires))) {
    fires <- fev_burnt_prepare(fires, crs_work)
  } else if (!fev_crs_equal(fires, r)) {
    fires <- sf::st_transform(fires, crs_work)
  }
  fires
}

#' The fuel vintage, dug out of the provenance record
#'
#' This is what the record is for. A risk layer built through the chain carries
#' the vintage of every source it came from, so the temporal check does not
#' have to be told again what the analysis already knows.
#'
#' @noRd
fev_provenance_millesime <- function(prov) {
  if (is.null(prov) || !length(prov$sources)) {
    return(NULL)
  }
  # A merged fuel source records one vintage per component; the fuel one is
  # what matters here, so prefer BD Forêt and fall back to any dated source.
  for (want in c("bdforet_v2", "bdforet_v1")) {
    for (s in prov$sources) {
      if (identical(s$dataset, want) && !all(is.na(unlist(s$millesime)))) {
        return(suppressWarnings(min(as.integer(unlist(s$millesime)), na.rm = TRUE)))
      }
    }
  }
  for (s in prov$sources) {
    m <- suppressWarnings(as.integer(unlist(s$millesime)))
    if (length(m) && !all(is.na(m))) {
      return(min(m, na.rm = TRUE))
    }
  }
  NULL
}

#' How much of the sample postdates the fuel it is validating
#' @noRd
fev_temporal_bias <- function(fires, millesime, max_lag_years) {
  n_total <- nrow(fires)

  if (is.null(millesime) || all(is.na(millesime))) {
    if (!is.null(max_lag_years)) {
      fev_abort(c(
        "{.arg max_lag_years} was given but the fuel vintage is unknown.",
        i = "There is nothing to compare the fire dates against, so no \\
             filtering can be applied.",
        i = "Pass {.arg millesime}, or build the risk layer through \\
             {.fn fev_fuel_source} with the vintage supplied so it travels in \\
             the provenance.",
        i = "BD For\u00eat v2 does not serve it and no per-department table was \\
             found; see the phase 2 report, section 2 bis."
      ), class = "fev_millesime_required")
    }
    fev_warn(c(
      "The fuel vintage is unknown, so the temporal bias check cannot run.",
      i = "Any skill statistic below is computed against fires that may \\
           postdate the fuel data by an unknown margin -- a stand mapped in \\
           2008 that burnt in 2010 was validated in a state it no longer had.",
      i = "This is the recorded consequence of BD For\u00eat v2 not serving its \\
           vintage, not an oversight."
    ), class = "fev_millesime_missing")
    return(list(fires = fires, n_total = n_total, n_beyond = NA_integer_,
                pct_area = NA_real_, millesime = NA, table = NULL,
                note = "temporal bias not assessed: fuel vintage unknown"))
  }

  millesime <- as.integer(millesime)[1]
  lag <- fires$fire_year - millesime
  area <- fires$area_ha
  area[is.na(area)] <- 0
  total_area <- sum(area)

  threshold <- max_lag_years %||% 5L
  beyond <- !is.na(lag) & lag > threshold
  pct_area <- if (total_area > 0) round(100 * sum(area[beyond]) / total_area, 1) else NA_real_

  tab <- data.frame(
    lag_years = c("<= 0 (fire before the vintage)",
                  paste0("1 to ", threshold),
                  paste0("> ", threshold)),
    n_fires = c(sum(!is.na(lag) & lag <= 0),
                sum(!is.na(lag) & lag > 0 & lag <= threshold),
                sum(beyond)),
    area_ha = round(c(sum(area[!is.na(lag) & lag <= 0]),
                      sum(area[!is.na(lag) & lag > 0 & lag <= threshold]),
                      sum(area[beyond])), 1),
    stringsAsFactors = FALSE
  )
  tab$pct_area <- if (total_area > 0) round(100 * tab$area_ha / total_area, 1) else NA_real_

  if (isTRUE(pct_area > 0)) {
    fev_warn(c(
      "{pct_area}% of the burnt area in this sample postdates the fuel \\
       vintage ({millesime}) by more than {threshold} year{?s}.",
      i = "{sum(beyond)} of {n_total} fire{?s}. Those burnt a landscape the \\
           fuel layer does not describe.",
      i = if (is.null(max_lag_years))
            "They are kept: pass {.arg max_lag_years} to drop them."
          else
            "They are dropped, on your {.arg max_lag_years}."
    ), class = "fev_temporal_bias", .envir = environment())
  }

  kept <- if (is.null(max_lag_years)) fires else fires[!beyond, ]
  list(fires = kept, n_total = n_total, n_beyond = sum(beyond),
       pct_area = pct_area, millesime = millesime, table = tab,
       note = sprintf("vintage %d; %s%% of burnt area beyond %d years",
                      millesime, pct_area, threshold))
}

#' Area under the ROC curve, by rank
#'
#' The Mann-Whitney identity rather than integrating the curve: exact, and it
#' handles ties in the risk values the way the curve's trapezoids do.
#'
#' @noRd
fev_auc <- function(score, positive) {
  n1 <- sum(positive)
  n0 <- sum(!positive)
  ranks <- rank(score, ties.method = "average")
  (sum(ranks[positive]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' @noRd
fev_roc <- function(score, positive, n_thresholds) {
  thresholds <- unique(stats::quantile(
    score, probs = seq(0, 1, length.out = max(n_thresholds, 2L)),
    na.rm = TRUE, names = FALSE
  ))
  thresholds <- sort(unique(c(-Inf, thresholds, Inf)), decreasing = TRUE)
  n1 <- sum(positive)
  n0 <- sum(!positive)
  tpr <- vapply(thresholds, function(t) sum(score >= t & positive) / n1, numeric(1))
  fpr <- vapply(thresholds, function(t) sum(score >= t & !positive) / n0, numeric(1))
  data.frame(threshold = thresholds, tpr = tpr, fpr = fpr)
}

#' Observed against expected, class by class
#' @noRd
fev_class_table <- function(score, positive, class_breaks) {
  class_breaks <- sort(class_breaks)
  if (!is.numeric(class_breaks) || !length(class_breaks)) {
    fev_abort("{.arg class_breaks} must be a numeric vector.")
  }
  lower <- c(0, utils::head(class_breaks, -1))
  labels <- paste(lower, "-", class_breaks)
  idx <- findInterval(score, class_breaks, rightmost.closed = TRUE,
                      left.open = TRUE) + 1L
  idx[idx > length(labels)] <- length(labels)

  expected <- tabulate(idx, nbins = length(labels))
  observed <- tabulate(idx[positive], nbins = length(labels))
  data.frame(
    class = labels,
    cells_total = expected,
    cells_burnt = observed,
    pct_of_area = round(100 * expected / sum(expected), 2),
    pct_of_burnt = round(100 * observed / sum(observed), 2),
    # Above 1, fire is over-represented in this class relative to how much
    # ground it covers. That ratio is the readable form of skill.
    ratio = round((observed / sum(observed)) / (expected / sum(expected)), 2),
    stringsAsFactors = FALSE
  )
}

#' @export
print.fev_validation <- function(x, ...) {
  cli::cli_h1("fev_validation")

  t <- x$temporal
  if (is.na(t$pct_area)) {
    cli::cli_alert_warning(
      "Temporal bias not assessed: the fuel vintage is unknown."
    )
  } else {
    n_used <- nrow(t$fires)
    cli::cli_li("Fuel vintage: {.val {t$millesime}}")
    cli::cli_li("{t$n_total} fire{?s} supplied, {n_used} used")
    if (isTRUE(t$pct_area > 0)) {
      cli::cli_alert_warning(
        "{t$pct_area}% of burnt area postdates the vintage beyond the lag."
      )
    }
  }

  cli::cli_li("{x$n_cells} cell{?s}, {x$n_burnt} burnt \\
               ({round(100 * x$n_burnt / x$n_cells, 1)}%)")
  cli::cli_li("AUC: {.strong {round(x$auc, 3)}}")
  if (x$auc < 0.55) {
    cli::cli_alert_warning("An AUC this close to 0.5 is a coin toss.")
  }

  cli::cli_text("")
  print(x$classes, row.names = FALSE)
  cli::cli_text("")
  cli::cli_alert_info(
    "Cells are not independent observations -- fires are contiguous -- so no \\
     confidence interval is reported. See {.fn fev_validate}."
  )
  invisible(x)
}

#' @export
plot.fev_validation <- function(x, ...) {
  op <- graphics::par(mfrow = c(1, 2))
  on.exit(graphics::par(op), add = TRUE)

  graphics::plot(x$roc$fpr, x$roc$tpr, type = "l", lwd = 2,
                 xlim = c(0, 1), ylim = c(0, 1), asp = 1,
                 xlab = "False positive rate", ylab = "True positive rate",
                 main = sprintf("ROC (AUC = %.3f)", x$auc), ...)
  graphics::abline(0, 1, lty = 3, col = "grey60")

  graphics::barplot(
    rbind(x$classes$pct_of_area, x$classes$pct_of_burnt),
    beside = TRUE, names.arg = x$classes$class, las = 2,
    col = c("grey75", "firebrick"),
    ylab = "% ", main = "Study area vs burnt area"
  )
  graphics::legend("topleft", legend = c("study area", "burnt"),
                   fill = c("grey75", "firebrick"), bty = "n")
  invisible(x)
}
