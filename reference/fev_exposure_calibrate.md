# Fit the exposure radius to local fires

Sweeps a series of radii, computes
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
at each, and scores each against observed fires with the same AUC
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
uses. Returns the whole sweep, not only the winner, because the shape of
the curve says more than its maximum: a flat curve means the radius
hardly matters on these fuels, and a sharp one means it does.

## Usage

``` r
fev_exposure_calibrate(
  fuel,
  burnt_areas,
  radii = NULL,
  type = "ember",
  millesime = NULL,
  max_lag_years = NULL,
  quiet = FALSE,
  ...
)
```

## Arguments

- fuel:

  A
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md),
  `fev_layer` or `SpatRaster`, as
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  takes.

- burnt_areas:

  Observed fires: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md),
  an `sf` or a `SpatVector`.

- radii:

  Radii to try, in CRS units. `NULL` uses a geometric sweep from three
  cells to a tenth of the smaller extent side, which spans the published
  scales without wandering past what the layer can support.

- type:

  Passed to
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  for provenance only; the radius is what varies here.

- millesime:

  Fuel vintage for the temporal check. `NULL` digs it out of the
  provenance, as
  [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
  does.

- max_lag_years:

  Passed to the temporal check. `NULL`, the default and the same as
  [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md),
  reports the bias without filtering on it. Setting it without a known
  vintage is an error there and here: there would be nothing to compare
  the fire dates against.

- quiet:

  Suppress progress and the standing caveats.

- ...:

  Passed to
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
  so `no_burn`, `na_rm` and `trim` apply identically at every radius.

## Value

An object of class `fev_exposure_calibration`: a list with `table` (one
row per radius: `radius`, `reachable`, `auc`, `n_burnt`, `note`), `best`
(the radius of maximum AUC, `NA` if none was reachable), `at_edge`
(whether that best sits on the first or last radius tried, in which case
it is the edge of the sweep rather than an optimum), `temporal` and
`provenance`.

## This is a fit, not a validation

The radius that maximises AUC is the radius that best separates burnt
from unburnt **in the fires you supplied**, with nothing held out to
test it on. Report it as a fitted parameter. A radius fitted on eleven
fires in one massif and then quoted as validated would be worse than the
Canadian default it replaces, because it would carry a local authority
it has not earned.

The honest use is the one the package's own limitation calls for:
replacing *"30, 100 and 500 m, from Alberta"* with *"250 m, fitted on
the Maures fires of 2003-2021, AUC 0.71"* — a statement whose provenance
a reader can weigh.

## The temporal bias applies here too, and harder

[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
warns when fires postdate the fuel vintage. Fitting on such a sample
does not merely describe a biased situation, it **bakes the bias into a
parameter**. The check runs first and its verdict travels with the
result.

## Radii out of reach are declared, never dropped

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
refuses `res > radius / 3`. At 25 m every radius below 75 m is
unreachable, which on the shipped defaults removes the radiant-heat
scale entirely. Those radii come back with `reachable = FALSE` and no
AUC rather than being quietly left out of the sweep, because a table
that silently contains only what happened to work reads as if it had
covered everything.

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
[`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md)
for the shipped values and where they come from,
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
for the AUC itself.

## Examples

``` r
if (FALSE) { # \dontrun{
zone <- sf::st_read(system.file("extdata", "maures.gpkg",
                                package = "firexpovulnR"), "study_area")
feux <- sf::st_read(system.file("extdata", "maures.gpkg",
                                package = "firexpovulnR"), "burnt_areas")
cal <- fev_exposure_calibrate(combustible, feux,
                              radii = c(100, 250, 500, 1000))
cal
plot(cal)
} # }
```
