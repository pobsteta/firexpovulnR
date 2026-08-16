# Fetch CORINE Land Cover (auxiliary fuel source)

Downloads CORINE Land Cover polygons for an area of interest. CORINE is
the package's **auxiliary** fuel source: it fills what BD Forêt v2
leaves unmapped, in particular non-forest burnable vegetation
(sclerophyllous vegetation, moors, grassland) and unambiguously
non-burnable classes (urban, water, bare rock).

## Usage

``` r
fev_fetch_corine(
  aoi,
  year = 2018,
  file = NULL,
  code_col = NULL,
  crs_work = 2154,
  cache = TRUE,
  layer = NULL
)
```

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- year:

  CORINE vintage. One of 1990, 2000, 2006, 2012, 2018. Unlike BD Forêt,
  CORINE has a common European reference date, so this **is** the
  vintage and is recorded as such.

- file:

  Optional path to a local CORINE file (any format GDAL reads). Use this
  outside France, or when CLMS requires manual download. The file is
  validated and its provenance recorded as a local import.

- code_col:

  Name of the land cover code column. Defaults to the year-specific
  column served by the WFS (e.g. `code_18` for 2018).

- crs_work:

  EPSG code to return the data in. Default `2154`.

- cache:

  Use the on-disk cache.

- layer:

  WFS layer name. Defaults to the verified layer for `year`.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding an `sf` of land cover polygons.

## Why auxiliary and not primary

CORINE's minimum mapping unit is 25 ha, against 0.5 ha for BD Forêt v2.
A 500 m focal window covers 78 ha, so a single CORINE unit is a third of
it; at 100 m (3 ha of window) CORINE is smaller than its own mapping
unit and the resulting fraction is meaningless. This is the decisive
argument for the source hierarchy, and it is why
[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
tracks which source each pixel came from.

## Access route

For metropolitan France, CORINE is redistributed on the same IGN
Géoplateforme WFS as BD Forêt v2 — no Copernicus Land Monitoring Service
authentication needed. **For studies outside France this route does not
apply**: obtain the data from CLMS and pass the file through `file`.
That path is not verified by this package's tests.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
clc <- fev_fetch_corine(aoi, year = 2018)

# Outside France, or when CLMS needs a manual download:
clc <- fev_fetch_corine(aoi, year = 2018, file = "U2018_CLC2018_V2020_20u1.gpkg")
} # }
```
