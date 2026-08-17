# Build the real fire-weather tables shipped with the two articles.
#
# Run with:  Rscript data-raw/build_weather_extracts.R
# Needs network, moves about 100 MB, takes a few minutes.
#
# ---------------------------------------------------------------------------
# Why this replaces an invented series
# ---------------------------------------------------------------------------
#
# Both articles used to fabricate their weather with rnorm(), because the CEMS
# historical product needs a personal Copernicus token the package refuses to
# handle. A package whose first requirement is traceability should not ship two
# worked examples resting on invented numbers, and the invented series could not
# say anything about the fires the articles are built around.
#
# fev_fetch_weather() reads the Open-Meteo archive, which re-serves ERA5 and
# ERA5-Land with no authentication at all. So the weather in both articles is now
# real, and the danger maps can be checked against the fires that actually
# happened.
#
# ---------------------------------------------------------------------------
# Three years, not thirty
# ---------------------------------------------------------------------------
#
# fev_fwi_percentile() wants a reference climatology, and the WMO normal is 30
# years. Thirty years at these grids is roughly 100 000 rows per site -- several
# megabytes in inst/extdata for a documentation example, which is not a
# reasonable thing to put in a package.
#
# So three years are shipped: the fire year and the two before it. That is a
# short reference and the articles say so, with the one call that widens it. What
# is NOT done is skipping the winter months to save space: the moisture codes are
# cumulative, and a table with June following the previous September would carry
# a drought code that never happened.
#
# Fetched 2026-08-17. One row per grid point and day, at 12:00 UTC.

library(sf)
library(firexpovulnR)

stopifnot("run from the package root" = file.exists("DESCRIPTION"))

sites <- list(
  # Couchey: the fire burnt the commune on 2026-07-29.
  couchey = list(gpkg = "couchey.gpkg", period = c("2024-01-01", "2026-12-31")),
  # The Maures: the Cannet-des-Maures fire ran on 2021-08-16.
  maures  = list(gpkg = "maures.gpkg", period = c("2019-01-01", "2021-12-31"))
)

for (nm in names(sites)) {
  s <- sites[[nm]]
  gpkg <- file.path("inst", "extdata", s$gpkg)
  stopifnot("build the site extract first" = file.exists(gpkg))
  study <- st_read(gpkg, "study_area", quiet = TRUE)

  w <- fev_fetch_weather(study, period = s$period)
  tab <- fev_data(w)

  # The served cell and its elevation travel with the table: several requested
  # points can share one reanalysis cell and still differ, because Open-Meteo
  # adjusts temperature to the requested location's elevation. The articles show
  # this, so the diagnostic has to be shipped, not just the series.
  grid <- w$source$points
  out <- file.path("inst", "extdata", paste0(nm, "_weather.csv.gz"))
  con <- gzfile(out, "w")
  write.csv(merge(tab, grid[, c("id", "cell_lat", "cell_long", "elev_m")],
                  by = "id", all.x = TRUE),
            con, row.names = FALSE)
  close(con)

  message(sprintf(
    "%-8s %d points, %d point-days, %s to %s -- %.0f KB",
    nm, nrow(grid), nrow(tab), min(as.Date(sprintf("%d-%02d-%02d", tab$yr,
                                                   tab$mon, tab$day))),
    max(as.Date(sprintf("%d-%02d-%02d", tab$yr, tab$mon, tab$day))),
    file.size(out) / 1024
  ))

  # A quick look at the day each article is built around, so a rebuild that
  # silently returns different numbers is visible in the log rather than only in
  # the rendered figures.
  day <- if (nm == "couchey") c(2026L, 7L, 29L) else c(2021L, 8L, 16L)
  hit <- tab[tab$yr == day[1] & tab$mon == day[2] & tab$day == day[3], ]
  message(sprintf("  %d-%02d-%02d: %.1f to %.1f C, RH %.0f to %.0f %%, wind %.1f to %.1f km/h",
                  day[1], day[2], day[3],
                  min(hit$temp), max(hit$temp), min(hit$rh), max(hit$rh),
                  min(hit$ws), max(hit$ws)))
}
