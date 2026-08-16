# Inspect the cache

Lists cached entries with their dataset, size, age and recorded vintage,
so you can see what an analysis will reuse before it runs.

## Usage

``` r
fev_cache_info()
```

## Value

A data frame with one row per cache entry: `dataset`, `key`, `file`,
`size_mb`, `modified`, `millesime`, `endpoint`. Zero rows when the cache
is empty.

## Examples

``` r
fev_cache_info()
#> Cache is empty (/home/runner/.cache/R/firexpovulnR does not exist yet).
#> [1] dataset   key       file      size_mb   modified  millesime endpoint 
#> <0 rows> (or 0-length row.names)
```
