# The cache directory is redirected to a temp dir for the whole file, so tests
# never touch the user's real cache.
local_cache <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(FIREXPOVULNR_CACHE_DIR = dir, .local_envir = env)
  dir
}

test_that("the cache directory honours the environment override", {
  dir <- local_cache()
  expect_equal(fev_cache_dir(), dir)
})

test_that("cache keys depend on every request parameter", {
  key <- firexpovulnR:::fev_cache_key
  aoi <- synth_aoi()

  k1 <- key("bdforet_v2", list(aoi = aoi, layer = "L1"))
  k2 <- key("bdforet_v2", list(aoi = aoi, layer = "L2"))
  k3 <- key("clc", list(aoi = aoi, layer = "L1"))

  # Different parameters must not collide: serving a cached layer for a
  # different request is the error that survives into a publication.
  expect_false(identical(k1, k2))
  expect_false(identical(k1, k3))
  expect_match(k1, "^bdforet_v2_")

  # Same parameters, same key -- including when the list order differs.
  expect_identical(k1, key("bdforet_v2", list(layer = "L1", aoi = aoi)))
})

test_that("cache keys treat identical geometries as identical", {
  key <- firexpovulnR:::fev_cache_key
  a <- synth_aoi()
  # Same footprint, rebuilt from scratch: vertex order must not matter.
  b <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(a)))

  expect_identical(key("x", list(aoi = a)), key("x", list(aoi = b)))
})

test_that("a write/read round trip preserves data and source record", {
  local_cache()
  key <- "test_entry"
  aoi <- synth_aoi()
  rec <- list(dataset = "test", millesime = NA, endpoint = "https://example.org")

  firexpovulnR:::fev_cache_write(key, aoi, rec)
  expect_true(firexpovulnR:::fev_cache_hit(key))

  back <- firexpovulnR:::fev_cache_read(key)
  expect_s3_class(back$data, "sf")
  expect_equal(back$source$dataset, "test")
  expect_true(is.na(back$source$millesime))
})

test_that("a data file without its provenance sidecar counts as a miss", {
  # Serving cached data with no traceable origin is worse than re-downloading:
  # it looks authoritative and cannot be audited.
  dir <- local_cache()
  key <- "orphan"
  firexpovulnR:::fev_cache_write(key, synth_aoi(), list(dataset = "x"))
  file.remove(file.path(dir, paste0(key, ".prov.rds")))

  expect_false(firexpovulnR:::fev_cache_hit(key))
})

test_that("fev_cache_info reports an empty cache without failing", {
  local_cache()
  expect_message(info <- fev_cache_info())
  expect_s3_class(info, "data.frame")
  expect_equal(nrow(info), 0L)
})

test_that("fev_cache_info lists entries with dataset and vintage", {
  local_cache()
  firexpovulnR:::fev_cache_write(
    "bdforet_v2_abc", synth_aoi(),
    list(dataset = "bdforet_v2", millesime = NA, endpoint = "https://data.geopf.fr/wfs/ows")
  )
  firexpovulnR:::fev_cache_write(
    "clc_def", synth_aoi(),
    list(dataset = "clc", millesime = 2018, endpoint = "https://data.geopf.fr/wfs/ows")
  )

  info <- fev_cache_info()
  expect_equal(nrow(info), 2L)
  expect_setequal(info$dataset, c("bdforet_v2", "clc"))
  expect_equal(info$millesime[info$dataset == "clc"], "2018")
  expect_true(is.na(info$millesime[info$dataset == "bdforet_v2"]))
})

test_that("fev_cache_clear removes data and sidecar together", {
  dir <- local_cache()
  firexpovulnR:::fev_cache_write("bdforet_v2_a", synth_aoi(),
                                 list(dataset = "bdforet_v2"))
  firexpovulnR:::fev_cache_write("clc_b", synth_aoi(), list(dataset = "clc"))

  expect_message(fev_cache_clear(dataset = "bdforet_v2", confirm = FALSE))

  # No orphan left behind.
  expect_length(list.files(dir, pattern = "^bdforet_v2_a\\."), 0L)
  expect_length(list.files(dir, pattern = "^clc_b\\."), 2L)
})

test_that("fev_cache_clear filters on age and reports when nothing matches", {
  local_cache()
  firexpovulnR:::fev_cache_write("clc_b", synth_aoi(), list(dataset = "clc"))

  expect_message(out <- fev_cache_clear(older_than = 365, confirm = FALSE))
  expect_length(out, 0L)
})

test_that("clearing an empty cache is a no-op, not an error", {
  local_cache()
  expect_message(out <- fev_cache_clear(confirm = FALSE))
  expect_length(out, 0L)
})
