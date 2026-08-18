# Confronting a categorical fuel layer with an independent continuous
# measurement.
#
# Phase 10 step 2 exists because CLCplus Backbone's weakest class -- 5,
# low-growing woody plants -- is the maquis, and the producers say so. A
# classification cannot validate itself, so the question has to be put to
# something that MEASURED the ground rather than inferred it. LiDAR HD does,
# which is the whole point of phase 8.
#
# Nothing here is CLCplus-specific: the same confrontation checks whether BD
# Forêt's "forêt fermée" really is closed, or whether CORINE 323 really carries
# understorey.

#' Profile fuel classes against an independent measurement
#'
#' Answers the question a classification cannot answer about itself: do the
#' pixels a land cover product calls class X actually carry what the class
#' claims? Summarises continuous metrics — LiDAR-derived understorey height,
#' fuel load by stratum, cover — over the cells of each categorical class, and
#' quantifies how separable one class is from the rest.
#'
#' @section Why LiDAR is the reference and not the other way round:
#' An optical classification infers vegetation structure from reflectance; LiDAR
#' measures it. Under a closed canopy the maquis is invisible to Sentinel-2 and
#' plainly there in a point cloud. So the LiDAR layer is the reference, the
#' classification is what is being tested, and the direction is not symmetric.
#'
#' @section Separability, and what it does not say:
#' For a named `class`, the reported statistic per metric is the probability
#' that a randomly chosen cell of that class scores higher than a randomly
#' chosen cell outside it — the Mann-Whitney statistic, the same one
#' [fev_validate()] reports as AUC. 0.5 means the class carries no information
#' about the metric; 1 means perfect separation.
#'
#' It is **descriptive**. No confidence interval is reported, for the same
#' reason as in `fev_validate()`: neighbouring cells are not independent, so any
#' interval computed cell-wise would be far too narrow. A high value on a small
#' plot is a reason to look further, not a validation.
#'
#' @section On resampling, which direction matters:
#' The two layers rarely share a grid. The reference is resampled onto the
#' fuel grid, because the fuel grid is the one the analysis runs on. When the
#' fuel grid is the **finer** of the two — a 10 m classification against a 25 m
#' LiDAR product, which is exactly the phase 10 case — this is upsampling, and
#' it creates no information. Each coarse measurement is then shared by several
#' fine cells, so the effective sample is smaller than the cell count suggests
#' and the statistic is more optimistic than it looks. The function says so
#' rather than leaving it to be noticed.
#'
#' @param fuel An [fev_fuel_source] with a categorical register, or a
#'   categorical `SpatRaster`.
#' @param reference An [fev_fuel_source] with a continuous register, or a
#'   numeric `SpatRaster`. Typically the output of [fev_fuel_lidar()].
#' @param metrics Names of the reference layers to profile. `NULL` takes the
#'   understorey-bearing subset when it is present — `H_Bush`, `FL_0_1`,
#'   `FL_1_3`, `Cover`, `PAI_tot` — and otherwise every layer.
#' @param class Class to test for separability, as it appears in the fuel
#'   layer's levels (e.g. `"5"` for CLCplus low-growing woody plants). `NULL`
#'   profiles every class without computing a separability statistic.
#' @param min_cells Classes with fewer cells than this are reported but
#'   excluded from the separability statistic. Default 30.
#' @param quiet Suppress the notes about resampling and sample size.
#'
#' @return An object of class `fev_fuel_profile`: a list with `summary` (one row
#'   per class and metric: `n`, `median`, `q25`, `q75`), `explained` (the
#'   between-class share of variance per metric), `separability` (one row per
#'   metric when `class` is given), and `notes`.
#'
#' @seealso [fev_fuel_lidar()] for the reference layer, [fev_validate()] for the
#'   same statistic applied to burnt area.
#'
#' @examples
#' # A classification that gets the shrub class right, against a measurement.
#' cls <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 500,
#'                    ymin = 0, ymax = 500, crs = "EPSG:2154")
#' terra::values(cls) <- rep(c(4, 5), each = 200)
#' levels(cls) <- data.frame(id = c(4, 5), class = c("4", "5"))
#'
#' meas <- cls
#' terra::values(meas) <- c(rep(0.5, 200), rep(4.5, 200))
#' names(meas) <- "H_Bush"
#'
#' p <- fev_fuel_profile(cls, meas, class = "5", quiet = TRUE)
#' p
#'
#' @export
fev_fuel_profile <- function(fuel,
                             reference,
                             metrics = NULL,
                             class = NULL,
                             min_cells = 30,
                             quiet = FALSE) {
  cat_r <- fev_profile_categorical(fuel)
  ref_r <- fev_profile_continuous(reference)

  metrics <- metrics %||% fev_profile_default_metrics(names(ref_r))
  missing <- setdiff(metrics, names(ref_r))
  if (length(missing)) {
    fev_abort(c(
      "The reference has no layer{?s} {.val {missing}}.",
      i = "It carries {.val {names(ref_r)}}."
    ), class = "fev_profile_missing_metric", .envir = environment())
  }
  ref_r <- ref_r[[metrics]]

  notes <- character()

  # The fuel grid is the one the analysis runs on, so the reference moves.
  fuel_res <- terra::res(cat_r)[1]
  ref_res <- terra::res(ref_r)[1]
  if (!terra::compareGeom(cat_r, ref_r, stopOnError = FALSE)) {
    if (!terra::same.crs(cat_r, ref_r)) {
      ref_r <- terra::project(ref_r, terra::crs(cat_r), method = "bilinear")
    }
    ref_r <- terra::resample(ref_r, cat_r, method = "bilinear")
    notes <- c(notes, sprintf(
      "Reference resampled from %g m to the %g m fuel grid (bilinear).",
      ref_res, fuel_res
    ))
  }

  upsampled <- ref_res > fuel_res * 1.001
  if (upsampled) {
    ratio <- (ref_res / fuel_res)^2
    notes <- c(notes, sprintf(
      paste0("This is UPSAMPLING: one %g m measurement now covers about %.1f ",
             "cells of the %g m grid, so the effective sample is smaller than ",
             "the cell count and the statistic is optimistic."),
      ref_res, ratio, fuel_res
    ))
  }

  lv <- fev_cat_levels(cat_r)
  codes <- terra::values(cat_r, mat = FALSE)
  if (!is.null(lv) && nrow(lv)) {
    labels <- stats::setNames(as.character(lv[[2]]), as.character(lv[[1]]))
    codes <- unname(labels[as.character(codes)])
  } else {
    codes <- as.character(codes)
  }

  vals <- terra::values(ref_r)
  keep <- !is.na(codes)
  codes <- codes[keep]
  vals <- vals[keep, , drop = FALSE]
  if (!length(codes)) {
    fev_abort("No cell carries both a class and a reference value.",
              class = "fev_profile_empty")
  }

  summary_df <- fev_profile_summarise(codes, vals, metrics)
  explained <- fev_profile_explained(codes, vals, metrics)

  separability <- NULL
  if (!is.null(class)) {
    separability <- fev_profile_separability(codes, vals, metrics, class,
                                             min_cells)
  }

  if (!quiet) {
    fev_profile_report(notes, summary_df, explained, class, separability,
                       min_cells)
  }

  structure(
    list(summary = summary_df, explained = explained,
         separability = separability, notes = notes,
         class_tested = class, upsampled = upsampled),
    class = "fev_fuel_profile"
  )
}

#' The layers that carry the understorey, when the reference has them
#'
#' LidarForFuel names these consistently, and they are the ones a shrub class
#' has to be tested against: bush height, load in the first and second metre
#' bands, cover and total plant area. Anything else in the stack describes the
#' canopy, which is not what is in doubt here.
#'
#' @noRd
fev_profile_default_metrics <- function(available) {
  wanted <- c("H_Bush", "FL_0_1", "FL_1_3", "Cover", "PAI_tot")
  hit <- intersect(wanted, available)
  if (length(hit)) hit else available
}

# A class layer with more distinct values than this is almost certainly a
# measurement passed by mistake. CORINE has 44 codes, BD Forêt 32, CLCplus 12;
# 255 leaves room for any byte-coded nomenclature and still catches the error.
.FEV_PROFILE_MAX_CLASSES <- 255L

#' @noRd
fev_profile_categorical <- function(x) {
  r <- if (inherits(x, "fev_fuel_source")) fev_fuel_categorical(x) else x
  if (is.null(r) || !inherits(r, "SpatRaster")) {
    fev_abort(c(
      "{.arg fuel} needs a categorical register.",
      i = "A profile compares CLASSES against a measurement; there is nothing \\
           to group by without them."
    ), class = "fev_profile_no_categorical")
  }
  idx <- match("class", names(r))
  if (is.na(idx)) idx <- 1L
  r <- r[[idx]]

  # Being a SpatRaster proves nothing -- a measurement is one too. A layer with
  # a level table is a classification; a bare numeric one is only usable as
  # classes if its values behave like codes. Without this a continuous layer
  # passed by mistake would be grouped into thousands of one-cell "classes" and
  # report a perfect, meaningless fit.
  if (is.null(fev_cat_levels(r))) {
    v <- terra::values(r, mat = FALSE)
    v <- v[!is.na(v)]
    code_like <- length(v) > 0 &&
      isTRUE(all(abs(v - round(v)) < .Machine$double.eps^0.5)) &&
      length(unique(v)) <= .FEV_PROFILE_MAX_CLASSES
    if (!code_like) {
      fev_abort(c(
        "{.arg fuel} is not a classification.",
        x = "It has no level table, and its values are not class codes: \\
             {length(unique(v))} distinct value{?s}, not all whole numbers.",
        i = "Pass a categorical layer, or an {.cls fev_fuel_source} whose \\
             categorical register is populated."
      ), class = "fev_profile_no_categorical", .envir = environment())
    }
  }
  r
}

#' @noRd
fev_profile_continuous <- function(x) {
  r <- if (inherits(x, "fev_fuel_source")) fev_fuel_continuous(x) else x
  if (is.null(r) || !inherits(r, "SpatRaster")) {
    fev_abort(c(
      "{.arg reference} needs a continuous register.",
      i = "The point of this function is to test a classification against a \\
           MEASUREMENT, so the reference cannot be another set of classes."
    ), class = "fev_profile_no_continuous")
  }
  # A categorical reference would compare a classification with a classification,
  # which measures agreement between two guesses rather than testing either.
  if (!is.null(fev_cat_levels(r))) {
    fev_abort(c(
      "{.arg reference} is categorical, and the reference must be measured.",
      i = "Comparing two classifications reports how far they agree, not \\
           whether either is right.",
      i = "Use a continuous layer -- {.fn fev_fuel_lidar} output, or any \\
           numeric raster of a measured quantity."
    ), class = "fev_profile_no_continuous")
  }
  r
}

#' One row per class and metric
#' @noRd
fev_profile_summarise <- function(codes, vals, metrics) {
  classes <- sort(unique(codes))
  rows <- lapply(classes, function(cl) {
    sel <- codes == cl
    do.call(rbind, lapply(seq_along(metrics), function(j) {
      v <- vals[sel, j]
      v <- v[!is.na(v)]
      q <- if (length(v)) {
        stats::quantile(v, c(0.25, 0.5, 0.75), names = FALSE)
      } else {
        rep(NA_real_, 3)
      }
      data.frame(class = cl, metric = metrics[j], n = length(v),
                 q25 = q[1], median = q[2], q75 = q[3],
                 stringsAsFactors = FALSE)
    }))
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' How much of a metric the classification accounts for at all
#'
#' The between-class share of total variance. It answers the question the
#' package's central limitation is about: not whether one class is distinctive,
#' but whether KNOWING THE CLASS tells you anything about the understorey. A
#' value near 0 means two cells of the same class differ as much as two cells
#' picked at random -- which is precisely what "a holm oak stand with dense
#' understorey and the same without are identical in both databases" means, put
#' as a number.
#'
#' Descriptive, like everything else here: no test, no interval. Neighbouring
#' cells are not independent and the shipped plots are small.
#'
#' @noRd
fev_profile_explained <- function(codes, vals, metrics) {
  do.call(rbind, lapply(seq_along(metrics), function(j) {
    v <- vals[, j]
    ok <- !is.na(v)
    v <- v[ok]
    g <- codes[ok]
    frac <- NA_real_
    if (length(v) > 1L && length(unique(g)) > 1L) {
      total <- sum((v - mean(v))^2)
      if (total > 0) {
        within <- sum(vapply(split(v, g), function(x) sum((x - mean(x))^2), 0))
        frac <- 1 - within / total
      }
    }
    data.frame(metric = metrics[j], n = length(v),
               n_classes = length(unique(g)),
               explained = frac, stringsAsFactors = FALSE)
  }))
}

#' How well one class separates from the rest, per metric
#' @noRd
fev_profile_separability <- function(codes, vals, metrics, class, min_cells) {
  present <- unique(codes)
  if (!class %in% present) {
    fev_abort(c(
      "Class {.val {class}} is not in the fuel layer.",
      i = "It carries {.val {sort(present)}}."
    ), class = "fev_profile_absent_class", .envir = environment())
  }
  positive <- codes == class
  n_pos <- sum(positive)
  n_neg <- sum(!positive)

  do.call(rbind, lapply(seq_along(metrics), function(j) {
    v <- vals[, j]
    ok <- !is.na(v)
    pos <- positive[ok]
    stat <- if (sum(pos) < min_cells || sum(!pos) < min_cells) {
      NA_real_
    } else {
      # Reuses fev_validate()'s Mann-Whitney identity rather than a second
      # implementation, including its integer-overflow fix.
      fev_auc(v[ok], pos)
    }
    data.frame(metric = metrics[j], n_class = n_pos, n_other = n_neg,
               separability = stat, stringsAsFactors = FALSE)
  }))
}

#' @noRd
fev_profile_report <- function(notes, summary_df, explained, class,
                               separability, min_cells) {
  for (n in notes) {
    fev_inform(n)
  }
  n_classes <- length(unique(summary_df$class))
  fev_inform("Profiled {n_classes} class{?es} over \\
              {length(unique(summary_df$metric))} metric{?s}.",
             .envir = environment())

  best <- explained[which.max(explained$explained), ]
  worst <- explained[which.min(explained$explained), ]
  if (nrow(best) && is.finite(best$explained)) {
    fev_inform(c(
      "Class membership accounts for {round(100 * best$explained, 1)}% of the \\
       variance in {.val {best$metric}} at best, \\
       {round(100 * worst$explained, 1)}% at worst.",
      i = "Near zero means two cells of the same class differ as much as two \\
           picked at random -- the classification carries no information \\
           about that metric."
    ), .envir = environment())
  }

  if (is.null(separability)) {
    return(invisible(TRUE))
  }
  if (all(is.na(separability$separability))) {
    fev_warn(c(
      "No separability statistic: fewer than {min_cells} cells on one side.",
      i = "Class {.val {class}} has {separability$n_class[1]} cell{?s} against \\
           {separability$n_other[1]} outside it.",
      i = "The profile above still stands; only the statistic is withheld."
    ), class = "fev_profile_too_small", .envir = environment())
    return(invisible(TRUE))
  }
  best <- separability[which.max(separability$separability), ]
  fev_inform(c(
    "Class {.val {class}} separates best on {.val {best$metric}}: \\
     {.strong {round(best$separability, 3)}}.",
    i = "0.5 is no information. Descriptive only -- neighbouring cells are \\
         not independent, so no interval is reported."
  ), .envir = environment())
  invisible(TRUE)
}

#' @export
print.fev_fuel_profile <- function(x, ...) {
  cli::cli_h1("fev_fuel_profile")
  if (length(x$notes)) {
    for (n in x$notes) {
      cli::cli_alert_info(n)
    }
  }
  print(x$summary, row.names = FALSE)
  cli::cli_h2("Variance accounted for by class membership")
  print(x$explained, row.names = FALSE)
  if (!is.null(x$separability)) {
    cli::cli_h2(paste0("Separability of class ", x$class_tested))
    print(x$separability, row.names = FALSE)
  }
  invisible(x)
}
