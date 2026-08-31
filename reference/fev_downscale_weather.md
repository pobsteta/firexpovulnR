# Correct weather to the elevation of each topographic zone

Produces one weather series per zone, with temperature moved by the
environmental lapse rate and relative humidity following from it at
constant dewpoint. The result is the exact shape
[`fev_fwi_calc()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_calc.md)
expects, so the FWI accumulates per zone from corrected inputs rather
than being adjusted after the fact.

## Usage

``` r
fev_downscale_weather(
  weather,
  zones,
  lapse_rate = 6.5,
  wind = c("none", "curvature"),
  curvature = NULL,
  curve_weight = 0.5,
  rain = c("none", "fitted"),
  quiet = FALSE
)
```

## Arguments

- weather:

  A weather table as
  [`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md)
  returns, or a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  holding one. Needs `elev_m`, the elevation the reanalysis thinks each
  point sits at, without which there is nothing to correct *from*.

- zones:

  A `fev_layer` from
  [`fev_topo_zones()`](https://pobsteta.github.io/firexpovulnR/reference/fev_topo_zones.md).

- lapse_rate:

  Kelvin per kilometre, positive for cooling with height. Default 6.5.

- wind:

  `"none"` (default) or `"curvature"`. The second applies the MicroMet
  terrain weighting through
  [`fev_curvature()`](https://pobsteta.github.io/firexpovulnR/reference/fev_curvature.md),
  which needs `curvature`. **Only the curvature half of the published
  scheme**: its slope term needs a wind direction and this package
  fetches none.

- curvature:

  A `fev_layer` from
  [`fev_curvature()`](https://pobsteta.github.io/firexpovulnR/reference/fev_curvature.md),
  on the zone grid. Required when `wind = "curvature"`.

- curve_weight:

  Weight on the curvature term, `gamma_c` in Liston and Elder. Default
  0.5, their default. A ridge then carries 1.25 times the reanalysis
  wind and a hollow 0.75 times.

- rain:

  `"none"` (default) or `"fitted"`. The second asks
  [`fev_rain_gradient()`](https://pobsteta.github.io/firexpovulnR/reference/fev_rain_gradient.md)
  whether these points show an orographic gradient and **applies nothing
  if they do not** — saying so rather than fitting noise.

- quiet:

  Suppress the report.

## Value

A data frame in
[`fev_fwi_calc()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_calc.md)'s
input shape, one `id` per zone, with `elev_m` set to the zone's mean
elevation and a `zone` column.

## What is corrected and what is not

**Temperature** moves with the lapse rate. **Humidity** follows, because
cooling air at constant water content raises its relative humidity —
that is thermodynamics, not a fitted relation.

**Wind and rain are passed through unchanged.** Topographic exposure and
orographic enhancement are both real and neither has a calibration this
package can defend on a Mediterranean massif. Inventing a multiplier for
either would put a number in the provenance that nobody could justify.
The consequence is precise and must be read: ISI keeps the coarse wind
signal, DMC and DC keep the coarse rain signal, and it is the fine-fuel
path — FFMC, and FWI through it — that gains structure.

## It helps a raw-FWI chain and hurts a percentile one

Measured on the Maures for 16 August 2021 over 597 840 cells,
decomposing the composite risk into its two terms:

|  |  |  |  |
|----|----|----|----|
| chain | sd(danger) | cor(risk, danger) | cor(risk, vulnerability) |
| coarse, percentile | 0.308 | **0.879** | 0.833 |
| coarse, raw FWI + minmax | 0.237 | 0.699 | 0.769 |
| downscaled, raw FWI + minmax | 0.249 | **0.801** | 0.827 |
| downscaled, percentile | 0.003 | 0.479 | 1.000 |

Downscaling lifts a raw-FWI chain — 0.699 to 0.801 — and **wrecks a
percentile one**, and the reason is structural rather than incidental.

A lapse rate is a **monotone** transform of a zone's whole series.
Shifting a series by a near-constant offset barely changes where any one
day ranks inside it. Every zone inherits a history that is a
deterministic transform of its parent reanalysis cell's, so every zone
ranks 16 August at nearly the same percentile and the spatial contrast
collapses: the standard deviation falls to 0.003.

What the coarse percentile chain has, and this destroys, is genuine:
distinct reanalysis cells carry distinct climatologies, and ranking
today against each one says where today is most exceptional. That is
information about local climate, not an artefact of cell boundaries.

So the two answer different questions and want different inputs. *Where
is it worst today* wants a downscaled raw FWI with
`normalise = "minmax"`. *Where is today most unusual* wants the
percentile, and has no use for a monotone correction.

## The lapse rate is a constant and the atmosphere is not

6.5 K/km is the ICAO standard mean. The real rate runs from about 9.8
K/km in dry unstable air to near zero, and **inverts** during
Mediterranean summer nights, when cold air pools in the valleys and the
slope above is warmer than the floor. The FWI takes noon conditions,
when inversions have usually broken, which is the argument for using a
mean rate here — not that it is always right, but that it is right at
the hour the index reads.

Pass your own `lapse_rate` if you have one for your season and site. It
is recorded either way.

## See also

[`fev_topo_zones()`](https://pobsteta.github.io/firexpovulnR/reference/fev_topo_zones.md),
[`fev_fwi_zonal()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_zonal.md)
to run the FWI on the result.

## Examples

``` r
if (FALSE) { # \dontrun{
dem <- fev_fetch_dem(zone)
z <- fev_topo_zones(fev_data(dem))
w <- fev_downscale_weather(meteo, z)
danger <- fev_fwi_zonal(w, z, dates = as.Date("2021-08-16"))
} # }
```
