rgrid <- function(values, n = 6) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * 25, ymin = 0,
                   ymax = n * 25, crs = "EPSG:2154")
  terra::values(r) <- values
  r
}

test_that("effis_mean is the unweighted arithmetic mean", {
  # CLIMAAX: normalise each component with min-max, then average with equal
  # weights. Here the inputs are already scaled, so the mean is checkable by
  # hand.
  d <- rgrid(rep(c(0, 0.5, 1, 1), 9))
  v <- rgrid(rep(c(1, 0.5, 0, 1), 9))
  out <- terra::values(fev_data(fev_risk(d, v, normalise = "none")))[, 1]
  expect_equal(unique(out), c(0.5, 0.5, 0.5, 1)[c(1, 4)])
  expect_setequal(round(unique(out), 6), c(0.5, 1))
})

test_that("weighted requires its weights and honours them", {
  d <- rgrid(rep(1, 36))
  v <- rgrid(rep(0, 36))
  expect_error(fev_risk(d, v, method = "weighted", normalise = "none"),
               class = "fev_error")

  out <- terra::values(fev_data(
    fev_risk(d, v, method = "weighted", weights = c(0.7, 0.3),
             normalise = "none")
  ))[, 1]
  expect_equal(unique(out), 0.7)

  expect_error(
    fev_risk(d, v, method = "weighted", weights = c(0.7, 0.7),
             normalise = "none"),
    class = "fev_error"
  )
  expect_error(
    fev_risk(d, v, method = "weighted", weights = 1, normalise = "none"),
    class = "fev_error"
  )
})

test_that("min-max normalisation restretches, and says so once", {
  fev_reset_once()
  # A layer legitimately spanning 0.3-0.6 comes out spanning 0-1. That is what
  # CLIMAAX does, and it is why "none" exists.
  d <- rgrid(seq(0.3, 0.6, length.out = 36))
  v <- rgrid(rep(0.5, 36))
  expect_warning(
    out <- fev_risk(d, rgrid(seq(0, 1, length.out = 36))),
    class = "fev_extent_dependent"
  )
  scaled <- terra::values(fev_data(out))[, 1]
  expect_equal(min(scaled), 0)
  expect_equal(max(scaled), 1)

  # A constant dimension has no range to rescale on.
  expect_error(fev_risk(d, v), class = "fev_bad_range")
  fev_reset_once()
})

test_that("the Pareto front is a set, and anti-correlated layers are all on it", {
  # Two perfectly anti-correlated dimensions: no cell dominates another, so
  # every cell is on the front. A front that excluded some of them would be a
  # bug, and this is the cleanest case in which to see it.
  d <- rgrid(seq(0, 1, length.out = 36))
  v <- rgrid(rev(seq(0, 1, length.out = 36)))
  out <- fev_risk(d, v, method = "pareto", normalise = "none")
  vals <- terra::values(fev_data(out))[, 1]
  expect_setequal(unique(vals), 1)
  expect_equal(out$units, "Pareto front membership, 0/1")
})

test_that("the Pareto front keeps only the non-dominated cells", {
  # Cell 1 dominates cell 2 on both dimensions, so cell 2 is off the front;
  # cells 1 and 3 trade off, so both are on it.
  d <- rgrid(c(1.0, 0.5, 0.2, rep(0.1, 33)))
  v <- rgrid(c(0.2, 0.1, 1.0, rep(0.05, 33)))
  vals <- terra::values(fev_data(
    fev_risk(d, v, method = "pareto", normalise = "none")
  ))[, 1]
  expect_equal(vals[1], 1)
  expect_equal(vals[2], 0)
  expect_equal(vals[3], 1)
  expect_equal(vals[4], 0)
})

test_that("peeling turns the front into a graded layer", {
  d <- rgrid(c(1.0, 0.6, 0.3, rep(0.1, 33)))
  v <- rgrid(c(1.0, 0.6, 0.3, rep(0.1, 33)))
  shallow <- terra::values(fev_data(
    fev_risk(d, v, method = "pareto", normalise = "none")
  ))[, 1]
  deep <- terra::values(fev_data(
    fev_risk(d, v, method = "pareto", normalise = "none", depth = Inf)
  ))[, 1]

  # Perfectly correlated dimensions: a total order, so front 1 is one cell.
  expect_equal(sum(shallow), 1)
  # Peeled, every distinct value gets its own level, best first.
  expect_equal(deep[1], 1)
  expect_gt(deep[2], deep[3])
  expect_gt(deep[3], deep[4])
})

test_that("Pareto refuses rather than running for hours", {
  # The guard that matters: the dominance scan is quadratic in the number of
  # distinct tuples, so a refusal beats an afternoon.
  set.seed(21)
  d <- rgrid(stats::runif(2500), n = 50)
  v <- rgrid(stats::runif(2500), n = 50)
  expect_error(
    fev_risk(d, v, method = "pareto", normalise = "none", max_unique = 100),
    class = "fev_pareto_too_large"
  )
  # Rounding harder collapses the tuples and it runs.
  expect_no_error(
    fev_risk(d, v, method = "pareto", normalise = "none", digits = 1)
  )
})

test_that("extra dimensions enter the combination, as CLIMAAX does", {
  # CLIMAAX passes five: the danger index plus four vulnerability indicators.
  d <- rgrid(rep(1, 36))
  v <- rgrid(rep(0, 36))
  wui <- rgrid(rep(1, 36))
  n2k <- rgrid(rep(0, 36))

  out <- fev_risk(d, v, wui = wui, natura = n2k, normalise = "none")
  expect_equal(unique(terra::values(fev_data(out))[, 1]), 0.5)

  step <- out$provenance$steps[[length(out$provenance$steps)]]
  expect_equal(step$params$n_dimensions, 4L)
  expect_equal(step$params$dimensions,
               c("danger", "vulnerability", "wui", "natura"))

  expect_error(fev_risk(d, v, wui, normalise = "none"), class = "fev_error")
})

test_that("mismatched grids are refused and point at fev_align", {
  d <- rgrid(rep(0.5, 36))
  v <- rgrid(rep(0.5, 144), n = 12)
  expect_error(fev_risk(d, v, normalise = "none"), class = "fev_grid_mismatch")

  s <- fev_align(danger = d, vulnerability = v, quiet = TRUE)
  expect_no_error(fev_risk(s$danger, s$vulnerability, normalise = "none"))
})

test_that("degenerate inputs are refused", {
  d <- rgrid(rep(0.5, 36))
  expect_error(fev_risk(d, rgrid(rep(NA_real_, 36)), normalise = "none"),
               class = "fev_all_na")
  expect_error(fev_risk(d, rgrid(seq(0, 5, length.out = 36)),
                        normalise = "none"),
               class = "fev_bad_range")
  expect_error(fev_risk(d, rgrid(rep(0.5, 36)), method = "pareto",
                        normalise = "none", depth = 0),
               class = "fev_error")
})

test_that("the method and its source are recorded", {
  d <- rgrid(seq(0, 1, length.out = 36))
  v <- rgrid(rep(0.5, 36))
  out <- fev_risk(d, v, normalise = "none")
  step <- out$provenance$steps[[length(out$provenance$steps)]]
  expect_equal(step$fun, "fev_risk")
  expect_equal(step$params$method, "effis_mean")
  expect_equal(step$params$normalise, "none")
  expect_false(step$params$extent_dependent)
  expect_match(step$params$source, "CLIMAAX")
})

test_that("the whole chain reaches risk with its provenance intact", {
  # danger index and vulnerability stack, both built by the package, combined.
  g <- rgrid(rep(0, 36))
  danger <- terra::setValues(g, seq(0, 100, length.out = 36))
  avail <- terra::setValues(g, rep(c(0, 0.5, 1, 1), 9))
  idx <- fev_danger_index(danger, avail, normalise = "percentile")

  human <- terra::setValues(g, seq(0, 1, length.out = 36))
  eco <- terra::setValues(g, rev(seq(0, 1, length.out = 36)))
  vuln <- fev_vuln_stack(human = human, eco = eco, weights = c(0.6, 0.4))

  risk <- fev_risk(idx, vuln, normalise = "none")
  funs <- vapply(risk$provenance$steps, function(s) s$fun, character(1))
  expect_true("fev_danger_index" %in% funs)
  expect_true("fev_vuln_stack" %in% funs)
  expect_equal(funs[length(funs)], "fev_risk")
  expect_s3_class(risk, "fev_risk_layer")
})
