# Merge a primary and an auxiliary fuel source

Fills the gaps of a primary fuel source with an auxiliary one, and
records for every pixel which dataset its class came from.

## Usage

``` r
fev_fuel_merge(
  primary,
  secondary,
  hierarchy = c("auto", "primary_first", "secondary_first")
)
```

## Arguments

- primary:

  The primary fuel source, a `fev_fuel_source` with a categorical
  register.

- secondary:

  The auxiliary fuel source.

- hierarchy:

  `"auto"` (default) ranks the two sources by type and lets the higher
  one win whichever position it was passed in; see the section on
  ranking. `"primary_first"` and `"secondary_first"` decide by argument
  position instead, `"secondary_first"` swapping the two roles —
  including which grid the result lands on.

## Value

A `fev_fuel_source` whose categorical register has two layers, `class`
and `source`, and whose lookup is the union of both tables.

## Details

In France the primary is BD Forêt v2 and the auxiliary is CORINE. BD
Forêt wins wherever it maps something; CORINE fills the rest — chiefly
the non-forest burnable vegetation it maps and BD Forêt does not
(sclerophyllous vegetation, moors, natural grassland) and the
unambiguously non-burnable classes (urban, water, bare rock).

## The per-pixel source layer

The result carries a `source` layer alongside `class`. Without it the
merged layer is uninterpretable: a 25 m pixel from BD Forêt and a 25 m
pixel resampled from a 25 ha CORINE unit look identical and mean
entirely different things. Any statistic computed on the merged layer
should be reported per source, or at least alongside the source
proportions that [`summary()`](https://rdrr.io/r/base/summary.html)
prints.

Merging is **idempotent** on that layer: re-merging an already-merged
source with the same auxiliary changes no pixel and no attribution,
because pixels already attributed keep their original source.

## Which source wins, and why it is not argument order

`hierarchy = "auto"` reads a rank per source type rather than trusting
the order you happened to write. The ranking, highest first: **ESA
WorldCover**, then **BD Forêt v2**, then **CLCplus Backbone**, then
**CORINE**. Sources of equal or unknown rank fall back to argument
order, which is what every earlier version did — so
`fev_fuel_merge(bdforet, corine)` is unchanged.

WorldCover sits on top deliberately, and the choice has a measured cost.
It buys 10 m and a 2021 vintage everywhere, against 25 m and a 2008–2018
vintage for BD Forêt. It pays in thematic depth: no species, no crown
cover, and a *Shrubland* class that separates the LiDAR-measured
understorey at only 0.688 at best on the two Maures plots — its
*Shrubland* and *Tree cover* cells carrying practically the same
understorey.

If that trade is wrong for your study, say so explicitly:
`fev_fuel_merge(bdforet, worldcover, hierarchy = "primary_first")`.

## What gets reprojected

The primary is never touched. When the auxiliary sits on a different CRS
or a different grid it is reprojected or resampled onto the primary's
grid with nearest neighbour — the only correct method for a class layer,
and one that does displace boundaries. Both operations warn and are
logged.

The result therefore adopts the primary's grid **and its extent**:
auxiliary coverage outside the primary's footprint is dropped, not
appended. Pass the same `aoi` to both
[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
calls and the question does not arise. Where BD Forêt covers a smaller
area than the study needs — a department it does not map — build the
primary on the full AOI, so the unmapped part is `NA` inside the extent
and CORINE can fill it.

## See also

[`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
to build the inputs.

## Examples

``` r
mk <- function(codes, type, millesime) {
  r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 100,
                   ymin = 0, ymax = 100, crs = "EPSG:2154")
  terra::values(r) <- codes
  levels(r) <- data.frame(id = sort(unique(stats::na.omit(codes))),
                          class = attr(codes, "labels"))
  fev_fuel_source(r, type = type, millesime = millesime)
}
bdf <- structure(c(1, 1, NA, NA, 1, 1, NA, NA, rep(NA, 8)),
                 labels = "FF2-57-57")
clc <- structure(rep(1, 16), labels = "323")
merged <- fev_fuel_merge(mk(bdf, "bdforet_v2", 2014),
                         mk(clc, "clc_2018", 2018))
#> "clc_2018" filled 12 cells (75%) that "bdforet_v2" left unmapped.
merged
#> 
#> ── fev_fuel_source: bdforet_v2+clc_2018 ────────────────────────────────────────
#> • Millesime: bdforet_v2 2014, clc_2018 2018
#> • Registers: "categorical"
#> • Categorical: 4 x 4 cells at 25 EPSG:2154, 2 classes
#> • Per-pixel source: "bdforet_v2" and "clc_2018"
#> • Lookup: 76 rows, 21 flagged ambiguous
#> 
#> Provenance: 2 sources, 3 steps.
```
