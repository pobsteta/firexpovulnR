# Fuel metrics from a LiDAR point cloud

Inverts a point cloud into a vertical bulk density profile and derives
the fuel metrics that describe what nothing else in this package can
see: the understorey.

## Usage

``` r
fev_fuel_lidar(
  las,
  res = 25,
  min_pulse_density = 10,
  metrics = NULL,
  profile = FALSE,
  lma = 140,
  wd = 591,
  threshold = 0.02,
  millesime = NA,
  ...
)
```

## Source

`lidarforfuel` 1.0.0.9001, Olivier Martin's team at INRAE,
<https://github.com/oliviermartin7/LidarForFuel>. Note the package is
installed as `lidarforfuel`, lowercase, not as its repository name.
Method published as *Unlocking the potential of Airborne LiDAR for
direct assessment of fuel bulk density and load distributions for
wildfire hazard mapping*. Signatures, band order, band count and the
`-1` null value verified on 2026-08-17 by reading the installed source
and by running it; see `specs/phase8-rapport-lidar.md`.

Evaluated by its authors against field plots in France, Spain and
Portugal — which is what makes it preferable here to a North American
equivalent.

## Arguments

- las:

  A `LAS`, a path, or a URL to a COPC tile. COPC is readable over HTTP,
  so a small extent needs no download.

- res:

  Output cell size in metres. 25 m matches the rest of the chain; below
  about 10 m most cells fall under `lidarforfuel`'s own minimum point
  count and come back empty.

- min_pulse_density:

  Warn below this, in pulses/m². Defaults to 10, the LiDAR HD
  specification. Legitimately 5 above 3200 m of altitude.

- metrics:

  Which metrics to keep. `NULL` gives the fuel subset, `"all"` gives all
  25.

- profile:

  Keep the 150-layer bulk density profile as well.

- lma, wd:

  Leaf mass per area (g/m²) and wood density (kg/m³).

- threshold:

  Bulk density above which a layer counts as fuel, kg/m³.

- millesime:

  Acquisition vintage, for the provenance record.

- ...:

  Passed to
  [`lidarforfuel::fCBDprofile_fuelmetrics()`](https://rdrr.io/pkg/lidarforfuel/man/fCBDprofile_fuelmetrics.html).

## Value

A `fev_fuel_source` of type `"lidarhd"` with its continuous register
populated.

## What comes out

A `fev_fuel_source` whose **continuous** register holds one layer per
metric. By default the fuel-relevant subset — canopy and understorey
loads, crown base height, fuel strata gap, bulk density, cover, plant
area index. The full 25 diagnostics and the 150-layer bulk density
profile are available on request; a register of 175 layers is rarely
what anyone wants.

## On the band names, which the upstream README gets wrong

`lidarforfuel` returns 175 bands: 25 named metrics then `CBD_1` to
`CBD_150`. Its README says 173 with 23 metrics. Reading the profile from
band 24 on that basis takes `Cover_4` and `Cover_6` for bulk density and
shifts everything by two. This function never indexes positionally — it
checks the names it got against the names it expects and refuses if they
differ, so a change upstream surfaces as an error rather than as
plausible wrong numbers.

## The null value is -1, not NA

Every metric comes back as `-1` when the computation does not complete —
typically too few points in the pixel. Left alone that gives negative
crown base heights and negative fuel loads, which pass any naive
plausibility check. They are converted to `NA` here.

## Density control, which is not optional

Pulse density is measured and recorded for every cloud, and the function
warns with the number below `min_pulse_density`. The reason is in
[`fev_lidar_density()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidar_density.md):
thinning does not blur the answer, it biases it towards a safer
landscape than the real one.

## Parameters imported from lidarforfuel

`lma` (leaf mass per area, 140 g/m²) and `wd` (wood density, 591 kg/m³)
are that package's defaults. They are **species values**, they were not
traced to a primary source, and they scale the fuel loads directly — a
stand whose actual LMA is half of 140 has its load overestimated by a
factor of two. Override them for your species, and they go into the
provenance either way.

## See also

[`fev_fuel_attach()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_attach.md)
to graft this onto a categorical fuel source,
[`fev_lidar_density()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidar_density.md),
[`fev_fetch_lidarhd()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_lidarhd.md).

## Examples

``` r
if (FALSE) { # \dontrun{
idx <- fev_lidarhd_available(aoi)
tiles <- fev_fetch_lidarhd(idx, max_tiles = 1)
fuel_lidar <- fev_fuel_lidar(fev_data(tiles)$path[1], res = 25)
fev_fuel_registers(fuel_lidar)
names(fev_fuel_continuous(fuel_lidar))
} # }
```
