# The correspondence tables are the module's factual base: if a code is wrong
# or a fuel type is misspelt, every downstream layer is wrong in a way that
# looks perfectly plausible. These tests pin the counts and the vocabulary.

test_that("the shipped tables have the class counts their producers publish", {
  # 32 posts for BD Forêt v2 (cartes.gouv.fr), 44 level-3 classes for CORINE
  # (CLC nomenclature guidelines). A mismatch means the table was edited
  # without going back to data-raw/build_fuel_lookups.R.
  expect_equal(nrow(fev_fuel_lookup("bdforet_v2")), 32L)
  expect_equal(nrow(fev_fuel_lookup("clc")), 44L)
})

test_that("every CORINE vintage resolves to the same table", {
  base <- fev_fuel_lookup("clc")
  for (y in c(1990, 2000, 2006, 2012, 2018)) {
    expect_equal(fev_fuel_lookup(paste0("clc_", y)), base)
  }
})

test_that("lookups only use the closed fuel-type vocabulary", {
  known <- fev_fuel_types()$fuel_type
  expect_true(all(fev_fuel_lookup("bdforet_v2")$fuel_type %in% known))
  expect_true(all(fev_fuel_lookup("clc")$fuel_type %in% known))
})

test_that("codes are unique and every row is justified", {
  for (type in c("bdforet_v2", "clc")) {
    tab <- fev_fuel_lookup(type)
    expect_equal(anyDuplicated(tab$code), 0L)
    expect_true(all(nzchar(tab$notes)))
    expect_true(all(tab$confidence %in% c("clear", "ambiguous")))
    expect_type(tab$burnable, "logical")
    expect_false(anyNA(tab$burnable))
  }
})

test_that("the classes the brief names are present and burnable", {
  # The brief singles these out as what CORINE must contribute: sclerophyllous
  # vegetation, moors, natural grassland. If one of them ever flips to
  # non-burnable the auxiliary source stops doing its job.
  clc <- fev_fuel_lookup("clc")
  for (code in c("321", "322", "323")) {
    expect_true(clc$burnable[clc$code == code], label = code)
  }
  # And the non-burnable ones it must also contribute.
  for (code in c("111", "332", "512")) {
    expect_false(clc$burnable[clc$code == code], label = code)
  }
})

test_that("holm oak is not folded into generic broadleaf", {
  # The single distinction BD Forêt buys over CORINE in the Mediterranean.
  bdf <- fev_fuel_lookup("bdforet_v2")
  expect_equal(bdf$fuel_type[bdf$code == "FF1G06-06"], "sclerophyll_closed")
  expect_equal(bdf$fuel_type[bdf$code == "FF1G01-01"], "broadleaf_closed")
})

test_that("weights and the burnable mask cannot contradict each other", {
  # A class the mask calls non-burnable must weigh exactly zero, or
  # fev_fuel_binary() and fev_fuel_availability() disagree about the same
  # pixel with no error anywhere.
  w <- fev_fuel_weights(quiet = TRUE)
  for (type in c("bdforet_v2", "clc")) {
    tab <- fev_fuel_lookup(type)
    expect_equal(
      unname(w[tab$fuel_type] > 0),
      tab$burnable,
      info = type
    )
  }
})

test_that("every fuel type in the vocabulary has a weight", {
  w <- fev_fuel_weights(quiet = TRUE)
  expect_setequal(names(w), fev_fuel_types()$fuel_type)
})

test_that("fev_fuel_weights() says its numbers are conventional", {
  expect_warning(fev_fuel_weights(), class = "fev_unsourced_default")
  expect_silent(fev_fuel_weights(quiet = TRUE))
})

test_that("weight overrides are validated", {
  expect_error(fev_fuel_weights(c(nonsense = 0.5), quiet = TRUE),
               class = "fev_error")
  expect_error(fev_fuel_weights(c(shrubland = 1.5), quiet = TRUE),
               class = "fev_error")
  expect_error(fev_fuel_weights(0.5, quiet = TRUE), class = "fev_error")
  w <- fev_fuel_weights(c(broadleaf_closed = 0.4), quiet = TRUE)
  expect_equal(unname(w[["broadleaf_closed"]]), 0.4)
  expect_equal(unname(w[["shrubland"]]), 1)
})

test_that("a user table replaces the shipped one", {
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(code = c("FF2-57-57", "LA4"),
               fuel_type = c("conifer_closed", "shrubland"),
               burnable = c("yes", "no")),
    f, row.names = FALSE
  )
  tab <- fev_fuel_lookup(file = f)
  expect_equal(nrow(tab), 2L)
  expect_equal(tab$burnable, c(TRUE, FALSE))
  # Absent optional columns are filled, not dropped.
  expect_true(all(c("label", "notes", "confidence") %in% names(tab)))
  expect_true(all(is.na(tab$notes)))
})

test_that("a malformed user table is refused with a reason", {
  f <- withr::local_tempfile(fileext = ".csv")

  utils::write.csv(data.frame(code = "A", fuel_type = "shrubland"), f,
                   row.names = FALSE)
  expect_error(fev_fuel_lookup(file = f), class = "fev_bad_lookup")

  utils::write.csv(
    data.frame(code = "A", fuel_type = "not_a_type", burnable = TRUE), f,
    row.names = FALSE
  )
  expect_error(fev_fuel_lookup(file = f), class = "fev_bad_lookup")

  utils::write.csv(
    data.frame(code = c("A", "A"), fuel_type = "shrubland", burnable = TRUE), f,
    row.names = FALSE
  )
  expect_error(fev_fuel_lookup(file = f), class = "fev_bad_lookup")

  utils::write.csv(
    data.frame(code = "A", fuel_type = "shrubland", burnable = "maybe"), f,
    row.names = FALSE
  )
  expect_error(fev_fuel_lookup(file = f), class = "fev_bad_lookup")

  expect_error(fev_fuel_lookup(file = "no-such-file.csv"), class = "fev_error")
})
