# Attach continuous fuel metrics to a categorical fuel source

Grafts a LiDAR-derived continuous register onto a fuel source that
already carries a categorical one, so a single object holds both
descriptions of the same ground.

## Usage

``` r
fev_fuel_attach(primary, lidar)
```

## Arguments

- primary:

  A `fev_fuel_source` with a categorical register.

- lidar:

  A `fev_fuel_source` with a continuous register, from
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md).

## Value

`primary`, with its continuous register populated.

## Why this is not fev_fuel_merge()

[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
arbitrates between sources that compete for the same pixel: BD Forêt and
CORINE both propose a class, one has to win, and the per-pixel `source`
layer records which. LiDAR competes for nothing. It carries quantities
neither categorical source has — bulk density, crown base height, load
by stratum — on the same ground. Folding that into `merge` would give
one function two incompatible behaviours, so it is a separate operation
writing to a separate register.

## Coverage is a per-metric mask, not a source layer

LiDAR HD is still being flown, so the continuous register is full of
holes where the categorical one is complete. The function reports the
share of categorical cells that get continuous values, because a fuel
object whose two registers describe different subsets of the map is easy
to misread.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md),
[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md),
[`fev_fuel_registers()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md).

## Examples

``` r
# Categorical from BD Forêt, continuous standing in for LiDAR.
cat_r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 200,
                     ymin = 0, ymax = 200, crs = "EPSG:2154")
terra::values(cat_r) <- rep_len(1:2, 64)
levels(cat_r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
names(cat_r) <- "class"
fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)

cbd <- terra::rast(cat_r)
terra::values(cbd) <- runif(64, 0, 0.4)
names(cbd) <- "CBD_max"
lidar <- fev_fuel_source(cbd, type = "custom", register = "continuous",
                         units = c(CBD_max = "kg/m3"))

both <- fev_fuel_attach(fuel, lidar)
#> Attached 1 continuous metric covering 100% of the categorical cells.
fev_fuel_registers(both)
#> [1] "categorical" "continuous" 
```
