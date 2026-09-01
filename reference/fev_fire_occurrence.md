# Fire occurrence from declared records

Turns the fire records of
[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
into an occurrence layer on a working grid: how often a fire is declared
to start per unit area and per year. This is the **ignition** term of
the hazard, which the rest of the package does not otherwise carry.

## Usage

``` r
fev_fire_occurrence(
  fires,
  template,
  communes = NULL,
  communes_key = NULL,
  period = NULL,
  measure = c("rate", "count", "burnt_rate"),
  denominator = c("area", "fuel"),
  fuel = NULL,
  lookup = NULL,
  min_area_ha = 0,
  output = c("raster", "communes"),
  quiet = FALSE
)
```

## Arguments

- fires:

  Fire records **carrying geometry**: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
  called with `communes`, or the `sf` itself. Records without geometry
  are refused, with the reason.

- template:

  The working grid: a `SpatRaster`, or a `fev_layer` holding one.
  Defines cell size, extent and CRS of the result.

- communes:

  Optional `sf` of every commune in scope, to turn unrecorded communes
  into zeros rather than `NA`. See the section above.

- communes_key:

  Name of the INSEE code column in `communes`. `NULL` auto-detects, as
  [`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
  does.

- period:

  Two-element vector of years bounding the observation window, used as
  the denominator. `NULL` reads it from the source record, then falls
  back to the data with a warning.

- measure:

  `"rate"` (default) fires per 100 km2 per year; `"count"` the raw
  number over the whole period; `"burnt_rate"` hectares burnt per 100
  km2 per year, which weights by size rather than counting equally. Only
  `"burnt_rate"` needs an `area_ha` column: it is refused outright when
  no record carries one, because summing absent areas would produce a
  uniform zero map reading as *nothing burnt* rather than *nothing
  supplied*.

- denominator:

  What a rate is per: `"area"` (default) the commune's own area, or
  `"fuel"` its burnable area. Ignored by `measure = "count"`, which has
  no denominator. See the section above.

- fuel:

  Required for `denominator = "fuel"`: a `fev_fuel_source`, `fev_layer`
  or `SpatRaster`, reduced to a burnable mask exactly as
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  reduces it. It keeps its own grid — this is a zonal sum, not a
  resampling.

- lookup:

  Passed to the fuel reduction, as in
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md).

- min_area_ha:

  Drop fires smaller than this before counting. `0` keeps everything,
  which is the point of BDIFF over EFFIS; raise it to ask how often a
  fire of consequence starts here.

- output:

  `"raster"` (default) for the gridded layer, or `"communes"` for the
  `sf` with the computed columns, which is what a communal choropleth
  wants and what carries the information without the false sharpness.

- quiet:

  Suppress the report.

## Value

For `output = "raster"`, a `fev_layer` of role `"occurrence"` holding a
`SpatRaster`. For `output = "communes"`, an `sf` with `insee`,
`n_fires`, `burnt_ha`, `area_km2`, `burnable_km2` (`NA` unless
`denominator = "fuel"`) and `occurrence`.

## What this is, in the hazard

Hazard is usually defined as the probability that a fire **starts** and
that it **spreads**.
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
and
[`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md)
describe spread — fuel, terrain, weather. None of them says anything
about where fires begin, which is an empirical question and mostly an
anthropogenic one: roads, field edges, tips, power lines.

Pass the result into
[`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md)
or
[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
as one more named dimension and it enters the combination like any
other.

## The resolution is communal, whatever the cell size says

BDIFF geolocates a fire to its **commune of departure**. Every cell
inside a commune therefore gets the same value, and the map has the cell
size of `template` with the information content of a commune. The
function reports the ratio between the two on every call and records it,
because a 25 m map of a 4 km observation is exactly the kind of thing
that reads as precision to someone who did not build it.

There is deliberately **no smoothing or kernel option**. Spreading a
commune count over a distance decay would invent sub-communal structure
that no source supports. If you want a smoother map, aggregate the grid,
do not interpolate the values.

## Absent is not zero, and only you can say which

`fires` holds the communes that recorded a fire. Nothing in it
distinguishes a commune that never burnt from one that never filed.

Without `communes`, only the communes present get a value and the rest
of the grid is `NA` — honest, and usually not what a risk combination
wants. With `communes`, every commune in that layer and outside `fires`
becomes **0**. That is a claim: that the extract covered those communes,
so silence there means no declared fire. It is written into the record
as `zeros_assumed_from`, because BDIFF's own exhaustivity caveat means a
zero is "nothing was filed", never "nothing burnt".

## The denominator, which decides what the numbers mean

A rate needs a period. It must be the period **observed**, not the span
of the fires that happen to be in the extract: a commune with one fire
in 2010 inside a 2006–2025 request has a rate of 1/20 per year, not 1/1.

So `period` is read, in order, from the argument, then from the
`period_requested` of the
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
record, then — with a warning — from the range of the fire dates
themselves, which is a lower bound on the true observation window and
therefore inflates every rate.

## Per unit of ground, or per unit of ground that can burn

`denominator = "area"` divides by the commune's own area. It is the
obvious choice and it answers a question nobody asked: a commune that is
nine tenths built-up has few fires because it has little to burn, and
its rate comes out low for a reason that is not a low propensity to
ignite.

`denominator = "fuel"` divides by the **burnable** area instead, which
is the forestry question — how often does a fire start per unit of
ground that can carry one — and the one that compares a Morvan commune
with a periurban one honestly. It needs a `fuel` layer, reduced through
the same path
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
uses, so both functions mean the same thing by "burnable". A graded
availability layer is summed as it stands, making the divisor a
burnable-*equivalent* area rather than a count of burnable hectares.

Two consequences are reported rather than smoothed over. A commune with
no burnable ground gets `NA`, not zero: a rate per unit of burnable land
is undefined where there is none — and if such a commune recorded a fire
anyway, that contradiction is named, because it points at a vintage gap
or at a fire that was not in the woods.

And the fuel is a **snapshot** while the fires are a **period**. BD
Forêt v2 was built between 2007 and 2018; a 2006–2025 record spans both
sides of it. The divisor describes the forest at one moment while the
numerator counts over two decades. The vintage goes into the record, and
a fuel dated outside the fire window warns — the discipline
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
applies to its own temporal bias.

## See also

[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
for the records,
[`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md)
and
[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
to combine this with the spread terms.

## Examples

``` r
# A commune layer and two fires in it, entirely offline.
poly <- function(x0) sf::st_polygon(list(cbind(
  c(x0, x0 + 2000, x0 + 2000, x0, x0), c(0, 0, 2000, 2000, 0))))
com <- sf::st_sf(
  INSEE_COM = c("21001", "21002"),
  geometry = sf::st_sfc(poly(0), poly(2000), crs = 2154)
)
fires <- sf::st_sf(
  insee = c("21001", "21001"),
  fire_year = c(2010L, 2015L),
  area_ha = c(3, 12),
  geometry = sf::st_geometry(com)[c(1, 1)]
)
grid <- terra::rast(terra::ext(0, 4000, 0, 2000), resolution = 500,
                    crs = "EPSG:2154")

occ <- fev_fire_occurrence(fires, grid, communes = com,
                           period = c(2006, 2025), quiet = TRUE)
#> Warning: The grid is 5 times finer than the observation.
#> ✖ Every cell in a commune carries the same value: this map has 500 m cells and
#>   ~2260 m of information.
#> ℹ Recorded in the provenance. Do not read sub-communal structure into it, and
#>   consider `output = "communes"` for anything a reader will look at directly.
terra::unique(fev_data(occ))
#>   occurrence
#> 1        0.0
#> 2        2.5
```
