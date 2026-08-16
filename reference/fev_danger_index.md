# Composite fire danger

Combines meteorological fire danger with fuel availability into one
normalised index in `[0, 1]`. Weather that cannot reach fuel is not
danger, and fuel with no weather to dry it is not either.

## Usage

``` r
fev_danger_index(
  danger,
  fuel_availability,
  method = c("product", "min", "mean", "geometric"),
  normalise = c("auto", "percentile", "minmax", "none"),
  weights = c(0.5, 0.5)
)
```

## Arguments

- danger:

  Meteorological fire danger: a `fev_danger_layer` from
  [`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md),
  a `SpatRaster`, or a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md).

- fuel_availability:

  Fuel availability in `[0, 1]`: a `fev_fuel_layer` from
  [`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md),
  or a `SpatRaster`.

- method:

  `"product"`, `"min"`, `"mean"` or `"geometric"`.

- normalise:

  How to bring `danger` into `[0, 1]`: `"auto"` (percentile ranks only),
  `"percentile"`, `"minmax"`, or `"none"` when it is already scaled.

- weights:

  Two weights for `method = "mean"`, danger then fuel. Must sum to 1.

## Value

A `fev_danger_layer` holding a `SpatRaster` named `danger` with values
in `[0, 1]`.

## Both inputs must already share a grid

This function does not resample. Fire danger from ERA5 is kilometric and
fuel is decametric; bringing them together is a deliberate, recorded
operation that belongs to
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md).
Passing mismatched grids here is an error, not a convenience to smooth
over.

[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
lands in phase 7. Until then, align the layers yourself and say so in
your methods — that is the same requirement, just manual.

## Normalising the danger side

`method` combines two numbers in `[0, 1]`, so danger has to get there
first. A
[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
result is already a percentile rank and is divided by 100. Anything else
needs `normalise` stated explicitly: the function will not guess whether
a layer of values between 0 and 60 is raw FWI, a percentile, or
something else entirely.

## Choosing a method

`"product"` is the default because fire needs both: either factor at
zero gives zero, which is the behaviour a fuel break or a wet week
should have. It is also the most severe — the product of two numbers
below 1 is below both — so a landscape of moderate danger over moderate
fuel scores low.

`"min"` is the limiting-factor reading: danger is whatever is scarcest.
`"mean"` lets one factor compensate for the other, which is the
EFFIS-style additive logic and is the least defensible physically,
though it is what composite indices usually do. `"geometric"` sits
between product and mean.

None of these is validated against burnt-area data here. That is
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md),
in phase 7.

## See also

[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md),
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md).

## Examples

``` r
g <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
d <- terra::setValues(g, seq(0, 100, length.out = 16))
a <- terra::setValues(g, rep(c(0, 0.5, 0.95, 1), 4))
idx <- fev_danger_index(d, a, normalise = "percentile")
terra::global(fev_data(idx), "range", na.rm = TRUE)
#>        min max
#> danger   0   1
```
