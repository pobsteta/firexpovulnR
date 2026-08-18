# The one gate for every test that touches the network.
#
# The brief forbids a routine `R CMD check` from depending on it, and the reason
# is on record: these tests once ran in CI and stayed green only for as long as
# IGN and EFFIS did. The first DNS timeout at data.geopf.fr turned the check
# red.
#
# Opt-in is an explicit truthy value, not merely a non-empty one -- the pkgdown
# workflow sets FIREXPOVULNR_TEST_NETWORK: "0" to mean off, and nzchar("0") is
# TRUE. Lives in a helper rather than in one test file so that a new network
# test cannot quietly invent its own weaker gate, which is exactly what the
# WorldCover fetch test did on its first pass.
skip_unless_network <- function() {
  if (!tolower(Sys.getenv("FIREXPOVULNR_TEST_NETWORK")) %in%
        c("1", "true", "yes")) {
    testthat::skip("network tests disabled (set FIREXPOVULNR_TEST_NETWORK=1)")
  }
  testthat::skip_if_offline()
}
