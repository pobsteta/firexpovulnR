# The vocabulary of fuel types

The closed set of structural fuel types the shipped correspondence
tables map onto, with what each one means. Both nomenclatures — BD Forêt
v2 TFV and CORINE level 3 — resolve to this single vocabulary, which is
what makes a merged layer interpretable when its pixels come from two
sources.

## Usage

``` r
fev_fuel_types()
```

## Value

A data frame with columns `fuel_type` and `description`.

## Why structural, and not a fuel model

These types describe stand structure, because structure is what the two
databases actually record. They are **not** fuel models: no
correspondence to Anderson 13, Scott & Burgan 40 or the Prometheus
models is shipped, because none was verified at a source. Deriving a
fuel model needs understorey and load information neither database
contains — that is the `medfate` extension point, and in the longer run
the LiDAR one.

## See also

[`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
for the tables that use this vocabulary.

## Examples

``` r
fev_fuel_types()
#>              fuel_type
#> 1   sclerophyll_closed
#> 2     broadleaf_closed
#> 3       conifer_closed
#> 4         mixed_closed
#> 5       broadleaf_open
#> 6         conifer_open
#> 7           mixed_open
#> 8    poplar_plantation
#> 9            unstocked
#> 10           shrubland
#> 11  transitional_shrub
#> 12           grassland
#> 13        agroforestry
#> 14 mosaic_agri_natural
#> 15   sparse_vegetation
#> 16      burnt_regrowth
#> 17    urban_vegetation
#> 18            cropland
#> 19            non_fuel
#>                                                       description
#> 1     Closed evergreen sclerophyllous forest (holm oak, cork oak)
#> 2                Closed broadleaf forest, predominantly deciduous
#> 3                                        Closed coniferous forest
#> 4                                Closed broadleaf/conifer mixture
#> 5                        Open broadleaf forest, 10-40% tree cover
#> 6                       Open coniferous forest, 10-40% tree cover
#> 7                            Open mixed forest, 10-40% tree cover
#> 8             Poplar plantation on alluvial ground, managed floor
#> 9  Forest land with no current tree cover (clearcut, disturbance)
#> 10                                  Heath, moor, maquis, garrigue
#> 11         Regeneration and encroachment shrub, a transient state
#> 12                                           Herbaceous formation
#> 13        Scattered trees over grazed grassland (dehesa, montado)
#> 14       Agriculture with significant areas of natural vegetation
#> 15                                     Under 50% vegetation cover
#> 16                             Burnt at the vintage of the source
#> 17       Parks, campsites and leisure grounds inside urban fabric
#> 18                                       Worked agricultural land
#> 19                                  Sealed, mineral, water or ice
```
