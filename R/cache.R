# On-disk cache for fetched data.
#
# Design choice: the cache key is a hash of the *normalised request*, so two
# calls with different parameters cannot collide. foretaccess solves the same
# problem with a fixed filename plus a "what do I do if the parameters
# differ?" policy; hashing removes the question. The cost is a re-download
# when an AOI moves by a metre, which is the safe direction to fail -- serving
# a cached layer for a different request is the kind of error that survives
# into a publication.
#
# Every cache entry is two files: the data, and a sidecar holding the source
# record. A cached layer with no provenance is worse than no cache at all,
# because it looks authoritative and cannot be traced.

#' Cache location and contents
#'
#' The package caches downloaded data under [tools::R_user_dir()], so repeated
#' analyses do not re-hit IGN, Copernicus or EFFIS.
#'
#' @param create Create the directory if it does not exist.
#' @return `fev_cache_dir()` returns the path as a string.
#'
#' @examples
#' fev_cache_dir()
#'
#' @export
fev_cache_dir <- function(create = FALSE) {
  path <- Sys.getenv("FIREXPOVULNR_CACHE_DIR", unset = "")
  if (!nzchar(path)) {
    path <- tools::R_user_dir("firexpovulnR", which = "cache")
  }
  if (create && !dir.exists(path)) {
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!ok && !dir.exists(path)) {
      fev_abort(c(
        "Could not create the cache directory {.file {path}}.",
        i = "Set {.envvar FIREXPOVULNR_CACHE_DIR} to a writable location."
      ))
    }
  }
  path
}

#' Build a cache key from a dataset name and its request parameters
#'
#' Geometries are reduced to a rounded bbox plus CRS: hashing the full
#' geometry would make the key depend on vertex ordering, so two identical
#' AOIs read from different files would miss each other.
#'
#' @noRd
fev_cache_key <- function(dataset, params = list()) {
  norm <- lapply(params, function(p) {
    if (inherits(p, c("sf", "sfc", "SpatVector", "SpatRaster"))) {
      bb <- fev_bbox(p)
      return(paste0(fev_crs_label(p), ":", paste(round(bb, 3), collapse = ",")))
    }
    if (is.null(p)) {
      return("NULL")
    }
    paste(as.character(p), collapse = "|")
  })
  norm <- norm[order(names(norm))]
  payload <- paste0(dataset, "|", paste(names(norm), unlist(norm),
                                        sep = "=", collapse = ";"))
  paste0(dataset, "_", substr(rlang::hash(payload), 1L, 16L))
}

#' @noRd
fev_cache_paths <- function(key, ext = "gpkg") {
  dir <- fev_cache_dir()
  list(
    data = file.path(dir, paste0(key, ".", ext)),
    prov = file.path(dir, paste0(key, ".prov.rds"))
  )
}

#' Is there a usable cache entry for this key?
#'
#' Both files must be present. A data file without its sidecar is treated as a
#' miss rather than served untraceably.
#'
#' @noRd
fev_cache_hit <- function(key, ext = "gpkg") {
  p <- fev_cache_paths(key, ext)
  file.exists(p$data) && file.exists(p$prov)
}

#' @noRd
fev_cache_write <- function(key, data, source_record, ext = "gpkg") {
  fev_cache_dir(create = TRUE)
  p <- fev_cache_paths(key, ext)
  if (inherits(data, c("sf", "sfc"))) {
    sf::st_write(data, p$data, delete_dsn = TRUE, quiet = TRUE)
  } else if (inherits(data, "SpatRaster")) {
    terra::writeRaster(data, p$data, overwrite = TRUE)
  } else if (is.data.frame(data)) {
    # Weather arrives as a point-day table rather than a geometry or a grid.
    # Stored as RDS so the integer day/month columns and the row order survive
    # the round trip, which a CSV would not guarantee.
    saveRDS(data, p$data)
  } else {
    fev_abort("Cannot cache an object of class {.cls {class(data)[1]}}.")
  }
  saveRDS(source_record, p$prov)
  invisible(p)
}

#' @noRd
fev_cache_read <- function(key, ext = "gpkg") {
  p <- fev_cache_paths(key, ext)
  data <- if (ext == "gpkg") {
    sf::st_read(p$data, quiet = TRUE)
  } else if (ext == "rds") {
    readRDS(p$data)
  } else {
    terra::rast(p$data)
  }
  list(data = data, source = readRDS(p$prov))
}

#' Inspect the cache
#'
#' Lists cached entries with their dataset, size, age and recorded vintage, so
#' you can see what an analysis will reuse before it runs.
#'
#' @return A data frame with one row per cache entry: `dataset`, `key`,
#'   `file`, `size_mb`, `modified`, `millesime`, `endpoint`. Zero rows when
#'   the cache is empty.
#'
#' @examples
#' fev_cache_info()
#'
#' @export
fev_cache_info <- function() {
  dir <- fev_cache_dir()
  empty <- data.frame(
    dataset = character(), key = character(), file = character(),
    size_mb = numeric(), modified = as.POSIXct(character()),
    millesime = character(), endpoint = character(),
    stringsAsFactors = FALSE
  )
  if (!dir.exists(dir)) {
    fev_inform("Cache is empty ({.file {dir}} does not exist yet).")
    return(empty)
  }
  provs <- list.files(dir, pattern = "\\.prov\\.rds$", full.names = TRUE)
  if (!length(provs)) {
    fev_inform("Cache at {.file {dir}} holds no entries.")
    return(empty)
  }

  rows <- lapply(provs, function(pf) {
    key <- sub("\\.prov\\.rds$", "", basename(pf))
    rec <- tryCatch(readRDS(pf), error = function(e) NULL)
    data_file <- list.files(dir, pattern = paste0("^", key, "\\.(gpkg|tif)$"),
                            full.names = TRUE)
    if (!length(data_file)) {
      return(NULL)
    }
    info <- file.info(data_file[1])
    data.frame(
      dataset   = rec$dataset %||% NA_character_,
      key       = key,
      file      = basename(data_file[1]),
      size_mb   = round(info$size / 1024^2, 3),
      modified  = info$mtime,
      millesime = as.character(rec$millesime %||% NA),
      endpoint  = rec$endpoint %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(out)) {
    return(empty)
  }
  out[order(out$modified, decreasing = TRUE), , drop = FALSE]
}

#' Clear cached data
#'
#' Deletes cache entries. Both the data file and its provenance sidecar are
#' removed together, so no untraceable data is left behind.
#'
#' @param dataset Optional dataset name (e.g. `"bdforet_v2"`). When `NULL`,
#'   every entry is targeted.
#' @param older_than Optional number of days. Only entries last modified
#'   before that many days ago are removed.
#' @param confirm When `TRUE` (the default in an interactive session), ask
#'   before deleting. Set `FALSE` in scripts.
#'
#' @return Invisibly, a character vector of the files removed.
#'
#' @examples
#' \dontrun{
#' fev_cache_clear(dataset = "bdforet_v2", confirm = FALSE)
#' fev_cache_clear(older_than = 90, confirm = FALSE)
#' }
#'
#' @export
fev_cache_clear <- function(dataset = NULL, older_than = NULL,
                            confirm = interactive()) {
  info <- suppressMessages(fev_cache_info())
  if (!nrow(info)) {
    fev_inform("Nothing to clear.")
    return(invisible(character()))
  }

  keep <- rep(TRUE, nrow(info))
  if (!is.null(dataset)) {
    keep <- keep & info$dataset %in% dataset
  }
  if (!is.null(older_than)) {
    cutoff <- Sys.time() - older_than * 86400
    keep <- keep & info$modified < cutoff
  }
  target <- info[keep, , drop = FALSE]

  if (!nrow(target)) {
    fev_inform("No cache entry matches those criteria.")
    return(invisible(character()))
  }

  dir <- fev_cache_dir()
  files <- unlist(lapply(target$key, function(k) {
    list.files(dir, pattern = paste0("^", k, "\\."), full.names = TRUE)
  }))

  if (isTRUE(confirm)) {
    cli::cli_alert_warning(
      "About to delete {nrow(target)} cache entr{?y/ies} \\
       ({round(sum(target$size_mb), 1)} MB) from {.file {dir}}."
    )
    ans <- readline("Proceed? [y/N] ")
    if (!tolower(trimws(ans)) %in% c("y", "yes")) {
      fev_inform("Cancelled; nothing was deleted.")
      return(invisible(character()))
    }
  }

  removed <- file.remove(files)
  fev_inform("Removed {sum(removed)} file{?s} \\
              ({nrow(target)} cache entr{?y/ies}).")
  invisible(files[removed])
}
