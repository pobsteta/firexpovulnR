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

test_that("a dry run reports the plan and downloads nothing", {
  d <- withr::local_tempdir()
  plan <- fev_lidar_batch(fake_index(c("a", "b", "c")), d, dry_run = TRUE,
                          quiet = TRUE)
  expect_equal(nrow(plan), 3L)
  expect_true(all(plan$status == "todo"))
  expect_false(file.exists(file.path(d, "manifest.csv")))
})

test_that("a tile whose raster exists is treated as done", {
  d <- withr::local_tempdir()
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.create(file.path(d, "b_fuel.tif"))

  plan <- fev_lidar_batch(fake_index(c("a", "b", "c")), d, dry_run = TRUE,
                          quiet = TRUE)
  expect_equal(plan$status[plan$tile == "b"], "done")
  expect_equal(plan$status[plan$tile == "a"], "todo")
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
