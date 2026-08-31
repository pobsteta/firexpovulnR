# Byram's fireline intensity

Turns a fuel load and a rate of spread into an intensity in kW/m — the
unit every published damage and mortality curve expects, and the one
this package has never produced.

## Usage

``` r
fev_byram_intensity(fuel_load, spread_rate, heat_yield = 18000)
```

## Source

Scott, J. H. and Reinhardt, E. D. (2001). *Assessing crown fire
potential by linking models of surface and crown fire behavior*. USDA
Forest Service Research Paper RMRS-RP-29, equation 1, after Byram
(1959).

Read from the paper on 2026-08-21, not from a summary.

## Arguments

- fuel_load:

  Fuel consumed in the flaming front, kg/m². A `SpatRaster`, `fev_layer`
  or number.

- spread_rate:

  Forward rate of spread, m/min.

- heat_yield:

  Heat yield of the fuel, kJ/kg. Default 18000, the value Scott and
  Reinhardt assume for canopy fuels after Finney.

## Value

Fireline intensity in kW/m, in the shape of `fuel_load`.

## Why the package needed this

[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
returns a number in `[0, 1]`. No fragility curve takes such a thing:
they take kW/m, or a flame length derived from it. So nothing could be
branched onto the risk layer, and the vulnerability half stayed a
normalised asset density. Byram is the bridge, and the LiDAR campaign
supplies its hardest term —
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
measures crown fuel load in kg/m².

## What it does not know

The **rate of spread** is not measured by anything in this package. It
comes from a spread model — Rothermel, or the Canadian FBP system — fed
by wind, slope and surface fuel. Passing a plausible number here
produces a plausible intensity, and there is no way for the function to
tell the difference. It is recorded, not validated.

And `fuel_load` must be the fuel consumed **in the flaming front**, not
the total load. Scott and Reinhardt are explicit that Byram's "available
fuel" excludes what burns in smouldering combustion. Handing it a total
load overstates the intensity.

## See also

[`fev_crown_fire()`](https://pobsteta.github.io/firexpovulnR/reference/fev_crown_fire.md)
for the thresholds it feeds.

## Examples

``` r
# A crown fuel load of 1 kg/m2 spreading at 15 m/min.
fev_byram_intensity(1, 15)
#> [1] 4500
```
