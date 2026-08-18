# Profile fuel classes against an independent measurement

Answers the question a classification cannot answer about itself: do the
pixels a land cover product calls class X actually carry what the class
claims? Summarises continuous metrics — LiDAR-derived understorey
height, fuel load by stratum, cover — over the cells of each categorical
class, and quantifies how separable one class is from the rest.

## Usage

``` r
fev_fuel_profile(
  fuel,
  reference,
  metrics = NULL,
  class = NULL,
  min_cells = 30,
  quiet = FALSE
)
```

## Arguments

- fuel:

  An
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  with a categorical register, or a categorical `SpatRaster`.

- reference:

  An
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  with a continuous register, or a numeric `SpatRaster`. Typically the
  output of
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md).

- metrics:

  Names of the reference layers to profile. `NULL` takes the
  understorey-bearing subset when it is present — `H_Bush`, `FL_0_1`,
  `FL_1_3`, `Cover`, `PAI_tot` — and otherwise every layer.

- class:

  Class to test for separability, as it appears in the fuel layer's
  levels (e.g. `"5"` for CLCplus low-growing woody plants). `NULL`
  profiles every class without computing a separability statistic.

- min_cells:

  Classes with fewer cells than this are reported but excluded from the
  separability statistic. Default 30.

- quiet:

  Suppress the notes about resampling and sample size.

## Value

An object of class `fev_fuel_profile`: a list with `summary` (one row
per class and metric: `n`, `median`, `q25`, `q75`), `explained` (the
between-class share of variance per metric), `separability` (one row per
metric when `class` is given), and `notes`.

## Why LiDAR is the reference and not the other way round

An optical classification infers vegetation structure from reflectance;
LiDAR measures it. Under a closed canopy the maquis is invisible to
Sentinel-2 and plainly there in a point cloud. So the LiDAR layer is the
reference, the classification is what is being tested, and the direction
is not symmetric.

## Separability, and what it does not say

For a named `class`, the reported statistic per metric is the
probability that a randomly chosen cell of that class scores higher than
a randomly chosen cell outside it — the Mann-Whitney statistic, the same
one
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
reports as AUC. 0.5 means the class carries no information about the
metric; 1 means perfect separation.

It is **descriptive**. No confidence interval is reported, for the same
reason as in
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md):
neighbouring cells are not independent, so any interval computed
cell-wise would be far too narrow. A high value on a small plot is a
reason to look further, not a validation.

## On resampling, which direction matters

The two layers rarely share a grid. The reference is resampled onto the
fuel grid, because the fuel grid is the one the analysis runs on. When
the fuel grid is the **finer** of the two — a 10 m classification
against a 25 m LiDAR product, which is exactly the phase 10 case — this
is upsampling, and it creates no information. Each coarse measurement is
then shared by several fine cells, so the effective sample is smaller
than the cell count suggests and the statistic is more optimistic than
it looks. The function says so rather than leaving it to be noticed.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
for the reference layer,
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
for the same statistic applied to burnt area.

## Examples

``` r
# A classification that gets the shrub class right, against a measurement.
cls <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 500,
                   ymin = 0, ymax = 500, crs = "EPSG:2154")
terra::values(cls) <- rep(c(4, 5), each = 200)
levels(cls) <- data.frame(id = c(4, 5), class = c("4", "5"))

meas <- cls
terra::values(meas) <- c(rep(0.5, 200), rep(4.5, 200))
names(meas) <- "H_Bush"

p <- fev_fuel_profile(cls, meas, class = "5", quiet = TRUE)
p
#> 
#> ── fev_fuel_profile ────────────────────────────────────────────────────────────
#>  class metric   n q25 median q75
#>      4 H_Bush 200 0.5    0.5 0.5
#>      5 H_Bush 200 4.5    4.5 4.5
#> 
#> ── Variance accounted for by class membership ──
#> 
#>  metric   n n_classes explained
#>  H_Bush 400         2         1
#> ── Separability of class 5 ──
#> 
#>  metric n_class n_other separability
#>  H_Bush     200     200            1
```
