# Put layers on a common grid, explicitly

Resamples a set of layers onto one grid and records exactly what was
done. This is the **only** function in the package that changes a
layer's grid; every other one refuses mismatched inputs and sends you
here.

## Usage

``` r
fev_align(
  ...,
  to = NULL,
  direction = c("finest", "coarsest"),
  method = NULL,
  crs_work = NULL,
  quiet = FALSE
)
```

## Arguments

- ...:

  Named layers: `SpatRaster`, `fev_layer` or
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md).
  Names become the layer names of the result.

- to:

  Optional target: a `SpatRaster` whose grid to adopt, or the name of
  one of the layers in `...`.

- direction:

  Which grid to align onto when `to` is not given: `"finest"` (default)
  or `"coarsest"`.

- method:

  Resampling method, or `NULL` to let each layer take the default
  described above. Passed to
  [`terra::resample()`](https://rspatial.github.io/terra/reference/resample.html).

- crs_work:

  EPSG code recorded as the working CRS of the result.

- quiet:

  Suppress the scale-ratio warning. It exists to be read; use this only
  in loops where you have already reported the ratio.

## Value

A
[`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md)
holding the aligned layers, whose provenance records the target grid,
the method used for each layer, and the scale ratio.

## Why it is a function of its own

Fire danger from the ERA5-driven CEMS product is on a 0.25° grid — 20 to
30 km at French latitudes. Fuel-derived exposure is at 20 to 100 m.
Bringing them together spans three orders of magnitude, and whichever
direction you go, something is lost or invented:

- **to the finest grid** (the default, because it is what a risk map is
  for): one danger value is copied across roughly a million fuel pixels.
  The map looks decametric and the weather in it is not. Nothing is
  added by this step except resolution that no data supports.

- **to the coarsest grid**: exposure is averaged over a 25 km cell,
  which destroys exactly the spatial contrast the fuel module exists to
  produce, but invents nothing.

Neither is right. The point of naming the operation is that the ratio
ends up in the provenance record and in a warning you cannot miss,
rather than in an implicit `resample()` three functions deep.

## Method

Categorical layers are always resampled with nearest neighbour, whatever
you ask for — anything else averages class codes into meaningless
numbers.

For continuous layers going to a **finer** grid the default is also
nearest neighbour, deliberately: bilinear interpolation between the
centres of two 25 km cells draws a smooth gradient across the
intervening landscape that the reanalysis never resolved, and it is very
convincing. Going to a **coarser** grid the default is `"average"`,
which is the honest summary of many fine cells.

## See also

[`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md),
which refuses to do this itself.

## Examples

``` r
danger <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 1000,
                      ymin = 0, ymax = 1000, crs = "EPSG:2154")
terra::values(danger) <- c(10, 20, 30, 40)
expo <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 1000,
                    ymin = 0, ymax = 1000, crs = "EPSG:2154")
terra::values(expo) <- runif(1600)
s <- fev_align(danger = danger, exposure = expo, quiet = TRUE)
vapply(s, function(r) terra::res(r)[1], numeric(1))
#>   danger exposure 
#>       25       25 
```
