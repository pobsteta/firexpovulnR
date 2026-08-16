# Export the provenance of an analysis

Returns the full provenance record of a
[`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md)
– sources with their vintages, the working CRS and resolution, and the
ordered log of every operation with the parameters it ran with.
Optionally writes it to a YAML file.

## Usage

``` r
fev_provenance(x, file = NULL)
```

## Arguments

- x:

  A `fev_stack` object.

- file:

  Optional path. When given, the record is written there as YAML and the
  record is returned invisibly.

## Value

A named list of class `fev_provenance`. Invisibly when `file` is given.

## Details

This is what makes an analysis replayable. The record is built as the
analysis runs, so it reflects the parameters actually used, including
defaults the caller never typed.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- seq_len(16)
s <- fev_stack(fuel = r, crs_work = 2154)
prov <- fev_provenance(s)
prov$crs_work
#> [1] 2154
```
