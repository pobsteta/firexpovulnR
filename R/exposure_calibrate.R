# Fitting the exposure radius to local fires, instead of importing it.
#
# The radii the package ships are Canadian, with one Portuguese validation, and
# `fev_exposure()` has said so at every session since phase 6 without ever
# offering a way out. Everything needed to do better was already here: an AUC in
# validate.R, a fire history in fev_fetch_burnt(), and a temporal bias check.
# This file is the wiring, not new science.
#
# The distinction this file must never blur: a maximum of AUC is a FIT, on the
# fires supplied, with nothing held back. It is not a validation.

#' Fit the exposure radius to local fires
#'
#' Sweeps a series of radii, computes [fev_exposure()] at each, and scores each
#' against observed fires with the same AUC [fev_validate()] uses. Returns the
#' whole sweep, not only the winner, because the shape of the curve says more
#' than its maximum: a flat curve means the radius hardly matters on these
#' fuels, and a sharp one means it does.
#'
#' @section This is a fit, not a validation:
#' The radius that maximises AUC is the radius that best separates burnt from
#' unburnt **in the fires you supplied**, with nothing held out to test it on.
#' Report it as a fitted parameter. A radius fitted on eleven fires in one massif
#' and then quoted as validated would be worse than the Canadian default it
#' replaces, because it would carry a local authority it has not earned.
#'
#' The honest use is the one the package's own limitation calls for: replacing
#' *"30, 100 and 500 m, from Alberta"* with *"250 m, fitted on the Maures fires
#' of 2003-2021, AUC 0.71"* — a statement whose provenance a reader can weigh.
#'
#' @section The temporal bias applies here too, and harder:
#' [fev_validate()] warns when fires postdate the fuel vintage. Fitting on such
#' a sample does not merely describe a biased situation, it **bakes the bias
#' into a parameter**. The check runs first and its verdict travels with the
#' result.
#'
#' @section Radii out of reach are declared, never dropped:
#' [fev_exposure()] refuses `res > radius / 3`. At 25 m every radius below 75 m
#' is unreachable, which on the shipped defaults removes the radiant-heat scale
#' entirely. Those radii come back with `reachable = FALSE` and no AUC rather
#' than being quietly left out of the sweep, because a table that silently
#' contains only what happened to work reads as if it had covered everything.
#'
#' @param fuel A [fev_fuel_source], `fev_layer` or `SpatRaster`, as
#'   [fev_exposure()] takes.
#' @param burnt_areas Observed fires: a [fev_source] from [fev_fetch_burnt()],
#'   an `sf` or a `SpatVector`.
#' @param radii Radii to try, in CRS units. `NULL` uses a geometric sweep from
#'   three cells to a tenth of the smaller extent side, which spans the
#'   published scales without wandering past what the layer can support.
#' @param type Passed to [fev_exposure()] for provenance only; the radius is
#'   what varies here.
#' @param millesime Fuel vintage for the temporal check. `NULL` digs it out of
#'   the provenance, as [fev_validate()] does.
#' @param max_lag_years Passed to the temporal check. `NULL`, the default and
#'   the same as [fev_validate()], reports the bias without filtering on it.
#'   Setting it without a known vintage is an error there and here: there would
#'   be nothing to compare the fire dates against.
#' @param quiet Suppress progress and the standing caveats.
#' @param ... Passed to [fev_exposure()], so `no_burn`, `na_rm` and `trim` apply
#'   identically at every radius.
#'
#' @return An object of class `fev_exposure_calibration`: a list with `table`
#'   (one row per radius: `radius`, `reachable`, `auc`, `n_burnt`, `note`),
#'   `best` (the radius of maximum AUC, `NA` if none was reachable), `at_edge`
#'   (whether that best sits on the first or last radius tried, in which case it
#'   is the edge of the sweep rather than an optimum), `temporal` and
#'   `provenance`.
#'
#' @seealso [fev_exposure()], [fev_exposure_radii()] for the shipped values and
#'   where they come from, [fev_validate()] for the AUC itself.
#'
#' @examples
#' \dontrun{
#' zone <- sf::st_read(system.file("extdata", "maures.gpkg",
#'                                 package = "firexpovulnR"), "study_area")
#' feux <- sf::st_read(system.file("extdata", "maures.gpkg",
#'                                 package = "firexpovulnR"), "burnt_areas")
#' cal <- fev_exposure_calibrate(combustible, feux,
#'                               radii = c(100, 250, 500, 1000))
#' cal
#' plot(cal)
#' }
#'
#' @export
fev_exposure_calibrate <- function(fuel,
                                   burnt_areas,
                                   radii = NULL,
                                   type = "ember",
                                   millesime = NULL,
                                   max_lag_years = NULL,
                                   quiet = FALSE,
                                   ...) {
  probe <- fev_exposure_input(fuel, NULL)
  haz <- probe$raster
  res <- terra::res(haz)[1]

  radii <- radii %||% fev_calibrate_default_radii(haz, res)
  if (!is.numeric(radii) || !length(radii) || anyNA(radii) || any(radii <= 0)) {
    fev_abort("{.arg radii} must be positive numbers, in CRS units.")
  }
  radii <- sort(unique(radii))

  fires <- fev_validate_fires(burnt_areas, haz)
  mil <- millesime %||% fev_provenance_millesime(probe$provenance)
  temporal <- fev_temporal_bias(fires, mil, max_lag_years)
  fires <- temporal$fires
  if (!nrow(fires)) {
    fev_abort(c(
      "No fire is left after the temporal filter.",
      i = "Nothing to fit the radius against."
    ), class = "fev_empty_result")
  }

  burnt <- terra::rasterize(terra::vect(fires), haz, background = 0)
  n_burnt <- as.numeric(terra::global(burnt, "sum", na.rm = TRUE)[1, 1])
  if (!n_burnt) {
    fev_abort("No fire falls on the fuel layer: nothing to fit against.",
              class = "fev_empty_result")
  }

  if (!isTRUE(quiet)) {
    fev_inform(c(
      "Fitting the exposure radius on {nrow(fires)} fire{?s}, \\
       {round(n_burnt)} burnt cell{?s}.",
      "!" = "This is a fit, not a validation: nothing is held out.",
      i = "Report the result as a fitted parameter with its sample."
    ), .envir = environment())
  }

  rows <- lapply(radii, function(rad) {
    if (res > rad / 3) {
      return(data.frame(radius = rad, reachable = FALSE, auc = NA_real_,
                        n_burnt = NA_real_,
                        note = sprintf("needs res <= %s m, layer is %s m",
                                       signif(rad / 3, 4), signif(res, 4)),
                        stringsAsFactors = FALSE))
    }
    e <- tryCatch(
      suppressMessages(fev_exposure(fuel, radius = rad, type = type,
                                    quiet = TRUE, ...)),
      error = function(err) err
    )
    if (inherits(e, "error")) {
      return(data.frame(radius = rad, reachable = FALSE, auc = NA_real_,
                        n_burnt = NA_real_,
                        note = conditionMessage(e), stringsAsFactors = FALSE))
    }
    score <- terra::values(fev_data(e))[, 1]
    pos <- terra::values(burnt)[, 1] > 0
    ok <- !is.na(score) & !is.na(pos)
    # Both classes must be present among the cells that actually carry a value:
    # trimming or a no-burn mask can remove every burnt cell and an AUC over one
    # class is not low, it is undefined.
    if (!any(pos[ok]) || !any(!pos[ok])) {
      return(data.frame(radius = rad, reachable = TRUE, auc = NA_real_,
                        n_burnt = sum(pos[ok]),
                        note = "only one class left after masking",
                        stringsAsFactors = FALSE))
    }
    # A constant score gives an AUC of exactly 0.5, which reads as "no skill"
    # when it actually means "no measurement". It happens for a real reason: a
    # fuel source covering only wooded formations is 1 inside its polygons and
    # NA outside, never 0, so every window that returns at all returns a full
    # ring. Merge a complete-coverage source underneath before fitting.
    if (length(unique(score[ok])) < 2L) {
      return(data.frame(radius = rad, reachable = TRUE, auc = NA_real_,
                        n_burnt = sum(pos[ok]),
                        note = "exposure is constant -- fuel layer has no non-burnable cell",
                        stringsAsFactors = FALSE))
    }
    data.frame(radius = rad, reachable = TRUE,
               auc = fev_auc(score[ok], pos[ok]), n_burnt = sum(pos[ok]),
               note = NA_character_, stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, rows)

  best <- if (all(is.na(tab$auc))) NA_real_ else tab$radius[which.max(tab$auc)]

  # An optimum sitting on the first or last radius tried is not an optimum, it
  # is the edge of the sweep. On the Maures at 25 m the AUC falls monotonically
  # from 75 m -- the finest radius the resolution allows -- so the best value
  # the fit can name is the smallest it was allowed to try, and the real one may
  # be below it, out of reach until the grid is finer.
  scored <- tab$radius[!is.na(tab$auc)]
  at_edge <- !is.na(best) && length(scored) > 1L &&
    (best == min(scored) || best == max(scored))

  prov <- fev_prov_add_step(
    probe$provenance %||% fev_prov_new(crs_work = NA),
    fun = "fev_exposure_calibrate",
    params = list(radii = paste(radii, collapse = ", "),
                  res = signif(res, 6), n_fires = nrow(fires),
                  n_burnt_cells = round(n_burnt),
                  best_radius = best, best_at_sweep_edge = at_edge,
                  best_auc = if (is.na(best)) NA_real_ else round(max(tab$auc, na.rm = TRUE), 4),
                  millesime = mil %||% NA),
    notes = paste0("radius fitted on the supplied fires, nothing held out: ",
                   "a fit, not a validation")
  )

  structure(list(table = tab, best = best, at_edge = at_edge,
                 temporal = temporal, n_fires = nrow(fires), res = res,
                 provenance = prov),
            class = "fev_exposure_calibration")
}

#' A sweep that spans the published scales without leaving the layer
#'
#' Three cells is the finest radius `fev_exposure()` will accept; a tenth of the
#' smaller side keeps the window from eating the extent, which is the other
#' error the function refuses. Geometric rather than linear, because the
#' published radii are themselves geometric -- 30, 100, 500 -- and a linear
#' sweep would spend most of its points at the coarse end where the metric
#' changes least.
#'
#' @noRd
fev_calibrate_default_radii <- function(haz, res) {
  span <- min(terra::nrow(haz), terra::ncol(haz)) * res
  lo <- res * 3
  hi <- max(span / 10, lo * 2)
  signif(exp(seq(log(lo), log(hi), length.out = 7L)), 2)
}

#' @export
print.fev_exposure_calibration <- function(x, ...) {
  cli::cli_h1("fev_exposure_calibration")
  cli::cli_alert_warning(
    "A fit on {x$n_fires} fire{?s}, nothing held out. Not a validation."
  )
  if (!is.null(x$temporal) && !is.null(x$temporal$note)) {
    cli::cli_li("Temporal check: {x$temporal$note}")
  }
  tab <- x$table
  tab$auc <- ifelse(is.na(tab$auc), "--", format(round(tab$auc, 3), nsmall = 3))
  tab$note[is.na(tab$note)] <- ""
  print(tab[, c("radius", "reachable", "auc", "note")], row.names = FALSE)
  if (is.na(x$best)) {
    cli::cli_alert_danger("No radius was reachable at {signif(x$res, 4)} m.")
  } else {
    cli::cli_alert_success(
      "Best: {x$best} m (AUC {round(max(x$table$auc, na.rm = TRUE), 3)})."
    )
    if (isTRUE(x$at_edge)) {
      cli::cli_alert_warning(
        "That is the edge of the sweep, not an interior optimum: the best \
         radius may lie outside the range tried."
      )
    }
  }
  invisible(x)
}

#' @export
plot.fev_exposure_calibration <- function(x, ...) {
  tab <- x$table[x$table$reachable & !is.na(x$table$auc), ]
  if (!nrow(tab)) {
    fev_abort("Nothing to plot: no radius produced an AUC.")
  }
  plot(tab$radius, tab$auc, type = "b", log = "x",
       xlab = "radius (m, log scale)", ylab = "AUC",
       main = "Exposure radius fitted on observed fires", ...)
  # 0.5 is what a coin gets. Without the line a curve running from 0.52 to 0.55
  # looks like a strong optimum.
  graphics::abline(h = 0.5, lty = 3)
  invisible(x)
}
