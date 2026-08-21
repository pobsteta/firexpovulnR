# What you may do with a result, which the package could not answer until now.
#
# Phase 12 step 1. The licence used to live as free text inside `provider`:
#
#   provider = "ESA WorldCover (public bucket, CC-BY 4.0)"
#
# That was adequate while every source was permissive. Two findings of the week
# ended it.
#
# FORMS-T is announced CC-BY-NC on the THEIA page and cc-by-4.0 in Zenodo's
# structured metadata. SUFOSAT is worse, or more instructive: the SAME data
# carries three answers depending on where you ask -- 403 on the bucket the STAC
# catalogue points at, CC-BY-NC on the superseded Zenodo version, CC-BY 4.0 on
# the current one. A licence is therefore not a property of the dataset but of
# the ACQUISITION PATH, which is exactly what a provenance record is for.
#
# Two rules, and they are not the same rule:
#
#   one dataset offered under several licences  -> take the most OPEN
#   several datasets combined into one result   -> the result must satisfy all
#
# The first is a choice and the package makes it. The second is not a choice at
# all, it is a consequence, and this file reports it rather than deciding it.

#' What licences a result carries, and what follows from them
#'
#' Walks the provenance of a layer, stack or source and lists every licence it
#' picked up along the way, with where each one was read.
#'
#' @section The most open, for one dataset:
#' When a producer offers the same data under several licences, this package
#' records the **most open** one. That is not optimism, it is what a licence is:
#' a producer publishing under CC-BY offers it on those terms, and nothing
#' obliges a user to adopt the terms of a different channel. Recording the most
#' restrictive "to be safe" would forbid a use the producer allows, and write
#' into the provenance a constraint nobody asked for.
#'
#' The licence recorded is the one of the **channel actually used**, and the
#' version matters: CC-BY on v3.0.1 says nothing about v2.
#'
#' @section The combination, which is not a choice:
#' A result derived from several sources must satisfy the terms of each, so the
#' effective constraint is the union of their restrictions. One non-commercial
#' input makes the result non-commercial. This function reports that; it does
#' not decide what you may do, and it is not legal advice.
#'
#' @section A licence not established stays empty:
#' Six of the package's twelve sources record `NA`, because their licence was
#' never read at the producer's own page — IGN's is a JavaScript application
#' that cannot be fetched, EFFIS's data policy was never opened, and so on. An
#' unverified licence is not a licence, and guessing one would be worse than
#' the gap: the gap is visible and a guess is not.
#'
#' `licence_from` is what separates a licence **read** from a licence
#' **decided**. FORMS is the case: its two channels disagree and the
#' contradiction has not been settled with the producer, so whatever the field
#' holds is an analyst's decision and says so.
#'
#' @param x A `fev_stack`, `fev_layer`, `fev_source`, or a provenance record.
#'
#' @return A data frame of class `fev_licences`, one row per source: `dataset`,
#'   `licence`, `licence_from`. Printing it adds the combined reading.
#'
#' @seealso [fev_provenance()] for the whole record.
#'
#' @examples
#' # The Maures extract is a local file, so its licence was never read from a
#' # producer: the answer is "not established", which is the honest one and the
#' # commonest.
#' gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
#' bdf <- sf::st_read(gpkg, "bdforet_v2", quiet = TRUE)
#' src <- suppressMessages(
#'   fev_fuel_source(bdf, type = "bdforet_v2", res = 100, millesime = 2014)
#' )
#' fev_licences(src)
#'
#' @export
fev_licences <- function(x) {
  srcs <- fev_licence_sources(x)
  if (!length(srcs)) {
    fev_abort(c(
      "No source in this provenance record.",
      i = "Licences are attached to sources, so a result built from none \\
           carries none."
    ), class = "fev_no_source")
  }
  tab <- do.call(rbind, lapply(srcs, function(s) {
    data.frame(
      dataset      = as.character(s$dataset %||% NA_character_),
      licence      = as.character(s$licence %||% NA_character_),
      licence_from = as.character(s$licence_from %||% NA_character_),
      stringsAsFactors = FALSE
    )
  }))
  tab <- tab[!duplicated(tab$dataset), , drop = FALSE]
  rownames(tab) <- NULL
  structure(tab, class = c("fev_licences", "data.frame"))
}

#' The sources of whatever was passed
#' @noRd
fev_licence_sources <- function(x) {
  prov <- if (inherits(x, "fev_source")) {
    return(list(x$source))
  } else if (is.list(x) && !is.null(x$sources)) {
    x
  } else {
    fev_layer_prov(x) %||% attr(x, "provenance") %||% x$provenance
  }
  if (is.null(prov) || is.null(prov$sources)) {
    return(list())
  }
  prov$sources
}

#' Is one licence more restrictive than another?
#'
#' Deliberately crude, and deliberately only about the one distinction that
#' propagates and bites: **non-commercial**. Ranking CC-BY against Etalab
#' against the Copernicus licence would be a legal judgement this package has no
#' business making, and the three are permissive enough that the ranking would
#' change nothing.
#'
#' @noRd
fev_licence_is_nc <- function(x) {
  !is.na(x) & grepl("NC", x, fixed = TRUE)
}

#' @export
print.fev_licences <- function(x, ...) {
  cli::cli_h1("fev_licences")
  tab <- as.data.frame(x)
  show <- tab
  show$licence[is.na(show$licence)] <- "-- non etablie"
  show$licence_from[is.na(show$licence_from)] <- ""
  print(show[, c("dataset", "licence")], row.names = FALSE)

  unknown <- sum(is.na(tab$licence))
  nc <- tab$dataset[fev_licence_is_nc(tab$licence)]

  cli::cli_par()
  if (length(nc)) {
    cli::cli_alert_warning(
      "{length(nc)} source{?s} non-commercial: {.val {nc}}. A result derived \\
       from {?it/them} is non-commercial too -- the terms of every input have \\
       to be satisfied at once."
    )
  } else if (!unknown) {
    cli::cli_alert_success(
      "No non-commercial source: nothing here restricts the result that way."
    )
  }
  if (unknown) {
    cli::cli_alert_info(
      "{unknown} licence{?s} not established, so this list is not a clearance. \\
       An unverified licence is recorded as missing rather than guessed."
    )
  }
  cli::cli_alert_info(
    "The package records what producers declare and reports what follows. It \\
     is not legal advice."
  )
  cli::cli_end()
  invisible(x)
}
