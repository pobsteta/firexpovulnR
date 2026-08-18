# Import FORMS canopy height (France, 10 m)

Reads a FORMS raster into the **continuous** register of a fuel source,
so that canopy height becomes available across France rather than only
where LiDAR HD has flown. FORMS is derived from Sentinel-1 and
Sentinel-2 with a U-Net trained on GEDI RH95, and is published under
CC-BY 4.0.

## Usage

``` r
fev_fetch_forms(
  file = NULL,
  aoi = NULL,
  variable = c("height", "biomass", "volume"),
  crs_work = 2154,
  quiet = FALSE
)
```

## Source

Schwartz, M. et al. (2023), *FORMS: Forest Multiple Source height, wood
volume, and biomass maps in France at 10 to 30 m resolution based on
Sentinel-1, Sentinel-2, and Global Ecosystem Dynamics Investigation
(GEDI) data with a deep learning approach*, Earth System Science Data
15, 4927. Data:
[doi:10.5281/zenodo.7840108](https://doi.org/10.5281/zenodo.7840108) ,
CC-BY 4.0. Read at article level 2026-08-18; the raster itself has not
been exercised by this package's tests.

## Arguments

- file:

  Path to a FORMS raster. Required — the product is distributed through
  Zenodo, and this package does not download it for you.

- aoi:

  Optional area of interest to crop to.

- variable:

  Which FORMS product the file holds: `"height"` (FORMS-H, 10 m),
  `"biomass"` (FORMS-B, 30 m) or `"volume"` (FORMS-V, 30 m). Recorded in
  the provenance and used to name the layer.

- crs_work:

  EPSG code to return the raster in. Default `2154`.

- quiet:

  Suppress the import report and the standing caveats.

## Value

A
[fev_source](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
holding a numeric `SpatRaster`, ready for
`fev_fuel_source(register = "continuous")`.

## Why import and not compute

Coupling GEDI with Sentinel-2 to obtain canopy height is a sound method
— including by regression kriging, with the anisotropy of GEDI's
acquisition modelled along track. But it has been done for the whole of
France and released freely. Recomputing it would cost a phase and
produce a result we would then have to validate ourselves.

## What it is good for, and what it is not

Height is well restored: MAE 2.94 m and R² 0.69 against 2020 National
Forest Inventory plots. **Biomass is not**: R² 0.18 against Renecofor
plots. Do not treat FORMS-B as if it carried FORMS-H's reliability.

Three caveats travel with the product, and this function repeats them
rather than assuming they were read:

- the model was trained on a **2020** composite, and the authors state
  that deploying it on other years risks significant error;

- **Mediterranean forests are underrepresented in its validation** —
  which is precisely the Maures;

- accuracy degrades on steep slopes, and biomass saturates above 400
  Mg/ha.

## It does not reach the understorey

Canopy height is not the package's missing quantity. The understorey is,
and no satellite product supplies it in Mediterranean evergreen
vegetation: GEDI does not resolve it below about 30 m of canopy height,
which covers the whole of the Maures. FORMS widens the *canopy*
description beyond the LiDAR footprint; it does not replace
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md).

Where it does help is
[`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md):
with FORMS as the reference, a classification can be confronted with a
measurement-derived height anywhere in France, not only on the two
shipped LiDAR plots.

## See also

[`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md)
to use it as a reference,
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
for the understorey it does not reach.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("massif_maures.gpkg")
h <- fev_fetch_forms("FORMS_H_2020_10m.tif", aoi = aoi)

# As a reference for profiling classes where no LiDAR has flown.
fev_fuel_profile(fuel, h, metrics = "height")
} # }
```
