# Repair rasterisation gaps in a categorical fuel layer

Fills small holes left by rasterising a polygon coverage, and **only**
those: a hole larger than the source's minimum mapping unit is left
empty, because it may be a genuine gap in the data rather than an
artefact of the grid.

## Usage

``` r
fev_fuel_fill_gaps(fuel, max_gap = NULL, quiet = FALSE)
```

## Arguments

- fuel:

  An
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md),
  typically the result of
  [`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md).

- max_gap:

  Largest hole to fill, in hectares. `NULL` (default) takes the minimum
  mapping unit of the complete-coverage component, which is the only
  value that makes this a repair. Passing a larger number is allowed and
  recorded, but it is then an assumption about unmapped ground.

- quiet:

  Suppress the report.

## Value

The `fev_fuel_source`, with holes below `max_gap` filled in the
categorical register and the operation recorded in the provenance.

## Why this is a repair and not an interpolation

A source cannot map an object smaller than its own minimum mapping unit.
CORINE Land Cover's is 25 ha; the smallest CORINE polygon in either
shipped extract measures 24.9 ha, so the specification is observed and
not merely claimed. A hole of 0.25 ha inside CORINE's extent therefore
cannot be a real land-cover unit — it is a sub-cell gap between polygons
that share a boundary, and the ground there is certainly one of the
neighbours.

That is why the threshold is a property of the data rather than a
parameter to tune, and why crossing it changes the answer from "repair"
to "invent". Above the minimum mapping unit this function refuses,
reports, and moves on.

## Why it matters more than its size suggests

42 empty cells out of 469 989 sound negligible. They are not:
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
propagates `NA` through its focal window, so each isolated empty cell
empties a disc of the window radius around it. Measured on the Couchey
extract, 42 cells emptied 26 303 — an amplification of 626 — and blanked
17.5% of the risk map once the legitimate edge frame is counted.

## Sources that map only part of their extent

BD Forêt v2 maps vegetation formations only, so its silence means "not
forest", which is information. Its minimum mapping unit is therefore
never used to justify a fill. Only a source flagged as complete coverage
in `.FEV_FUEL_MMU` can license one; if none of the merged components is,
this function fills nothing and says why.

## See also

[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md),
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md).

## Examples

``` r
r <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 500,
                 ymin = 0, ymax = 500, crs = "EPSG:2154")
terra::values(r) <- rep(1, terra::ncell(r))
levels(r) <- data.frame(id = 1, code_18 = "311")
r[5, 5] <- NA          # a one-cell rasterisation sliver
f <- fev_fuel_source(r, type = "clc_2018", millesime = 2018)
sum(is.na(terra::values(fev_fuel_categorical(f))))
#> [1] 1

# 0.0625 ha is far below CORINE's 25 ha minimum mapping unit, so it cannot
# be a real land-cover unit and is repaired.
g <- fev_fuel_fill_gaps(f)
#> 1 empty cell in 1 gap.
#> ✔ 1 filled: below 25 ha, so no component could have mapped them.
#> ℹ Largest gap: 0.06 ha.
#> ℹ Class from the modal 3x3 neighbour; the source layer records them as
#>   "gap_filled" rather than claiming a dataset mapped them.
sum(is.na(terra::values(fev_fuel_categorical(g))))
#> [1] 0
```
