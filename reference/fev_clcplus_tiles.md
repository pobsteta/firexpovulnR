# Which CLCplus tiles cover an area

CLCplus Backbone is distributed as 100 x 100 km cloud-optimised GeoTIFF
tiles on the EEA reference grid. Since the download is manual — the
product sits behind EU Login — the least this package can do is say
exactly which tiles to fetch, rather than leaving you to work it out
from a map.

## Usage

``` r
fev_clcplus_tiles(aoi)
```

## Source

EEA reference grid coding system: European Environment Agency, *About
the EEA reference grid*, ETRS89-LAEA (EPSG:3035), false easting 4 321
000 m, false northing 3 210 000 m. Tiling of the product as 100 km
cloud-optimised GeoTIFF: CLMS product page for CLCplus Backbone 2023.
Both read 2026-08-18.

## Arguments

- aoi:

  Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or `SpatRaster`.
  Must carry a CRS.

## Value

A data frame with one row per tile: `tile`, and the tile's bounds in
EPSG:3035 (`xmin`, `ymin`, `xmax`, `ymax`).

## How the tile code is built

The EEA reference grid codes a cell as its size followed by its
lower-left coordinate expressed in units of that size, in EPSG:3035. A
100 km tile whose corner sits at 4 000 000 m east and 2 200 000 m north
is therefore `E40N22`. The arithmetic is the documented coding system;
**the exact filename prefix CLMS puts in front of it was not verified**,
so match on the `E..N..` part when you browse the download list.

## See also

[`fev_fetch_clcplus()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_clcplus.md),
which imports a tile once you have it.

## Examples

``` r
aoi <- sf::st_sf(
  geometry = sf::st_sfc(
    sf::st_polygon(list(cbind(c(970000, 975000, 975000, 970000, 970000),
                              c(6252000, 6252000, 6256000, 6256000, 6252000)))),
    crs = 2154
  )
)
fev_clcplus_tiles(aoi)
#>     tile  xmin    ymin    xmax    ymax
#> 1 E40N22 4e+06 2200000 4100000 2300000
```
