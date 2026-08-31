# Data source registry

Returns the endpoints and layer names the package contacts, so they can
be inspected without reading the source, and overridden when a provider
moves something.

## Usage

``` r
fev_sources()
```

## Value

A named list with `endpoints`, `layers`, `verified` (the date the rest
were confirmed) and `unverified` (the endpoints that were not).

## Details

All values were verified on 2026-08-15 by real network calls, **except**
those named in `unverified`. See `specs/phase2-rapport-faisabilite.md`
in the repository for the evidence behind each verified one.

## One endpoint is not verified

`data_gouv_api`, the route
[`fev_fetch_bdiff()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdiff.md)
uses to reach BDIFF, was written without ever being called: the
environment it was added in has no egress to data.gouv.fr. Listing it
beside the others without saying so would make the whole registry mean
less, so it is named in `unverified` and every result obtained through
it carries `endpoint_verified = FALSE`.

## Examples

``` r
fev_sources()$endpoints$ign_wfs
#> [1] "https://data.geopf.fr/wfs/ows"
fev_sources()$layers$bdforet_v2
#> [1] "LANDCOVER.FORESTINVENTORY.V2:formation_vegetale"
fev_sources()$unverified
#> [1] "data_gouv_api"
```
