# Combine vulnerability dimensions

Aggregates several normalised layers — human, economic, ecological —
into one, by weighted mean.

## Usage

``` r
fev_vuln_stack(..., weights = NULL, method = c("weighted_mean", "max"))
```

## Arguments

- ...:

  Named layers: `fev_vuln_layer` objects, `fev_layer`, or `SpatRaster`
  with values in `[0, 1]`.

- weights:

  Numeric vector, one per layer, summing to 1. `NULL` gives equal
  weights and says so.

- method:

  `"weighted_mean"` (default) or `"max"`, which takes the worst
  dimension rather than trading them off.

## Value

A `fev_vuln_layer` named `vulnerability`.

## On the weights

They are the analysis's value judgement, not a property of the data:
setting human vulnerability to 0.6 and ecological to 0.4 is a statement
about what matters, and there is no data-driven answer to it. The
package has no default beyond equal weights, refuses weights that do not
sum to 1, and writes them into the provenance so that a reader of the
result can see the judgement that produced it.

## Grids must already match

As everywhere else outside
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md),
mismatched grids are an error.

## See also

[`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md),
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md).

## Examples

``` r
g <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
human <- terra::setValues(g, seq(0, 1, length.out = 16))
eco <- terra::setValues(g, rev(seq(0, 1, length.out = 16)))
v <- fev_vuln_stack(human = human, eco = eco, weights = c(0.6, 0.4))
terra::global(fev_data(v), "mean", na.rm = TRUE)
#>               mean
#> vulnerability  0.5
```
