# Run the FWI per zone and map it back onto the grid

Accumulates the FWI codes independently in each zone — which is what
makes the downscaling mean anything, since the codes carry memory — then
paints the result onto the zone raster.

## Usage

``` r
fev_fwi_zonal(
  weather,
  zones,
  index = "FWI",
  dates = NULL,
  init = c(ffmc = 85, dmc = 6, dc = 15),
  reset = c("none", "annual"),
  reset_month = 1L,
  quiet = FALSE
)
```

## Arguments

- weather:

  A per-zone table from
  [`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md).

- zones:

  The `fev_layer` from
  [`fev_topo_zones()`](https://pobsteta.github.io/firexpovulnR/reference/fev_topo_zones.md)
  the weather was downscaled onto.

- index:

  Which index to map, default `"FWI"`.

- dates:

  Dates to materialise, as `Date`. `NULL` gives every day in the table,
  which on a fine grid over a season is a large object — the function
  says how large before building it.

- init, reset, reset_month:

  As
  [`fev_fwi_from_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_from_weather.md).

- quiet:

  Suppress the report.

## Value

A `fev_danger_layer` on the zone grid, one layer per date.

## Why this does not go through [`fev_fwi_from_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_from_weather.md)

That function places each weather point on a regular longitude/latitude
lattice, because its points are reanalysis cell centres and they form
one. Zone representative points do not, and feeding them to it would
produce a sparse grid of mostly empty cells. Same engine, different
assembly.

## See also

[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md),
[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
for what usually comes next.
