# Fetch ESA WorldCover (10 m land cover, no account needed)

Reads the WorldCover tiles covering an area of interest straight from
the public bucket, crops to the area, turns the product's nodata into
`NA`, and records provenance. Eleven classes at 10 m, derived from
Sentinel-1 and Sentinel-2.

## Usage

``` r
fev_fetch_worldcover(aoi, year = 2021, crs_work = 2154, quiet = FALSE)
```

## Source

ESA WorldCover, CC-BY 4.0, <https://esa-worldcover.org>. Overall
accuracy 74.4% (2020, v100) and 76.7% (2021, v200).

Verified 2026-08-18. Tile geometry, data type and nodata were read from
the product itself; the eleven class codes were confirmed against the
colour table embedded in the raster, all eleven RGB triplets matching
the published legend — verification from the data rather than from a
document about it.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- year:

  Vintage, 2020 or 2021. Default 2021, the more accurate.

- crs_work:

  EPSG code to return the raster in. Default `2154`. The product is in
  EPSG:4326, so a reprojection is the normal case; it uses nearest
  neighbour and is logged.

- quiet:

  Suppress the report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a categorical `SpatRaster` of class codes.

## It does not download a tile

A WorldCover tile is 3° square — 36 000 by 36 000 cells — and an
analysis usually wants a fraction of one. GDAL reads cloud-optimised
GeoTIFFs by range request, so only the requested window crosses the
network.

## Where it sits in the hierarchy, and what that costs

`fev_fuel_merge(hierarchy = "auto")`, the default, puts WorldCover
**above** BD Forêt: 10 m and a recent vintage everywhere beat 25 m and a
2008-2018 vintage.

That trade is not free, and the cost was measured rather than guessed.
On the two Maures LiDAR plots, WorldCover's *Shrubland* class separates
the measured understorey only weakly — 0.688 at best on the 0–1 m load,
0.55 to 0.58 elsewhere, against 0.5 for no information — and its
*Shrubland* and *Tree cover* classes carry practically the same
understorey (median bush height 3.2 m against 2.8 m). It carries no
species and no crown-cover reading, both of which BD Forêt does.

So this ranking buys resolution and recency and pays in thematic depth.
Pass `hierarchy = "primary_first"` with BD Forêt as primary to reverse
it.

## The two vintages are not a time series

2020 is v100 and 2021 is v200, and the producers warn against
differencing them: the method changed between versions, and the change
signal is dominated by that rather than by the ground. Pick one vintage
per analysis.

## See also

[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
to put it on a grid,
[`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md)
to test its classes against a measurement before trusting them.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
wc <- fev_fetch_worldcover(aoi, year = 2021)
fuel <- fev_fuel_source(wc, type = "worldcover_2021", res = 10)
} # }
```
