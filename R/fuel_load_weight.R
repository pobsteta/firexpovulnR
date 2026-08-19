# The bridge between the continuous register and the graded exposure path.
#
# Phase 11 step 4, and deliberately the smallest addition of the four. Both
# halves already existed: fev_fuel_source() has carried a continuous register
# since phase 4, and fev_exposure() has accepted a graded availability layer
# since phase 6. Nothing joined them, so an exposure computed after a LiDAR
# campaign was still a proportion of a binary mask.
#
# The measurement that makes this worth doing: on 32 windows across the Maures,
# within the SINGLE class FF1G06-06 (holm oak, 520 cells), crown fuel load runs
# from 0.05 to 1.98 kg/m2. A binary mask counts those cells identically.

#' Turn a measured fuel metric into a graded availability
#'
#' Rescales one continuous metric — crown bulk density, crown fuel load,
#' whatever [fev_fuel_lidar()] produced — onto `[0, 1]` and labels it
#' `"availability"`, which is what [fev_exposure()] consumes to weight each
#' neighbouring cell by how much fuel it actually holds instead of whether it
#' holds any.
#'
#' @section Why this is a rescale and not a model:
#' There is no physical mapping from crown bulk density to a probability of
#' contributing to spread, and this function does not invent one. It puts the
#' metric on the scale the graded path expects, in the way you choose, and
#' records the choice. The result is an ordering of cells by measured fuel, not
#' an estimate of anything.
#'
#' That is why the method matters and why it is recorded: `"minmax"` says a cell
#' at half the maximum load contributes half, `"percentile_rank"` says a cell in
#' the median contributes half. Those are different claims and the data does not
#' choose between them.
#'
#' @section What `NA` means here, and why it is not zero:
#' LiDAR HD has not flown everywhere, and where it has not, the metric is `NA`.
#' `NA` is **not** "no fuel" — it is "not measured", and the difference decides
#' whether the resulting exposure map is a measurement or a fiction.
#'
#' This function leaves `NA` as `NA`. [fev_exposure()] with its default
#' `na_rm = FALSE` then returns `NA` for any cell whose neighbourhood is not
#' fully measured, which looks like a hole and is one. Filling it would take a
#' campaign covering 2 km² of the Maures and quietly extend its authority over
#' the other 300.
#'
#' `fill` exists for the case where you have a defensible value for the
#' unmeasured ground — a class median from [fev_fuel_availability()], say — and
#' it writes into the record that you supplied it.
#'
#' @param x A [fev_fuel_source] carrying a continuous register, a `fev_layer`,
#'   or a `SpatRaster`.
#' @param metric Name of the layer to use, e.g. `"CBD_max"`, `"CFL"`, `"TFL"`.
#'   Required when the input holds more than one.
#' @param method `"minmax"`, `"percentile_rank"` or `"log"`, as
#'   [fev_vuln_layer()] uses, and with the same consequences: the first two are
#'   extent-dependent, so the same stand scores differently under a different
#'   area of interest.
#' @param clamp Optional `c(low, high)` in the metric's own units, applied
#'   before rescaling, so one exceptional cell does not set the whole scale.
#' @param fill Value in `[0, 1]` for unmeasured cells, or `NULL` to leave them
#'   `NA`. Default `NULL`.
#' @param quiet Suppress the report.
#'
#' @return A `fev_layer` of role `"availability"`, values in `[0, 1]`, ready to
#'   pass to [fev_exposure()] or [fev_exposure_aniso()].
#'
#' @seealso [fev_fuel_lidar()] for the metrics, [fev_exposure()] for the graded
#'   path, [fev_fuel_availability()] for the categorical equivalent.
#'
#' @examples
#' g <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' cbd <- terra::setValues(g, seq(0.02, 0.4, length.out = 100))
#' names(cbd) <- "CBD_max"
#' w <- fev_fuel_load_weight(cbd, metric = "CBD_max", quiet = TRUE)
#' range(terra::values(fev_data(w)), na.rm = TRUE)
#'
#' @export
fev_fuel_load_weight <- function(x,
                                 metric = NULL,
                                 method = c("minmax", "percentile_rank", "log"),
                                 clamp = NULL,
                                 fill = NULL,
                                 quiet = FALSE) {
  method <- match.arg(method)

  prov <- fev_layer_prov(x) %||% attr(x, "provenance") %||%
    fev_prov_new(crs_work = NA)
  r <- fev_as_raster(x, "fuel metric")

  if (terra::nlyr(r) > 1L) {
    if (is.null(metric)) {
      fev_abort(c(
        "{.arg metric} is required: the input holds \\
         {terra::nlyr(r)} layers.",
        i = "Available: {.val {names(r)}}.",
        i = "Exposure weights one quantity, and which one is a decision about \\
             what carries fire -- not something to take by position."
      ), .envir = environment())
    }
    if (!metric %in% names(r)) {
      fev_abort(c(
        "No layer named {.val {metric}}.",
        i = "Available: {.val {names(r)}}."
      ), .envir = environment())
    }
    r <- r[[metric]]
  } else if (!is.null(metric) && !identical(names(r), metric)) {
    fev_abort(c(
      "The single layer is named {.val {names(r)}}, not {.val {metric}}.",
      i = "Pass the name it has, or drop {.arg metric}."
    ), .envir = environment())
  }
  metric <- names(r)

  n_total <- terra::ncell(r)
  n_measured <- as.numeric(terra::global(!is.na(r), "sum", na.rm = TRUE)[1, 1])

  if (!n_measured) {
    fev_abort(c(
      "{.val {metric}} is entirely {.val NA}: nothing was measured here.",
      i = "A LiDAR campaign covers what it flew over, and this area is not in \\
           it."
    ), class = "fev_all_na", .envir = environment())
  }

  if (!is.null(clamp)) {
    if (!is.numeric(clamp) || length(clamp) != 2L || clamp[1] >= clamp[2]) {
      fev_abort("{.arg clamp} must be {.code c(low, high)} with low < high.")
    }
    r <- terra::clamp(r, clamp[1], clamp[2], values = TRUE)
  }

  rng <- as.numeric(terra::global(r, range, na.rm = TRUE)[1, ])
  w <- switch(
    method,
    minmax = if (diff(rng) == 0) {
      # A constant metric rescales to nothing at all: 0/0. One value everywhere
      # means the measurement separates no cell from any other, so the honest
      # graded weight is a flat one, and it is worth saying out loud.
      terra::setValues(r, ifelse(is.na(terra::values(r)), NA_real_, 1))
    } else {
      (r - rng[1]) / diff(rng)
    },
    percentile_rank = fev_rank_unit(r),
    log = {
      if (rng[1] < 0) {
        fev_abort(c(
          "{.val {method}} needs non-negative values; {.val {metric}} goes \\
           down to {.val {signif(rng[1], 4)}}.",
          i = "Pass {.arg clamp} to cut the negative tail if it is noise."
        ), .envir = environment())
      }
      lg <- log1p(r)
      lr <- as.numeric(terra::global(lg, range, na.rm = TRUE)[1, ])
      if (diff(lr) == 0) lg * 0 + 1 else (lg - lr[1]) / diff(lr)
    }
  )

  filled <- FALSE
  if (!is.null(fill)) {
    if (!is.numeric(fill) || length(fill) != 1L || is.na(fill) ||
        fill < 0 || fill > 1) {
      fev_abort("{.arg fill} must be a single number in {.code [0, 1]}.")
    }
    w <- terra::classify(w, cbind(NA, fill))
    filled <- TRUE
  }
  names(w) <- "availability"

  pct <- 100 * n_measured / n_total
  if (!quiet) {
    cli::cli_h1("fev_fuel_load_weight: {metric}")
    cli::cli_li("Method: {method}\\
                {if (!is.null(clamp)) paste0(', clamped to [', clamp[1], ', ', clamp[2], ']')}")
    cli::cli_li("{signif(rng[1], 3)} to {signif(rng[2], 3)} over \\
                {round(pct)}% of cells")
    if (pct < 99 && !filled) {
      cli::cli_alert_warning(
        "{round(100 - pct)}% of cells are unmeasured and stay {.val NA}. \\
         {.fn fev_exposure} will return {.val NA} wherever a neighbourhood is \\
         not fully measured -- that hole is real, not a defect."
      )
    }
    if (filled) {
      cli::cli_alert_warning(
        "Unmeasured cells were filled with {.val {fill}}: a value you \\
         supplied, not one that was measured. It is in the record."
      )
    }
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_fuel_load_weight",
    params = list(metric = metric, method = method,
                  clamp = if (is.null(clamp)) NA else paste(clamp, collapse = ", "),
                  range_in = paste(signif(rng, 6), collapse = ", "),
                  measured_pct = signif(pct, 4),
                  fill = fill %||% NA),
    notes = paste0(
      "continuous fuel metric rescaled to a graded availability; a rescale, ",
      "not a model of contribution to spread",
      if (filled) "; unmeasured cells filled with a supplied value" else
        "; unmeasured cells left NA"
    )
  )

  new_fev_layer(w, role = "availability", provenance = prov,
                units = paste0("0-1, from ", metric))
}

#' Percentile rank onto `[0, 1]`, NA-preserving
#' @noRd
fev_rank_unit <- function(r) {
  v <- terra::values(r)[, 1]
  ok <- !is.na(v)
  out <- rep(NA_real_, length(v))
  if (sum(ok) > 1L) {
    out[ok] <- (rank(v[ok], ties.method = "average") - 1) / (sum(ok) - 1)
  } else {
    out[ok] <- 1
  }
  terra::setValues(r, out)
}
