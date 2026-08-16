# Save and reload a `fev_stack`

`terra` rasters hold a C++ pointer, so a plain
[`base::saveRDS()`](https://rdrr.io/r/base/readRDS.html) of a
`fev_stack` writes an object whose layers are unusable when reloaded.
These two functions wrap the layers with
[`terra::wrap()`](https://rspatial.github.io/terra/reference/wrap.html)
first, so the object – and the provenance record travelling with it –
survives a round trip to disk.

## Usage

``` r
fev_stack_save(x, file)

fev_stack_read(file)
```

## Arguments

- x:

  A `fev_stack`.

- file:

  Path to an `.rds` file.

## Value

`fev_stack_save()` returns `file` invisibly; `fev_stack_read()` returns
a `fev_stack`.

## Details

Large in-memory rasters are materialised by wrapping. For heavy layers,
write the rasters to GeoTIFF separately and keep only the provenance
here.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- seq_len(16)
s <- fev_stack(fuel = r, crs_work = 2154)
f <- tempfile(fileext = ".rds")
fev_stack_save(s, f)
s2 <- fev_stack_read(f)
names(s2)
#> [1] "fuel"
```
