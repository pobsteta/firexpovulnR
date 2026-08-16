# Validate a risk map against observed burnt areas

Tests whether observed fires fell where the map said risk was high: an
AUC, a ROC curve, and the observed-versus-expected distribution across
risk classes. Runs the temporal bias check first, because a good AUC
computed against fires that postdate the fuel data is not evidence of
anything.

## Usage

``` r
fev_validate(
  risk,
  burnt_areas,
  max_lag_years = NULL,
  millesime = NULL,
  class_breaks = c(0.2, 0.4, 0.6, 0.8, 1),
  n_thresholds = 200
)
```

## Source

Class-table form after
[`fireexposuR::fire_exp_validate()`](https://docs.ropensci.org/fireexposuR/reference/fire_exp_validate.html)
1.2.0, whose default `class_breaks = c(0.2, 0.4, 0.6, 0.8, 1)` is reused
here. Read from the installed package on 2026-08-16.

## Arguments

- risk:

  A `fev_risk_layer` from
  [`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md),
  a `fev_layer`, or a `SpatRaster`.

- burnt_areas:

  Observed fires: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md),
  an `sf` or a `SpatVector`, carrying a fire date.

- max_lag_years:

  Drop fires whose year exceeds the fuel vintage by more than this.
  `NULL` keeps everything and only reports.

- millesime:

  Fuel vintage, when it is not in `risk`'s provenance or you want to
  override it.

- class_breaks:

  Upper bounds of the risk classes for the observed-versus-expected
  table. The default matches
  [`fireexposuR::fire_exp_validate()`](https://docs.ropensci.org/fireexposuR/reference/fire_exp_validate.html).

- n_thresholds:

  Number of thresholds along the ROC curve.

## Value

An object of class `fev_validation`, with `auc`, `roc`, `classes`,
`temporal` and the provenance record.

## The temporal bias check

Every fire's year is compared to the vintage of the fuel layer the risk
map was built on, read from the provenance record. The function reports
how many fires and what share of burnt **area** postdate that vintage by
more than `max_lag_years`, and — when `max_lag_years` is given — drops
them from the sample.

If the vintage is unknown the check cannot run. That is the recorded
consequence of BD Forêt v2 not serving it (see
[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)):
the function then refuses if you asked for filtering, and warns loudly
if you did not.

## What AUC does and does not say

The AUC here is the probability that a randomly chosen burnt cell scores
higher than a randomly chosen unburnt one. 0.5 is a coin toss.

It is computed over **cells**, which are not independent observations:
fires are spatially contiguous, so the effective sample size is far
smaller than the cell count and any confidence interval built on that
count would be far too narrow. None is reported for that reason. Treat
the AUC as a descriptive comparison of two distributions, not as a test.

The class table alongside it is the more readable statement, and is the
form
[`fireexposuR::fire_exp_validate()`](https://docs.ropensci.org/fireexposuR/reference/fire_exp_validate.html)
uses: the share of burnt area in each risk class against the share of
the study area in that class. A map with skill concentrates burnt area
in classes that occupy little ground.

## See also

[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md),
[`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md).

## Examples

``` r
# Risk rising towards the south: row 1 of a SpatRaster is its northern edge,
# so values run 0 at the top to 1 at the bottom.
g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 2000,
                 ymin = 0, ymax = 2000, crs = "EPSG:2154")
terra::values(g) <- rep(seq(0, 1, length.out = 20), each = 20)

# A fire in the south, where the map said risk was highest.
fires <- sf::st_sf(
  FIREDATE = "2016-07-18",
  geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 2000, 2000, 0, 0), c(0, 0, 500, 500, 0)
  ))), crs = 2154)
)
v <- fev_validate(g, fires, millesime = 2014)
v$auc
#> [1] 1
v$classes
#>       class cells_total cells_burnt pct_of_area pct_of_burnt ratio
#> 1   0 - 0.2          80           0          20            0     0
#> 2 0.2 - 0.4          80           0          20            0     0
#> 3 0.4 - 0.6          80           0          20            0     0
#> 4 0.6 - 0.8          80          20          20           20     1
#> 5   0.8 - 1          80          80          20           80     4
```
