# Exposure weighted by wind and slope

The same annulus as
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
split into angular sectors and recombined with weights that make
approach from some directions count more than others: from where the
wind blows, and from downslope.

## Usage

``` r
fev_exposure_aniso(
  fuel,
  radius = NULL,
  wind = NULL,
  kappa_wind = 0,
  dem = NULL,
  kappa_slope = 0,
  n_sectors = 8L,
  type = c("ember", "ember_short", "radiant"),
  no_burn = NULL,
  lookup = NULL,
  na_rm = FALSE,
  trim = NULL,
  filename = "",
  ...,
  quiet = FALSE
)
```

## Arguments

- fuel:

  As
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  takes it.

- radius:

  Annulus radius in CRS units.

- wind:

  Wind direction in degrees, meteorological convention (from). A single
  number, or `NULL` for no wind weighting.

- kappa_wind:

  Concentration of the wind weight. `0` is isotropic; 1 to 2 is a
  moderate bias; above 4 the upwind sectors carry nearly everything.

- dem:

  Elevation for the slope weight: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_dem()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_dem.md),
  a `fev_layer` or a `SpatRaster`, on the fuel grid. `NULL` for no slope
  weighting.

- kappa_slope:

  Concentration of the slope weight, multiplied by `tan(slope)`. `0`
  disables it.

- n_sectors:

  Number of angular sectors. Default 8.

- type, no_burn, lookup, na_rm, trim, filename, quiet, ...:

  As
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md).

## Value

A `fev_layer` of role `"exposure"`, values in `[0, 1]`.

## This is not the published metric

Beverly et al. define exposure isotropically and Khan et al. validated
it isotropically. Directional weighting is a **departure**, it has no
validation of its own, and both concentration parameters are judgements
of the analysis rather than properties of the data — exactly like the
weights of
[`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md).
They are written into the provenance for that reason. Set both to zero
and you get the published metric back, which is the default and the
thing to compare against.

## How the two weights are built

Each sector `k` has a mean bearing. Its weight is the product of two von
Mises-like factors, `exp(kappa * cos(delta))`, normalised over sectors
so they sum to one:

- **Wind.** `delta` is the angle between the sector bearing and the
  direction the wind comes **from** — fire arrives from upwind, so that
  is the direction that must weigh more. `kappa_wind` is constant over
  the map.

- **Slope.** `delta` is the angle between the sector bearing and the
  direction of steepest descent at the assessed cell, which is what
  `terra::terrain(v = "aspect")` returns. Fire runs uphill, so a cell is
  exposed from below. `kappa` here is **not** constant: it is
  `kappa_slope * tan(slope)`, so flat ground gets no anisotropy at all
  and steep ground gets a lot. That is the behaviour you want and it
  falls out of the physics rather than being imposed.

## What it costs

`n_sectors` focal passes, each over roughly `1 / n_sectors` of the ring,
so the weighted-operation count is about the same as the isotropic
version. What is not the same is memory: `n_sectors` intermediate layers
are held at once. Eight sectors on a departmental grid is the point
where `filename` stops being optional.

Eight is the default because 45 degrees is about the angular precision a
wind direction deserves; more sectors buy resolution the input does not
have.

## On wind direction

`wind` is a **meteorological** direction in degrees: the direction the
wind blows *from*, clockwise from north, as
[`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md)
returns it and as every anemometer reports it. A north wind is 0 and
pushes fire southwards, so the exposure it raises is on the northern
side of a cell. Passing a vector direction here — the way the wind goes
— inverts the whole result, and there is no way for the function to
detect it.

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
for the isotropic metric this decomposes,
[`fev_fetch_dem()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_dem.md)
for the terrain,
[`fev_exposure_calibrate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_calibrate.md)
for the radius.

## Examples

``` r
g <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 400,
                 ymin = 0, ymax = 400, crs = "EPSG:2154")
fuel <- terra::setValues(g, rep(rep(c(1, 0), each = 20), 40))
# With no wind and no terrain this is fev_exposure(), by construction.
e <- fev_exposure_aniso(fuel, radius = 60, quiet = TRUE)
terra::global(fev_data(e), "mean", na.rm = TRUE)
#>          mean
#> exposure  0.5
```
