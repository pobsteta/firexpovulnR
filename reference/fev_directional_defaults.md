# Directional vulnerability defaults

Parameters of the directional assessment of Beverly and Forbes (2023):
radial transects drawn outward from a value, each split into three
segments, and judged viable where they intersect enough high-exposure
ground.

## Usage

``` r
fev_directional_defaults()
```

## Source

Beverly, J.L., Forbes, A.M. (2023). Assessing directional vulnerability
to wildfire. *Natural Hazards* 117: 831-849. Not read directly;
parameters and their empirical justification verified against the
`fireexposuR` 1.2.0 reference documentation on 2026-08-16.

## Value

A named list of the defaults.

## These two thresholds are empirical, not conventional

`thresh_exp = 0.6` comes from the observation that fires burned
preferentially where exposure exceeded 60%. `thresh_viable = 0.8` comes
from observed burned pathways, whose average intersection with pre-fire
high-exposure patches was 80%. Both were measured on Canadian
landscapes. Unlike the fuel availability weights of
[`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md),
they are sourced — they are simply sourced from somewhere else.

## Examples

``` r
fev_directional_defaults()
#> $seg_lengths
#> [1] 5000 5000 5000
#> 
#> $interval
#> [1] 1
#> 
#> $thresh_exp
#> [1] 0.6
#> 
#> $thresh_viable
#> [1] 0.8
#> 
#> $source
#> [1] "Beverly & Forbes 2023 (Natural Hazards 117:831-849)"
#> 
```
