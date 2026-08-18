# Build a fuel source

Turns a fetched land cover dataset into a fuel source on a defined grid:
a categorical class layer, the correspondence table that gives those
classes fire meaning, and the provenance to say where they came from and
for which vintage.

## Usage

``` r
fev_fuel_source(
  x,
  type = c("bdforet_v2", "clc_2018", "worldcover_2021", "lidarhd", "custom"),
  res = 25,
  crs_work = 2154,
  field = NULL,
  lookup = NULL,
  millesime = NULL,
  aoi = NULL,
  touches = FALSE,
  register = c("auto", "categorical", "continuous"),
  units = NULL,
  provenance = NULL
)
```

## Arguments

- x:

  A
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_bdforet()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdforet.md)
  or
  [`fev_fetch_corine()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_corine.md),
  or a plain `sf`, `SpatVector` or `SpatRaster`.

- type:

  Source type: `"bdforet_v2"`, `"clc_2018"` (and the other CORINE
  vintages), `"worldcover_2021"` (and 2020), `"lidarhd"` (phase 8, not
  implemented) or `"custom"`.

- res:

  Target cell size in CRS units, metres for the projected defaults. See
  the resolution section.

- crs_work:

  EPSG code of the working CRS. Default `2154`, BD Forêt's native CRS. A
  categorical source is **not** reprojected silently: when `crs_work`
  differs from the data's CRS the reprojection is warned about and
  logged, because nearest-neighbour on a class layer displaces
  boundaries.

- field:

  Name of the class column. Defaults to `code_tfv` for BD Forêt and to
  the `code_XX` column CORINE serves for its vintage.

- lookup:

  Correspondence table. Defaults to the shipped one for `type`; pass
  your own from
  [`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
  to override it.

- millesime:

  Vintage of the data. See the vintage section. `NULL` takes it from
  `x`'s provenance record when there is one.

- aoi:

  Optional area of interest to crop the grid to.

- touches:

  Rasterisation rule for polygons. See the section above.

- register:

  For `type = "custom"` with a `SpatRaster`: which register the layers
  populate. `"auto"` reads a categorical raster as categorical and a
  plain numeric one as continuous.

- units:

  Named character vector of units for continuous layers, e.g.
  `c(cbd = "kg/m3")`. Recorded in the provenance and printed.

- provenance:

  Provenance record to carry forward. Taken from `x` when `NULL`.

## Value

An object of class `fev_fuel_source`.

## The two registers

A fuel source carries a **categorical** register (a class code per
pixel) and a **continuous** register (named numeric metrics per pixel).
BD Forêt and CORINE populate the first. The second exists so that
continuous fuel descriptions — LiDAR-derived load, bulk density, crown
base height — can be carried by the same object without the abstraction
assuming everything is a class. Use
[`fev_fuel_registers()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md)
to see which are populated.

## On the target resolution

`res` defaults to 25 m, and the floor below which it buys nothing is a
property of the source, not a constant: BD Forêt v2's minimum mapped
width is 20 m, ESA WorldCover's is 10 m. Below its source's own width a
grid resolves boundaries the data never had. At 100 m the advantage over
CORINE — whose native raster is 100 m — disappears entirely. Between
those, the cost is quadratic in memory and in focal-window time.

One resolution earns its cost for a reason unrelated to detail.
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
requires `res <= radius / 3`, so the 30 m radiant-heat radius is
**refused** at 25 m and becomes computable at 10 m — exactly, since 10 =
30 / 3. A 10 m source is therefore the only way to reach that scale at
all, and it costs about 39 times the focal work of 25 m: 6.25 times the
cells, each with 6.25 times the window.

## On the vintage

For `type = "bdforet_v2"` the vintage is **required**. BD Forêt v2 was
built department by department between 2007 and 2018, so a stand mapped
in 2008 may have burnt in 2010 and be in another state entirely; without
the vintage the temporal-bias check in
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
cannot run at all. The WFS does not serve it and no per-department table
was found (phase 2 report, section 2 bis), so it has to come from you.
Passing `millesime = NA` explicitly is accepted — it records "we looked
and do not know", which is honest — but it is not the default, so that
the check is never skipped by accident.

## Rasterising polygons

`touches = FALSE` (the default) assigns a cell to a polygon only when
the cell centre falls inside it, which is the standard convention and
keeps burnable area unbiased. It does drop polygons narrower than the
cell — at 25 m that means some of BD Forêt's 20 m minimum-width
features. `touches = TRUE` keeps them, at the cost of inflating every
class's area and letting thin non-burnable features (a road strip) claim
whole cells. Neither is free; the choice is recorded in the provenance.

## See also

[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
to combine a primary and an auxiliary source,
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md),
[`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md)
and
[`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
for the layers derived from one.

## Examples

``` r
# A miniature BD Forêt-style polygon layer.
poly <- sf::st_sf(
  code_tfv = c("FF2-57-57", "LA4"),
  geometry = sf::st_sfc(
    sf::st_polygon(list(cbind(c(0, 100, 100, 0, 0), c(0, 0, 100, 100, 0)))),
    sf::st_polygon(list(cbind(c(100, 200, 200, 100, 100), c(0, 0, 100, 100, 0)))),
    crs = 2154
  )
)
fuel <- fev_fuel_source(poly, type = "bdforet_v2", res = 25, millesime = 2014)
fuel
#> 
#> ── fev_fuel_source: bdforet_v2 ─────────────────────────────────────────────────
#> • Millesime: 2014
#> • Registers: "categorical"
#> • Categorical: 4 x 8 cells at 25 EPSG:2154, 2 classes
#> • Lookup: 32 rows, 4 flagged ambiguous
#> 
#> Provenance: 1 source, 1 step.
```
