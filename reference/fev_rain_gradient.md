# Is there an orographic rain gradient in these points at all?

Regresses each point's mean precipitation on its elevation and reports
whether the result is worth using. Called by
[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md)
when `rain = "fitted"`, and exported because the answer is worth knowing
before deciding.

## Usage

``` r
fev_rain_gradient(weather, p_max = 0.05)
```

## Arguments

- weather:

  A weather table, as
  [`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md)
  returns.

- p_max:

  Significance the slope must reach to be considered usable. Default
  0.05.

## Value

A list with `slope` (mm per metre of elevation), `relative` (fraction of
the mean per 1000 m), `r_squared`, `p_value`, `n_points`, `elev_range_m`
and `usable`.

## Why fit rather than import a coefficient

Published orographic coefficients exist — MicroMet carries monthly ones
from the western United States. Importing them here would put a number
in the provenance derived from a different continent's topography and
storm tracks. The reanalysis points already sit at different elevations;
if there is a gradient in them, it is this analysis's own gradient.

## What it found on the Maures, and why that is the useful case

Twenty points spanning 464 m of elevation: R² = 0.087, p = 0.21. **No
usable gradient.** That is not a disappointing result, it is the
function working: the reanalysis does not resolve orographic enhancement
over a massif this small, and a correction fitted anyway would have been
fitted to noise and would have travelled in the provenance looking like
a measurement.

## See also

[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md).

## Examples

``` r
w <- data.frame(id = rep(letters[1:6], each = 3),
                elev_m = rep(c(10, 60, 110, 160, 210, 260), each = 3),
                prec = rep(c(1, 1.2, 1.4, 1.6, 1.8, 2), each = 3))
fev_rain_gradient(w)$usable
#> Warning: essentially perfect fit: summary may be unreliable
#> Warning: essentially perfect fit: summary may be unreliable
#> [1] TRUE
```
