# Is LiDAR HD available over an area, and which tiles

Queries the IGN tile index and reports what exists over an area of
interest, without downloading anything.

## Usage

``` r
fev_lidarhd_available(
  aoi,
  product = c("points", "mnh", "mns", "mnt"),
  crs_work = 2154,
  cache = TRUE
)
```

## Source

IGN Géoplateforme WFS, layers `IGNF_NUAGES-DE-POINTS-LIDAR-HD:dalle` and
`:bloc`, schema and values verified 2026-08-17. See
`specs/phase8-rapport-lidar.md`.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- product:

  Which tile index to query: `"points"` for the point clouds (the
  default), or `"mnh"`, `"mns"`, `"mnt"` for the derived height, surface
  and terrain rasters — far lighter when a canopy height model is all
  you need.

- crs_work:

  EPSG code to return the tile footprints in. Default `2154`, the tiles'
  native CRS.

- cache:

  Use the on-disk cache. See
  [`fev_cache_dir()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_dir.md).

## Value

An object of class `fev_lidarhd_index`: an `sf` of tile footprints with
columns `name`, `url`, `format`, `timestamp`, `id_chantier`, plus a
`coverage` attribute giving the share of the AOI the tiles cover. Zero
rows when the area is not flown.

## Why this comes first

The LiDAR HD programme is still being flown. Metropolitan coverage was
announced for the end of 2026 and was not complete when this function
was written: the Var was covered, the Côte-d'Or was not. Attempting a
download before checking wastes time on the good case and produces a
confusing failure on the bad one, so the check is a function of its own
and returns an empty table rather than an error when there is nothing.

## What a tile is

A 1 km square in Lambert-93, delivered as **COPC** — Cloud Optimized
Point Cloud. COPC is octree-indexed and readable by HTTP range request,
so an extent or a level of detail can be read without pulling the whole
file. That matters: a tile runs 120 to 260 MB — measured, not assumed —
and a Mediterranean massif needs several hundred of them.

## See also

[`fev_fetch_lidarhd()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_lidarhd.md)
to retrieve the tiles,
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
to turn them into fuel metrics.

## Examples

``` r
if (FALSE) { # \dontrun{
# The Maures: covered.
aoi <- sf::st_as_sfc(sf::st_bbox(
  c(xmin = 6.30, ymin = 43.20, xmax = 6.35, ymax = 43.25),
  crs = sf::st_crs(4326)
))
idx <- fev_lidarhd_available(aoi)
nrow(idx)
attr(idx, "coverage")

# Couchey: not flown, so an empty index rather than an error.
nrow(fev_lidarhd_available(sf::st_read("couchey.gpkg", "study_area")))
} # }
```
