# Structural fuel type

Maps class codes onto the package's shared fuel-type vocabulary, so that
a layer merged from two nomenclatures can be read as one thing.

## Usage

``` r
fev_fuel_type(x, lookup = NULL)
```

## Arguments

- x:

  A `fev_fuel_source`.

- lookup:

  Correspondence table. Defaults to the one carried by `x`.

## Value

A `fev_fuel_layer` holding a categorical `SpatRaster` named `fuel_type`.

## Register consumed

Categorical.

## This is a relabelling, not a fuel model

The types describe stand structure — closed conifer, open broadleaf,
shrubland — because structure is what BD Forêt and CORINE record. They
are not Anderson, Scott & Burgan or Prometheus fuel models, and no
correspondence to those is shipped: deriving one needs understorey and
load information neither database contains. That is the `medfate`
extension point, and the reason the continuous register exists.

## See also

[`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md)
for the vocabulary.

## Examples

``` r
r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
terra::values(r) <- rep(1:2, 8)
levels(r) <- data.frame(id = 1:2, class = c("FF1G06-06", "LA4"))
fuel <- fev_fuel_source(r, type = "bdforet_v2", millesime = 2014)
ft <- fev_fuel_type(fuel)
terra::levels(fev_data(ft))[[1]]
#>   id              class
#> 1  1 sclerophyll_closed
#> 2  2          shrubland
```
