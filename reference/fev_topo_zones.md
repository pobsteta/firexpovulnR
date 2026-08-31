# Topographic zones for downscaling

Cuts a digital elevation model into elevation bands, optionally crossed
with aspect classes, so that weather can be corrected once per zone
rather than once per cell.

## Usage

``` r
fev_topo_zones(dem, n_elev = 8L, n_aspect = 1L, stations = NULL, quiet = FALSE)
```

## Arguments

- dem:

  Elevation: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_dem()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_dem.md),
  a `fev_layer` or a `SpatRaster`.

- n_elev:

  Number of elevation bands. Default 8.

- n_aspect:

  Number of aspect classes, or `1` for none. Aspect is a proxy for
  insolation, which this package cannot use yet: ERA5 supplies no
  radiation to the FWI, so crossing by aspect multiplies the zones
  without changing any input. Left at 1 unless you intend to use the
  zones for something else.

- stations:

  The weather points the downscaling will draw from: a table with `id`,
  `lat` and `long`, or `NULL`. **Supply them.** Without them the zones
  are elevation bands alone, and a band pools cells scattered across the
  whole area under one series — which replaces the reanalysis's
  horizontal variation by the vertical one instead of adding to it.
  Measured on the Maures: bands alone gave 8 distinct FWI values where
  the coarse chain gave 17, so the downscaling made the field *flatter*.
  Crossing the bands with each point's own territory keeps both.

- quiet:

  Suppress the report.

## Value

A `fev_layer` of role `"topo_zone"` holding integer zone ids, with a
`zones` attribute: one row per zone with `zone`, `n_cells`, `elev_mean`,
`elev_min`, `elev_max`, and the representative latitude cffdrs needs.

## Why zones and not cells

The FWI codes are cumulative, so a per-cell downscaling means running
the whole seasonal integration in every cell — 678 000 integrations over
the Maures where the input carries eight distinct values. Zones put the
cost where the information is: a handful of integrations, mapped back
onto the grid. Raising `n_elev` past the point where bands differ by
less than the lapse rate can resolve buys nothing but time.

## Bands are quantiles, not equal intervals

Equal elevation intervals on a massif put nearly every cell in the
lowest band and leave the top ones almost empty, which spends the
integrations where there is no ground. Quantiles give bands of
comparable area. The consequence is that band edges are not round
numbers and change with the area of interest, so zone ids are not
comparable between two runs on different extents — the table returned
says where the edges fell.

## See also

[`fev_downscale_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_downscale_weather.md)
for the correction itself.

## Examples

``` r
g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 2000,
                 ymin = 0, ymax = 2000, crs = "EPSG:2154")
dem <- terra::init(g, "y") / 4
z <- fev_topo_zones(dem, n_elev = 4, quiet = TRUE)
attr(z, "zones")[, c("zone", "n_cells", "elev_mean")]
#>   zone n_cells elev_mean
#> 1    1     100      62.5
#> 2    2     100     187.5
#> 3    3     100     312.5
#> 4    4     100     437.5
```
