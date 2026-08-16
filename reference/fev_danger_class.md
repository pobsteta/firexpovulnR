# Classify fire danger into named classes

Cuts a Fire Weather Index layer into danger classes, and records which
scheme's breaks were used.

## Usage

``` r
fev_danger_class(
  x,
  scheme = c("effis", "caliver_europe", "custom"),
  breaks = NULL,
  labels = NULL
)
```

## Arguments

- x:

  A `SpatRaster` of Fire Weather Index values, a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  or a `fev_layer`.

- scheme:

  `"effis"` (default), `"caliver_europe"`, or `"custom"` when `breaks`
  is supplied.

- breaks:

  Five interior class boundaries, overriding `scheme`.
  [`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
  returns a set derived from your own record.

- labels:

  Class labels, one more than `breaks`.

## Value

A `fev_danger_layer` holding a categorical `SpatRaster` named
`danger_class`.

## Why this is not just [`terra::classify()`](https://rspatial.github.io/terra/reference/classify.html)

The two published schemes disagree substantially — an FWI of 40 is *Very
High* under the EFFIS operational breaks and *Extreme* under the caliver
breaks derived from ERA-Interim. A classified map is a different map
under each, and nothing in a GeoTIFF says which one was applied. Here
the scheme, its breaks and its source go into the provenance record with
the result, so the question is answerable six months later.

## Classifying percentile ranks instead

If your layer is a
[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
result, absolute FWI breaks are meaningless for it and this function
refuses. Percentile ranks are already calibrated; cut them on percentile
breaks of your own choosing, and say what they are.

## See also

[`fev_fwi_classes()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_classes.md)
for the schemes and how they differ,
[`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
to derive breaks from a record.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- seq(0, 75, length.out = 16)
terra::freq(fev_data(fev_danger_class(r)))
#>   layer        value count
#> 1     1          Low     3
#> 2     1     Moderate     2
#> 3     1         High     3
#> 4     1    Very High     2
#> 5     1      Extreme     4
#> 6     1 Very Extreme     2
terra::freq(fev_data(fev_danger_class(r, "caliver_europe")))
#>   layer     value count
#> 1     1  Very Low     1
#> 2     1  Moderate     1
#> 3     1      High     2
#> 4     1 Very High     3
#> 5     1   Extreme     9
```
