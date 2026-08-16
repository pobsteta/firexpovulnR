# Fetch BD Forêt v2 (primary fuel source)

Downloads vegetation formation polygons from the IGN Géoplateforme WFS
for an area of interest. BD Forêt v2 is the package's **primary fuel
source**: its 0.5 ha minimum mapping unit and 20 m minimum width are
what make hectometric focal exposure meaningful, where CORINE's 25 ha
unit is not.

## Usage

``` r
fev_fetch_bdforet(
  aoi,
  millesime = NA,
  dept = NULL,
  crs_work = 2154,
  cache = TRUE,
  layer = .FEV_LAYERS$bdforet_v2
)
```

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- millesime:

  Vintage of the data, as a year, or a data frame with columns `dept`
  and `year` for a multi-department AOI. `NA` by default because the
  source does not provide it — supply it rather than let it default.

- dept:

  Optional department code(s) to record in provenance. Purely
  documentary: filtering is done by `aoi`.

- crs_work:

  EPSG code to return the data in. Default `2154`, BD Forêt's native CRS
  — leaving it there avoids reprojecting the categorical primary source.

- cache:

  Use the on-disk cache. See
  [`fev_cache_dir()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_dir.md).

- layer:

  WFS layer name. Defaults to the verified BD Forêt v2 layer; override
  only if IGN moves it.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding an `sf` of vegetation formations with columns `id`, `code_tfv`,
`tfv`, `tfv_g11`, `essence`.

## Access route

`geoservices.ign.fr` was retired in March 2026 and now redirects to
cartes.gouv.fr, which documents no programmatic route. This function
uses the Géoplateforme WFS instead — no authentication, filtered
server-side by AOI, so only the study area is transferred rather than
whole departments. Pagination and the IGN axis-order quirk are handled
by `happign`.

## On the vintage

**The WFS does not serve the vintage.** It is absent from the layer
schema, and no per-department table was found at IGN or in any related
project. BD Forêt v2 was built department by department between 2007 and
2018, so a national assembly is not a snapshot: a stand mapped in 2008
may have burnt in 2010 and be in a completely different state.

`millesime` is therefore recorded as `NA` unless you supply it, and
nothing is inferred. Supply it when you know it —
[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
requires it, and the temporal-bias check in `fev_validate()` cannot run
without it.

## See also

[`fev_fetch_corine()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_corine.md)
for the auxiliary source,
[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
to turn this into a fuel layer.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
bdf <- fev_fetch_bdforet(aoi, millesime = 2014, dept = "83")
bdf
table(fev_data(bdf)$code_tfv)
} # }
```
