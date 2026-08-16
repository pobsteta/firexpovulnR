# BD Forêt v2 vintage, from the imagery it was photo-interpreted on

Retrieves the aerial survey dates of the BD ORTHO campaigns covering an
area of interest, which is what IGN defines the BD Forêt v2 validity
date to be.

## Usage

``` r
fev_bdforet_millesime(
  aoi,
  period = .FEV_BDFORET_V2_WINDOW,
  strategy = NULL,
  crs_work = 2154,
  cache = TRUE
)
```

## Source

IGN, *BD Forêt® Version 2 — Descriptif de contenu*, September 2014,
§2.3, <https://inventaire-forestier.ign.fr/IMG/pdf/DC_BDFORET_v2.pdf>,
read 2026-08-16. Mosaicking graph layers and their `date_vol` field
verified by `DescribeFeatureType` and by real `GetFeature` requests over
the Var on the same day.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- period:

  Two years bounding the search. Defaults to the BD Forêt v2
  construction window, 2007 to 2018.

- strategy:

  `NULL` (default) returns every candidate. `"oldest"` and `"newest"`
  collapse to a single year, and say which rule produced it.

- crs_work:

  EPSG code to work in. Default `2154`.

- cache:

  Use the on-disk cache. See
  [`fev_cache_dir()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_dir.md).

## Value

With `strategy = NULL`, a data frame of class `fev_millesime` with one
row per campaign: `dep`, `pva`, `date_vol`, `year`, `n_polygons` and
`pct_area` — the share of the mosaic area over the AOI that campaign
covers. With a strategy, a single integer year carrying the table as its
`candidates` attribute.

## Why this is the vintage, not a proxy for it

The BD Forêt v2 content description states it directly: *« La date de
validation est celle de la prise de vues de la BD ORTHO® servant à la
production des données. »* The database describes the stand as the
photo-interpreter saw it on the infrared imagery, so the survey date is
the date of the landscape state it records — which is exactly what a
temporal bias check needs, and arguably better than a publication date
would be.

The WFS serving BD Forêt v2 carries no date field of any kind (schema
verified 2026-08-16: `id`, `code_tfv`, `tfv`, `tfv_g11`, `essence`,
`geom`), so this is the only route to it that does not involve guessing.

## It usually returns more than one candidate

BD ORTHO reflies a department roughly every five years, and BD Forêt v2
was built between 2007 and 2018. Most departments therefore have two
campaigns inside that window — the Var has 2008 and 2014 — and **IGN
does not publish which one fed which department's production**. This
function will not choose for you.

Two things narrow it. Full metropolitan coverage was planned for early
2016, so a survey flown after that fed an update rather than an initial
production. And `strategy = "oldest"` is the conservative reading:
assuming the older campaign maximises the lag the validation reports,
which errs toward flagging temporal bias rather than hiding it.

## See also

[`fev_fetch_bdforet()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdforet.md),
which accepts `millesime = "auto"` to call this, and
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md),
which is what needs the answer.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")

# Every campaign that could have fed the BD Forêt v2 of this area:
fev_bdforet_millesime(aoi)

# Collapsed conservatively, for an automated pipeline:
millesime <- fev_bdforet_millesime(aoi, strategy = "oldest")
bdf <- fev_fetch_bdforet(aoi, millesime = millesime)
} # }
```
