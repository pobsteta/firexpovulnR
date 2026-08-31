# Terrain curvature on the MicroMet scale

Convex ground — ridges, spurs — accelerates wind; concave ground
shelters it. This computes the curvature that
[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md)
turns into a wind multiplier, on the scale Liston and Elder define:
divided by twice its own maximum absolute value, so it lands in
`[-0.5, 0.5]`.

## Usage

``` r
fev_curvature(dem, length_scale = 500, quiet = FALSE)
```

## Source

Liston, G. E. and Elder, K. (2006). A meteorological distribution system
for high-resolution terrestrial modeling (MicroMet). *Journal of
Hydrometeorology* 7(2): 217-234.

Formulation checked on 2026-08-19 against an independent implementation
rather than taken from memory:
`windwt = 1 + slopewt * wind_slope + curvewt * curvature`, with both
terms divided by twice their maximum absolute value and
`slopewt + curvewt = 1` suggested. The publisher's own page is
paywalled.

## Arguments

- dem:

  Elevation: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_dem()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_dem.md),
  a `fev_layer` or a `SpatRaster`.

- length_scale:

  Distance in CRS units over which curvature is measured. Default 500.

- quiet:

  Suppress the report.

## Value

A `fev_layer` of role `"curvature"`, values in `[-0.5, 0.5]`.

## The length scale is the parameter that matters

Curvature has no meaning without a distance over which to measure it.
Liston and Elder use roughly half the dominant topographic wavelength —
the distance from a valley floor to the ridge above it. Too short and
the result is surface roughness; too long and a whole massif reads as
one gentle dome. Several hundred metres suits a Mediterranean massif;
the default is 500 m and it is a choice, not a constant.

## It is scaled against the area processed

Dividing by the observed maximum makes the result **extent-dependent**,
like `"minmax"` in
[`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md):
the same ridge scores differently under a different area of interest.
That is how the published scheme is defined, and the consequence is the
same one — a curvature layer is comparable within one analysis and not
between two.

## See also

[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md),
which consumes it.

## Examples

``` r
g <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 3000,
                 ymin = 0, ymax = 3000, crs = "EPSG:2154")
# A ridge running north-south.
dem <- terra::init(g, "x")
dem <- 300 - abs(dem - 1500) / 5
cv <- fev_curvature(dem, length_scale = 300, quiet = TRUE)
range(terra::values(fev_data(cv)), na.rm = TRUE)
#> [1] 0.0 0.5
```
