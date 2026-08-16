# Percentile rank against a reference climatology

Replaces each fire danger value by its rank within a local reference
distribution, expressed as a percentile from 0 to 100. A value of 95
means the day is worse than 95% of the reference period at that place.

## Usage

``` r
fev_fwi_percentile(
  x,
  ref_period = NULL,
  by = c("pixel", "region"),
  regions = NULL,
  season = c("04-01", "10-31"),
  time = NULL,
  min_ref = 365
)
```

## Source

Method reimplemented rather than depended on: caliver (Vitolo, Di
Giuseppe, D'Andrea) was archived from CRAN in October 2021.
Reference-period length guidance: WMO, *Guidelines on the Calculation of
Climate Normals*, WMO-No. 1203, 2017 edition; the standard normal is 30
years, redefined in 2015 as the most recent 30-year period ending in a
year ending in 0. Fire season default: 1 April – 31 October in the
northern hemisphere, as used by Vitolo et al. (2018), *PLoS ONE* 13(1):
e0189419.

## Arguments

- x:

  A `SpatRaster` of daily fire danger, one layer per day, or a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  holding one. Layers must carry dates: without them there is no way to
  subset a reference period, and a climatology built on an unknown
  period is not a climatology.

- ref_period:

  Two-element vector bounding the reference: years (`c(1991, 2020)`) or
  dates. `NULL` uses every layer, and says so.

- by:

  `"pixel"` or `"region"`. See the section above.

- regions:

  Required for `by = "region"`: an `sf`, `SpatVector` or categorical
  `SpatRaster` of zones.

- season:

  Two `"MM-DD"` strings restricting the reference to a fire season, or
  `NULL` for the whole year. Defaults to 1 April – 31 October, the
  northern-hemisphere season caliver uses. Off-season days in a
  reference distribution drag every percentile up, because most of them
  are near zero.

- time:

  Dates of the layers, when `x` does not carry them.

- min_ref:

  Warn when a reference distribution has fewer than this many values.
  Defaults to 365 — one year of daily data.

## Value

A `fev_danger_layer` holding a `SpatRaster` of percentile ranks in
`[0, 100]`, one layer per input layer.

## Why this exists

Absolute FWI thresholds are calibrated somewhere. Applied elsewhere they
mostly reproduce the climatology: a map of raw FWI over France in August
is close to a map of summer dryness, and classifying it on Canadian or
even European-mean breaks puts the whole Mediterranean in the top class
every year, which discriminates nothing. Percentile ranks are
dimensionless and local, so a 98th percentile day means the same thing
in the Var and in Brittany — an unusually dangerous day *there*.

The cost is that they say nothing about absolute severity. A 98th
percentile day in Brittany may be an FWI a Var fire brigade would
ignore. Report both, or say which one you are mapping.

## Pixel or region

`by = "pixel"` ranks each cell against its own history. It is the
sharper choice and needs no extra input, but at the ~25 km grid of the
ERA5-driven CEMS product a single cell mixes coast and ridge.

`by = "region"` pools the reference values of every cell in a region and
ranks all of them against that one distribution, which is what caliver
does for administrative units. It needs `regions`, and it makes the
result depend on a zoning choice that should be reported.

## Length of the reference period

The WMO climatological standard normal is a **30-year** period ending in
a year ending in 0 — 1991–2020 at present (WMO-No. 1203, 2017 edition).
This function warns below 10 years and informs below 30. Nothing stops
you using less; the record just says how much less.

## See also

[`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
for caliver's threshold derivation, which answers a different question,
and
[`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md)
to combine the result with fuel.

## Examples

``` r
# Three years of daily values on a tiny grid.
r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 50,
                 ymin = 0, ymax = 50, crs = "EPSG:2154", nlyr = 30)
terra::values(r) <- matrix(seq_len(120), nrow = 4)
terra::time(r) <- seq(as.Date("2020-06-01"), by = "day", length.out = 30)
p <- fev_fwi_percentile(r, season = NULL, min_ref = 10)
#> No `ref_period` given: every layer is used as its own reference.
#> ℹ Each value is then ranked against the record it belongs to, which is
#>   defensible only when that record is the climatology you mean.
#> Warning: The reference period spans 1 year.
#> ℹ The WMO climatological standard normal is 30 years (WMO-No. 1203). Below ten,
#>   a single hot summer moves every percentile in the map.
#> ℹ It is recorded in the provenance either way.
terra::global(fev_data(p), "max", na.rm = TRUE)
#>               max
#> lyr.1    3.333333
#> lyr.2    6.666667
#> lyr.3   10.000000
#> lyr.4   13.333333
#> lyr.5   16.666667
#> lyr.6   20.000000
#> lyr.7   23.333333
#> lyr.8   26.666667
#> lyr.9   30.000000
#> lyr.10  33.333333
#> lyr.11  36.666667
#> lyr.12  40.000000
#> lyr.13  43.333333
#> lyr.14  46.666667
#> lyr.15  50.000000
#> lyr.16  53.333333
#> lyr.17  56.666667
#> lyr.18  60.000000
#> lyr.19  63.333333
#> lyr.20  66.666667
#> lyr.21  70.000000
#> lyr.22  73.333333
#> lyr.23  76.666667
#> lyr.24  80.000000
#> lyr.25  83.333333
#> lyr.26  86.666667
#> lyr.27  90.000000
#> lyr.28  93.333333
#> lyr.29  96.666667
#> lyr.30 100.000000
```
