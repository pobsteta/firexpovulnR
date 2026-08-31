# Which CSV header feeds which column

The mapping
[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
uses to turn BDIFF's published headers into the columns it returns. Each
entry names one output column and the headers that may carry it, in
preference order.

## Usage

``` r
fev_bdiff_columns(...)
```

## Arguments

- ...:

  Named overrides, e.g. `cause = "origine_du_feu"`. Each replaces the
  candidates for that column.

## Value

A named list of character vectors, one per output column.

## Why this is a lookup and not a constant

The headers are a publication choice of the producer, not part of any
standard, and the export has been through more than one wording.
Hard-coding them would make the connector fail on the next revision with
a message about a missing column rather than about a renamed one.
Override the entry that moved and the connector keeps working.

Headers are compared after normalisation: lower-cased, accents stripped,
every run of non-alphanumeric characters collapsed to a single
underscore. So `"Surface parcourue (m2)"` and `"surface_parcourue_m2"`
are the same candidate and you do not have to reproduce the punctuation.

## What is required and what is not

`insee` is required, and so is at least one of `fire_date` and
`fire_year`: without a commune code there is nothing to geolocate, and
without a date there is no period to filter on. Everything else is
optional and comes back as `NA` when the export does not carry it.

## These candidates are expected, not verified

They were written from BDIFF's documented export rather than read off a
live download, for the same reason the remote route is unverified — see
[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md).
The design consequence is deliberate: a wrong candidate produces an
error that lists the headers actually present, not a silently empty
column.

## See also

[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md).

## Examples

``` r
names(fev_bdiff_columns())
#>  [1] "fire_id"           "fire_date"         "fire_year"        
#>  [4] "insee"             "commune"           "dep"              
#>  [7] "area_total"        "area_forest"       "area_other_wooded"
#> [10] "area_other"        "cause"            
fev_bdiff_columns()$area_total
#> [1] "surface_parcourue_m2" "surface_parcourue"    "surface_totale_m2"   
#> [4] "surface_totale"      
# An export that renamed one field:
fev_bdiff_columns(cause = "origine")$cause
#> [1] "origine"
```
