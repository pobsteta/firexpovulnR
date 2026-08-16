# Create a `fev_stack`

A `fev_stack` bundles the raster layers of an analysis with the
provenance record that makes it replayable: sources and their vintages,
the working CRS and resolution, and an ordered log of every operation
with the parameters it used.

## Usage

``` r
fev_stack(..., crs_work = 2154, provenance = NULL)
```

## Arguments

- ...:

  Named `SpatRaster` objects, one per layer. Names become layer names
  and must be unique and non-empty.

- crs_work:

  Integer EPSG code of the working CRS. Defaults to `2154` (RGF93 /
  Lambert-93), the CRS of BD Forêt v2, the primary fuel source. Use
  `3035` (ETRS89-LAEA) for CORINE-driven or multi-country studies.

- provenance:

  An existing provenance record to carry forward. When `NULL` a fresh
  one is created.

## Value

An object of class `fev_stack`: a named list of `SpatRaster` with a
`provenance` attribute.

## Details

Layers are **not** required to share a grid. Fire danger from ERA5 is
kilometric while fuel-derived exposure is decametric, and forcing them
onto one grid at construction time would hide a resampling step that has
to be explicit. Use
[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
when layers must be combined.

All layers must, however, share a CRS. Mixing CRS in one object makes
every downstream extent comparison wrong in a way that is hard to see.

## See also

[`fev_provenance()`](https://pobsteta.github.io/firexpovulnR/reference/fev_provenance.md)
to export the record,
[`fev_check_crs()`](https://pobsteta.github.io/firexpovulnR/reference/fev_check_crs.md)
to validate inputs before building one.

## Examples

``` r
r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 250,
                 ymin = 0, ymax = 250, crs = "EPSG:2154")
terra::values(r) <- runif(100)
s <- fev_stack(exposure = r, crs_work = 2154)
s
#> 
#> ── fev_stack ───────────────────────────────────────────────────────────────────
#> 1 layer, working CRS 2154
#> • exposure: 10 x 10 cells, res "25 x 25"
#> 
#> Provenance: 0 sources, 1 step. See `fev_provenance()`.
```
