# Fuel correspondence tables

Returns the table that maps a land cover nomenclature onto the package's
fuel vocabulary: which classes are burnable, and what structural fuel
type each one is.

## Usage

``` r
fev_fuel_lookup(type = c("bdforet_v2", "clc", "clcplus"), file = NULL)
```

## Source

BD Forêt v2 TFV codes and labels: IGN, the 32 posts published by
cartes.gouv.fr, cross-checked against the attributes served by the
Géoplateforme WFS on 2026-08-15.

CORINE level 3 codes and labels: Copernicus Land Monitoring Service, CLC
nomenclature guidelines,
<https://land.copernicus.eu/content/corine-land-cover-nomenclature-guidelines/html/>,
verified 2026-08-16 against the 2019 illustrated guidelines, which agree
on all 44 rows.

CLCplus Backbone codes and labels: European Environment Agency catalogue
record for the 2023 vintage,
[doi:10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2](https://doi.org/10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2)
, verified 2026-08-18. Nomenclature derived from the EAGLE Land Cover
Components.

## Arguments

- type:

  Nomenclature to load: `"bdforet_v2"`, `"clc"` or `"clcplus"`. Both
  land cover tables are vintage-independent, so `"clc_2018"` and
  `"clcplus_2023"` resolve to `"clc"` and `"clcplus"`.

- file:

  Optional path to a CSV of your own, replacing the shipped table
  entirely. It must have columns `code`, `fuel_type` and `burnable`;
  `nomenclature`, `label`, `crown_cover`, `confidence` and `notes` are
  filled with `NA` when absent. `fuel_type` values must come from
  [`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md).

## Value

A data frame with columns `nomenclature`, `code`, `label`,
`crown_cover`, `fuel_type`, `burnable`, `confidence`, `notes`.

## What is sourced here and what is not

`code` and `label` are the producers' own values, verified at their
source (phase 2 report, sections 3 and 7). `crown_cover` is read off the
BD Forêt v2 nomenclature itself — *forêt fermée* is above 40% tree
cover, *forêt ouverte* between 10 and 40%.

`fuel_type` and `burnable` are **this package's reading**, not an
imported classification. Every row carries a `confidence` flag
(`"clear"` or `"ambiguous"`) and a `notes` sentence stating what the
doubt is. 4 of the 32 BD Forêt rows and 17 of the 44 CORINE rows are
flagged ambiguous — read them before running an analysis you intend to
publish.

## The rows most likely to be wrong for you

Agricultural CORINE classes (211, 221, 222, 223, 231, 241, 242) default
to `burnable = FALSE`, on the grounds that a worked field neither
carries fire nor throws embers for most of the year. Stubble fires,
abandoned olive groves and ungrazed pasture all break that assumption.
Override the table if your study area sits on a crop-forest interface.

CORINE 334 (burnt areas) is burnable at the vintage of the CORINE layer,
not at your analysis date — Mediterranean shrubland regrowth is among
the most flammable states there is by year five.

## See also

[`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md)
for the vocabulary,
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md)
and
[`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md)
for the functions that consume these tables.

## Examples

``` r
bdf <- fev_fuel_lookup("bdforet_v2")
nrow(bdf)
#> [1] 32
bdf[bdf$confidence == "ambiguous", c("code", "label", "notes")]
#>         code                                  label
#> 1        FF0       Forêt fermée sans couvert arboré
#> 2     FF1-00 Forêt fermée de feuillus purs en îlots
#> 8  FF1-49-49    Forêt fermée d'un autre feuillu pur
#> 26       FO0      Forêt ouverte sans couvert arboré
#>                                                                                                                                                                                                                                                                                                                            notes
#> 1  Clearcut or disturbance inside closed forest. Burnable is a judgement call: fresh logging slash is among the most flammable states a stand ever reaches, while a scraped or replanted cut carries almost nothing. The database does not say which, and gives no date. Flagged TRUE because slash is the more dangerous error.
#> 2                                                Broadleaf islets. The dominant species is not stated, so evergreen sclerophyll stands (holm oak, cork oak) cannot be separated from deciduous ones -- a distinction that matters for flammability. Defaults to the deciduous reading, which is the more common case nationally.
#> 8                                                                                                               Catch-all for pure broadleaf stands of any other species. The species is unknown by construction, so the fuel type is a default, not a determination. Override this row if your study area has a known dominant.
#> 26                                                                                                                                                                                                                                                                   Open forest with no tree cover left. Same reasoning as FF0.

clc <- fev_fuel_lookup("clc")
table(clc$fuel_type, clc$burnable)
#>                      
#>                       FALSE TRUE
#>   agroforestry            0    1
#>   broadleaf_closed        0    1
#>   burnt_regrowth          0    1
#>   conifer_closed          0    1
#>   cropland                9    0
#>   grassland               0    1
#>   mixed_closed            0    1
#>   mosaic_agri_natural     0    1
#>   non_fuel               22    0
#>   shrubland               0    2
#>   sparse_vegetation       0    1
#>   transitional_shrub      0    1
#>   urban_vegetation        0    2

# CLCplus splits what CORINE 311 could not: deciduous from evergreen
# broadleaf, which is the sclerophyll distinction the Mediterranean needs.
cpl <- fev_fuel_lookup("clcplus")
cpl[cpl$code %in% c("3", "4"), c("code", "label", "fuel_type")]
#>   code                               label          fuel_type
#> 3    3 Woody - broadleaved deciduous trees   broadleaf_closed
#> 4    4 Woody - broadleaved evergreen trees sclerophyll_closed
```
