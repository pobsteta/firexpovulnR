# Data source registry

Returns the endpoints and layer names the package contacts, so they can
be inspected without reading the source, and overridden when a provider
moves something.

## Usage

``` r
fev_sources()
```

## Value

A named list with `endpoints` and `layers`.

## Details

All values were verified on 2026-08-15 by real network calls. See
`specs/phase2-rapport-faisabilite.md` in the repository for the evidence
behind each one.

## Examples

``` r
fev_sources()$endpoints$ign_wfs
#> [1] "https://data.geopf.fr/wfs/ows"
fev_sources()$layers$bdforet_v2
#> [1] "LANDCOVER.FORESTINVENTORY.V2:formation_vegetale"
```
