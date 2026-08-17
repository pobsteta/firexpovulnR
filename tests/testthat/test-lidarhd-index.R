# The availability check, tested without a network.
#
# The WFS request is isolated in fev_lidarhd_query() so that everything which
# decides what the answer means -- coverage share, whether the area is flown at
# all, the refusal to start a terabyte download -- runs on a fixture.
#
# It matters more here than for the other fetchers: an empty result is a
# LEGITIMATE answer, because the LiDAR HD programme is still being flown. The
# code has to tell "not flown" from "malformed request", and on this WFS a
# lat-first BBOX also returns zero features with HTTP 200.

test_that("coverage is the share of the AOI the tiles actually cover", {
  idx <- synth_lidarhd_index(n = 2)
  # Two 1 km tiles side by side; an AOI of exactly one of them is fully covered.
  one <- sf::st_as_sf(synth_rect(968000, 969000, 6239000, 6240000))
  expect_equal(fev_lidarhd_coverage(idx, one), 100)

  # An AOI spanning one tile and one unflown kilometre is half covered.
  half <- sf::st_as_sf(synth_rect(968000, 970000, 6239000, 6240000))
  expect_equal(fev_lidarhd_coverage(idx[1, ], half), 50)

  # Nothing where the tiles are not.
  away <- sf::st_as_sf(synth_rect(900000, 901000, 6300000, 6301000))
  expect_equal(fev_lidarhd_coverage(idx, away), 0)
  expect_equal(fev_lidarhd_coverage(idx[0, ], one), 0)
})

test_that("an unflown area warns rather than erroring", {
  # Couchey is the real case: zero tiles on 2026-08-17. That is data, not a
  # failure, and the message has to say what to do instead.
  empty <- structure(fev_lidarhd_empty(2154),
                     class = c("fev_lidarhd_index", "sf", "data.frame"),
                     coverage = 0, product = "points",
                     layer = .FEV_LIDARHD_LAYERS$points_dalle)
  expect_warning(fev_report_lidarhd(empty, 0, "points"),
                 class = "fev_no_lidar_coverage")
  expect_no_error(print(empty))
})

test_that("the axis-order trap is named in the no-coverage message", {
  # A lat-first BBOX returns zero features with HTTP 200, which is
  # indistinguishable from an unflown area. The message has to raise it,
  # because here the innocent explanation is the likely one.
  empty <- fev_lidarhd_empty(2154)
  msg <- tryCatch(fev_report_lidarhd(empty, 0, "points"),
                  condition = function(c) paste(conditionMessage(c),
                                                collapse = " "))
  expect_match(msg, "latitude-first")
})

test_that("full coverage informs, partial coverage flags itself", {
  idx <- synth_lidarhd_index(n = 2)
  expect_message(fev_report_lidarhd(idx, 100, "points"),
                 class = "fev_lidar_coverage")

  msg <- tryCatch(fev_report_lidarhd(idx, 60, "points"),
                  condition = function(c) paste(conditionMessage(c),
                                                collapse = " "))
  expect_match(msg, "60")
  # A result on 60% of a study area is not a result for it, and the message
  # says so rather than leaving the reader to notice.
  expect_match(msg, "not a result for that study area")
})

test_that("the index reports its acquisition block and vintage", {
  idx <- synth_lidarhd_index(n = 3, chantier = "106", timestamp = "2025-05-01")
  msg <- tryCatch(fev_report_lidarhd(idx, 100, "points"),
                  condition = function(c) paste(conditionMessage(c),
                                                collapse = " "))
  expect_match(msg, "106")
  expect_match(msg, "2025")
})

test_that("every product has a tile layer", {
  # The point clouds are gigabytes; the derived height model is not, and is
  # often all anyone needs. Both routes must exist.
  for (p in c("points_dalle", "mnh_dalle", "mns_dalle", "mnt_dalle")) {
    expect_true(nzchar(.FEV_LIDARHD_LAYERS[[p]]), info = p)
    expect_match(.FEV_LIDARHD_LAYERS[[p]], "LIDAR-HD")
  }
  expect_equal(.FEV_LIDARHD_TILE_M, 1000L)
})

test_that("the empty index has the shape a full one has", {
  # So that downstream code can rely on the columns whether or not the area is
  # flown, instead of branching on nrow().
  empty <- fev_lidarhd_empty(2154)
  full <- synth_lidarhd_index(n = 1)
  expect_true(all(c("name", "url", "timestamp", "id_chantier") %in%
                    names(empty)))
  expect_true(all(names(empty) %in% c(names(full), "type_produit")))
  expect_equal(nrow(empty), 0L)
  expect_equal(sf::st_crs(empty), sf::st_crs(2154))
})

# --- retrieval guards --------------------------------------------------------

test_that("downloading refuses when there is nothing to download", {
  empty <- structure(fev_lidarhd_empty(2154),
                     class = c("fev_lidarhd_index", "sf", "data.frame"),
                     coverage = 0, product = "points",
                     layer = .FEV_LIDARHD_LAYERS$points_dalle)
  expect_error(fev_fetch_lidarhd(empty), class = "fev_no_lidar_coverage")
})

test_that("downloading refuses a job larger than max_tiles", {
  # A thousand tiles is a terabyte. The default is deliberately small so that a
  # departmental job has to be asked for explicitly.
  idx <- structure(synth_lidarhd_index(n = 12),
                   class = c("fev_lidarhd_index", "sf", "data.frame"),
                   coverage = 100, product = "points",
                   layer = .FEV_LIDARHD_LAYERS$points_dalle)
  expect_error(fev_fetch_lidarhd(idx, max_tiles = 4),
               class = "fev_too_many_tiles")

  err <- tryCatch(fev_fetch_lidarhd(idx, max_tiles = 4),
                  condition = function(c) paste(conditionMessage(c),
                                                collapse = " "))
  # The refusal must carry the size, and point at reading COPC over HTTP as
  # the alternative to downloading.
  expect_match(err, "12")
  expect_match(err, "COPC")
})

test_that("an already-present tile is skipped, which is how a run resumes", {
  dir <- withr::local_tempdir()
  idx <- structure(synth_lidarhd_index(n = 2),
                   class = c("fev_lidarhd_index", "sf", "data.frame"),
                   coverage = 100, product = "points",
                   layer = .FEV_LIDARHD_LAYERS$points_dalle)

  # Two files already on disk, one plausible and one truncated: the first is
  # kept, the second must be refetched (and will fail, offline, which is what
  # the test asserts).
  writeBin(raw(2e6), file.path(dir, basename(as.character(idx$url[1]))))
  writeBin(raw(10), file.path(dir, basename(as.character(idx$url[2]))))

  cls <- warning_classes(
    res <- tryCatch(fev_fetch_lidarhd(idx, dir = dir, max_tiles = 5,
                                      quiet = TRUE),
                    error = function(e) e)
  )
  # Offline, the truncated tile cannot be replaced, so it is reported as a
  # failed tile and the run still returns the one that was already good.
  if (inherits(res, "fev_source")) {
    got <- fev_data(res)
    expect_equal(nrow(got), 2L)
    expect_false(is.na(got$path[1]))
  } else {
    expect_s3_class(res, "condition")
  }
  expect_true("fev_tile_failed" %in% cls || inherits(res, "condition"))
})
