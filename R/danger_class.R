# Classifying a danger layer, with the scheme recorded.
#
# fev_fwi_classes() ships two published schemes whose breaks differ by a factor
# of three, and fev_fwi_thresholds() derives a third from the record itself. A
# classified map is therefore uninterpretable without knowing which produced
# it, and a figure in a paper carries no such label. This function exists so
# that the scheme travels with the raster rather than with the memory of
# whoever ran the script.

#' Classify fire danger into named classes
#'
#' Cuts a Fire Weather Index layer into danger classes, and records which
#' scheme's breaks were used.
#'
#' @section Why this is not just `terra::classify()`:
#' The two published schemes disagree substantially — an FWI of 40 is
#' *Very High* under the EFFIS operational breaks and *Extreme* under the
#' caliver breaks derived from ERA-Interim. A classified map is a different map
#' under each, and nothing in a GeoTIFF says which one was applied. Here the
#' scheme, its breaks and its source go into the provenance record with the
#' result, so the question is answerable six months later.
#'
#' @section Classifying percentile ranks instead:
#' If your layer is a [fev_fwi_percentile()] result, absolute FWI breaks are
#' meaningless for it and this function refuses. Percentile ranks are already
#' calibrated; cut them on percentile breaks of your own choosing, and say what
#' they are.
#'
#' @param x A `SpatRaster` of Fire Weather Index values, a [fev_source] or a
#'   `fev_layer`.
#' @param scheme `"effis"` (default), `"caliver_europe"`, or `"custom"` when
#'   `breaks` is supplied.
#' @param breaks Five interior class boundaries, overriding `scheme`.
#'   [fev_fwi_thresholds()] returns a set derived from your own record.
#' @param labels Class labels, one more than `breaks`.
#'
#' @return A `fev_danger_layer` holding a categorical `SpatRaster` named
#'   `danger_class`.
#'
#' @seealso [fev_fwi_classes()] for the schemes and how they differ,
#'   [fev_fwi_thresholds()] to derive breaks from a record.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- seq(0, 75, length.out = 16)
#' terra::freq(fev_data(fev_danger_class(r)))
#' terra::freq(fev_data(fev_danger_class(r, "caliver_europe")))
#'
#' @export
fev_danger_class <- function(x,
                             scheme = c("effis", "caliver_europe", "custom"),
                             breaks = NULL,
                             labels = NULL) {
  scheme <- match.arg(scheme)
  if (identical(scheme, "custom") && is.null(breaks)) {
    fev_abort(c(
      "{.code scheme = \"custom\"} needs {.arg breaks}.",
      i = "Derive them from your own record with {.fn fev_fwi_thresholds}."
    ))
  }
  if (!is.null(breaks) && !identical(scheme, "custom")) {
    scheme <- "custom"
  }

  prov <- fev_layer_prov(x)
  role <- if (inherits(x, "fev_layer")) x$role else NA_character_
  if (identical(role, "fwi_percentile")) {
    fev_abort(c(
      "This layer holds percentile ranks, not Fire Weather Index values.",
      i = "Absolute FWI breaks mean nothing against a 0-100 rank -- every \\
           cell would land in the top class.",
      i = "Percentile ranks are already calibrated. Cut them on percentile \\
           breaks you choose and state, e.g. {.code terra::classify()} at 90 \\
           and 98."
    ), class = "fev_wrong_scale")
  }

  r <- fev_as_raster(x, "x")[[1]]
  tab <- if (identical(scheme, "custom")) {
    fev_fwi_classes(breaks = as.numeric(breaks), labels = labels)
  } else {
    fev_fwi_classes(scheme, labels = labels)
  }

  rcl <- cbind(tab$lower, tab$upper, seq_len(nrow(tab)))
  out <- terra::classify(r, rcl, include.lowest = TRUE, right = FALSE)
  levels(out) <- data.frame(id = seq_len(nrow(tab)),
                            class = as.character(tab$class))
  names(out) <- "danger_class"

  source_note <- switch(
    scheme,
    effis = "EFFIS Fire Danger Forecast page, verified 2026-08-15",
    caliver_europe = paste("Vitolo et al. 2018, PLoS ONE 13(1):e0189419;",
                           "ERA-Interim 1980-2016, April-October, Europe"),
    custom = "user-supplied breaks"
  )

  prov <- prov %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_danger_class",
    params = list(scheme = scheme, breaks = tab$upper[-nrow(tab)],
                  labels = as.character(tab$class),
                  source = source_note),
    notes = "class breaks differ by a factor of three between published schemes"
  )

  new_fev_layer(out, role = "danger_class", provenance = prov,
                units = paste0("danger class (", scheme, ")"),
                class = "fev_danger_layer")
}
