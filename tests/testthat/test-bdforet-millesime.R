# The vintage lookup, tested without a network.
#
# The fetch is isolated in fev_fetch_ortho_graph() so everything that decides
# what the answer is -- slice selection, period filtering, grouping, area
# shares, and whether the question is settled -- can be exercised on a fixture.
# The live request has its own test in test-integration-network.R.

graph_fixture <- function(dep = "83", years = c(2008, 2014),
                          areas = c(1, 1), crs = 2154) {
  # Adjacent squares whose areas are in the ratio given, so the pct_area
  # column has a value checkable by hand.
  areas <- rep_len(areas, length(years))
  widths <- sqrt(areas) * 1000
  x0 <- c(0, cumsum(utils::head(widths, -1)))
  geom <- Map(function(x, w) {
    sf::st_polygon(list(cbind(c(x, x + w, x + w, x, x),
                              c(0, 0, w, w, 0))))
  }, x0, widths)

  sf::st_sf(
    dep = rep_len(dep, length(years)),
    pva = as.integer(years),
    date_vol = as.Date(paste0(years, "-07-01")),
    slice = rep_len("fixture", length(years)),
    geometry = sf::st_sfc(geom, crs = crs)
  )
}

test_that("the right archived graphs are chosen for a window", {
  # BD Forêt v2 was built 2007-2018, which straddles three slices.
  layers <- fev_ortho_graphs_for(c(2007L, 2018L))
  expect_named(layers, c("2006-2010", "2011-2015", "2016-2020"))

  # A narrow window picks one.
  expect_named(fev_ortho_graphs_for(c(2012L, 2013L)), "2011-2015")
  # A window on a boundary picks both slices it touches.
  expect_named(fev_ortho_graphs_for(c(2010L, 2011L)),
               c("2006-2010", "2011-2015"))
  # Outside every slice, nothing.
  expect_length(fev_ortho_graphs_for(c(1900L, 1910L)), 0L)
})

test_that("campaigns are grouped by department and year", {
  g <- graph_fixture(years = c(2008, 2008, 2014))
  tab <- fev_millesime_table(g, c(2007L, 2018L), 2154)
  expect_s3_class(tab, "fev_millesime")
  expect_equal(nrow(tab), 2L)
  expect_equal(tab$year, c(2008L, 2014L))
  expect_equal(tab$n_polygons, c(2L, 1L))
  expect_equal(sum(tab$pct_area), 100)
})

test_that("the area share says which campaign dominates", {
  # Three quarters of the mosaic flown in 2014, one quarter in 2008.
  g <- graph_fixture(years = c(2008, 2014), areas = c(1, 3))
  tab <- fev_millesime_table(g, c(2007L, 2018L), 2154)
  expect_equal(tab$pct_area, c(25, 75))
})

test_that("the period filters the campaigns, not just the layers", {
  # An archived slice spans five years, so a request for 2011-2013 still
  # returns 2014 polygons from the 2011-2015 graph. They have to be dropped
  # here or the answer includes a survey outside the window asked for.
  g <- graph_fixture(years = c(2008, 2014))
  expect_equal(nrow(fev_millesime_table(g, c(2007L, 2010L), 2154)), 1L)
  expect_equal(fev_millesime_table(g, c(2007L, 2010L), 2154)$year, 2008L)
  expect_equal(nrow(fev_millesime_table(g, c(2016L, 2018L), 2154)), 0L)
})

test_that("an AOI over two departments keeps them apart", {
  g <- rbind(graph_fixture(dep = "83", years = 2014),
             graph_fixture(dep = "06", years = 2014))
  tab <- fev_millesime_table(g, c(2007L, 2018L), 2154)
  expect_equal(nrow(tab), 2L)
  expect_setequal(tab$dep, c("83", "06"))
})

test_that("a single campaign settles the question, several do not", {
  # The distinction that matters: with one candidate the vintage is known,
  # with two it is not, and the package must not pick.
  one <- fev_millesime_table(graph_fixture(years = 2014), c(2007L, 2018L), 2154)
  expect_message(fev_report_millesime(one, c(2007L, 2018L)),
                 class = "fev_millesime_found")

  two <- fev_millesime_table(graph_fixture(), c(2007L, 2018L), 2154)
  expect_warning(fev_report_millesime(two, c(2007L, 2018L)),
                 class = "fev_millesime_ambiguous")
})

test_that("undated polygons are dropped rather than counted", {
  g <- graph_fixture(years = c(2008, 2014))
  g$date_vol[1] <- NA
  tab <- fev_millesime_table(g, c(2007L, 2018L), 2154)
  expect_equal(nrow(tab), 1L)
  expect_equal(tab$year, 2014L)
})

test_that("an empty graph gives an empty table with the right shape", {
  empty <- fev_millesime_table(graph_fixture()[0, ], c(2007L, 2018L), 2154)
  expect_s3_class(empty, "fev_millesime")
  expect_equal(nrow(empty), 0L)
  expect_true(all(c("dep", "pva", "date_vol", "year", "n_polygons",
                    "pct_area") %in% names(empty)))
  expect_no_error(print(empty))
})

test_that("the candidate table prints", {
  tab <- fev_millesime_table(graph_fixture(), c(2007L, 2018L), 2154)
  expect_no_error(print(tab))

  y <- structure(2008L, candidates = tab, strategy = "oldest",
                 class = c("fev_millesime_year", "integer"))
  expect_no_error(print(y))
  expect_equal(as.integer(y), 2008L)
})

test_that("a window outside every archived slice is refused", {
  aoi <- sf::st_as_sf(synth_rect(0, 1000, 0, 1000))
  expect_error(
    fev_bdforet_millesime(aoi, period = c(1900, 1910), cache = FALSE),
    class = "fev_no_graph"
  )
})

test_that("strategy is validated before anything is fetched", {
  aoi <- sf::st_as_sf(synth_rect(0, 1000, 0, 1000))
  expect_error(
    fev_bdforet_millesime(aoi, strategy = "median", cache = FALSE),
    class = "error"
  )
})

test_that("fev_fuel_source now points at the lookup when the vintage is absent", {
  # The refusal is unchanged; what changed is that it can name a way out.
  aoi <- synth_fuel_aoi()
  err <- tryCatch(
    fev_fuel_source(synth_bdforet(), type = "bdforet_v2", res = 50, aoi = aoi),
    condition = function(e) e
  )
  expect_s3_class(err, "fev_millesime_required")
  expect_match(paste(conditionMessage(err), collapse = " "),
               "fev_bdforet_millesime")
})
