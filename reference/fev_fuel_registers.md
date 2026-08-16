# Which registers of a fuel source are populated

A fuel source carries a categorical register (class codes) and a
continuous register (numeric metrics per pixel). Downstream functions
declare which one they consume:
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md),
[`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md)
and
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
all read the categorical register.

## Usage

``` r
fev_fuel_registers(x)

fev_fuel_categorical(x)

fev_fuel_continuous(x)
```

## Arguments

- x:

  A `fev_fuel_source`.

## Value

`fev_fuel_registers()` returns a character vector of the populated
registers. `fev_fuel_categorical()` and `fev_fuel_continuous()` return
the corresponding `SpatRaster`, or `NULL`.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- rep(1:2, 8)
levels(r) <- data.frame(id = 1:2, class = c("LA4", "LA6"))
f <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
fev_fuel_registers(f)
#> [1] "categorical"
```
