# Fetch SUFOSAT forest clear-cuts (10 m, mainland France)

Reads the national clear-cut map for an area of interest and decodes it
into the year and day of each detected disturbance. Downloaded once from
Zenodo and cached; the national file is 254 MB and arrives in under a
minute.

## Usage

``` r
fev_fetch_sufosat(
  aoi,
  fires = NULL,
  years = NULL,
  min_prob = NULL,
  crs_work = 2154,
  quiet = FALSE
)
```

## Source

SUFOSAT v3.0.1, CESBIO and GlobEO, with ADEME support.
[doi:10.5281/zenodo.17253008](https://doi.org/10.5281/zenodo.17253008) ,
CC-BY 4.0.

Verified 2026-08-20 against the data, not the datasheet: 119 159 x 126
813 cells at 10 m in EPSG:2154, values `YYDDD` with years 17 to 25 and
days 1 to 366. The current Zenodo version is CC-BY 4.0; the superseded
one was CC-BY-NC, and the copy catalogued on the THEIA STAC sits on a
bucket that refuses anonymous reads — same file, three different answers
about how you may get it.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- fires:

  Fire perimeters to exclude: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md),
  an `sf`, a `SpatVector`, or `NULL`. **Supply them** unless you want
  fires counted as cuts.

- years:

  Keep only these detection years, or `NULL` for all.

- min_prob:

  Keep only detections at or above this probability in percent, or
  `NULL` to skip it. Downloads a second 82 MB raster.

- crs_work:

  EPSG code to return the raster in. Default `2154`, which is the
  product's own projection, so the default does not reproject.

- quiet:

  Suppress the report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a `SpatRaster` with `cut_year` and `cut_doy`, plus `prob` when
`min_prob` was used. Cells with no detection are `NA`.

## It cannot tell a fire from a cut, and that is measured

The method detects a drop in Sentinel-1 backscatter — vegetation removed
— and is blind to the cause. Over the Maures study area it reports 2 626
ha of "clear-cut" for 2021, of which **97% lies inside the perimeter of
the Cannet-des-Maures fire**, with a median detection on day 246 (3
September), fifteen days after the fire was contained.

Passing `fires` removes those detections. Leaving it `NULL` does not
fail — the raw map is a legitimate thing to want — but it warns, because
a fuel correction built on it would record a fire as an exploitation.
The two are not the same fuel afterwards: a cut removes the stand, a
severe fire leaves it dead and standing, which is a different fire
hazard entirely.

## What survives the exclusion is worth having

On the Maures, 599 ha are detected **inside** the 2021 fire perimeter
during **2022** — post-fire salvage logging. That is a real fuel change,
dated, that nothing else in this package can see. Exclude the fire by
perimeter and year, not by perimeter alone, if you want to keep it:
`fires` masks every year, so pass only the years you mean to remove.

## Accuracy, as the producers report it

Precision 99.4%, recall 80.9%, minimum mapping unit 0.1 ha. The recall
is the number to keep in mind: about one cut in five is missed, so an
absence of detection is not evidence of no cut.

## See also

[`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
for the perimeters to exclude,
[`fev_fetch_severity()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_severity.md)
for the optical counterpart on a single fire.

## Examples

``` r
if (FALSE) { # \dontrun{
zone <- sf::st_read("massif_maures.gpkg", "study_area")
feux <- sf::st_read("massif_maures.gpkg", "burnt_areas")
coupes <- fev_fetch_sufosat(zone, fires = feux)
terra::plot(fev_data(coupes)[["cut_year"]])
} # }
```
