# Fire weather from the open Open-Meteo archive

Retrieves the four variables the Canadian Fire Weather Index System
needs — noon temperature, relative humidity, wind speed and 24-hour
precipitation — over a grid of points, **without any API key**.

## Usage

``` r
fev_fetch_weather(
  aoi,
  period,
  spacing = 0.1,
  hour = 12L,
  max_points = 25L,
  cache = TRUE,
  crs_work = 2154
)
```

## Source

Open-Meteo historical weather archive, <https://open-meteo.com/>, which
re-serves ERA5 and ERA5-Land. Endpoint, variable names, units and the
availability of 1991 verified by real calls on 2026-08-17. Multi-point
requests return a JSON array, one object per point — also verified.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

- period:

  Two dates or years bounding the record, e.g.
  `c("1991-01-01", "2020-12-31")`.

- spacing:

  Point spacing in degrees. Defaults to `0.1`, the native resolution of
  ERA5-Land; asking for less does not add information.

- hour:

  Hour to keep, UTC. Defaults to 12.

- max_points:

  Refuse rather than start a job larger than this. Each point is a
  separate series in the response.

- cache:

  Use the on-disk cache. See
  [`fev_cache_dir()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_dir.md).

- crs_work:

  EPSG code recorded for the point grid.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a data frame with one row per point and day — columns `id`,
`lat`, `long`, `yr`, `mon`, `day`, `temp`, `rh`, `ws`, `prec` — which is
exactly the shape
[`fev_fwi_calc()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_calc.md)
consumes. The point grid travels in the `points` field of the source
record.

## Rain is summed, the rest is read

Three of the four inputs are the noon observation. The fourth is not:
the system takes the rainfall **accumulated over the 24 hours ending at
noon**. So hourly precipitation is summed over that window, and one
extra day is fetched at the start of each chunk to fill it. Reading the
noon hour's rain instead throws away 23 hours a day and inflates the
drought codes without making the FWI look wrong — see the note on
saturation in
[`fev_fwi_from_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_from_weather.md).

## Why this exists next to fev_fetch_fwi()

[`fev_fetch_fwi()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_fwi.md)
downloads indices already computed by the CEMS, which is the
authoritative product and needs a personal Copernicus token. This route
needs none, reaches back to 1940, and comes at roughly 0.1° — about 11
km, two and a half times finer than the 0.25° CEMS grid. The trade is
that the indices are then computed here by `cffdrs` rather than by
ECMWF, and that a third-party service sits between the reanalysis and
you.

Use CEMS when you have a token and want the reference product. Use this
when you do not, or when you want a finer grid, and say which you used.

## Noon, not daily aggregates

The FWI system is defined on **noon local standard time** observations.
This function requests hourly data and keeps the noon hour, rather than
substituting daily maximum temperature and minimum humidity as
operational implementations often do. That is exact but wasteful: 24
hours are transferred for each one kept. A 30-year record over nine
points is of the order of 90 MB of transfer, which is why the result is
cached and the request is chunked by year.

## Wind is already in km/h

Open-Meteo serves `wind_speed_10m` in kilometres per hour, which is what
the system wants — unlike E-OBS, whose `FG` is in metres per second and
is the classic way to get FWI wrong by a factor of 3.6.

## See also

[`fev_fwi_from_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_from_weather.md)
to turn this into a dated FWI raster,
[`fev_fetch_fwi()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_fwi.md)
for the CEMS product.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
w <- fev_fetch_weather(aoi, period = c("2021-01-01", "2021-12-31"))
head(fev_data(w))
} # }
```
