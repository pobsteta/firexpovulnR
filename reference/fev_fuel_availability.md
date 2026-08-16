# Weighted fuel availability

Grades the burnable mask: instead of 1 for every fuel, each pixel takes
a weight in `[0, 1]` for its fuel type, so that Mediterranean shrubland
and a beech stand are not treated as the same hazard.

## Usage

``` r
fev_fuel_availability(x, weights = fev_fuel_weights(), lookup = NULL)
```

## Arguments

- x:

  A `fev_fuel_source`.

- weights:

  Named numeric vector, one weight per fuel type. Defaults to
  [`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md),
  which warns that it is conventional.

- lookup:

  Correspondence table. Defaults to the one carried by `x`.

## Value

A `fev_fuel_layer` holding a `SpatRaster` named `availability` with
values in `[0, 1]`.

## Register consumed

Categorical. The continuous register is the phase 8 path: with
LiDAR-derived load and bulk density per stratum, availability can be
measured rather than assigned per class, and the per-class weights below
become a fallback for areas with no LiDAR coverage.

## The weights are conventional, not sourced

Read
[`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md)
before using the defaults. No published weighting of BD Forêt or CORINE
classes was verified during phase 2, so the numbers are the package's
own convention. They are written into the provenance record with the
result, whichever ones you use.

## See also

[`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md),
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md).

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- rep(1:2, 8)
levels(r) <- data.frame(id = 1:2, class = c("FF1G09-09", "LA4"))
fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
av <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))
#> Warning: 1 class is absent from the lookup and become "NA" in `fev_fuel_availability()`.
#> ✖ "FF1G09-09"
#> ℹ That is 50% of mapped cells. They are not treated as non-burnable: an unknown
#>   class would then understate exposure exactly where the data is weakest.
#> ℹ Add 1 row to your lookup, or pass a table that covers it.
terra::global(fev_data(av), "max", na.rm = TRUE)
#>              max
#> availability   1
```
