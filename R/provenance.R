# Provenance record: sources, parameters and an ordered operation log.
#
# The brief's first requirement is that an analysis can be replayed six months
# later. That is only true if every parameter that changed the numbers is
# written down at the moment it was used -- not reconstructed afterwards from
# the script, which may have been edited since. So every fev_* function that
# transforms data appends a step here, and the record travels with the object.

#' Create an empty provenance record
#'
#' @param crs_work Integer EPSG code of the working CRS.
#' @param ... Further named fields stored at the top level.
#' @return A list of class `fev_provenance`.
#' @noRd
fev_prov_new <- function(crs_work = NULL, ...) {
  structure(
    list(
      package  = list(
        name    = "firexpovulnR",
        version = as.character(utils::packageVersion("firexpovulnR")),
        created = fev_now()
      ),
      session  = fev_session_info(),
      crs_work = crs_work,
      sources  = list(),
      steps    = list(),
      ...
    ),
    class = c("fev_provenance", "list")
  )
}

#' Reduce an arbitrary R value to something a YAML file can carry
#'
#' Parameters passed to fev_* functions may be rasters, sf objects, functions
#' or environments. Writing those verbatim into the record is impossible, and
#' dropping them silently would defeat the purpose. Instead each is replaced
#' by a short, honest description of what it was.
#'
#' @noRd
fev_prov_scalarise <- function(x, .depth = 0L) {
  if (.depth > 5L) {
    return("<nested too deep>")
  }
  if (is.null(x)) {
    return("NULL")
  }
  if (inherits(x, "SpatRaster")) {
    return(sprintf(
      "<SpatRaster %dx%dx%d, res %s, %s>",
      terra::nrow(x), terra::ncol(x), terra::nlyr(x),
      paste(signif(terra::res(x), 6), collapse = "x"),
      fev_crs_label(x)
    ))
  }
  if (inherits(x, c("SpatVector", "sf", "sfc"))) {
    n <- if (inherits(x, "sfc")) length(x) else nrow(x)
    return(sprintf("<%s, %d feature%s, %s>",
                   class(x)[1], n, if (identical(n, 1L)) "" else "s",
                   fev_crs_label(x)))
  }
  if (inherits(x, "crs")) {
    return(fev_crs_label(x))
  }
  if (is.function(x)) {
    return("<function>")
  }
  if (inherits(x, c("Date", "POSIXt"))) {
    return(format(x))
  }
  if (is.atomic(x) && length(x) <= 24L) {
    return(x)
  }
  if (is.atomic(x)) {
    return(sprintf("<%s vector, length %d>", typeof(x), length(x)))
  }
  if (is.list(x)) {
    out <- lapply(x, fev_prov_scalarise, .depth = .depth + 1L)
    if (is.null(names(out))) {
      names(out) <- paste0("[[", seq_along(out), "]]")
    }
    return(out)
  }
  sprintf("<%s>", paste(class(x), collapse = "/"))
}

#' Record a data source
#'
#' Called by every `fev_fetch_*()` function. `millesime` has no default on
#' purpose: for BD Forêt v2 it is not served by the WFS and is not recoverable
#' from the data, so it must come from the caller or be recorded as absent.
#'
#' @param prov A provenance record.
#' @param dataset Short dataset identifier, e.g. `"bdforet_v2"`.
#' @param provider Data provider, e.g. `"IGN"`.
#' @param endpoint URL actually contacted.
#' @param query The exact request, as a named list or string.
#' @param millesime Vintage of the source. `NA` when genuinely unknown --
#'   never guessed.
#' @param version Product version, when the provider publishes one.
#' @param crs_native CRS as delivered by the provider, before any transform.
#' @param licence Licence identifier, or `NA` when it has not been established.
#'   Not a guess: an unverified licence must stay `NA`.
#' @param licence_from Where that identifier was read, or the fact that it was
#'   decided rather than read. This is the field that separates a licence lu
#'   from a licence supposee, and it is why the licence is not a bare string.
#' @param ... Further named fields.
#' @return The provenance record, with one more source.
#' @noRd
fev_prov_add_source <- function(prov,
                                dataset,
                                provider = NA_character_,
                                endpoint = NA_character_,
                                query = NULL,
                                millesime = NA,
                                version = NA_character_,
                                crs_native = NA_character_,
                                licence = NA_character_,
                                licence_from = NA_character_,
                                ...) {
  rec <- list(
    dataset       = dataset,
    provider      = provider,
    version       = version,
    millesime     = millesime,
    endpoint      = endpoint,
    query         = fev_prov_scalarise(query),
    crs_native    = crs_native,
    licence       = licence,
    licence_from  = licence_from,
    downloaded_at = fev_now()
  )
  extra <- lapply(list(...), fev_prov_scalarise)
  prov$sources[[length(prov$sources) + 1L]] <- c(rec, extra)
  prov
}

#' Append an operation to the log
#'
#' @param prov A provenance record.
#' @param fun Name of the function performing the operation.
#' @param params Named list of the parameters that affected the result.
#' @param notes Optional free-text note, e.g. why a fallback was taken.
#' @return The provenance record, with one more step.
#' @noRd
fev_prov_add_step <- function(prov, fun, params = list(), notes = NULL) {
  step <- list(
    seq    = length(prov$steps) + 1L,
    time   = fev_now(),
    fun    = fun,
    params = fev_prov_scalarise(params)
  )
  if (!is.null(notes)) {
    step$notes <- as.character(notes)
  }
  prov$steps[[length(prov$steps) + 1L]] <- step
  prov
}

#' Combine two provenance records
#'
#' Used when two objects that each carry a history are combined, as in
#' `fev_fuel_merge()`. `a` is the base — its package, session and working CRS
#' are kept — and `b`'s sources and steps are appended after it. Steps are
#' renumbered so `seq` stays a reading order.
#'
#' Sources are de-duplicated on dataset plus vintage plus download time, so
#' that re-merging the same auxiliary twice does not record it twice. Steps are
#' not: doing the same operation twice is a fact about the analysis, and the
#' record is meant to say what happened, not what was intended.
#'
#' @noRd
fev_prov_merge <- function(a, b) {
  if (is.null(a)) return(b)
  if (is.null(b)) return(a)

  out <- a
  key <- function(s) paste(s$dataset, s$millesime, s$downloaded_at, sep = "|")
  seen <- vapply(a$sources, key, character(1))
  for (s in b$sources) {
    if (!key(s) %in% seen) {
      out$sources[[length(out$sources) + 1L]] <- s
      seen <- c(seen, key(s))
    }
  }

  out$steps <- c(a$steps, b$steps)
  for (i in seq_along(out$steps)) {
    out$steps[[i]]$seq <- i
  }
  out
}

#' Drop NULLs so the YAML stays readable
#'
#' `yaml::as.yaml()` renders a NULL as `~`, which litters the file with empty
#' keys that carry no information. NA is kept, because "we looked and it is
#' unknown" is information -- the millesime case exactly.
#'
#' @noRd
fev_prov_compact <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  x <- x[!vapply(x, is.null, logical(1))]
  lapply(x, fev_prov_compact)
}

#' Export the provenance of an analysis
#'
#' Returns the full provenance record of a [fev_stack()] -- sources with their
#' vintages, the working CRS and resolution, and the ordered log of every
#' operation with the parameters it ran with. Optionally writes it to a YAML
#' file.
#'
#' This is what makes an analysis replayable. The record is built as the
#' analysis runs, so it reflects the parameters actually used, including
#' defaults the caller never typed.
#'
#' @param x A `fev_stack` object.
#' @param file Optional path. When given, the record is written there as YAML
#'   and the record is returned invisibly.
#'
#' @return A named list of class `fev_provenance`. Invisibly when `file` is
#'   given.
#'
#' @examples
#' r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' terra::values(r) <- seq_len(16)
#' s <- fev_stack(fuel = r, crs_work = 2154)
#' prov <- fev_provenance(s)
#' prov$crs_work
#'
#' @export
fev_provenance <- function(x, file = NULL) {
  if (!inherits(x, "fev_stack")) {
    fev_abort(c(
      "{.arg x} must be a {.cls fev_stack}, not {.cls {class(x)[1]}}.",
      i = "Provenance is carried by the stack, so it can only be exported \\
           from one."
    ))
  }
  prov <- attr(x, "provenance")
  if (is.null(prov)) {
    fev_abort("This {.cls fev_stack} carries no provenance record.")
  }
  if (is.null(file)) {
    return(prov)
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    fev_abort("Package {.pkg yaml} is required to write a provenance file.")
  }
  txt <- yaml::as.yaml(fev_prov_compact(unclass(prov)), indent = 2)
  writeLines(txt, con = file)
  fev_inform("Provenance written to {.file {file}} \\
              ({length(prov$sources)} source{?s}, {length(prov$steps)} step{?s}).")
  invisible(prov)
}

#' @export
print.fev_provenance <- function(x, ...) {
  cli::cli_h1("firexpovulnR provenance")
  cli::cli_text("Created {.val {x$package$created}} with \\
                 {.pkg firexpovulnR} {x$package$version}")
  if (!is.null(x$crs_work)) {
    cli::cli_text("Working CRS: {.val {x$crs_work}}")
  }
  cli::cli_h2("Sources ({length(x$sources)})")
  if (!length(x$sources)) {
    cli::cli_alert_info("None recorded.")
  } else {
    for (s in x$sources) {
      mil <- if (is.na(s$millesime)) "millesime unknown" else paste("millesime", s$millesime)
      cli::cli_li("{.strong {s$dataset}} ({s$provider}) - {mil}")
    }
  }
  cli::cli_h2("Steps ({length(x$steps)})")
  if (!length(x$steps)) {
    cli::cli_alert_info("None recorded.")
  } else {
    for (st in x$steps) {
      cli::cli_li("{st$seq}. {.fn {st$fun}} at {st$time}")
    }
  }
  invisible(x)
}
