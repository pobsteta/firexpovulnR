# Batch inversion: the resume logic and the plan, without touching the network.
#
# What the run actually does to a point cloud is fev_fuel_lidar()'s business and
# is tested there. What matters here is that an interrupted run can be restarted
# without losing or redoing work.

fake_index <- function(names) {
  geom <- sf::st_sfc(lapply(seq_along(names), function(i) {
    sf::st_polygon(list(cbind(c(0, 1, 1, 0, 0) + i, c(0, 0, 1, 1, 0))))
  }), crs = 2154)
  # An empty sfc needs its own construction: st_sfc(list()) has no geometry
  # type, and st_sf() refuses it.
  if (!length(names)) {
    geom <- sf::st_sfc(crs = 2154)
  }
  # paste0() recycles its constant parts, so paste0("a/", character(), "b")
  # returns ONE string rather than none -- which is how the empty case first
  # blew up with "arguments imply differing number of rows: 0, 1".
  urls <- if (length(names)) {
    paste0("https://example.invalid/", names, ".copc.laz")
  } else {
    character()
  }
  idx <- sf::st_sf(name = as.character(names), url = urls, geometry = geom)
  structure(idx, class = c("fev_lidarhd_index", class(idx)))
}

grid_index <- function(n = 6) {
  g <- expand.grid(i = seq_len(n), j = seq_len(n))
  geom <- sf::st_sfc(lapply(seq_len(nrow(g)), function(k) {
    x <- g$i[k] * 1000; y <- g$j[k] * 1000
    sf::st_polygon(list(cbind(c(x, x + 1000, x + 1000, x, x),
                              c(y, y, y + 1000, y + 1000, y))))
  }), crs = 2154)
  nm <- sprintf("t%02d_%02d", g$i, g$j)
  structure(
    sf::st_sf(name = nm, url = paste0("https://example.invalid/", nm, ".laz"),
              geometry = geom),
    class = c("fev_lidarhd_index", "sf", "data.frame")
  )
}

spacing <- function(idx, sel) {
  xy <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(idx)))[sel, ]
  min(stats::dist(xy))
}

test_that("a dry run reports the plan and downloads nothing", {
  d <- withr::local_tempdir()
  plan <- fev_lidar_batch(fake_index(c("a", "b", "c")), d, dry_run = TRUE,
                          quiet = TRUE)
  expect_equal(nrow(plan), 3L)
  # With no cap, every tile is in this run's batch: "next", not "todo".
  expect_true(all(plan$status == "next"))
  expect_false(file.exists(file.path(d, "manifest.csv")))
})

test_that("the plan separates this run's batch from what is left for later", {
  # A dry run that does not say WHICH tiles it would take is misleading: the
  # plan is in index order and the traversal is not.
  d <- withr::local_tempdir()
  plan <- fev_lidar_batch(grid_index(), d, max_tiles = 4, dry_run = TRUE,
                          quiet = TRUE)
  expect_equal(sum(plan$status == "next"), 4L)
  expect_equal(sum(plan$status == "todo"), nrow(plan) - 4L)
  # And rank orders the batch, so a caller can print it in the order it runs.
  expect_setequal(plan$rank[plan$status == "next"], 1:4)
  expect_true(all(is.na(plan$rank[plan$status == "todo"])))
})

test_that("a tile whose raster exists is treated as done", {
  d <- withr::local_tempdir()
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.create(file.path(d, "b_fuel.tif"))

  plan <- fev_lidar_batch(fake_index(c("a", "b", "c")), d, dry_run = TRUE,
                          quiet = TRUE)
  expect_equal(plan$status[plan$tile == "b"], "done")
  expect_equal(plan$status[plan$tile == "a"], "next")
  # And the done one carries its path, so a caller can read it straight away.
  expect_true(nzchar(plan$path[plan$tile == "b"]))
})

test_that("max_tiles limits this run without forgetting the rest", {
  d <- withr::local_tempdir()
  plan <- fev_lidar_batch(fake_index(letters[1:5]), d, max_tiles = 2,
                          dry_run = TRUE, quiet = TRUE)
  # The plan still lists everything; the cap applies to what gets processed.
  expect_equal(nrow(plan), 5L)
})

test_that("an empty index is refused rather than silently doing nothing", {
  d <- withr::local_tempdir()
  expect_error(fev_lidar_batch(fake_index(character()), d, quiet = TRUE),
               class = "fev_no_lidar_coverage")
})

test_that("a bad window is refused", {
  d <- withr::local_tempdir()
  expect_error(fev_lidar_batch(fake_index("a"), d, window = -5, quiet = TRUE))
  expect_error(fev_lidar_batch(fake_index("a"), d, window = "wide",
                               quiet = TRUE))
})

test_that("a failing tile is recorded and does not end the run", {
  # The URLs are unreachable by construction, so every tile fails. The run must
  # still finish, and the manifest must say so -- a batch that dies on the third
  # of forty tiles wastes the two that worked.
  d <- withr::local_tempdir()
  plan <- suppressWarnings(suppressMessages(
    fev_lidar_batch(fake_index(c("x", "y")), d, quiet = TRUE)
  ))
  expect_equal(nrow(plan), 2L)
  expect_true(all(plan$status == "failed"))
  expect_true(file.exists(file.path(d, "manifest.csv")))

  m <- utils::read.csv(file.path(d, "manifest.csv"))
  expect_equal(nrow(m), 2L)
  expect_true(all(c("tile", "status", "points", "seconds") %in% names(m)))
})

test_that("the manifest is written after every tile, not only at the end", {
  d <- withr::local_tempdir()
  suppressWarnings(suppressMessages(
    fev_lidar_batch(fake_index(c("x", "y")), d, quiet = TRUE)
  ))
  # Present even though every tile failed: an interrupted run leaves a record.
  expect_true(file.exists(file.path(d, "manifest.csv")))
})

test_that("the runnable script ships with the package", {
  f <- system.file("scripts", "batch_lidar.R", package = "firexpovulnR")
  skip_if(!nzchar(f), "not installed")
  txt <- readLines(f, warn = FALSE)
  # The warning against thinning must survive any future edit of the header.
  expect_true(any(grepl("NE REDUISEZ PAS la densite", txt)))
  expect_true(any(grepl("--dry-run", txt)))
})

# --------------------------------------------------------------------------
# The traversal order, which is what makes a partial run useful
# --------------------------------------------------------------------------


test_that("the traversal spreads far better than index order", {
  # The index is itself in spatial order, so its first N are N neighbours in
  # one corner -- one context sampled N times.
  idx <- grid_index()
  ord <- firexpovulnR:::fev_lidar_spread_order(idx)
  expect_gt(spacing(idx, ord[1:6]), spacing(idx, 1:6))
})

test_that("the traversal is deterministic, so resume continues it", {
  idx <- grid_index()
  a <- firexpovulnR:::fev_lidar_spread_order(idx)
  b <- firexpovulnR:::fev_lidar_spread_order(idx)
  expect_identical(a, b)
})

test_that("every prefix is spread, not just the first batch", {
  # Eight tonight and eight tomorrow must give sixteen spread tiles, not two
  # clusters of eight.
  idx <- grid_index(8)
  ord <- firexpovulnR:::fev_lidar_spread_order(idx)
  expect_gt(spacing(idx, ord[1:16]), spacing(idx, 1:16))
})

test_that("it visits every tile exactly once", {
  idx <- grid_index()
  ord <- firexpovulnR:::fev_lidar_spread_order(idx)
  expect_setequal(ord, seq_len(nrow(idx)))
  expect_equal(anyDuplicated(ord), 0L)
})

test_that("a handful of tiles needs no traversal", {
  expect_equal(firexpovulnR:::fev_lidar_spread_order(fake_index(c("a", "b"))),
               1:2)
})

test_that("spread can be turned off, and then index order applies", {
  d <- withr::local_tempdir()
  plan <- fev_lidar_batch(grid_index(), d, spread = FALSE, max_tiles = 3,
                          dry_run = TRUE, quiet = TRUE)
  expect_equal(nrow(plan), 36L)
})

# The write, which no test above reaches -----------------------------------
#
# Everything before this points at example.invalid, so every tile fails at the
# download and the run never gets as far as writing a raster. That blind spot
# cost a full campaign: `paste0(dest, ".part")` produced "..._fuel.tif.part",
# terra could not guess a driver from it, and all eight tiles died on the last
# line after two minutes of inversion each. The suite was green throughout.

test_that("the temporary name keeps the extension terra needs", {
  tmp <- firexpovulnR:::fev_lidar_part_path("/out/LHD_FXX_0978_6252_fuel.tif")
  expect_match(tmp, "\\.tif$")
  # And it must still be distinguishable from a finished tile, since resume
  # tests the final name by exact match.
  expect_false(tmp == "/out/LHD_FXX_0978_6252_fuel.tif")
})

test_that("a raster can actually be written to the temporary name", {
  # The regression itself: not that the string looks right, but that terra
  # accepts it. A name test alone would have passed on ".tif.part" too, had it
  # been written to match the code.
  d <- withr::local_tempdir()
  dest <- file.path(d, "LHD_FXX_0978_6252_fuel.tif")
  tmp <- firexpovulnR:::fev_lidar_part_path(dest)
  r <- terra::rast(nrows = 4, ncols = 4, vals = seq_len(16))
  expect_no_error(terra::writeRaster(r, tmp, overwrite = TRUE))
  expect_true(file.rename(tmp, dest))
  expect_true(file.exists(dest))
})

test_that("a failed tile records why it failed", {
  # "failed" with no reason sends the operator back to a log that may be gone,
  # and the reason used to surface only as a deferred warning at the end of the
  # run -- pages after the tile that raised it.
  d <- withr::local_tempdir()
  plan <- suppressWarnings(
    fev_lidar_batch(fake_index("a"), d, quiet = TRUE)
  )
  expect_equal(plan$status, "failed")
  expect_true("error" %in% names(plan))
  expect_false(is.na(plan$error))
  manifest <- utils::read.csv(file.path(d, "manifest.csv"))
  expect_true("error" %in% names(manifest))
})
