# Fetch EFFIS burnt area perimeters

Downloads burnt area polygons from the EFFIS/GWIS service, for
validating a risk surface against what actually burnt.

## Usage

``` r
fev_fetch_burnt(
  aoi,
  period = NULL,
  file = NULL,
  crs_work = 2154,
  cache = TRUE,
  layer = .FEV_LAYERS$effis_ba
)
```

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- period:

  Two-element character or numeric vector giving the first and last year
  (or dates) to keep, e.g. `c("2016", "2025")`. `NULL` keeps everything
  returned.

- file:

  Optional path to a local burnt-area file, for extracts obtained
  through the EFFIS data request form.

- crs_work:

  EPSG code to return the data in. Default `2154`.

- cache:

  Use the on-disk cache.

- layer:

  WFS type name. Defaults to the verified `ms:modis.ba.poly`.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding an `sf` of burnt area polygons, with at least `FIREDATE`,
`AREA_HA` and `COUNTRY`. A `fire_year` column is added for convenience.

## Coverage is shorter than you may expect

The public EFFIS endpoint serves roughly **2016 onward** — not 2006.
EFFIS states that historic data, database extracts and raw perimeters go
through their data request form instead. This function therefore
compares the period you asked for against the period actually returned,
and warns with numbers rather than a vague caveat: silently validating
on ten years while believing you validated on eighteen is the failure
mode worth preventing.

Use `file` to bring in an extract obtained through the EFFIS request
form.

## The CRS is forced, deliberately

EFFIS ships a `.prj` declaring `GCS_unknown` although the coordinates
are plain WGS84, so
[`sf::st_crs()`](https://r-spatial.github.io/sf/reference/st_crs.html)
reads `unknown`. The package sets EPSG:4326 explicitly and records the
override in provenance. It is never applied silently, because "the
provider mislabels its CRS" is exactly the kind of assumption that must
be visible in a methods section.

## See also

[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md),
which uses these to score a risk surface and runs the temporal-bias
check against the fuel vintage.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
ba <- fev_fetch_burnt(aoi, period = c("2016", "2025"))
fev_source_info(ba)$period_returned
} # }
```
