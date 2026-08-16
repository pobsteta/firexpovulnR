# Fire Weather Index from weather forcings

Computes the Canadian Fire Weather Index System codes and indices —
FFMC, DMC, DC, ISI, BUI, FWI and DSR — from daily noon weather, wrapping
[`cffdrs::fwi()`](https://rdrr.io/pkg/cffdrs/man/fwi.html) for tabular
input and
[`cffdrs::fwiRaster()`](https://rdrr.io/pkg/cffdrs/man/fwiRaster.html)
for gridded input.

## Usage

``` r
fev_fwi_calc(
  weather,
  init = c(ffmc = 85, dmc = 6, dc = 15),
  months = NULL,
  lat_adjust = TRUE,
  out = "all"
)
```

## Source

`cffdrs` 1.9.2, Wang, Cantin, Parisien, Wotton, Anderson and Flannigan.
Startup values and argument defaults read from the installed package on
2026-08-16. The underlying system is Van Wagner, C.E. (1987),
*Development and structure of the Canadian Forest Fire Weather Index
System*, Forestry Technical Report 35, Canadian Forestry Service — cited
as the origin of the method, not read for this implementation.

## Arguments

- weather:

  Daily noon weather. Either a `data.frame` with columns `temp`, `rh`,
  `ws`, `prec`, `lat` (and optionally `long`, `yr`, `mon`, `day`, `id`),
  a `SpatRaster` with layers named `temp`, `rh`, `ws`, `prec` for a
  single day, or a list of such `SpatRaster` for consecutive days.

- init:

  Startup values. See the section above.

- months:

  Month of each gridded step, `1`-`12`, used for the day-length
  adjustment. Length 1 or one per element of `weather`.

- lat_adjust:

  Apply the latitude day-length adjustment. Leave `TRUE` unless you have
  a reason.

- out:

  Passed to `cffdrs`: `"all"` keeps the inputs alongside the indices,
  `"fwi"` returns the indices only.

## Value

A `fev_danger_layer` for gridded input, or a `data.frame` for tabular
input, in both cases carrying the parameters in its provenance.

## Units, which are where this goes wrong

The system expects **noon local standard time** observations, in `temp`
degrees Celsius, `rh` percent, `ws` **kilometres per hour** and `prec`
millimetres accumulated over the preceding 24 hours. Wind in metres per
second is the classic mistake and produces indices that look entirely
reasonable; this function warns when the wind distribution suggests it,
but it cannot know. Check your source.

## Latitude is required, and why, exactly

`cffdrs` defaults a missing latitude to 55°N and a missing longitude to
120°W — central British Columbia — with a warning that is easy to miss
in a loop. Latitude drives the day-length adjustment in DMC and DC.

Measured on the installed package (2026-08-16), that adjustment is
**banded**, not continuous: 43.3°N, 51°N and 55°N give bit-identical
codes, because metropolitan France and central British Columbia sit in
the same ≥ 30°N band. So for a study in metropolitan France the
substitution happens to be harmless.

It is not harmless anywhere else. At 20°N — Guadeloupe, Martinique — ten
rainless days give a DMC 16% lower and a DC 26% lower than the
substituted 55°N would; in the southern hemisphere, Réunion at 21°S, the
gap is larger again. A default that is correct in the place you wrote
the script and wrong in the place you copy it to is worse than no
default, so this function **refuses** input without `lat` instead of
substituting one.

## Startup values

`init` defaults to `ffmc = 85`, `dmc = 6`, `dc = 15` — the spring
startup values `cffdrs` ships, read from the installed package. They
originate in the Canadian system's specification (Van Wagner 1987) and
assume a snow-melt spring startup, which much of Mediterranean France
does not have. If your series starts mid-season, or in a climate without
a defined startup, carry the codes over from a spin-up period instead of
accepting these.

## On a sequence of grids

The moisture codes are cumulative: each day's FFMC, DMC and DC depend on
the previous day's.
[`cffdrs::fwiRaster()`](https://rdrr.io/pkg/cffdrs/man/fwiRaster.html)
computes **one day**. Pass a list of daily `SpatRaster` and this
function iterates, feeding each day's codes into the next, which is the
part callers usually get wrong by re-initialising every day.

## See also

[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md),
which is what makes these numbers comparable between climates, and
[`fev_fetch_fwi()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_fwi.md)
for the CEMS indices.

## Examples

``` r
w <- data.frame(
  lat = 43.3, long = 6.4, yr = 2020, mon = 7, day = 1:5,
  temp = c(25, 28, 30, 31, 29), rh = c(40, 35, 30, 28, 33),
  ws = c(10, 12, 15, 20, 11), prec = c(0, 0, 0, 0, 2)
)
out <- fev_fwi_calc(w)
out$FWI
#> [1]  6.634547 11.183450 17.121411 24.640454 10.307107
```
