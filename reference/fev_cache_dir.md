# Cache location and contents

The package caches downloaded data under
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html), so
repeated analyses do not re-hit IGN, Copernicus or EFFIS.

## Usage

``` r
fev_cache_dir(create = FALSE)
```

## Arguments

- create:

  Create the directory if it does not exist.

## Value

`fev_cache_dir()` returns the path as a string.

## Examples

``` r
fev_cache_dir()
#> [1] "/home/runner/.cache/R/firexpovulnR"
```
