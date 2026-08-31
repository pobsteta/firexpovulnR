# Fetch Copernicus DEM GLO-30 (30 m elevation, worldwide, no account)

Reads the one-degree tiles covering an area straight from the public
bucket, crops, reprojects, and records provenance. Feeds
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)'s
slope weighting.

## Usage

``` r
fev_fetch_dem(aoi, crs_work = 2154, quiet = FALSE)
```

## Source

Copernicus DEM GLO-30, ESA, free and open under the Copernicus licence.
Distributed as cloud-optimised GeoTIFF on a public bucket.

Verified 2026-08-19 from the product: one-degree tiles at one arc-second
(about 30 m), EPSG:4326, named by the south-west corner of the tile,
header read remotely in 5.9 s.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- crs_work:

  EPSG code to return the raster in. Default `2154`. The product is in
  EPSG:4326, so a reprojection is the normal case; it uses bilinear
  interpolation, which is right for a continuous surface.

- quiet:

  Suppress the report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a `SpatRaster` of elevation in metres.

## It is a surface model, not a terrain model

GLO-30 is a **DSM**: it includes canopy and buildings. Over closed
forest the surface it describes is the top of the trees, so a slope
computed from it is the slope of the canopy, not of the ground beneath.
At 30 m the canopy is smoothed considerably and the large-scale slope
survives; at the scale of a single stand edge it does not.

For the use this package puts it to — weighting exposure sectors by the
large-scale lie of the land — that is acceptable, and it is why the
slope weighting is deliberately coarse rather than pretending to a
precision the input has not got. If you need ground slope under canopy,
use a LiDAR HD terrain model where one has flown.

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
for the slope weighting this feeds.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
dem <- fev_fetch_dem(aoi)
} # }
```
