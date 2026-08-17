# Retrieve LiDAR HD tiles

Downloads the tiles covering an area, skipping those already present so
an interrupted run can be resumed.

## Usage

``` r
fev_fetch_lidarhd(
  aoi,
  dir = NULL,
  max_tiles = 10L,
  product = "points",
  crs_work = 2154,
  quiet = FALSE
)
```

## Arguments

- aoi:

  Area of interest, or an index from
  [`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md).

- dir:

  Directory to download into. Defaults to a `lidarhd` subdirectory of
  the package cache.

- max_tiles:

  Refuse rather than start a job larger than this. There is no default
  that is right for everyone, so the default is deliberately small.

- product:

  Passed to
  [`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md)
  when `aoi` is not already an index.

- crs_work:

  EPSG code for the index.

- quiet:

  Suppress per-tile progress.

## Value

A `fev_source` holding a data frame of local paths, with the provenance
of the index it came from.

## Volume, and resuming

One tile is of the order of a gigabyte. A Mediterranean massif is a
thousand tiles, so a departmental job is a terabyte-scale download that
will be interrupted at least once. Files already on disk with a
plausible size are therefore skipped rather than refetched, which makes
re-running the same call the way to resume.

Nothing here parallelises the download on purpose: hammering a public
service with concurrent requests is how access gets withdrawn for
everyone.

## Reading without downloading

The tiles are COPC, so `lidR` can read an extent straight from the URL
over HTTP without a local copy. When you need metrics over a few
hectares rather than a department, that is the cheaper route —
`fev_fetch_lidarhd()` is for when you genuinely need the files.

## See also

[`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md),
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md).

## Examples

``` r
if (FALSE) { # \dontrun{
idx <- fev_lidarhd_available(aoi)
tiles <- fev_fetch_lidarhd(idx, max_tiles = 4)
fev_data(tiles)$path
} # }
```
