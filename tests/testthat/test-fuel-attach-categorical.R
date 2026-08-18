# Carrying a second classification alongside instead of making it compete.
#
# The case this exists for: a 10 m raster wins every pixel of `class`, and the
# species and crown cover of the source it displaced would otherwise be lost.

mk <- function(type, codes, n = 8, res = 25, millesime = 2014) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res,
                   ymin = 0, ymax = n * res, crs = "EPSG:2154")
  terra::values(r) <- rep_len(seq_along(codes), terra::ncell(r))
  levels(r) <- data.frame(id = seq_along(codes), class = codes)
  names(r) <- "class"
  suppressMessages(fev_fuel_source(r, type = type, res = res,
                                   millesime = millesime,
                                   register = "categorical"))
}

wc <- function(...) mk("worldcover_2021", c("10", "20"), ...)
bd <- function(...) mk("bdforet_v2", c("FF1G06-06", "LA4"), ...)

test_that("a categorical source is carried alongside, not merged", {
  out <- suppressMessages(fev_fuel_attach(wc(), bd()))
  expect_true("bdforet_v2" %in% names(fev_fuel_categorical(out)))
  # And `class` is untouched by the attachment.
  expect_equal(
    terra::values(fev_fuel_categorical(out)[["class"]]),
    terra::values(fev_fuel_categorical(wc())[["class"]])
  )
})

test_that("the species survives a merge that gave WorldCover every pixel", {
  # Since 0.23.0 the ranking puts BD Forêt first, so this scenario has to be
  # asked for -- and it is the one attach exists for: a user who wants the 10 m
  # class and the vintage, and refuses to pay for them with the botany.
  merged <- suppressWarnings(suppressMessages(
    fev_fuel_merge(bd(), wc(), hierarchy = "secondary_first")
  ))
  src <- fev_cat_levels(fev_fuel_categorical(merged)[["source"]])
  expect_equal(src[[2]][1], "worldcover_2021")

  both <- suppressMessages(fev_fuel_attach(merged, bd()))
  lv <- fev_cat_levels(fev_fuel_categorical(both)[["bdforet_v2"]])
  expect_true(all(c("FF1G06-06", "LA4") %in% lv[[2]]))
})

test_that("the attached layer takes its name from the source, or from `name`", {
  a <- suppressMessages(fev_fuel_attach(wc(), bd()))
  expect_true("bdforet_v2" %in% names(fev_fuel_categorical(a)))

  b <- suppressMessages(fev_fuel_attach(wc(), bd(), name = "essence"))
  expect_true("essence" %in% names(fev_fuel_categorical(b)))
})

test_that("a name already in use is refused rather than silently doubled", {
  a <- suppressMessages(fev_fuel_attach(wc(), bd()))
  expect_error(suppressMessages(fev_fuel_attach(a, bd())),
               class = "fev_attach_name_taken")
  expect_error(suppressMessages(fev_fuel_attach(wc(), bd(), name = "class")),
               class = "fev_attach_name_taken")
})

test_that("both lookups are readable afterwards", {
  out <- suppressMessages(fev_fuel_attach(wc(), bd()))
  codes <- out$lookup$code
  expect_true("20" %in% codes)
  expect_true("FF1G06-06" %in% codes)
})

test_that("the downstream chain still reads `class` and ignores the passenger", {
  out <- suppressMessages(fev_fuel_attach(wc(), bd()))
  b1 <- fev_fuel_binary(out)
  b2 <- fev_fuel_binary(wc())
  expect_equal(terra::values(fev_data(b1)), terra::values(fev_data(b2)))
})

test_that("fill_gaps leaves the attached layer alone", {
  # Its NAs mean "not forest here", which is information; filling them from a
  # modal neighbour would invent species.
  r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 200,
                   ymin = 0, ymax = 200, crs = "EPSG:2154")
  terra::values(r) <- rep(1, 64)
  levels(r) <- data.frame(id = 1, class = "311")
  names(r) <- "class"
  r[3, 3] <- NA
  base <- suppressMessages(fev_fuel_source(r, type = "clc_2018",
                                           millesime = 2018,
                                           register = "categorical"))
  passenger <- bd(n = 8, res = 25)
  both <- suppressMessages(fev_fuel_attach(base, passenger, name = "essence"))

  before <- terra::values(fev_fuel_categorical(both)[["essence"]])
  filled <- suppressMessages(fev_fuel_fill_gaps(both))
  after <- terra::values(fev_fuel_categorical(filled)[["essence"]])

  expect_equal(before, after)
  # while `class` really was repaired
  expect_lt(sum(is.na(terra::values(fev_fuel_categorical(filled)[["class"]]))),
            sum(is.na(terra::values(fev_fuel_categorical(both)[["class"]]))))
})

test_that("the continuous branch is unchanged", {
  base <- wc()
  cbd <- terra::rast(fev_fuel_categorical(base)[["class"]])
  terra::values(cbd) <- runif(terra::ncell(cbd), 0, 0.4)
  names(cbd) <- "CBD_max"
  lidar <- suppressMessages(fev_fuel_source(cbd, type = "custom",
                                            register = "continuous",
                                            units = c(CBD_max = "kg/m3")))
  out <- suppressMessages(fev_fuel_attach(base, lidar))
  expect_true("continuous" %in% fev_fuel_registers(out))
  expect_equal(names(fev_fuel_categorical(out)), "class")
})

test_that("the provenance says it arbitrated nothing", {
  out <- suppressMessages(fev_fuel_attach(wc(), bd()))
  steps <- out$provenance$steps
  expect_true(any(vapply(steps, function(st) {
    identical(st$fun, "fev_fuel_attach") &&
      isTRUE(grepl("no pixel arbitration", st$notes %||% ""))
  }, logical(1))))
})
