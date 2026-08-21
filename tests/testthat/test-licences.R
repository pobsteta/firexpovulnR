# Licences, and the two rules that are not the same rule.
#
# What made this a first-class field rather than free text inside `provider`:
# SUFOSAT carries three answers for the SAME data depending on where you ask --
# 403 on the bucket the STAC catalogue points at, CC-BY-NC on the superseded
# Zenodo version, CC-BY 4.0 on the current one. A licence belongs to the
# acquisition path, not to the dataset.

prov_with <- function(...) {
  p <- fev_prov_new(crs_work = 2154)
  for (s in list(...)) {
    p <- fev_prov_add_source(p, dataset = s$dataset, licence = s$licence,
                             licence_from = s$from %||% NA_character_)
  }
  p
}

layer_with <- function(prov) {
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 10,
                   ymin = 0, ymax = 10, crs = "EPSG:2154")
  new_fev_layer(terra::setValues(g, 1), role = "risk", provenance = prov)
}

test_that("every source contributes a row, with where its licence was read", {
  l <- layer_with(prov_with(
    list(dataset = "a", licence = "CC-BY-4.0", from = "fiche produit"),
    list(dataset = "b", licence = "CC-BY-NC-4.0", from = "depot")))
  tab <- fev_licences(l)
  expect_s3_class(tab, "fev_licences")
  expect_equal(nrow(tab), 2L)
  expect_true(all(c("dataset", "licence", "licence_from") %in% names(tab)))
  expect_equal(tab$licence_from[1], "fiche produit")
})

test_that("an unestablished licence stays NA and is never guessed", {
  # The gap is visible; a guess would not be. Six of the package's own sources
  # are in this state because their producer's page was never read.
  l <- layer_with(prov_with(list(dataset = "a", licence = NA_character_,
                                 from = "non etablie")))
  expect_true(is.na(fev_licences(l)$licence))
  expect_message(print(fev_licences(l)), "not established")
})

test_that("a non-commercial input is reported as governing the result", {
  # Not a choice the package makes: a derived work has to satisfy the terms of
  # every input at once, so one NC input makes the result NC.
  l <- layer_with(prov_with(
    list(dataset = "libre", licence = "CC-BY-4.0"),
    list(dataset = "restreint", licence = "CC-BY-NC-4.0")))
  expect_message(print(fev_licences(l)), "non-commercial")
  expect_message(print(fev_licences(l)), "restreint")
})

test_that("all-permissive says so rather than staying silent", {
  l <- layer_with(prov_with(
    list(dataset = "a", licence = "CC-BY-4.0"),
    list(dataset = "b", licence = "Copernicus")))
  expect_message(print(fev_licences(l)), "No non-commercial source")
})

test_that("only NC is detected, because only NC propagates and bites", {
  # Ranking CC-BY against Etalab against the Copernicus licence would be a legal
  # judgement the package has no business making.
  expect_true(firexpovulnR:::fev_licence_is_nc("CC-BY-NC-4.0"))
  expect_false(firexpovulnR:::fev_licence_is_nc("CC-BY-4.0"))
  expect_false(firexpovulnR:::fev_licence_is_nc("Copernicus"))
  expect_false(firexpovulnR:::fev_licence_is_nc(NA_character_))
})

test_that("a source object answers directly, without a layer around it", {
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 10,
                   ymin = 0, ymax = 10, crs = "EPSG:2154")
  s <- new_fev_source(terra::setValues(g, 1), dataset = "demo",
                      licence = "CC-BY-4.0", licence_from = "fiche")
  expect_equal(fev_licences(s)$licence, "CC-BY-4.0")
})

test_that("the same dataset twice is listed once", {
  l <- layer_with(prov_with(
    list(dataset = "a", licence = "CC-BY-4.0"),
    list(dataset = "a", licence = "CC-BY-4.0")))
  expect_equal(nrow(fev_licences(l)), 1L)
})

test_that("a record with no source is an error, not an empty answer", {
  expect_error(fev_licences(layer_with(fev_prov_new(crs_work = 2154))),
               class = "fev_no_source")
})

test_that("the package's own sources carry the field", {
  # Twelve acquisition functions; six record a licence read at the producer,
  # six record NA because it was not. Both must be present as a field.
  skip_if_not_installed("terra")
  g <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 10,
                   ymin = 0, ymax = 10, crs = "EPSG:2154")
  s <- new_fev_source(terra::setValues(g, 1), dataset = "x")
  # new_fev_source() does not force the field, so a source built without it
  # must still answer rather than fail.
  expect_true(is.na(fev_licences(s)$licence))
})
