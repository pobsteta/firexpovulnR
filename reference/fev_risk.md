# Composite fire risk

Crosses composite danger with vulnerability, and optionally with further
dimensions, into one risk layer.

## Usage

``` r
fev_risk(
  danger,
  vulnerability,
  ...,
  method = c("effis_mean", "pareto", "weighted"),
  weights = NULL,
  normalise = c("minmax", "none"),
  depth = 1,
  digits = 3,
  max_unique = 50000
)
```

## Source

CLIMAAX Climate Risk Assessment Handbook, FWI wildfire workflow, read
2026-08-16:
<https://handbook.climaax.eu/notebooks/workflows/FIRE/02_wildfire_FWI/FWI_Risk_Assessment.html>.
The min-max-then-average step and the
`paretoset(..., sense = [max, ...])` call were read from the notebook's
own code, not from its prose.

## Arguments

- danger:

  Composite danger: a `fev_layer` from
  [`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md),
  or a `SpatRaster`.

- vulnerability:

  Vulnerability: a `fev_layer` from
  [`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md),
  or a `SpatRaster`.

- ...:

  Further named dimensions to enter the combination, as CLIMAAX does
  with its wildland-urban interface, protected area, ecological
  irreplaceability and restoration cost indicators.

- method:

  `"effis_mean"`, `"pareto"` or `"weighted"`.

- weights:

  Required for `"weighted"`: one per dimension, summing to 1.

- normalise:

  `"minmax"` (default, as CLIMAAX) or `"none"`.

- depth:

  For `"pareto"`: how many successive fronts to peel. `1` gives the
  CLIMAAX boolean front; a larger number gives a graded layer where the
  first front scores 1 and deeper fronts score less; `Inf` peels until
  nothing is left.

- digits:

  For `"pareto"`: values are rounded to this many decimals before
  dominance is computed. A front computed on floating-point noise in the
  fifteenth decimal is not a front, and rounding is what keeps the
  problem tractable.

- max_unique:

  For `"pareto"`: refuse rather than run for hours when the rounded
  values yield more distinct combinations than this.

## Value

A `fev_risk_layer` holding a `SpatRaster` named `risk`.

## The three methods answer different questions

`"effis_mean"` normalises every component with min-max and takes their
unweighted arithmetic mean. This is the CLIMAAX danger-index step
applied to risk: simple, continuous, and it lets a very high score on
one dimension be bought back by a low score on another. That
compensation is the whole objection to it.

`"pareto"` is what the CLIMAAX wildfire workflow actually does for risk.
It returns the **Pareto front**: the cells that cannot be improved on
one dimension without being worse on another, treating every dimension
as equally important with no weights at all. Note what this gives you —
a **set**, not a score. A cell is on the front or it is not, and the
front says nothing about how far from it the others are. Use `depth` to
peel successive fronts and get a graded layer instead.

`"weighted"` is a weighted mean. It requires `weights` and writes them
into the record, because they are the analysis's judgement and nothing
in the data supplies them.

## Normalisation restretches layers that were already scaled

`normalise = "minmax"` is the default because it is what CLIMAAX does.
It rescales each component on its own observed range, so a
[`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md)
layer that legitimately spans 0.3 to 0.6 comes out spanning 0 to 1, and
its lowest cell becomes a zero. When your components are already on a
meaningful common scale — which is what the rest of this package
produces — pass `normalise = "none"`.

Min-max also makes the result depend on the extent processed: the same
cell scores differently under a different AOI.

## Grids must already match

As everywhere outside
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md),
mismatched grids are an error.

## See also

[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
to test the result against burnt areas,
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
to put the inputs on one grid.

## Examples

``` r
g <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 150,
                 ymin = 0, ymax = 150, crs = "EPSG:2154")
danger <- terra::setValues(g, seq(0, 1, length.out = 36))
vuln <- terra::setValues(g, rev(seq(0, 1, length.out = 36)))

mean_risk <- fev_risk(danger, vuln, normalise = "none")
terra::global(fev_data(mean_risk), "mean", na.rm = TRUE)
#>      mean
#> risk  0.5

front <- fev_risk(danger, vuln, method = "pareto", normalise = "none")
terra::global(fev_data(front), "sum", na.rm = TRUE)
#>      sum
#> risk  36
```
