# Fetch GHS-POP resident population (100 m, worldwide, no account)

Reads the Global Human Settlement population tiles covering an area
straight from the JRC open-data server, crops to the area, and records
provenance. Values are **residents per cell**, so a sum over an area is
a headcount.

## Usage

``` r
fev_fetch_ghsl(aoi, epoch = 2020, crs_work = 2154, quiet = FALSE)
```

## Source

GHS-POP R2023A, European Commission Joint Research Centre, CC-BY 4.0.
<https://human-settlement.emergency.copernicus.eu>

Verified 2026-08-19 against the product itself, not a datasheet: two
tiles were read and their extents compared to establish the tiling,
which is how the 1 000 000 m tile size and the -41 000 m x-origin offset
in this file were obtained. A crop over the Maures returned 35 039
residents at 100 m.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- epoch:

  Population epoch, one of the five-yearly GHSL epochs (1975 to 2030).
  Default 2020. Recorded as the vintage.

- crs_work:

  EPSG code to return the raster in. Default `2154`. `NULL` leaves it in
  the product's World Mollweide, which is what to pass when you want to
  measure what a reprojection costs. The product is in World Mollweide,
  so a reprojection is the normal case. It uses `"sum"` rather than an
  interpolation, because the values are people per cell and what must
  survive a change of projection is the **total**. The drift is
  reported, and warned about above 1%.

- quiet:

  Suppress the report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a `SpatRaster` of residents per cell.

## Why this source

It needs no account and no key, it is global, and it is what the CLIMAAX
wildfire workflow uses — so a risk layer built with it can be compared
against that method's own outputs rather than against a different
population product. It is modelled from census counts redistributed onto
built-up surface, which is the next section.

## What a population raster is and is not

GHS-POP is **modelled**, not observed: census or register counts are
disaggregated onto the built-up surface GHSL detects from imagery. Two
consequences the package will not paper over.

First, the spatial detail is the built-up layer's, while the totals are
the census's. A cell's value is an expectation, not a count of people
who sleep there.

Second, and this is what matters for fire: it is **residential**. A
campsite, a hiking trail or a motorway carries no resident population
and will read as empty, when summer daytime exposure in a Mediterranean
massif is exactly where people burn. Do not read a low GHS-POP as a low
human exposure in August.

## It is exposure of assets, not vulnerability

This function supplies *how much is exposed*. It says nothing about *how
badly it is harmed*, which is what vulnerability means in a risk
assessment and what this package still does not have — there is no
damage function anywhere in it.
[`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md)
will happily normalise this raster onto `[0, 1]` and the result will be
a normalised asset density. A hospital and a barn at the same population
density come out identical, and no amount of weighting in
[`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md)
changes that.

## See also

[`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md)
to normalise it,
[`fev_wui()`](https://pobsteta.github.io/firexpovulnR/reference/fev_wui.md)
for the interface where it matters most,
[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
to combine it.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
pop <- fev_fetch_ghsl(aoi, epoch = 2020)
human <- fev_vuln_layer(pop, method = "log")
} # }
```
