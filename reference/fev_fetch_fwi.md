# Fetch CEMS fire danger indices

Downloads Canadian Fire Weather Index System indices from the Copernicus
Emergency Management Service historical reconstruction, hosted on the
Early Warning Data Store (EWDS) and driven by ERA5 reanalysis.

## Usage

``` r
fev_fetch_fwi(
  aoi,
  period,
  product = c("fire_weather_index", "fine_fuel_moisture_code", "duff_moisture_code",
    "drought_code", "initial_spread_index", "build_up_index",
    "fire_daily_severity_index"),
  grid = "0.25/0.25",
  dataset = "cems-fire-historical-v1",
  user = "ecmwfr",
  path = NULL,
  transfer = TRUE
)
```

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS. Converted to a lon/lat bounding box for the request.

- period:

  Two-element vector of dates or years bounding the request, e.g.
  `c("1991-01-01", "2020-12-31")`.

- product:

  Character vector of indices to retrieve. Defaults to the Canadian FWI
  system set.

- grid:

  Request grid as `"lat/lon"` degrees. Explicit on purpose.

- dataset:

  EWDS dataset identifier.

- user:

  `ecmwfr` user id.

- path:

  Directory for the downloaded file. Defaults to the package cache.

- transfer:

  Perform the download. `FALSE` builds and returns the request without
  contacting the service — useful to inspect exactly what would be sent.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a `SpatRaster` of the requested indices. When
`transfer = FALSE`, the request list is returned instead.

## Credentials

The EWDS needs a personal Copernicus API token. The package never
handles it: it reads `ECMWF_KEY` from the environment (set it in
`~/.Renviron`), or falls back to whatever `ecmwfr` already has in its
keyring. **Never put a token in a script or commit one.**

    # in ~/.Renviron
    ECMWF_KEY=your-token-here

## Resolution, and why it matters here more than elsewhere

The reanalysis is on a 0.25° grid — roughly 20-30 km at French
latitudes. Fuel-derived exposure is at 20-100 m. **That is a ratio of
several hundred**, and it is the central methodological difficulty of
the whole chain. Nothing in this function hides it: combining these
layers with anything else goes through
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md),
which warns and records the ratio.

Note also that the EWDS request examples use `grid = "0.5/0.5"` while
the dataset overview announces 0.25° for the reanalysis. The discrepancy
is unresolved upstream, so `grid` is an explicit argument here rather
than a hidden default.

## Verification status

The dataset identifier, service name and variable names were read from
the EWDS documentation and from the `ecmwfr` source on 2026-08-15. **No
live request has been made from this package**, because that requires a
personal token. Treat the first real call as part of your own
validation, and check that what comes back matches what you asked for.

## See also

[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
to turn raw indices into regional percentile ranks, which is what makes
them comparable across climates.

## Examples

``` r
# Inspect the request that would be sent, without any credentials:
aoi <- sf::st_as_sfc(sf::st_bbox(
  c(xmin = 6.2, ymin = 43.1, xmax = 6.6, ymax = 43.4), crs = sf::st_crs(4326)
))
req <- fev_fetch_fwi(aoi, period = c("2020-01-01", "2020-12-31"),
                     transfer = FALSE)
req$dataset_short_name
#> [1] "cems-fire-historical-v1"
req$variable
#> [1] "fire_weather_index"        "fine_fuel_moisture_code"  
#> [3] "duff_moisture_code"        "drought_code"             
#> [5] "initial_spread_index"      "build_up_index"           
#> [7] "fire_daily_severity_index"
```
