# Directional vulnerability from a point

Draws transects outward from a value in every direction and reports
which bearings offer a continuous high-exposure pathway to it. The
answer to "where would a fire come from" rather than "how much fuel is
around".

## Usage

``` r
fev_directional(
  exposure,
  point,
  seg_lengths = c(5000, 5000, 5000),
  interval = 1,
  n_wedges = NULL,
  max_dist = NULL,
  thresh_exp = 0.6,
  thresh_viable = 0.8,
  step = NULL
)
```

## Source

Beverly, J.L., Forbes, A.M. (2023). Assessing directional vulnerability
to wildfire. *Natural Hazards* 117: 831-849. Parameters verified against
the `fireexposuR` 1.2.0 reference documentation on 2026-08-16.

## Arguments

- exposure:

  A `fev_exposure_layer` from
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
  or a `SpatRaster` of exposure values in `[0, 1]`.

- point:

  The value at risk: an `sf`, `sfc`, `SpatVector` of one point, or a
  length-2 numeric `c(x, y)` in the exposure layer's CRS.

- seg_lengths:

  Segment lengths outward from the point, in CRS units.

- interval:

  Degrees between transects.

- n_wedges:

  Alternative to `interval`: number of evenly spaced directions, so
  `interval = 360 / n_wedges`.

- max_dist:

  Total transect length. When given, overrides `seg_lengths` by
  splitting it into three equal segments.

- thresh_exp:

  Exposure at or above which ground counts as hazardous.

- thresh_viable:

  Share of a segment that must be hazardous for it to be viable.

- step:

  Sampling interval along a transect. Defaults to the cell size.

## Value

An object of class `fev_directional`: a list with `table` (one row per
bearing, one logical column per segment plus `viable` for all segments),
the parameters used, and a provenance record.

## Method

Follows Beverly and Forbes (2023). From the value, a transect is drawn
at every `interval` degrees. Each transect is cut into consecutive
segments — by default three of 5 km — and a segment counts as **viable**
when at least `thresh_viable` of the ground it crosses has exposure of
at least `thresh_exp`. A direction with all three segments viable is a
continuous corridor of hazardous fuel reaching the value from that
bearing.

Bearings are compass bearings: 0 and 360 are north, increasing
clockwise.

## The two thresholds are measured, not conventional

`thresh_exp = 0.6` because observed fires burned preferentially where
exposure exceeded 60%; `thresh_viable = 0.8` because observed burned
pathways intersected pre-fire high-exposure patches by 80% on average.
Both from Canadian landscapes — see
[`fev_directional_defaults()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional_defaults.md).

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
[`fev_directional_defaults()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional_defaults.md).

## Examples

``` r
r <- terra::rast(nrows = 60, ncols = 60, xmin = 0, xmax = 6000,
                 ymin = 0, ymax = 6000, crs = "EPSG:2154")
terra::values(r) <- 0
r[1:30, ] <- 0.9          # a high-exposure block to the north
d <- fev_directional(r, point = c(3000, 3000), seg_lengths = c(500, 500, 500),
                     interval = 45)
d$table
#>   bearing  seg1 frac1  seg2 frac2  seg3 frac3 viable
#> 1      45  TRUE     1  TRUE     1  TRUE     1   TRUE
#> 2      90 FALSE     0 FALSE     0 FALSE     0  FALSE
#> 3     135 FALSE     0 FALSE     0 FALSE     0  FALSE
#> 4     180 FALSE     0 FALSE     0 FALSE     0  FALSE
#> 5     225 FALSE     0 FALSE     0 FALSE     0  FALSE
#> 6     270 FALSE     0 FALSE     0 FALSE     0  FALSE
#> 7     315  TRUE     1  TRUE     1  TRUE     1   TRUE
#> 8     360  TRUE     1  TRUE     1  TRUE     1   TRUE
```
