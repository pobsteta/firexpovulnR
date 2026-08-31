# Fetch BDIFF fire records (France, 2006 onward)

Reads the *Base de Donnees sur les Incendies de Forets en France*: one
record per declared fire, with the commune it started in, its date, the
area it ran through split by vegetation type, and its cause when known.

## Usage

``` r
fev_fetch_bdiff(
  aoi = NULL,
  period = NULL,
  departements = NULL,
  communes = NULL,
  communes_key = NULL,
  file = NULL,
  resource = NULL,
  columns = fev_bdiff_columns(),
  area_units = c("m2", "ha"),
  crs_work = 2154,
  cache = TRUE
)
```

## Source

BDIFF, *Base de Donnees sur les Incendies de Forets en France*, hosted
by IGN for the ministries in charge of forests and the interior:
<https://bdiff.agriculture.gouv.fr/>. Coverage from 2006; Promethee (the
Mediterranean base) merged into it in early 2023. Consolidation, absence
of an area threshold and the exhaustivity caveat are stated on the
base's own help pages, read 2026-08-31.

## Arguments

- aoi:

  Optional area of interest to clip to: `sf`, `sfc`, `bbox`,
  `SpatVector` or `SpatRaster`. Requires `communes`, since without
  geometry there is nothing to clip.

- period:

  Two-element vector giving the first and last year, e.g.
  `c(2006, 2025)`. `NULL` keeps everything.

- departements:

  Character vector of department codes to keep, e.g.
  `c("21", "39", "2A")`. Compared as strings, so `"01"` and `"1"` both
  work. `NULL` keeps everything.

- communes:

  Optional `sf` of commune polygons carrying an INSEE code, to geolocate
  the records. Without it the result is a plain data frame.

- communes_key:

  Name of the INSEE code column in `communes`. `NULL` auto-detects among
  the usual names and says which it chose.

- file:

  Path to a CSV exported from the BDIFF interface. The verified route.

- resource:

  Title or URL of the data.gouv.fr resource to download, overriding the
  automatic choice. Ignored when `file` is given.

- columns:

  Header-to-column mapping; see
  [`fev_bdiff_columns()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdiff_columns.md).

- area_units:

  Units the area columns are published in: `"m2"` (the default, and what
  the BDIFF export declares) or `"ha"`. A plausibility check warns when
  the values do not look like the declared unit.

- crs_work:

  EPSG code for the returned geometry. Default `2154`. Ignored when
  `communes` is absent.

- cache:

  Use the on-disk cache.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md).
Its data is a data frame with one row per fire — `fire_id`, `fire_date`,
`fire_year`, `insee`, `commune`, `dep`, `area_ha`, `area_forest_ha`,
`area_other_wooded_ha`, `area_other_ha`, `cause` — or an `sf` of commune
polygons when `communes` is supplied.

## What this brings that nothing else in the package does

[`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
gives perimeters, from remote sensing, from roughly 2016, and only for
fires large enough to be seen from orbit. BDIFF is declarative and has
**no area threshold at all**, so it is the only source here that can
answer "how often does a fire start in this commune". That is the
ignition term of the hazard, and the package has never had it.

It is also the only source that separates burnt area by vegetation type,
so agricultural and non-forest vegetation fires can be told apart from
forest fires rather than pooled.

## Geolocation is the commune of departure, not a perimeter

BDIFF records the **commune where the fire started**, not where it went
and not a contour. Passing `communes` joins the commune polygons and
returns an `sf`; the geometry is then a commune, and a 3 ha fire carries
the shape of the 40 km2 commune it started in.

The consequence is not cosmetic. You can build an occurrence density per
commune from this. You cannot build a 50 m occurrence raster from it,
and anything that reads like one is an artefact of the join. For
perimeters, use
[`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
and accept its size threshold, or derive them from
[`fev_fetch_severity()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_severity.md).
The two sources are complementary, and neither substitutes for the
other.

## Exhaustivity is not guaranteed, and the gap is not random

Entry is collaborative. BDIFF states that the base may contain
imprecision and lack exhaustivity despite verification. Nothing here can
correct that, and the failure mode worth naming is that the
under-reporting is very probably **spatially structured**: departments
differ in how completely they file. For a map of occurrence that is
worse than random noise, because it looks like signal. **A commune with
no recorded fire is not a commune with no fire.**

The caveat is warned once per session and written into the provenance
record on every call.

## Consolidation runs a year behind

Fiches for campaign year `Y` are validated by the deconcentrated
services between December `Y` and April `Y+1`, and only then published
and passed to EFFIS. So the current year, and the previous one until
roughly May, are not consolidated. This function compares what you asked
for against what can be consolidated today and warns with the years
rather than a vague caveat.

## Two acquisition routes, and only one of them is verified

`file` reads a CSV exported from the BDIFF search interface. This is the
route the package tests and the one to prefer.

Without `file`, the function resolves the dataset on **data.gouv.fr**
through its public API and downloads a CSV resource. BDIFF publishes no
API of its own – no WFS, no documented REST – so this is the only
programmatic route that rests on a stable contract rather than on
scraping a search form.

**This remote route has not been exercised against the live service.**
Every endpoint in
[`fev_sources()`](https://pobsteta.github.io/firexpovulnR/reference/fev_sources.md)
was verified by a real call on 2026-08-15; this one was not, because the
environment it was written in cannot reach `data.gouv.fr`. It is marked
`endpoint_verified = FALSE` in the source record and warns once per
session. Treat a result obtained through it as unverified provenance
until someone has run it and confirmed the resource it picked.

## Column names are a lookup, not a constant

The CSV headers are a publication choice of the producer and they move.
The mapping from headers to the columns this function returns is
[`fev_bdiff_columns()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdiff_columns.md)
— a default with documented candidates, entirely overridable, like every
other imported table in the package. When a required column cannot be
matched the error lists the headers actually present, so the fix is one
`columns` argument away rather than a reading of the source.

## See also

[`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
for perimeters,
[`fev_bdiff_columns()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdiff_columns.md)
for the header mapping,
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
which scores a risk surface.

## Examples

``` r
if (FALSE) { # \dontrun{
# The verified route: export a CSV from the BDIFF interface first.
fires <- fev_fetch_bdiff(
  file = "bdiff_bfc_2006_2025.csv",
  period = c(2006, 2025),
  departements = c("21", "25", "39", "58", "70", "71", "89", "90")
)
fev_source_info(fires)$n_features

# With commune polygons, the result is an sf ready for a density.
com <- sf::st_read("admin_express_communes.gpkg")
fires <- fev_fetch_bdiff(file = "bdiff_bfc.csv", communes = com)
} # }
```
