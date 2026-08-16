# Cross-check against fireexposuR, the reference implementation.
#
# The brief is explicit about how to read a disagreement here: if the two
# diverge, this package's reimplementation is the suspect, and the cause has to
# be found before the difference is explained away.
#
# The tolerance is 1e-4 and is not arbitrary. fireexposuR::fire_exp() ends with
# terra::round(4), so its output is quantised to four decimals; anything below
# 1e-4 is that rounding and nothing else. A test that passed at 1e-2 would be
# checking almost nothing, since exposure values live in 0-1.
#
# fireexposuR is in Suggests and used only here.

tol <- 1e-4

expect_matches_fireexposuR <- function(fuel, radius, ...) {
  ours <- terra::values(fev_data(fev_exposure(fuel, radius = radius,
                                              quiet = TRUE, ...)))
  theirs <- terra::values(fireexposuR::fire_exp(fuel, t_dist = radius))
  # NA pattern must match too: an implementation that filled the edges would
  # agree everywhere it computed anything and still be wrong.
  testthat::expect_equal(is.na(ours), is.na(theirs))
  testthat::expect_lt(max(abs(ours - theirs), na.rm = TRUE), tol)
  invisible(max(abs(ours - theirs), na.rm = TRUE))
}

test_that("exposure matches fireexposuR on a solid patch", {
  skip_if_not_installed("fireexposuR")
  fuel <- synth_exposure_landscape()
  expect_matches_fireexposuR(fuel, radius = 100)
})

test_that("exposure matches fireexposuR at every transmission distance", {
  skip_if_not_installed("fireexposuR")
  # 30, 100 and 500 m are the three published distances. The layer is sized so
  # that even the 500 m window fits with room to spare.
  fuel <- synth_exposure_landscape(nrow = 120, ncol = 120, res = 25)
  for (radius in c(100, 250, 500)) {
    expect_matches_fireexposuR(fuel, radius = radius)
  }
})

test_that("exposure matches fireexposuR on a fragmented landscape", {
  skip_if_not_installed("fireexposuR")
  # A solid block is an easy case: the window is either fully inside or fully
  # outside it over most of the map. Scattered fuel exercises the window
  # geometry cell by cell, which is where an off-by-one in the annulus radius
  # would show up.
  set.seed(11)
  fuel <- synth_exposure_landscape()
  terra::values(fuel) <- stats::rbinom(terra::ncell(fuel), 1, 0.35)
  expect_matches_fireexposuR(fuel, radius = 100)
})

test_that("exposure matches fireexposuR on a graded hazard layer", {
  skip_if_not_installed("fireexposuR")
  # fire_exp() accepts any 0-1 layer, so the weighted variant is checkable
  # against it too -- it is the same focal operation over non-binary values.
  set.seed(12)
  fuel <- synth_exposure_landscape()
  terra::values(fuel) <- stats::runif(terra::ncell(fuel))
  expect_matches_fireexposuR(fuel, radius = 100)
})

test_that("the no_burn mask behaves as fireexposuR's does", {
  skip_if_not_installed("fireexposuR")
  fuel <- synth_exposure_landscape()
  no_burn <- terra::rast(fuel)
  terra::values(no_burn) <- NA
  no_burn[5:10, 5:10] <- 1

  ours <- terra::values(fev_data(
    fev_exposure(fuel, radius = 100, no_burn = no_burn, quiet = TRUE)
  ))
  theirs <- terra::values(
    fireexposuR::fire_exp(fuel, t_dist = 100, no_burn = no_burn)
  )
  expect_equal(is.na(ours), is.na(theirs))
  expect_lt(max(abs(ours - theirs), na.rm = TRUE), tol)
})

test_that("the annulus window is the one fireexposuR builds", {
  skip_if_not_installed("MultiscaleDTM")
  # Checked directly rather than only through its consequences: the window is
  # the single place where a reimplementation of this metric can go quietly
  # wrong, and comparing rasters alone would not localise it.
  for (res in c(10, 25, 100)) {
    for (radius in c(100, 300, 500)) {
      ours <- fev_annulus_window(res, radius)
      theirs <- MultiscaleDTM::annulus_window(c(res, radius), "map", res)
      attributes(theirs) <- list(dim = dim(theirs))
      expect_equal(ours, theirs,
                   info = paste("res", res, "radius", radius))
    }
  }
})

test_that("the resolution constraint is the same as fireexposuR's", {
  skip_if_not_installed("fireexposuR")
  # Both refuse res > t_dist / 3. Checked so the two stay in step: relaxing it
  # here would make the cross-check pass on grids fireexposuR will not accept.
  fuel <- synth_exposure_landscape(nrow = 60, ncol = 60, res = 25)
  expect_error(fev_exposure(fuel, radius = 60, quiet = TRUE),
               class = "fev_res_too_coarse")
  expect_error(fireexposuR::fire_exp(fuel, t_dist = 60))
  expect_no_error(fev_exposure(fuel, radius = 75, quiet = TRUE))
})
