# Default fuel availability weights

A continuous weight in `[0, 1]` per structural fuel type, used by
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
to turn a class layer into a graded one.

## Usage

``` r
fev_fuel_weights(weights = NULL, quiet = FALSE)
```

## Arguments

- weights:

  Optional named numeric vector overriding some or all of the defaults.
  Names must be values of
  [`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md).

- quiet:

  Suppress the warning that these values are conventional. Use it only
  once you have made that clear elsewhere.

## Value

A named numeric vector, one weight per fuel type.

## These numbers are not sourced, and that is the point of this page

Unlike
[`fev_fwi_classes()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_classes.md)
and
[`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md),
**nothing here comes from a publication or a service**. No
fuel-availability weighting for BD Forêt or CORINE classes was verified
at a source during phase 2, and none is invented in the tables. These
are a convention: an ordering the package can defend qualitatively —
Mediterranean shrubland above closed conifer above closed broadleaf,
worked cropland at zero — with the actual numbers chosen to be round
rather than measured.

Treat them as a starting point you are expected to replace. Whatever you
pass to
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
is written into the provenance record, so a reader can see which numbers
produced your results. If you keep these, say so in your methods, and
say that they are conventional.

## Consistency with the burnable mask

A fuel type whose classes are non-burnable in the shipped lookups
carries a weight of exactly 0, so
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
and
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md)
cannot contradict each other. If you override one, check the other.

## See also

[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md),
[`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md).

## Examples

``` r
fev_fuel_weights(quiet = TRUE)
#>           shrubland      conifer_closed  sclerophyll_closed        conifer_open 
#>                1.00                0.95                0.95                0.90 
#>  transitional_shrub        mixed_closed          mixed_open           grassland 
#>                0.90                0.80                0.80                0.70 
#>      burnt_regrowth      broadleaf_open    broadleaf_closed           unstocked 
#>                0.70                0.65                0.60                0.60 
#>        agroforestry mosaic_agri_natural   sparse_vegetation   poplar_plantation 
#>                0.50                0.35                0.30                0.30 
#>    urban_vegetation            cropland            non_fuel 
#>                0.25                0.00                0.00 

# Down-weight closed broadleaf for a study where it is largely beech.
fev_fuel_weights(c(broadleaf_closed = 0.4), quiet = TRUE)
#>           shrubland      conifer_closed  sclerophyll_closed        conifer_open 
#>                1.00                0.95                0.95                0.90 
#>  transitional_shrub        mixed_closed          mixed_open           grassland 
#>                0.90                0.80                0.80                0.70 
#>      burnt_regrowth      broadleaf_open    broadleaf_closed           unstocked 
#>                0.70                0.65                0.40                0.60 
#>        agroforestry mosaic_agri_natural   sparse_vegetation   poplar_plantation 
#>                0.50                0.35                0.30                0.30 
#>    urban_vegetation            cropland            non_fuel 
#>                0.25                0.00                0.00 
```
