test_that("a fresh record carries package, session and stack versions", {
  p <- firexpovulnR:::fev_prov_new(crs_work = 2154)

  expect_s3_class(p, "fev_provenance")
  expect_equal(p$crs_work, 2154)
  expect_equal(p$package$name, "firexpovulnR")

  # GDAL/GEOS/PROJ change resampling and reprojection behaviour, so a result
  # is not reproducible without them. They belong in the record.
  expect_true(all(c("gdal", "geos", "proj", "terra", "sf") %in% names(p$session)))
})

test_that("steps accumulate in order with their parameters", {
  p <- firexpovulnR:::fev_prov_new()
  p <- firexpovulnR:::fev_prov_add_step(p, "fev_exposure", list(radius = 500))
  p <- firexpovulnR:::fev_prov_add_step(p, "fev_risk", list(method = "effis_mean"))

  expect_length(p$steps, 2L)
  expect_equal(p$steps[[1]]$seq, 1L)
  expect_equal(p$steps[[2]]$seq, 2L)
  expect_equal(p$steps[[1]]$params$radius, 500)
  expect_equal(p$steps[[2]]$fun, "fev_risk")
})

test_that("an unknown millesime is recorded as NA, never invented", {
  # BD Forêt v2 does not serve its vintage through the WFS. Recording NA is
  # the honest outcome; anything else would fabricate the one number the
  # temporal-bias check depends on.
  p <- firexpovulnR:::fev_prov_new()
  p <- firexpovulnR:::fev_prov_add_source(
    p,
    dataset  = "bdforet_v2",
    provider = "IGN",
    endpoint = "https://data.geopf.fr/wfs/ows"
  )

  expect_length(p$sources, 1L)
  expect_true(is.na(p$sources[[1]]$millesime))
  expect_false(is.na(p$sources[[1]]$downloaded_at))
})

test_that("scalarise reduces unserialisable values to honest descriptions", {
  scl <- firexpovulnR:::fev_prov_scalarise

  expect_equal(scl(500), 500)
  expect_equal(scl(NULL), "NULL")
  expect_equal(scl(mean), "<function>")

  # A raster cannot go into YAML, but dropping it would lose the fact that a
  # raster was passed at all -- and its geometry is what a reader needs.
  desc <- scl(synth_raster(nrow = 3, ncol = 4, res = 25))
  expect_match(desc, "SpatRaster 3x4")
  expect_match(desc, "EPSG:2154")

  expect_match(scl(synth_aoi()), "^<sf, 1 feature")
  expect_match(scl(seq_len(100)), "length 100")

  nested <- scl(list(a = 1, b = list(c = "x")))
  expect_equal(nested$b$c, "x")
})

test_that("fev_provenance exports YAML that reads back to the same values", {
  s <- fev_stack(fuel = synth_raster(), crs_work = 2154)
  f <- withr::local_tempfile(fileext = ".yml")

  expect_message(fev_provenance(s, file = f))
  expect_true(file.exists(f))

  back <- yaml::read_yaml(f)
  expect_equal(back$crs_work, 2154)
  expect_equal(back$package$name, "firexpovulnR")
  expect_equal(back$steps[[1]]$fun, "fev_stack")
})

test_that("fev_provenance refuses anything that is not a stack", {
  expect_error(fev_provenance(1:10), class = "fev_error")
  expect_error(fev_provenance(synth_raster()), class = "fev_error")
})

test_that("compact drops NULLs but keeps NA", {
  cmp <- firexpovulnR:::fev_prov_compact
  out <- cmp(list(a = 1, b = NULL, c = NA, d = list(e = NULL, f = 2)))

  expect_named(out, c("a", "c", "d"))
  expect_true(is.na(out$c))
  expect_named(out$d, "f")
})
