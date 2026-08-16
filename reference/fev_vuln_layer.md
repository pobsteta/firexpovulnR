# Normalise a layer of assets to a 0-1 vulnerability

Rescales a raster of exposed assets — people, buildings, protected
habitat — onto `[0, 1]`, so that layers measured in different units can
be combined.

## Usage

``` r
fev_vuln_layer(
  x,
  method = c("minmax", "percentile_rank", "log"),
  invert = FALSE,
  clamp = NULL,
  name = "vulnerability"
)
```

## Arguments

- x:

  A `SpatRaster`, a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  or a `fev_layer`.

- method:

  `"minmax"`, `"percentile_rank"` or `"log"`.

- invert:

  Reverse the scale, for a layer where a high value means low
  vulnerability — distance to a fire station, say.

- clamp:

  Optional `c(low, high)` bounds applied before normalising, to stop a
  single outlier setting the whole scale.

- name:

  Layer name for the result.

## Value

A `fev_vuln_layer` holding a `SpatRaster` with values in `[0, 1]`.

## Choosing a method, which is not a detail

`"minmax"` is a linear rescale between the layer's own minimum and
maximum. It preserves the shape of the distribution, and it is
**extent-dependent**: the same village scores differently depending on
whether the biggest city in the AOI is inside the frame. Fine for a
single study area, wrong for comparing two.

`"percentile_rank"` replaces each value by its rank among all cells. It
destroys the shape of the distribution and that is usually the point:
with population density, a handful of city cells otherwise compress
everything else into the bottom percent of a minmax scale. It is also
extent-dependent.

`"log"` applies [`log1p()`](https://rdrr.io/r/base/Log.html) and then
rescales, which keeps the ordering while compressing a long right tail.
It needs non-negative values, and it treats a difference between 10 and
100 people as equal to one between 100 and 1000 — a substantive claim
about how vulnerability grows with exposure, not a display choice.

None of the three is neutral. Whichever you use ends up in the
provenance.

## See also

[`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md)
to combine several.

## Examples

``` r
pop <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 250,
                   ymin = 0, ymax = 250, crs = "EPSG:2154")
terra::values(pop) <- c(rep(1, 99), 10000)   # one dense cell
terra::global(fev_data(fev_vuln_layer(pop, "minmax")), "mean", na.rm = TRUE)
#> Warning: "minmax" normalisation rescales on this extent's own range.
#> ℹ Observed range 1 and 10000. The same cell scores differently under a
#>   different AOI, so vulnerability layers are not comparable between study
#>   areas.
#> ℹ Shown once per session; recorded in the provenance every time.
#>               mean
#> vulnerability 0.01
terra::global(fev_data(fev_vuln_layer(pop, "log")), "mean", na.rm = TRUE)
#>               mean
#> vulnerability 0.01
```
