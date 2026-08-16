# Fire exposure from surrounding fuel

The proportion of burnable fuel within a transmission distance of each
cell: how much of the surrounding landscape could carry fire to it.

## Usage

``` r
fev_exposure(
  fuel,
  radius = NULL,
  type = c("ember", "ember_short", "radiant"),
  no_burn = NULL,
  lookup = NULL,
  na_rm = FALSE,
  quiet = FALSE
)
```

## Source

Beverly, J.L., Bothwell, P., Conner, J.C.R., Herd, E.P.K. (2010).
[doi:10.1071/WF09071](https://doi.org/10.1071/WF09071) . Beverly, J.L.,
McLoughlin, N., Chapman, E. (2021), *Landscape Ecology* 36: 785-801.
Khan, S.I. et al. (2025), *Natural Hazards* 121: 16273-16295,
[doi:10.1007/s11069-025-07424-8](https://doi.org/10.1007/s11069-025-07424-8)
. Window geometry checked against `fireexposuR` 1.2.0 on 2026-08-16.

## Arguments

- fuel:

  A `fev_fuel_source` (reduced with
  [`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md)),
  a `fev_fuel_layer`, or a `SpatRaster` with values in `[0, 1]`.

- radius:

  Transmission distance in CRS units. `NULL` takes it from `type`.

- type:

  `"ember"` (500 m, the default), `"ember_short"` (100 m) or `"radiant"`
  (30 m). Ignored when `radius` is given.

- no_burn:

  Optional `SpatRaster` of cells that cannot burn — water, rock, sealed
  surface — masked out of the **result**, not the window. Must contain
  only 1 and `NA`.

- lookup:

  Correspondence table, when `fuel` is a `fev_fuel_source`.

- na_rm:

  Ignore `NA` cells inside the window rather than propagating them.
  `FALSE` matches `fireexposuR`; `TRUE` is more forgiving at the edges
  of a study area, at the cost of computing a proportion over fewer
  cells than the ring contains.

- quiet:

  Suppress the first-use note about the radii.

## Value

A `fev_exposure_layer` holding a `SpatRaster` named `exposure`.

## What the window is

An **annulus**, from one cell out to `radius`. The assessment cell
itself is excluded, because the metric asks what can reach a place, not
what is already there. A value of 0.5 means half the cells in that ring
are burnable. Values run 0 to 1.

The grid must be at least three times finer than the radius — below that
the ring is a handful of cells and the proportion is quantised into a
few values. That constraint comes from `fireexposuR` and is enforced
here too.

## The radii are Canadian, with one Mediterranean validation

30 m for radiant heat, 100 m for short-range embers, 500 m for
long-range embers, from Beverly et al. (2010, 2021) on Alberta fuels.
Khan et al. (2025) validated the metric over mainland Portugal — about
80% of burned area fell where exposure was 80% or more — so it does
transpose to an Iberian context. It has not been calibrated on holm oak,
garrigue or maquis, and Portugal is not the Var. See
[`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md)
for what exactly is sourced. A message says this on first use in a
session; the radius used is recorded in the provenance every time.

## Graded exposure

Passing a
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
layer instead of a binary mask gives a weighted exposure: each
surrounding cell contributes its availability rather than a flat 1. That
is a departure from the published metric, which is binary, so it is not
the default and the record says which was used.

## See also

[`fev_directional()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional.md)
for the same landscape seen from one point,
[`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md)
for the sources.

## Examples

``` r
fuel <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
                    ymin = 0, ymax = 1000, crs = "EPSG:2154")
terra::values(fuel) <- 0
fuel[10:30, 10:30] <- 1
e <- fev_exposure(fuel, radius = 100, quiet = TRUE)
terra::global(fev_data(e), "max", na.rm = TRUE)
#>          max
#> exposure   1
```
