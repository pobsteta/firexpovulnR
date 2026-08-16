# Clear cached data

Deletes cache entries. Both the data file and its provenance sidecar are
removed together, so no untraceable data is left behind.

## Usage

``` r
fev_cache_clear(dataset = NULL, older_than = NULL, confirm = interactive())
```

## Arguments

- dataset:

  Optional dataset name (e.g. `"bdforet_v2"`). When `NULL`, every entry
  is targeted.

- older_than:

  Optional number of days. Only entries last modified before that many
  days ago are removed.

- confirm:

  When `TRUE` (the default in an interactive session), ask before
  deleting. Set `FALSE` in scripts.

## Value

Invisibly, a character vector of the files removed.

## Examples

``` r
if (FALSE) { # \dontrun{
fev_cache_clear(dataset = "bdforet_v2", confirm = FALSE)
fev_cache_clear(older_than = 90, confirm = FALSE)
} # }
```
