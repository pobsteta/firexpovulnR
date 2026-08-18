# Invert LiDAR HD tiles in batch, with resume

Walks a set of LiDAR HD tiles one at a time: downloads, inverts to fuel
metrics with
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md),
writes one raster per tile, and deletes the point cloud before moving
on. Interrupt it whenever you like and start it again — it picks up
where it stopped.

## Usage

``` r
fev_lidar_batch(
  aoi,
  out_dir,
  res = 25,
  window = NULL,
  max_tiles = NULL,
  spread = TRUE,
  keep_las = FALSE,
  dry_run = FALSE,
  quiet = FALSE
)
```

## Arguments

- aoi:

  Area of interest, or an `fev_lidarhd_index` from
  [`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md).

- out_dir:

  Directory for the per-tile rasters and the manifest. Created if
  absent.

- res:

  Target cell size in metres, passed to
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md).

- window:

  Side of a centred square to process within each tile, in metres.
  `NULL` processes the whole tile.

- max_tiles:

  Stop after this many tiles in one run — a way to take an overnight job
  in shifts. `NULL` for no limit.

- spread:

  Choose those tiles spread across the area rather than in index order.
  On by default, and it matters: the index is in spatial order, so the
  first eight tiles of it are eight neighbours in one corner. See the
  section below.

- keep_las:

  Keep the downloaded point clouds instead of deleting each one after
  its tile is inverted. Off by default: at roughly 200 MB a tile, a
  departmental run would fill a disk.

- dry_run:

  Report what would be done and return the plan without downloading
  anything.

- quiet:

  Suppress progress reporting.

## Value

A data frame, one row per tile: `tile`, `status`, `points`, `seconds`,
`path`, `rank`. `status` is `"done"` for a tile whose raster already
exists, `"next"` for one this run will take, `"todo"` for one left for a
later run, and `"written"` or `"failed"` afterwards. `rank` gives the
position in the traversal, so a dry run shows the actual batch rather
than the index order. Also written to `manifest.csv` in `out_dir` after
every tile, so an interrupted run leaves a readable record.

## Why resume is the point

Measured on real tiles over the Maures, none of these finished: 3.0 M
points in over 25 minutes, 11.1 M in over 40, a whole tile in over 90.
Downloading is not the bottleneck — a 248 MB tile arrives in 42 seconds
— the inversion is. A departmental run is therefore an overnight batch
job, and any batch job that cannot be interrupted will be, at the worst
moment.

Resume is by **output presence**, not by a state file that can drift
from the truth: a tile whose raster is on disk is done. Each raster is
written to a temporary name and renamed only once complete, so an
interrupted write is never mistaken for a finished tile.

## What `window` is for

A full tile is a square kilometre and, at LiDAR HD's density, tens of
millions of points. `window` processes a centred square of `window`
metres instead, which is what makes a spread of tiles affordable: eight
250 m windows across a massif sample eight contexts, where one whole
tile samples one, for a fraction of the cost.

Spread beats contiguity for anything you intend to compare against a
classification — which is what
[`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md)
does.

## Why the order is not the index order

`max_tiles` without `spread` would hand you the first N tiles of an
index that is itself in spatial order — eight neighbours in one corner
of the massif, sampling one context eight times. `spread = TRUE` walks
the tiles by farthest-point traversal instead: each tile chosen is the
one furthest from everything chosen so far.

The traversal is deterministic and computed over the whole set, so every
prefix of it is well spread **and** resume continues the spread rather
than re-drawing it. Eight tiles tonight and eight tomorrow give sixteen
spread tiles, not two clusters of eight.

## Do not thin the cloud to go faster

It is the obvious optimisation and it destroys the measurement. As pulse
density falls the understorey stratum is the first thing to disappear,
so thinning biases exactly the quantity these metrics exist to carry.
Reduce `window`, or process fewer tiles; never reduce the density. See
[`fev_lidar_density()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidar_density.md).

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
for the inversion and what it costs,
[`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md)
for the coverage check.

## Examples

``` r
if (FALSE) { # \dontrun{
study <- sf::st_read("massif_maures.gpkg")

# What it would do, without downloading anything.
fev_lidar_batch(study, "out/lidar", window = 250, dry_run = TRUE)

# Overnight, in shifts. Run it again tomorrow and it continues.
fev_lidar_batch(study, "out/lidar", window = 250, max_tiles = 8)
} # }
```
