# Import CLCplus Backbone (10 m raster land cover)

Reads a CLCplus Backbone raster, crops it to an area of interest, turns
the product's absence codes into `NA`, and records its provenance.
CLCplus is a 10 m raster derived from Sentinel-2 time series, with 11
land cover classes and complete coverage of the EEA area.

## Usage

``` r
fev_fetch_clcplus(
  file = NULL,
  aoi = NULL,
  year = 2023,
  crs_work = 2154,
  quiet = FALSE
)
```

## Source

Codes, labels, resolution, CRS and vintages: European Environment Agency
catalogue record for CLCplus Backbone 2023,
[doi:10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2](https://doi.org/10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2)
, verified 2026-08-18.

Accuracy figures and the three regionally weaker classes: Copernicus
Land Monitoring Service, CLCplus Backbone product documentation, read at
summary level 2026-08-18. The ATBD was read directly and carries no
per-class figure; the Product User Manual was not reachable, and the
validation reports are announced as forthcoming.

## Arguments

- file:

  Path to a CLCplus Backbone raster (any format GDAL reads). Required —
  see the access-route section.

- aoi:

  Optional area of interest to crop to: `sf`, `sfc`, `bbox`,
  `SpatVector` or `SpatRaster`. Must carry a CRS.

- year:

  Vintage. One of 2018, 2021, 2023. Recorded in the provenance and used
  to pick the source type.

- crs_work:

  EPSG code to return the raster in. Default `2154`. The product is
  distributed in EPSG:3035, so a reprojection is the normal case here;
  it uses nearest neighbour and is logged.

- quiet:

  Suppress the import report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a `SpatRaster` of class codes.

## Access route, and why this is not a downloader

The Copernicus Land Monitoring Service serves CLCplus behind EU Login,
with an OAuth2 token exchange for programmatic access. This package does
not handle personal tokens — the same rule that made
[`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md)
use Open-Meteo rather than the CEMS historical product. Download the
raster for your area from the CLMS portal or WEkEO, then pass the file
here. The route is recorded in the provenance as a manual import, which
is what it is.

## What it gains over CORINE, and what it loses

It **gains** the distinction CORINE cannot make. CORINE class 311 puts
holm oak and beech in one bucket; CLCplus separates broadleaved
deciduous (class 3) from broadleaved evergreen (class 4), and around the
Mediterranean the latter *is* the sclerophyll type. It also has no
rasterisation slivers, being a raster already, and a two-yearly vintage
against CORINE's six.

It **loses** the shrub layer. CORINE separates natural grassland (321),
moors and heathland (322), sclerophyllous vegetation (323) and
transitional woodland-shrub (324). CLCplus collapses the woody ones into
class 5. Maquis, heath and post-fire regeneration become one value.

This is why it is offered as an auxiliary source beside CORINE rather
than as a replacement for it.

## The weak class is the one that burns

Independent validation of the 2018 and 2021 rasters gave overall
accuracies of 85.2% and 85.3%, both within 0.5%. Producer's and user's
accuracies meet the per-class target of at least 85% for every class
**except three**, stated to be regionally lower: 5 (low-growing woody
plants), 8 (lichens and mosses) and 9 (non- and sparsely vegetated). The
reasons given are fuzzy class definition, limited spectral-temporal
separability and sparse reference data.

Class 5 is maquis and garrigue. The weakest class of the product is the
one that carries fire in the Var, so this function says so on import
rather than leaving it in a PDF. Validate it locally before relying on
it —
[`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md)
is what that validation looks like.

**By how much they fall short is not public.** The Algorithm Theoretical
Basis Document was read and carries no per-class figure; the validation
reports are announced as forthcoming. So the package records *which*
classes are weak, not *how* weak, which is the honest limit of what is
known.

## Absence is not a class

The raster carries three special values. 253 is the coastal seawater
buffer, a real if artificial surface, and it maps to non-fuel. **254
(outside the product area) and 255 (no data) are turned into `NA`**,
because they are the absence of a class rather than a class. Giving them
a fuel type would assert that unknown ground is non-fuel, which the
package refuses everywhere else.

Note that these `NA` are *real* gaps, not rasterisation slivers, and
[`fev_fuel_fill_gaps()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_fill_gaps.md)
declines to fill them for exactly that reason.

## See also

[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
to put it on a grid,
[`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
for the correspondence table,
[`fev_fetch_corine()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_corine.md)
for the source it sits beside.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
cpl <- fev_fetch_clcplus("CLMS_CLCplus_RASTER_2023_010m_eu.tif",
                         aoi = aoi, year = 2023)
fuel <- fev_fuel_source(cpl, type = "clcplus_2023", res = 10)
} # }
```
