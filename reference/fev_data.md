# The `fev_source` class, and how to get at its contents

`fev_fetch_*()` functions return a `fev_source`: the spatial data
together with the provenance record that says where it came from —
dataset, provider, endpoint, exact request, vintage and download time.
These accessors pull out one or the other.

## Usage

``` r
fev_data(x)

fev_source_info(x)
```

## Arguments

- x:

  A `fev_source`, or — for `fev_data()` — any `fev_layer`: the objects
  returned by
  [`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md),
  [`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md),
  [`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md),
  [`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
  and
  [`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md),
  which wrap their raster for the same reason.

## Value

`fev_data()` returns the underlying `sf` or `SpatRaster`.
`fev_source_info()` returns the record as a named list.

## Details

Data and record are held in one S3 object rather than as attributes on
the `sf`/`SpatRaster`, because `SpatRaster` is S4 and drops user
attributes at the first arithmetic operation — the record would vanish
silently on first use.

## Examples

``` r
# Offline example: build a source object by hand.
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- seq_len(16)
s <- firexpovulnR:::new_fev_source(r, dataset = "demo", provider = "none")
fev_source_info(s)$dataset
#> [1] "demo"
```
