# Turn a measured fuel metric into a graded availability

Rescales one continuous metric — crown bulk density, crown fuel load,
whatever
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
produced — onto `[0, 1]` and labels it `"availability"`, which is what
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
consumes to weight each neighbouring cell by how much fuel it actually
holds instead of whether it holds any.

## Usage

``` r
fev_fuel_load_weight(
  x,
  metric = NULL,
  method = c("minmax", "percentile_rank", "log"),
  clamp = NULL,
  fill = NULL,
  quiet = FALSE
)
```

## Arguments

- x:

  A
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  carrying a continuous register, a `fev_layer`, or a `SpatRaster`.

- metric:

  Name of the layer to use, e.g. `"CBD_max"`, `"CFL"`, `"TFL"`. Required
  when the input holds more than one.

- method:

  `"minmax"`, `"percentile_rank"` or `"log"`, as
  [`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md)
  uses, and with the same consequences: the first two are
  extent-dependent, so the same stand scores differently under a
  different area of interest.

- clamp:

  Optional `c(low, high)` in the metric's own units, applied before
  rescaling, so one exceptional cell does not set the whole scale.

- fill:

  Value in `[0, 1]` for unmeasured cells, or `NULL` to leave them `NA`.
  Default `NULL`.

- quiet:

  Suppress the report.

## Value

A `fev_layer` of role `"availability"`, values in `[0, 1]`, ready to
pass to
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
or
[`fev_exposure_aniso()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_aniso.md).

## Why this is a rescale and not a model

There is no physical mapping from crown bulk density to a probability of
contributing to spread, and this function does not invent one. It puts
the metric on the scale the graded path expects, in the way you choose,
and records the choice. The result is an ordering of cells by measured
fuel, not an estimate of anything.

That is why the method matters and why it is recorded: `"minmax"` says a
cell at half the maximum load contributes half, `"percentile_rank"` says
a cell in the median contributes half. Those are different claims and
the data does not choose between them.

## What `NA` means here, and why it is not zero

LiDAR HD has not flown everywhere, and where it has not, the metric is
`NA`. `NA` is **not** "no fuel" — it is "not measured", and the
difference decides whether the resulting exposure map is a measurement
or a fiction.

This function leaves `NA` as `NA`.
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
with its default `na_rm = FALSE` then returns `NA` for any cell whose
neighbourhood is not fully measured, which looks like a hole and is one.
Filling it would take a campaign covering 2 km² of the Maures and
quietly extend its authority over the other 300.

`fill` exists for the case where you have a defensible value for the
unmeasured ground — a class median from
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md),
say — and it writes into the record that you supplied it.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
for the metrics,
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
for the graded path,
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
for the categorical equivalent.

## Examples

``` r
g <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
cbd <- terra::setValues(g, seq(0.02, 0.4, length.out = 100))
names(cbd) <- "CBD_max"
w <- fev_fuel_load_weight(cbd, metric = "CBD_max", quiet = TRUE)
range(terra::values(fev_data(w)), na.rm = TRUE)
#> [1] 0 1
```
