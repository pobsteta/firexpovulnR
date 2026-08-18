# Attach continuous fuel metrics to a categorical fuel source

Carries a second description of the same ground alongside the first,
instead of making the two compete for the pixel. What the attached
source holds decides where it lands: **continuous** metrics populate the
continuous register, a **class** layer becomes a named extra layer of
the categorical one.

## Usage

``` r
fev_fuel_attach(primary, extra, name = NULL)
```

## Arguments

- primary:

  A `fev_fuel_source` with a categorical register. It keeps deciding
  `class`.

- extra:

  A `fev_fuel_source` to carry alongside. With a continuous register —
  from
  [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
  — it populates the continuous one. With only a categorical register,
  its classes become an extra layer.

- name:

  Name for the attached categorical layer. `NULL` uses the source's own
  label. Ignored for a continuous attachment.

## Value

`primary`, with the extra description carried alongside.

## Why this is not fev_fuel_merge()

[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
arbitrates. Two sources propose a class for the same pixel, one has to
win, and the per-pixel `source` layer records which. The loser's
information is gone.

Attaching arbitrates nothing. LiDAR competes for nothing to begin with —
bulk density and crown base height are quantities no categorical source
has. And a second classification need not compete either, if you want it
for the attributes the deciding one lacks rather than for the class
itself.

## Keeping the species when a 10 m raster decides the class

This is the case the categorical branch exists for. With
`fev_fuel_merge(hierarchy = "auto")`, ESA WorldCover outranks BD Forêt
and, having complete coverage, takes **every** pixel — BD Forêt
contributes nothing, and its species and crown cover go with it.

Attaching it afterwards keeps both: the 10 m class from WorldCover, and
the botany from BD Forêt riding alongside in its own layer.

    fuel <- fev_fuel_merge(bdforet, worldcover)   # WorldCover decides `class`
    fuel <- fev_fuel_attach(fuel, bdforet)        # species survives beside it

The attached layer decides no pixel.
[`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md),
[`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md)
and the exposure chain all read `class` and ignore it, and
[`fev_fuel_fill_gaps()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_fill_gaps.md)
leaves it alone — its `NA` mean "not forest here", which is information,
and filling them from a modal neighbour would invent species.

## Coverage is a per-metric mask, not a source layer

LiDAR HD is still being flown, so the continuous register is full of
holes where the categorical one is complete. The function reports the
share of categorical cells that get continuous values, because a fuel
object whose two registers describe different subsets of the map is easy
to misread.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md),
[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md),
[`fev_fuel_registers()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md).

## Examples

``` r
# Categorical from BD Forêt, continuous standing in for LiDAR.
cat_r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 200,
                     ymin = 0, ymax = 200, crs = "EPSG:2154")
terra::values(cat_r) <- rep_len(1:2, 64)
levels(cat_r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
names(cat_r) <- "class"
fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)

cbd <- terra::rast(cat_r)
terra::values(cbd) <- runif(64, 0, 0.4)
names(cbd) <- "CBD_max"
lidar <- fev_fuel_source(cbd, type = "custom", register = "continuous",
                         units = c(CBD_max = "kg/m3"))

both <- fev_fuel_attach(fuel, lidar)
#> Attached 1 continuous metric covering 100% of the categorical cells.
fev_fuel_registers(both)
#> [1] "categorical" "continuous" 

# And the categorical branch: a second classification kept alongside rather
# than made to compete.
other <- terra::rast(cat_r)
terra::values(other) <- rep_len(1:2, 64)
levels(other) <- data.frame(id = 1:2, class = c("10", "20"))
names(other) <- "class"
wc <- fev_fuel_source(other, type = "worldcover_2021", register = "categorical")

names(fev_fuel_categorical(fev_fuel_attach(wc, fuel)))
#> Attached "bdforet_v2" alongside class, covering 100% of the mapped cells.
#> ℹ It decides no pixel: class still comes from "worldcover_2021". Use it for
#>   what the deciding source does not carry -- species, crown cover.
#> ℹ `fev_fuel_fill_gaps()` leaves it alone: its "NA" mean "not forest here",
#>   which is information.
#> [1] "class"      "bdforet_v2"
```
