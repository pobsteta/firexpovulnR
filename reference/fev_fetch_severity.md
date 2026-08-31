# Burn severity (dNBR) from Sentinel-2

Finds the least cloudy Sentinel-2 scene before and after a fire,
computes the Normalized Burn Ratio on each, and returns their difference
— the standard burn severity index — cropped to the area of interest.

## Usage

``` r
fev_fetch_severity(
  aoi,
  fire_date = NULL,
  pre_window = 45,
  post_window = 45,
  buffer_days = 3,
  max_cloud = 20,
  n_candidates = 4,
  min_coverage = 0.95,
  crs_work = 2154,
  quiet = FALSE
)
```

## Source

Sentinel-2 L2A cloud-optimised mirror maintained by Element 84 on AWS
Open Data, from Copernicus Sentinel data — free and open under the
Copernicus licence. STAC API at
<https://earth-search.aws.element84.com/v1>.

Verified 2026-08-19 by computing the index rather than by reading about
it: see the figures in the section above.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- fire_date:

  When the fire burned. One date, or **two** — start and end. `NULL`
  reads `FIREDATE` and `FINALDATE` from `aoi` when they are there, which
  is what
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
  returns.

- pre_window, post_window:

  Days to search before the start and after the end, outside a
  `buffer_days` margin.

- buffer_days:

  Days to exclude either side of the fire. Default 3.

- max_cloud:

  Maximum scene cloud cover in percent. Default 20.

- n_candidates:

  How many before-fire scenes to try. Each is differenced against the
  after scene and scored by how close its median comes to zero on ground
  outside the perimeter; the best wins. `1` takes the least cloudy and
  skips the check. Default 4.

- min_coverage:

  Fraction of the area a scene must actually carry data over. **Cloud
  cover does not report this**: an edge-of-swath scene covering 1% of
  the area is published at 0% cloud. Default 0.95.

- crs_work:

  EPSG code to return the raster in. Default `2154`.

- quiet:

  Suppress the report.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a single-layer `SpatRaster` named `dNBR`, with the two scene
identifiers and dates in its record.

## What dNBR is, and what it is not

NBR contrasts near infrared against shortwave infrared: living foliage
is bright in the first and dark in the second, and fire reverses both.
The difference before minus after is therefore a **change in
reflectance**, not a measurement of damage. Mapping it to mortality,
biomass loss or economic loss takes a local calibration against field
plots, and the published thresholds below are indicative, not a
substitute for one.

The usual thresholds (USGS, after Key and Benson): below 0.10 unburnt,
0.10 to 0.27 low, 0.27 to 0.66 moderate, above 0.66 high. Measured over
the 6 510 ha Cannet-des-Maures fire of 16 to 19 August 2021, from two
tiles mosaicked over 663 000 cells: median dNBR **0.576** inside the
perimeter against **0.000** outside, 41.9% of the burnt area above the
high-severity threshold and 4.9% below the unburnt one — the unburnt
islands every large fire leaves.

That 0.000 outside is the control worth insisting on: a dNBR that does
not come back to zero on ground that did not burn is measuring something
else — phenology between the two dates, haze, or a scene that does not
reach.

## Choosing the two dates is most of the method

An **initial assessment** compares the closest clear scenes either side
of the fire and captures the immediate effect, including the char that
later washes off. An **extended assessment** compares the same season a
year apart and captures what survived, which is closer to what an
ecologist means by severity. This function does the first, because it is
what the arguments describe and because the second needs a judgement
about the growing season that no default can make. Widen `post_window`
to a year and you get the second — the record says which dates were used
either way.

Phenology is the trap. A July pre-image against an October post-image
over Mediterranean vegetation puts summer senescence into the signal,
and it will look like low-severity burn across the whole scene. The
out-of-perimeter median is the check.

## Three ways to get a plausible map and a wrong number

Each of these was found by running the function against a fire whose
answer was known, and none of them crashed. Each returned a severity map
a reader would have accepted.

**The fire is still burning.** Counting the margin from the fire's
*start* picked a scene from 19 August 2021 — three days after ignition
and, as EFFIS records it, two hours before containment. Most of the
perimeter had not burned yet. The margin is therefore counted from the
**end**: pass both dates, or an `aoi` carrying EFFIS's `FIREDATE` and
`FINALDATE`.

**The scene does not reach.** The least cloudy candidate was an
edge-of-swath partial covering **1% of the area**, published at **0.0%
cloud**. Cloud cover does not report coverage, so `min_coverage` does.

**The scene reaches, but the fire is bigger than the tile.** The
Cannet-des-Maures straddles the edge of 31TGH, which carries 46.6% of
its bounding box. A single-scene index described half the fire and said
nothing about it — worse, a coverage check on the *cropped* result
reported 100%, because it measured what came back rather than what was
asked for. Every tile of a pass is mosaicked, and coverage is measured
against the area.

## See also

[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md),
which today knows only burnt against unburnt.

## Examples

``` r
if (FALSE) { # \dontrun{
feux <- sf::st_read("massif_maures.gpkg", "burnt_areas")
gros <- feux[which.max(feux$area_ha), ]
sev <- fev_fetch_severity(gros, fire_date = "2021-08-16")
terra::plot(fev_data(sev))
} # }
```
