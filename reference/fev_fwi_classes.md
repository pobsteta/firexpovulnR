# Fire danger classes for the Fire Weather Index

The six classes a Fire Weather Index value is mapped into, under one of
two published schemes. Both are shipped because they disagree by a
factor of three, and which one you use changes what your maps say.

## Usage

``` r
fev_fwi_classes(
  scheme = c("effis", "caliver_europe"),
  breaks = NULL,
  labels = NULL
)
```

## Source

EFFIS, *Fire Danger Forecast*,
<https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/fire-danger-forecast>,
verified 2026-08-15. The "Very Extreme" class was introduced in June
2021 to discriminate within the large areas classified *Extreme* around
the Mediterranean in summer.

Vitolo, C., Di Giuseppe, F., D'Andrea, M. (2018), *Caliver: An R package
for CALIbration and VERification of forest fire gridded model outputs*,
PLoS ONE 13(1): e0189419.
[doi:10.1371/journal.pone.0189419](https://doi.org/10.1371/journal.pone.0189419)
. European thresholds `2, 5, 10, 19, 33` read from the paper on
2026-08-16.

## Arguments

- scheme:

  `"effis"` (default) or `"caliver_europe"`. Ignored when `breaks` is
  given.

- breaks:

  Numeric vector of the five interior class boundaries, overriding
  `scheme`.
  [`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
  returns one.

- labels:

  Character vector of six class labels.

## Value

A data frame with columns `class`, `lower`, `upper`, and a `scheme`
attribute.

## The two schemes disagree, and that is worth knowing

|              |           |                              |
|--------------|-----------|------------------------------|
| Class        | EFFIS     | caliver / Vitolo et al. 2018 |
| Very Low     | —         | \< 2                         |
| Low          | \< 11.2   | 2–5                          |
| Moderate     | 11.2–21.3 | 5–10                         |
| High         | 21.3–38.0 | 10–19                        |
| Very High    | 38.0–50.0 | 19–33                        |
| Extreme      | 50.0–70.0 | ≥ 33                         |
| Very Extreme | \> 70.0   | —                            |

They are not two estimates of one quantity. The EFFIS breaks are
operational forecast thresholds for a European-scale warning service,
tuned so that the top classes stay rare enough to be actionable. The
caliver breaks were **derived from a reanalysis record** — the median of
yearly 98th percentiles over ERA-Interim 1980–2016, April to October,
put through the Canadian intensity relation — and describe the
distribution of that record.

An FWI of 40 is *Very High* under EFFIS and comfortably *Extreme* under
caliver. Say which you used.

## On the missing "very low" EFFIS class

A threshold of `5.2` for a "Very Low" EFFIS class circulates widely in
the literature and on third-party sites. **It does not appear on the
current EFFIS page**, which defines six classes starting at *Low*. It is
not added here on the grounds that it is common — pass your own `breaks`
if you need it, and say so in your methods.

## On using absolute breaks at all

These are service thresholds and record statistics, not physical
constants. The point of
[`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
is that raw FWI breaks mean different things in different climates: an
FWI of 25 is exceptional in Brittany and ordinary in the Var. Prefer
percentile ranks for cross-regional comparison, and
[`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
to derive breaks from your own record rather than import someone else's.

## Examples

``` r
fev_fwi_classes()
#>          class lower upper
#> 1          Low  -Inf  11.2
#> 2     Moderate  11.2  21.3
#> 3         High  21.3  38.0
#> 4    Very High  38.0  50.0
#> 5      Extreme  50.0  70.0
#> 6 Very Extreme  70.0   Inf
fev_fwi_classes("caliver_europe")
#>       class lower upper
#> 1  Very Low  -Inf     2
#> 2       Low     2     5
#> 3  Moderate     5    10
#> 4      High    10    19
#> 5 Very High    19    33
#> 6   Extreme    33   Inf
```
