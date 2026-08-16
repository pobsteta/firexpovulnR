# Danger thresholds derived from a climatology

Reimplements caliver's `get_fire_danger_levels()`: the five interior FWI
breaks separating six danger classes, derived from the record itself
rather than imported.

## Usage

``` r
fev_fwi_thresholds(x, ndays = 4, season = c("04-01", "10-31"), time = NULL)
```

## Source

caliver, `R/get_fire_danger_levels.R`, ecmwf/caliver on GitHub, read
2026-08-16. Method published as Vitolo, C., Di Giuseppe, F., D'Andrea,
M. (2018), *Caliver: An R package for CALIbration and VERification of
forest fire gridded model outputs*, PLoS ONE 13(1): e0189419.
[doi:10.1371/journal.pone.0189419](https://doi.org/10.1371/journal.pone.0189419)
. Applied there to ERA-Interim 1980–2016 over the April–October season,
the published European result is `2, 5, 10, 19, 33`.

## Arguments

- x:

  A `SpatRaster` of daily fire danger, or a numeric vector with a
  `years` attribute, or a `fev_source`.

- ndays:

  Days per year on which a fire is expected. caliver's default is 4,
  which yields the 98th percentile.

- season:

  Fire season, as in
  [`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md).

- time:

  Dates of the layers, when `x` does not carry them.

## Value

A numeric vector of five breaks, with the derived extreme value in its
`extreme` attribute. Feed it to
[`fev_fwi_classes()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_classes.md).

## The algorithm, and where its constants come from

For each year, the `(1 - ndays/365)` quantile of the fire index is taken
— with the default `ndays = 4` that is the 98th percentile, read as "the
level exceeded on the four days a year a fire is expected". The **median
across years** of those yearly extremes is the extreme danger value. It
is then inverted through the Canadian system's intensity relation to a
fire intensity, and the six classes fall out of a geometric progression
of that intensity.

The numeric constants (`0.289`, `0.980`, `1.546`, `1.013`, `0.647`) are
caliver's, read from its source. They belong to the Canadian
FWI-intensity relationships. This package has **not** verified them
against Van Wagner's original report — it reproduces a published
implementation, and says so.

## What it is not

This is not
[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md).
That one asks "how unusual is today here"; this one asks "where should
the class boundaries sit for this record". caliver's own documentation
insists on the distinction, and mixing them produces a map that is
neither.

## Examples

``` r
r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 50,
                 ymin = 0, ymax = 50, crs = "EPSG:2154", nlyr = 40)
set.seed(1)
terra::values(r) <- runif(160, 0, 60)
terra::time(r) <- seq(as.Date("2019-06-01"), by = "day", length.out = 40)
fev_fwi_thresholds(r, season = NULL)
#> [1]  2  7 16 31 59
#> attr(,"extreme")
#> [1] 59.00933
#> attr(,"n_years")
#> [1] 1
#> attr(,"percentile")
#> [1] 0.98
```
