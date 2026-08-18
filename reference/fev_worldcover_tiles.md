# Which 3-degree tiles cover an area

WorldCover tiles are named by their south-west corner, floored to a
multiple of three degrees: the tile holding 43.3 N 6.35 E is `N42E006`.
Verified by reading `N42E006`, whose extent is exactly 6-9 E and 42-45
N.

## Usage

``` r
fev_worldcover_tiles(aoi)
```

## Arguments

- aoi:

  Area of interest. Must carry a CRS.

## Value

A data frame with `tile` and the tile bounds in EPSG:4326.

## See also

[`fev_fetch_worldcover()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_worldcover.md).

## Examples

``` r
aoi <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_point(c(6.35, 43.3)), crs = 4326
))
fev_worldcover_tiles(sf::st_buffer(aoi, 0.05))
#>      tile xmin ymin xmax ymax
#> 1 N42E006    6   42    9   45
```
