# Fire exposure transmission distances

Default radii for the focal exposure metrics, with the source of each
and the process it stands for.

## Usage

``` r
fev_exposure_radii()
```

## Source

Beverly, J.L., Bothwell, P., Conner, J.C.R., Herd, E.P.K. (2010).
Assessing the exposure of the built environment to potential ignition
sources generated from vegetative fuel. *International Journal of
Wildland Fire* 19(3): 299-313.
[doi:10.1071/WF09071](https://doi.org/10.1071/WF09071)

Beverly, J.L., McLoughlin, N., Chapman, E. (2021). A simple metric of
landscape fire exposure. *Landscape Ecology* 36: 785-801. Not read
directly; distances verified through the `fireexposuR` 1.2.0 reference
documentation on 2026-08-16.

Khan, S.I., Colaço, M.C., Sequeira, A.C., Rego, F.C., Beverly, J.L.
(2025). Validating a landscape metric to map fire exposure to hazardous
fuels in Portugal. *Natural Hazards* 121: 16273-16295.
[doi:10.1007/s11069-025-07424-8](https://doi.org/10.1007/s11069-025-07424-8)
. Read at abstract level on 2026-08-16.

## Value

A data frame with columns `type`, `min_m`, `max_m`, `process`, `source`.

## Where these come from

The three distances are the ones the exposure literature uses
throughout: 30 m for radiant heat, 100 m for short-range embers, 500 m
for long-range embers. They originate in Beverly et al. (2010), derived
on four Alberta communities, and are carried forward unchanged in
Beverly et al. (2021), which is the landscape-scale formulation this
package implements.

Beverly et al. (2021) is paywalled and **has not been read directly**.
The distances above were instead verified on 2026-08-16 against the
reference documentation of `fireexposuR` 1.2.0 — an rOpenSci
peer-reviewed package written by the same group — which states them
explicitly and cites both papers. That is a secondary source, and it is
named as one.

## On transposing them to Mediterranean fuels

The brief that governs this package assumed these radii were unvalidated
outside boreal and coniferous Canadian fuels. That is no longer quite
true, and the change is worth stating precisely.

Khan et al. (2025) applied the metric to mainland Portugal over
1995–2018 on a 100 m grid and validated it against burned area in five
fire years: roughly 80% of burned area fell in sites with exposure of
80% or more, and the authors conclude the Canadian metric "aligned well
with wildfires modulated by Portuguese climate and vegetation". So the
**metric** transposes to an Iberian Mediterranean-Atlantic context.

What that paper does not settle is the **radius**: its abstract states
the grid resolution but not the transmission distance used, and it was
read at abstract level only. Nor does Portugal — maritime pine,
eucalyptus, Atlantic shrubland — stand in for holm oak, garrigue and
maquis. Treat 500 m as a defensible starting point with one
Mediterranean validation behind it, not as a calibrated value for the
Var.
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
says so on first use.

## What is still not sourced

No radius **per fuel type** is shipped. Beverly et al. (2021) is
reported to define hazardous fuel by conifer content, but the criterion
was not read at its source, so nothing is derived from it here. Do not
infer per-fuel-type distances from the three values below.

## See also

[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md),
which consumes these.

## Examples

``` r
fev_exposure_radii()
#>          type min_m max_m            process
#> 1     radiant   0.1    30       radiant heat
#> 2 ember_short   0.1   100 short-range embers
#> 3       ember 100.1   500  long-range embers
#>                                                                  source
#> 1 Beverly et al. 2010 (Alberta); carried forward in Beverly et al. 2021
#> 2 Beverly et al. 2010 (Alberta); carried forward in Beverly et al. 2021
#> 3   Beverly et al. 2010/2021; validated in Portugal by Khan et al. 2025
```
