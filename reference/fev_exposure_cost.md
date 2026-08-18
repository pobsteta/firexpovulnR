# What a focal exposure pass will cost, before committing to it

Reports the size of the window and the weighted operation count for a
fuel grid, at its own resolution or at a hypothetical one. Exists
because the cost of this step grows as the **fourth power** of the
inverse cell size — both the cell count and the window area scale as
`res^-2` — so the step from 25 m to 10 m is not a 2.5-fold increase but
roughly forty-fold, and that is worth knowing before a run rather than
during one.

## Usage

``` r
fev_exposure_cost(x, res = NULL, radius = NULL, rate = 2e+08)
```

## Arguments

- x:

  A fuel layer: `SpatRaster`,
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  or `fev_layer`.

- res:

  Cell size to cost, in CRS units. `NULL` uses `x`'s own.

- radius:

  Radius in metres. `NULL` costs all three shipped radii.

- rate:

  Weighted operations per second, for the time estimate. The default was
  measured on the machine this package was developed on; yours will
  differ, which is why it is an argument and the result is called an
  estimate.

## Value

A data frame with one row per radius: `radius`, `res`, `reachable`,
`window_cells`, `ring_cells`, `ops` and `seconds`.

## The other reason to ask

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
requires `res <= radius / 3`, so a coarse grid does not merely cost
less, it puts the short radii out of reach entirely. At 25 m the 30 m
radiant-heat radius is refused; at 10 m it passes, exactly, since
`10 = 30 / 3`. This function reports whether each radius is reachable at
the resolution asked about, which is the trade the cost has to be
weighed against.

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
[`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md).

## Examples

``` r
r <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 2500,
                 ymin = 0, ymax = 2500, crs = "EPSG:2154")
terra::values(r) <- 1

# What the three scales cost on this grid, and which are out of reach.
fev_exposure_cost(r)
#>   radius res reachable window_cells ring_cells      ops seconds
#> 1     30  25     FALSE           NA         NA       NA      NA
#> 2    100  25      TRUE           81         48   480000  0.0024
#> 3    500  25      TRUE         1681       1256 12560000  0.0628

# And what refining to 10 m would cost.
fev_exposure_cost(r, res = 10)
#>   radius res reachable window_cells ring_cells       ops seconds
#> 1     30  10      TRUE           49         28   1750000 0.00875
#> 2    100  10      TRUE          441        316  19750000 0.09875
#> 3    500  10      TRUE        10201       7844 490250000 2.45125
```
