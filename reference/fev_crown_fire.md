# Van Wagner's crown fire thresholds

Two questions, two criteria, and the package now measures the input to
both: does a surface fire climb into the canopy, and once up does it
keep going.

## Usage

``` r
fev_crown_fire(
  cbh,
  cbd = NULL,
  fmc = 100,
  intensity = NULL,
  spread_rate = NULL,
  quiet = FALSE
)
```

## Source

Van Wagner, C. E. (1977), as formulated by Scott and Reinhardt (2001),
USDA Forest Service Research Paper RMRS-RP-29, equations 11 and 14.

Verified on 2026-08-21 against the paper's own worked examples, which is
a stronger check than reading the equations: CBH 3 m at 100% FMC gives
**875 kW/m**, and CBD 0.2 kg/m³ gives **15.0 m/min**. Both reproduce
exactly.

The paper's figure 5 caption states the critical mass flow rate as 0.05
kg m-2 **min**-1 where its text says 0.05 kg m-2 **sec**-1. The text is
right — 0.05 kg/m²/s times 60 gives the 3.0 of equation 14 — and the
caption is a slip in the source.

## Arguments

- cbh:

  Crown base height, m. A `SpatRaster`, `fev_layer` or number —
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
  produces `CBH`.

- cbd:

  Canopy bulk density, kg/m³, as
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
  produces `CBD_max`. Optional; without it only the initiation threshold
  is returned.

- fmc:

  Foliar moisture content, percent. Default 100, the value Scott and
  Reinhardt use in their worked example. It is a season and a species,
  not a constant, and it is recorded.

- intensity:

  Surface fireline intensity, kW/m, from
  [`fev_byram_intensity()`](https://pobsteta.github.io/firexpovulnR/reference/fev_byram_intensity.md).
  Optional; with it the result says whether the threshold is passed
  rather than only where it sits.

- spread_rate:

  Forward rate of spread, m/min. Optional; with `cbd` it says whether
  active crowning can be sustained.

- quiet:

  Suppress the standing caveat.

## Value

A `SpatRaster` or numeric vector with `i_initiation` (kW/m) and, when
`cbd` is given, `r_active` (m/min). With `intensity` or `spread_rate`,
the logical layers `crowns` and `active` are added.

## Initiation, decided by crown base height

A surface fire crowns when its intensity exceeds
`[CBH (460 + 25.9 FMC) / 100]^1.5`. Low crowns crown easily: at 100%
foliar moisture, 1 m of clearance needs 168 kW/m and 6 m needs 2 476 — a
factor of fifteen for a factor of six in height.

This is why the FSG and CBH the LiDAR campaign measures matter more than
the species. Measured over 48 windows on the Maures, **84% of forested
cells have a crown base height of exactly zero**: the crowns reach the
ground, and the clearance that would stop a surface fire is not there.
Nine of the eleven classes present have a median CBH of zero, so the
class does not tell you which cells those are.

## Propagation, decided by canopy bulk density

Once in the canopy, active spread needs a mass flow of fuel into the
flaming zone, so the fire must move at least `3.0 / CBD` m/min. A dense
canopy sustains crowning at a slower spread rate; a sparse one needs the
fire to run.

The Maures measurements put class median CBD_max between 0.041 and 0.244
kg/m³, which is a critical spread rate between 73 and 12 m/min — a range
wide enough that the answer genuinely depends on the stand. Cell by cell
the spread is wider still, 0.02 to 0.99.

## What this is not

A threshold, not a damage function. It says whether a crown fire is
possible, not what it destroys. And both criteria are Van Wagner's,
developed on Canadian conifers: nothing here has been calibrated on cork
oak or maquis, any more than the exposure radii were.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
for the measurements this consumes,
[`fev_byram_intensity()`](https://pobsteta.github.io/firexpovulnR/reference/fev_byram_intensity.md)
for the intensity.

## Examples

``` r
# The paper's own examples.
fev_crown_fire(cbh = 3, fmc = 100, quiet = TRUE)[["i_initiation"]]
#> [1] 875.249
fev_crown_fire(cbh = 3, cbd = 0.2, quiet = TRUE)[["r_active"]]
#> [1] 15
```
