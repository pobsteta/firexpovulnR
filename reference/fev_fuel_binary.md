# Burnable / non-burnable mask

Reduces a fuel source to the binary layer the exposure metrics operate
on: 1 where the class is fuel that can carry fire, 0 where it cannot,
`NA` where the source maps nothing or the lookup has no row for the
class.

## Usage

``` r
fev_fuel_binary(x, lookup = NULL)
```

## Arguments

- x:

  A `fev_fuel_source`.

- lookup:

  Correspondence table. Defaults to the one carried by `x`.

## Value

A `fev_fuel_layer` holding a 0/1 `SpatRaster` named `burnable`.

## Register consumed

Categorical.

## Unmatched classes become NA, loudly

A class present in the raster but absent from the lookup is not silently
non-burnable. It becomes `NA` and the function reports how many classes
and what share of mapped cells that is. Treating an unknown class as
non-burnable would understate exposure exactly where the data is
weakest.

## What "burnable" means here, and what it does not

It is a presence mask, not a flammability ranking: beech and Aleppo pine
are both 1. Grading between them is
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md).
And the shipped lookups make debatable calls on agricultural classes —
see
[`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
before using this on a crop-forest interface.

## See also

[`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
for the table that decides this,
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
for the graded version.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- rep(1:2, 8)
levels(r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
mask <- fev_fuel_binary(fuel)
terra::global(fev_data(mask), "mean", na.rm = TRUE)
#>          mean
#> burnable    1
```
