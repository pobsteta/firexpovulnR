# Batch inversion of LiDAR HD tiles, with resume.
#
# The phase 8 brief asked for this and it was never written: "Volumetrie
# serieuse : prevois un mode de reprise apres interruption et un test de charge
# sur quelques dalles avant tout traitement departemental."
#
# The load test now exists -- see the cost section of fev_fuel_lidar(), where
# three unfinished runs give lower bounds -- and it is what makes resume
# non-negotiable rather than nice to have. A tile can take hours. A run that
# loses everything when the laptop sleeps is not a run.

#' Invert LiDAR HD tiles in batch, with resume
#'
#' Walks a set of LiDAR HD tiles one at a time: downloads, inverts to fuel
#' metrics with [fev_fuel_lidar()], writes one raster per tile, and deletes the
#' point cloud before moving on. Interrupt it whenever you like and start it
#' again — it picks up where it stopped.
#'
#' @section Why resume is the point:
#' Measured on real tiles over the Maures, none of these finished: 3.0 M points
#' in over 25 minutes, 11.1 M in over 40, a whole tile in over 90. Downloading
#' is not the bottleneck — a 248 MB tile arrives in 42 seconds — the inversion
#' is. A departmental run is therefore an overnight batch job, and any batch job
#' that cannot be interrupted will be, at the worst moment.
#'
#' Resume is by **output presence**, not by a state file that can drift from the
#' truth: a tile whose raster is on disk is done. Each raster is written to a
#' temporary name and renamed only once complete, so an interrupted write is
#' never mistaken for a finished tile.
#'
#' @section What `window` is for:
#' A full tile is a square kilometre and, at LiDAR HD's density, tens of
#' millions of points. `window` processes a centred square of `window` metres
#' instead, which is what makes a spread of tiles affordable: eight 250 m
#' windows across a massif sample eight contexts, where one whole tile samples
#' one, for a fraction of the cost.
#'
#' Spread beats contiguity for anything you intend to compare against a
#' classification — which is what [fev_fuel_profile()] does.
#'
#' @section Do not thin the cloud to go faster:
#' It is the obvious optimisation and it destroys the measurement. As pulse
#' density falls the understorey stratum is the first thing to disappear, so
#' thinning biases exactly the quantity these metrics exist to carry. Reduce
#' `window`, or process fewer tiles; never reduce the density. See
#' [fev_lidar_density()].
#'
#' @param aoi Area of interest, or an `fev_lidarhd_index` from
#'   [fev_lidarhd_available()].
#' @param out_dir Directory for the per-tile rasters and the manifest. Created
#'   if absent.
#' @param res Target cell size in metres, passed to [fev_fuel_lidar()].
#' @param window Side of a centred square to process within each tile, in
#'   metres. `NULL` processes the whole tile.
#' @param max_tiles Stop after this many tiles in one run — a way to take an
#'   overnight job in shifts. `NULL` for no limit.
#' @param keep_las Keep the downloaded point clouds instead of deleting each one
#'   after its tile is inverted. Off by default: at roughly 200 MB a tile, a
#'   departmental run would fill a disk.
#' @param dry_run Report what would be done and return the plan without
#'   downloading anything.
#' @param quiet Suppress progress reporting.
#'
#' @return A data frame, one row per tile: `tile`, `status`, `points`,
#'   `seconds`, `path`. Also written to `manifest.csv` in `out_dir` after every
#'   tile, so an interrupted run leaves a readable record.
#'
#' @seealso [fev_fuel_lidar()] for the inversion and what it costs,
#'   [fev_lidarhd_available()] for the coverage check.
#'
#' @examples
#' \dontrun{
#' study <- sf::st_read("massif_maures.gpkg")
#'
#' # What it would do, without downloading anything.
#' fev_lidar_batch(study, "out/lidar", window = 250, dry_run = TRUE)
#'
#' # Overnight, in shifts. Run it again tomorrow and it continues.
#' fev_lidar_batch(study, "out/lidar", window = 250, max_tiles = 8)
#' }
#'
#' @export
fev_lidar_batch <- function(aoi,
                            out_dir,
                            res = 25,
                            window = NULL,
                            max_tiles = NULL,
                            keep_las = FALSE,
                            dry_run = FALSE,
                            quiet = FALSE) {
  fev_require("lidR", "read a point cloud")
  if (!is.character(out_dir) || length(out_dir) != 1L) {
    fev_abort("{.arg out_dir} must be a single path.")
  }
  if (!is.null(window) && (!is.numeric(window) || window <= 0)) {
    fev_abort("{.arg window} must be a positive number of metres, or NULL.")
  }

  idx <- if (inherits(aoi, "fev_lidarhd_index")) {
    aoi
  } else if (isTRUE(quiet)) {
    # No `quiet` argument on the availability check: it reports coverage and
    # vintages, which is worth seeing once. Silence it here rather than invent
    # a parameter it does not have.
    suppressMessages(fev_lidarhd_available(aoi))
  } else {
    fev_lidarhd_available(aoi)
  }
  if (!nrow(idx)) {
    fev_abort("No LiDAR HD tile covers this area.",
              class = "fev_no_lidar_coverage")
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  las_dir <- file.path(out_dir, "las")
  dir.create(las_dir, recursive = TRUE, showWarnings = FALSE)

  tiles <- as.character(idx$name)
  urls <- as.character(idx$url)
  dest <- file.path(out_dir, paste0(tiles, "_fuel.tif"))
  done <- file.exists(dest)

  plan <- data.frame(
    tile = tiles, status = ifelse(done, "done", "todo"),
    points = NA_real_, seconds = NA_real_,
    path = ifelse(done, dest, NA_character_),
    stringsAsFactors = FALSE
  )

  todo <- which(!done)
  if (!is.null(max_tiles) && length(todo) > max_tiles) {
    todo <- todo[seq_len(max_tiles)]
  }

  if (!quiet) {
    fev_inform(c(
      "{nrow(plan)} tile{?s}: {sum(done)} already done, \\
       {length(todo)} to process now.",
      i = if (!is.null(window)) {
        paste0("Processing a centred {window} m square of each, not the whole ",
               "tile.")
      } else {
        "Processing whole tiles. Expect hours each -- see {.fn fev_fuel_lidar}."
      },
      i = "Resume is by output presence: stop this whenever you like."
    ), .envir = environment())
  }
  if (dry_run) {
    return(plan)
  }

  for (i in todo) {
    t0 <- proc.time()[["elapsed"]]
    row <- fev_lidar_batch_one(urls[i], tiles[i], dest[i], las_dir, res,
                               window, keep_las, quiet)
    plan$status[i] <- row$status
    plan$points[i] <- row$points
    plan$seconds[i] <- round(proc.time()[["elapsed"]] - t0, 1)
    plan$path[i] <- row$path
    # Rewritten after every tile: an interrupted run must still leave a record
    # that says which tiles were attempted and which failed.
    utils::write.csv(plan, file.path(out_dir, "manifest.csv"), row.names = FALSE)
    if (!quiet) {
      fev_inform("[{which(todo == i)}/{length(todo)}] {tiles[i]}: \\
                  {plan$status[i]} in {plan$seconds[i]}s.",
                 .envir = environment())
    }
  }

  if (!quiet) {
    ok <- sum(plan$status %in% c("done", "written"))
    bad <- sum(plan$status == "failed")
    fev_inform(c(
      "{ok} tile{?s} available, {bad} failed, \\
       {sum(plan$status == 'todo')} still to do.",
      i = "Run this again to continue; finished tiles are skipped."
    ), .envir = environment())
  }
  invisible(plan)
}

#' One tile, isolated so that its failure does not end the run
#'
#' A batch that dies on the third of forty tiles because one download timed out
#' is worse than useless: it wastes the two that worked.
#'
#' @noRd
fev_lidar_batch_one <- function(url, tile, dest, las_dir, res, window,
                                keep_las, quiet) {
  fail <- function() list(status = "failed", points = NA_real_,
                          path = NA_character_)
  las_file <- file.path(las_dir, basename(url))

  if (!file.exists(las_file) || file.size(las_file) < 1e6) {
    ok <- tryCatch({
      # The default 60 s is far too short for 200 MB; without this every tile
      # fails at a quarter downloaded, which is how the first attempt at this
      # was lost.
      old <- options(timeout = max(3600, getOption("timeout")))
      on.exit(options(old), add = TRUE)
      utils::download.file(url, las_file, quiet = TRUE, mode = "wb")
      file.exists(las_file) && file.size(las_file) > 1e6
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!isTRUE(ok)) {
      unlink(las_file)
      return(fail())
    }
  }

  out <- tryCatch({
    las <- lidR::readLAS(las_file)
    if (!is.null(window)) {
      las <- fev_lidar_centre_window(las, window)
    }
    n <- lidR::npoints(las)
    r <- suppressMessages(fev_fuel_lidar(las, res = res))
    tmp <- paste0(dest, ".part")
    terra::writeRaster(fev_fuel_continuous(r), tmp, overwrite = TRUE)
    # Rename only once written: a half-written raster must never look finished
    # to the next run's resume check.
    file.rename(tmp, dest)
    list(status = "written", points = n, path = dest)
  }, error = function(e) {
    if (!quiet) {
      fev_warn("{tile} failed: {conditionMessage(e)}", .envir = environment())
    }
    fail()
  })

  if (!keep_las) {
    unlink(las_file)
  }
  out
}

#' A centred square of a tile
#' @noRd
fev_lidar_centre_window <- function(las, window) {
  h <- las@header@PHB
  cx <- (h$`Min X` + h$`Max X`) / 2
  cy <- (h$`Min Y` + h$`Max Y`) / 2
  lidR::clip_rectangle(las, cx - window / 2, cy - window / 2,
                       cx + window / 2, cy + window / 2)
}
