# Validate CRS and extents at the start of a chain

Checks that every input carries a projected CRS (not lon/lat), that the
working CRS matches the primary fuel source's native CRS, and that the
extents actually overlap. Run this before building a
[`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md):
each of these failures otherwise surfaces much later as an empty result,
which reads like a data problem rather than a CRS problem.

## Usage

``` r
fev_check_crs(..., crs_work = 2154, primary = NULL, strict = TRUE)
```

## Arguments

- ...:

  Named spatial objects: `SpatRaster`, `SpatVector`, `sf` or `sfc`.
  Names appear in the messages, so use meaningful ones.

- crs_work:

  Integer EPSG code of the intended working CRS. Default `2154` (RGF93 /
  Lambert-93), matching BD Forêt v2.

- primary:

  Name of the input that is the primary fuel source, as a string
  matching one of `...`. When given, a mismatch between its native CRS
  and `crs_work` is reported prominently: reprojecting it is exactly
  what the working-CRS rule exists to avoid.

- strict:

  When `TRUE` (default), a missing or geographic CRS is an error. When
  `FALSE`, it is a warning and the check returns its findings so the
  caller can decide.

## Value

Invisibly, an object of class `fev_crs_check`: a list with `inputs` (a
data frame of one row per input: name, class, CRS label, projected
flag), `crs_work`, `primary`, and `issues` (a character vector of
problems found, empty when clean).

## Choosing `crs_work`

Work in the projection of the layer driving your finest computation.

- Primary source = BD Forêt v2 (IGN) → `crs_work = 2154`, the package
  default.

- Primary source = CORINE, or a multi-country study → `crs_work = 3035`
  (ETRS89-LAEA), which is equal-area and therefore comparable across
  regions.

## Examples

``` r
r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 250,
                 ymin = 0, ymax = 250, crs = "EPSG:2154")
terra::values(r) <- runif(100)
chk <- fev_check_crs(fuel = r, crs_work = 2154, primary = "fuel")
#> CRS check passed: 1 input, all projected in "EPSG:2154".
chk$issues
#> character(0)
```
