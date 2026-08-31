# The wildland-urban interface

Where people and burnable vegetation are close enough that one reaches
the other: cells holding assets with fuel within `distance`, and
optionally the converse — fuel with assets within `distance`.

## Usage

``` r
fev_wui(
  assets,
  fuel,
  distance = 100,
  assets_min = 0,
  side = c("assets", "fuel", "both"),
  lookup = NULL,
  quiet = FALSE
)
```

## Arguments

- assets:

  A raster of exposed assets: a
  [fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  from
  [`fev_fetch_ghsl()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_ghsl.md),
  a `fev_layer`, or a `SpatRaster`. Cells above `assets_min` count as
  present.

- fuel:

  A
  [fev_fuel_source](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md),
  `fev_layer` or `SpatRaster`, reduced to a burnable mask exactly as
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  reduces it.

- distance:

  Interface distance, in CRS units. Default 100 m, the short-range ember
  scale of
  [`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md)
  and the order of the French *obligation légale de débroussaillement*.
  It is a parameter, not a constant: pass what your context justifies.

- assets_min:

  Threshold above which an assets cell counts as present. Default `0`,
  i.e. any non-zero value. With a modelled population surface that is a
  low bar — GHS-POP spreads fractions of a person over cells with a
  trace of built-up — so raise it when the result looks implausibly
  wide.

- side:

  `"assets"`, `"fuel"` or `"both"`.

- lookup:

  Passed to the fuel reduction, as in
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md).

- quiet:

  Suppress the report.

## Value

A `fev_layer` of role `"wui"`, values 1 on the interface and 0
elsewhere, ready to enter
[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
as a further dimension.

## Which definition this is

There is no single WUI. The literature splits broadly into a **housing
density** definition (the US federal register's interface and intermix,
thresholds on structures per unit area) and a **proximity** definition
(anything built within a set distance of wildland). This function
implements the second, because it is the one the package's inputs can
actually support: GHS-POP gives a modelled population surface, not a
structure count, and counting structures per hectare from it would be
inventing a precision the source does not carry.

The consequence is worth stating plainly: this identifies *proximity*,
not *risk to a dwelling*. A single isolated house 80 m from maquis and a
dense hamlet 80 m from the same maquis both come out as interface, and
the second is a far larger problem.

## Distance is measured through the window, not around obstacles

The neighbourhood is a disc of radius `distance`, so a river, a motorway
or a cliff between the assets and the fuel counts for nothing. Fire does
cross most of those; embers cross all of them. That is the argument for
the simple version, and it is also the reason not to read the output as
a fire-break analysis.

## Two sides, and why both are offered

`side = "assets"` returns the exposed assets — what a mayor asks for.
`"fuel"` returns the fuel that threatens them — what a forester asks
for, since that is where clearing obligations apply. `"both"` returns
their union. The three answer different questions and the record says
which was asked.

## See also

[`fev_fetch_ghsl()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_ghsl.md)
for an assets source,
[`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
for the graded metric this complements,
[`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
to combine them.

## Examples

``` r
g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 200,
                 ymin = 0, ymax = 200, crs = "EPSG:2154")
# Fuel on the left half, one inhabited cell just across the divide.
fuel <- terra::setValues(g, rep(rep(c(1, 0), each = 10), 20))
pop <- terra::setValues(g, 0)
pop[10, 12] <- 50
wui <- fev_wui(pop, fuel, distance = 30, quiet = TRUE)
terra::global(fev_data(wui), "sum", na.rm = TRUE)
#>     sum
#> wui   1
```
