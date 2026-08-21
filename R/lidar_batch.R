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
#' @section Why the order is not the index order:
#' `max_tiles` without `spread` would hand you the first N tiles of an index
#' that is itself in spatial order — eight neighbours in one corner of the
#' massif, sampling one context eight times. `spread = TRUE` walks the tiles by
#' farthest-point traversal instead: each tile chosen is the one furthest from
#' everything chosen so far.
#'
#' The traversal is deterministic and computed over the whole set, so every
#' prefix of it is well spread **and** resume continues the spread rather than
#' re-drawing it. Eight tiles tonight and eight tomorrow give sixteen spread
#' tiles, not two clusters of eight.
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
#' @param spread Choose those tiles spread across the area rather than in index
#'   order. On by default, and it matters: the index is in spatial order, so the
#'   first eight tiles of it are eight neighbours in one corner. See the section
#'   below.
#' @param keep_las Keep the downloaded point clouds instead of deleting each one
#'   after its tile is inverted. Off by default: at roughly 200 MB a tile, a
#'   departmental run would fill a disk.
#' @param dry_run Report what would be done and return the plan without
#'   downloading anything.
#' @param fires Fire perimeters, as [fev_fetch_burnt()] returns them, or `NULL`.
#'   When given, the run reports which finished windows fall in a burn and —
#'   the point of it — whether any fire **postdates the LiDAR acquisition**.
#' @param quiet Suppress progress reporting.
#'
#' @return A data frame, one row per tile: `tile`, `status`, `points`,
#'   `seconds`, `path`, `error`, `rank`. `status` is `"done"` for a tile whose
#'   raster already exists, `"next"` for one this run will take, `"todo"` for
#'   one left for a later run, and `"written"` or `"failed"` afterwards.
#'   `error` carries the reason a tile failed, so the manifest answers the
#'   question on its own rather than sending you back to a console log.
#'   `rank` gives the position in the traversal, so a dry run shows the actual
#'   batch rather than the index order. Also written to `manifest.csv` in
#'   `out_dir` after every tile, so an interrupted run leaves a readable
#'   record.
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
                            spread = TRUE,
                            keep_las = FALSE,
                            dry_run = FALSE,
                            fires = NULL,
                            quiet = FALSE) {
  fev_require("lidR", "read a point cloud")
  if (!is.character(out_dir) || length(out_dir) != 1L) {
    fev_abort("{.arg out_dir} must be a single path.")
  }
  if (!is.null(window) && (!is.numeric(window) || window <= 0)) {
    fev_abort("{.arg window} must be a positive number of metres, or NULL.")
  }

  # The AOI, kept rather than consumed. `window` cuts a square centred on the
  # TILE, and the index holds every tile that *intersects* the area -- so on any
  # edge tile that square lands outside the study area entirely. Measured on the
  # Maures: 13 of the first 24 windows, more than half the campaign, inverted
  # ground that was never in the area under study.
  aoi_geom <- if (inherits(aoi, "fev_lidarhd_index")) NULL else fev_lidar_aoi(aoi)

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

  # Where to cut, and whether a cut is possible at all inside the area.
  centres <- fev_lidar_window_centres(idx, aoi_geom, window)
  outside <- !done & !stats::complete.cases(centres)

  plan <- data.frame(
    tile = tiles,
    status = ifelse(done, "done", ifelse(outside, "outside", "todo")),
    points = NA_real_, seconds = NA_real_,
    path = ifelse(done, dest, NA_character_),
    # A manifest that says "failed" without saying why sends you back to a log
    # that may no longer exist -- and the reason only reached the console as a
    # deferred warning at the very end of the run, long after the tile that
    # raised it had scrolled past.
    error = NA_character_,
    stringsAsFactors = FALSE
  )

  # Order the WHOLE set once, then take the first undone ones. Index order is
  # spatial -- 0966_6257, 0966_6258, 0966_6259 -- so taking the first N of it
  # would hand back eight adjacent tiles in one corner of the massif, which is
  # the contiguity this function's own documentation argues against.
  #
  # The order is deterministic, and that matters for resume: run two must
  # continue the spread rather than re-draw it, or the union of several nights
  # is no better spread than one.
  order_all <- if (isTRUE(spread)) {
    fev_lidar_spread_order(idx, xy = centres)
  } else {
    seq_len(nrow(plan))
  }
  todo <- order_all[!done[order_all] & !outside[order_all]]
  if (!is.null(max_tiles) && length(todo) > max_tiles) {
    todo <- todo[seq_len(max_tiles)]
  }

  # A dry run that does not say WHICH tiles it would take is misleading: the
  # plan is in index order, the traversal is not, and `max_tiles` cuts the
  # latter. Mark the selection so the caller sees the actual next batch.
  plan$status[todo] <- "next"
  plan$rank <- match(seq_len(nrow(plan)), todo)

  if (!quiet && any(outside)) {
    fev_inform(c(
      "{sum(outside)} tile{?s} dropped: no {window} m window fits inside the \\
       area of interest.",
      i = "They touch the area only at the edge. Processing them would invert \\
           ground outside the study area."
    ), .envir = environment())
  }
  if (!quiet) {
    fev_inform(c(
      "{nrow(plan)} tile{?s}: {sum(done)} already done, \\
       {sum(outside)} outside, {length(todo)} to process now.",
      i = if (!is.null(window)) {
        paste0("Processing a centred {window} m square of each, not the whole ",
               "tile.")
      } else {
        "Processing whole tiles. Expect hours each -- see {.fn fev_fuel_lidar}."
      },
      i = "Resume is by output presence: stop this whenever you like."
    ), .envir = environment())
  }
  # Avant la sortie de l'essai a blanc : c'est la qu'on consulte l'etat, et un
  # controle qui ne s'affiche qu'apres une session de calcul serait vu trop tard.
  if (!is.null(fires) && !quiet) {
    fev_lidar_fire_check(plan, dest, idx, fires)
  }

  if (dry_run) {
    return(plan)
  }

  for (i in todo) {
    t0 <- proc.time()[["elapsed"]]
    row <- fev_lidar_batch_one(urls[i], tiles[i], dest[i], las_dir, res,
                               window, centres[i, ], keep_las, quiet)
    plan$status[i] <- row$status
    plan$points[i] <- row$points
    plan$seconds[i] <- round(proc.time()[["elapsed"]] - t0, 1)
    plan$path[i] <- row$path
    plan$error[i] <- row$error
    # Rewritten after every tile: an interrupted run must still leave a record
    # that says which tiles were attempted and which failed.
    utils::write.csv(plan, file.path(out_dir, "manifest.csv"), row.names = FALSE)
    if (!quiet) {
      why <- if (is.na(plan$error[i])) "" else paste0(" -- ", plan$error[i])
      fev_inform("[{which(todo == i)}/{length(todo)}] {tiles[i]}: \\
                  {plan$status[i]} in {plan$seconds[i]}s{why}.",
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
                                centre, keep_las, quiet) {
  fail <- function(why) list(status = "failed", points = NA_real_,
                             path = NA_character_, error = why)
  las_file <- file.path(las_dir, basename(url))

  # What the server says the file weighs. A LiDAR HD tile is 120 to 290 MB, so
  # "more than a megabyte" accepts a download that stopped a third of the way
  # through -- which is exactly what happened to tile 0970_6244: 122 MB of the
  # 290 announced, past the size check, and LASlib failing on a truncated EVLR
  # header. Worse, the truncated file then sat in the cache and failed again on
  # every rerun, since resume only asks whether the file is there.
  expected <- fev_lidar_expected_size(url)
  if (file.exists(las_file) && !is.na(expected) &&
      file.size(las_file) != expected) {
    unlink(las_file)
  }

  if (!file.exists(las_file) || file.size(las_file) < 1e6) {
    ok <- tryCatch({
      # The default 60 s is far too short for 200 MB; without this every tile
      # fails at a quarter downloaded, which is how the first attempt at this
      # was lost.
      old <- options(timeout = max(3600, getOption("timeout")))
      on.exit(options(old), add = TRUE)
      utils::download.file(url, las_file, quiet = TRUE, mode = "wb")
      file.exists(las_file) && file.size(las_file) > 1e6 &&
        (is.na(expected) || file.size(las_file) == expected)
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!isTRUE(ok)) {
      got <- if (file.exists(las_file)) file.size(las_file) else 0
      unlink(las_file)
      return(fail(if (is.na(expected)) {
        "download failed"
      } else {
        sprintf("download truncated: %.0f of %.0f MB", got / 1e6, expected / 1e6)
      }))
    }
  }

  out <- tryCatch({
    # A cloud that will not read is a cloud to fetch again, not one to keep:
    # `keep_las` is there to spare re-downloads, not to preserve a corrupt file
    # so it can fail identically on every future run.
    las <- withCallingHandlers(
      tryCatch(lidR::readLAS(las_file),
               error = function(e) { unlink(las_file); stop(e) }),
      warning = function(w) invokeRestart("muffleWarning")
    )
    if (!is.null(window)) {
      las <- fev_lidar_centre_window(las, window, centre)
    }
    n <- lidR::npoints(las)
    r <- suppressMessages(fev_fuel_lidar(las, res = res))
    tmp <- fev_lidar_part_path(dest)
    terra::writeRaster(fev_fuel_continuous(r), tmp, overwrite = TRUE)
    # Rename only once written: a half-written raster must never look finished
    # to the next run's resume check.
    file.rename(tmp, dest)
    list(status = "written", points = n, path = dest, error = NA_character_)
  }, error = function(e) {
    if (!quiet) {
      fev_warn("{tile} failed: {conditionMessage(e)}", .envir = environment())
    }
    fail(conditionMessage(e))
  })

  if (!keep_las) {
    unlink(las_file)
  }
  out
}

#' Where a tile is written before it counts as finished
#'
#' The suffix goes BEFORE the extension, not after it. `terra::writeRaster()`
#' picks its driver from the extension, so `..._fuel.tif.part` is not a slightly
#' odd name -- it is a name terra refuses outright, with "cannot guess file type
#' from filename". That refusal cost a whole eight-tile campaign: every tile
#' downloaded, every tile inverted for two minutes, and every one thrown away on
#' the last line. The tests could not see it because they point at
#' `example.invalid`, so every tile failed at the download and no test ever
#' reached the write.
#'
#' `_fuel.part.tif` keeps the driver inferable and still cannot be mistaken for
#' a finished tile, since resume tests `_fuel.tif` by exact name.
#'
#' @noRd
fev_lidar_part_path <- function(dest) {
  sub("\\.tif$", ".part.tif", dest)
}

#' What the server says a file weighs, or `NA` if it will not say
#'
#' Split in two so the parsing can be tested without a network: the fetch is one
#' line, the reading of it is the part that can be wrong.
#'
#' @noRd
fev_lidar_expected_size <- function(url) {
  h <- tryCatch(curlGetHeaders(url, redirect = TRUE), error = function(e) NULL)
  fev_lidar_content_length(h)
}

#' @noRd
fev_lidar_content_length <- function(headers) {
  if (is.null(headers) || !length(headers)) {
    return(NA_real_)
  }
  # A redirect chain carries one set of headers per hop; the last Content-Length
  # is the one describing the file actually served.
  hit <- grep("^content-length:", headers, ignore.case = TRUE, value = TRUE)
  if (!length(hit)) {
    return(NA_real_)
  }
  n <- suppressWarnings(as.numeric(sub("^[^:]*:[[:space:]]*", "",
                                       trimws(hit[length(hit)]))))
  if (is.na(n) || n <= 0) NA_real_ else n
}

#' The area of interest as one geometry, in whatever it was given as
#' @noRd
fev_lidar_aoi <- function(aoi) {
  g <- tryCatch(sf::st_geometry(sf::st_as_sf(aoi)), error = function(e) NULL)
  if (is.null(g) || !length(g)) {
    return(NULL)
  }
  sf::st_union(sf::st_make_valid(g))
}

#' Which finished windows fall in a burn, and whether any burn is USABLE
#'
#' The question this answers is narrow and easy to forget: a LiDAR acquisition
#' can only predict the severity of a fire that came AFTER it. The Maures
#' campaign is the cautionary case — five windows intersect the 2021 fires, 27.5
#' ha of them, and every one is worthless for that purpose because the point
#' clouds were flown in May 2025, four years later. What they measure is what
#' grew back.
#'
#' So the check reports two different things and does not confuse them: windows
#' in a burn, which is a fuel-recovery sample, and windows in a burn that
#' postdates the flight, which is the only case that supports a
#' structure-predicts-severity test. Left to a yearly review, that second case
#' would be found a year late.
#'
#' @noRd
fev_lidar_fire_check <- function(plan, dest, idx, fires) {
  done <- plan$status %in% c("done", "written")
  if (!any(done)) {
    return(invisible(NULL))
  }
  f <- if (inherits(fires, "fev_source")) fires$data else fires
  if (inherits(f, "SpatVector")) {
    f <- sf::st_as_sf(f)
  }
  if (!inherits(f, "sf") || !nrow(f)) {
    return(invisible(NULL))
  }
  f <- sf::st_transform(f, sf::st_crs(idx))

  wins <- do.call(rbind, lapply(which(done), function(i) {
    r <- terra::rast(dest[i])
    sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(
      c(xmin = terra::xmin(r), xmax = terra::xmax(r),
        ymin = terra::ymin(r), ymax = terra::ymax(r)),
      crs = sf::st_crs(idx))))
  }))
  hits <- sf::st_intersects(wins, sf::st_geometry(f))
  n_win <- sum(lengths(hits) > 0)
  if (!n_win) {
    cli::cli_li("No finished window falls in a burn.")
    return(invisible(NULL))
  }

  # The acquisition date the index carries, against the fire years.
  flown <- suppressWarnings(max(as.Date(substr(as.character(idx$timestamp), 1, 10)),
                                na.rm = TRUE))
  years <- if ("fire_year" %in% names(f)) f$fire_year else NA_integer_
  after <- vapply(hits, function(k) {
    if (!length(k) || all(is.na(years[k]))) FALSE else
      any(years[k] > as.integer(format(flown, "%Y")), na.rm = TRUE)
  }, logical(1))

  cli::cli_li("{n_win} finished window{?s} fall{?s/} in a burn.")
  if (any(after)) {
    cli::cli_alert_success(
      "{sum(after)} of them burnt AFTER the {format(flown, '%Y-%m')} flight: \
       the structure was measured before the fire, so a \
       CBH-predicts-severity test is possible on {?it/them}."
    )
  } else {
    cli::cli_alert_info(
      "All of them burnt before the {format(flown, '%Y-%m')} flight, so they \
       measure what grew back, not what burnt. Good for fuel recovery, useless \
       for predicting severity."
    )
  }
  invisible(NULL)
}

#' Where to cut each tile so the square lands inside the area of interest
#'
#' The tile centre is the wrong point on an edge tile: the index holds every
#' tile that *intersects* the area, so a square centred on the tile can sit
#' wholly outside it. Thirteen of the first twenty-four Maures windows did, and
#' the metrics computed there described ground nobody had asked about -- while
#' looking, in the manifest, exactly like the eleven that were legitimate.
#'
#' The centre used instead is a point on the intersection shrunk by half the
#' window, which is empty exactly when no window of that size fits inside the
#' area. So the same computation both places the square and decides whether the
#' tile is workable at all: a tile with no centre is a tile to drop, not a tile
#' to cut badly.
#'
#' With no area of interest -- an index passed directly -- the tile centre is
#' all there is, and it is used.
#'
#' @return A two-column matrix of coordinates, one row per tile, `NA` where no
#'   window fits.
#' @noRd
fev_lidar_window_centres <- function(idx, aoi_geom, window) {
  n <- nrow(idx)
  xy <- suppressWarnings(
    sf::st_coordinates(sf::st_centroid(sf::st_geometry(idx)))[, 1:2, drop = FALSE]
  )
  if (is.null(aoi_geom) || is.null(window)) {
    return(xy)
  }

  aoi <- sf::st_transform(aoi_geom, sf::st_crs(idx))
  out <- matrix(NA_real_, nrow = n, ncol = 2L,
                dimnames = list(NULL, c("X", "Y")))
  parts <- suppressWarnings(sf::st_intersection(
    sf::st_sf(.i = seq_len(n), geometry = sf::st_geometry(idx)), aoi
  ))
  if (!nrow(parts)) {
    return(out)
  }
  # Shrink by half the window: what survives is where a centre can go with the
  # whole square still inside.
  core <- suppressWarnings(sf::st_buffer(sf::st_geometry(parts), -window / 2))
  keep <- !sf::st_is_empty(core)
  if (any(keep)) {
    pts <- suppressWarnings(sf::st_point_on_surface(core[keep]))
    out[parts$.i[keep], ] <- sf::st_coordinates(pts)[, 1:2, drop = FALSE]
  }
  out
}

#' A centred square of a tile
#' @noRd
fev_lidar_centre_window <- function(las, window, centre = NULL) {
  if (is.null(centre) || anyNA(centre)) {
    h <- las@header@PHB
    centre <- c((h$`Min X` + h$`Max X`) / 2, (h$`Min Y` + h$`Max Y`) / 2)
  }
  cx <- centre[[1]]
  cy <- centre[[2]]
  lidR::clip_rectangle(las, cx - window / 2, cy - window / 2,
                       cx + window / 2, cy + window / 2)
}


#' A deterministic, well-spread traversal of the tiles
#'
#' Farthest-point traversal: start from the tile nearest the centroid, then
#' repeatedly take whichever tile is furthest from everything taken so far. No
#' randomness, so two runs of this agree, which is what lets resume continue a
#' spread instead of starting a new one.
#'
#' @noRd
fev_lidar_spread_order <- function(idx, xy = NULL) {
  n <- nrow(idx)
  if (n < 3L) {
    return(seq_len(n))
  }
  # Spread on the points actually cut, not on the tile centres: once the window
  # is placed inside the area of interest, those are what the traversal must
  # keep apart. Tiles with no usable centre fall back to their own so the
  # traversal stays defined -- they are excluded from the batch elsewhere.
  fallback <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(idx)))[, 1:2,
                                                                       drop = FALSE]
  if (is.null(xy)) {
    xy <- fallback
  } else {
    xy <- xy[, 1:2, drop = FALSE]
    gap <- !stats::complete.cases(xy)
    xy[gap, ] <- fallback[gap, ]
  }
  centre <- colMeans(xy)
  first <- which.min(colSums((t(xy) - centre)^2))

  ord <- integer(n)
  ord[1] <- first
  # Distance to the nearest already-chosen tile, updated as we go: cheaper than
  # rescanning every pair, and exactly what "furthest from all chosen" needs.
  nearest <- colSums((t(xy) - xy[first, ])^2)
  nearest[first] <- -Inf
  for (k in 2:n) {
    pick <- which.max(nearest)
    ord[k] <- pick
    nearest <- pmin(nearest, colSums((t(xy) - xy[pick, ])^2))
    nearest[pick] <- -Inf
  }
  ord
}
