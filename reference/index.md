# Package index

## Objet, provenance et contrôles

La classe qui transporte une analyse et le dossier qui la rend
rejouable. Les couches ne partagent pas forcément une grille : le
décalage d’échelle est porté par l’objet, pas masqué par lui.

- [`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md)
  :

  Create a `fev_stack`

- [`as_fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/as_fev_stack.md)
  :

  Coerce to a `fev_stack`

- [`fev_stack_save()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack_save.md)
  [`fev_stack_read()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack_save.md)
  :

  Save and reload a `fev_stack`

- [`fev_provenance()`](https://pobsteta.github.io/firexpovulnR/reference/fev_provenance.md)
  : Export the provenance of an analysis

- [`fev_data()`](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  [`fev_source_info()`](https://pobsteta.github.io/firexpovulnR/reference/fev_data.md)
  :

  The `fev_source` class, and how to get at its contents

- [`fev_check_crs()`](https://pobsteta.github.io/firexpovulnR/reference/fev_check_crs.md)
  : Validate CRS and extents at the start of a chain

## Acquisition et cache

Un client par source, chacun rendant ses métadonnées de provenance — jeu
de données, millésime, requête exacte, date de téléchargement. Le cache
est indexé par empreinte de requête, donc deux appels de paramètres
différents ne peuvent pas se confondre.

- [`fev_fetch_fwi()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_fwi.md)
  : Fetch CEMS fire danger indices
- [`fev_fetch_bdforet()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdforet.md)
  : Fetch BD Forêt v2 (primary fuel source)
- [`fev_fetch_corine()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_corine.md)
  : Fetch CORINE Land Cover (auxiliary fuel source)
- [`fev_fetch_clcplus()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_clcplus.md)
  : Import CLCplus Backbone (10 m raster land cover)
- [`fev_fetch_forms()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_forms.md)
  : Import FORMS canopy height (France, 10 m)
- [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
  : Fetch EFFIS burnt area perimeters
- [`fev_bdforet_millesime()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdforet_millesime.md)
  : BD Forêt v2 vintage, from the imagery it was photo-interpreted on
- [`fev_lidarhd_available()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidarhd_available.md)
  : Is LiDAR HD available over an area, and which tiles
- [`fev_fetch_lidarhd()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_lidarhd.md)
  : Retrieve LiDAR HD tiles
- [`fev_cache_info()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_info.md)
  : Inspect the cache
- [`fev_cache_clear()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_clear.md)
  : Clear cached data
- [`fev_cache_dir()`](https://pobsteta.github.io/firexpovulnR/reference/fev_cache_dir.md)
  : Cache location and contents
- [`fev_sources()`](https://pobsteta.github.io/firexpovulnR/reference/fev_sources.md)
  : Data source registry

## Combustible

L’abstraction porte deux registres, catégoriel et continu, et ne suppose
jamais que l’information est une classe. Les tables de correspondance
sont justifiées ligne par ligne et intégralement surchargeables.

- [`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  : Build a fuel source
- [`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
  : Merge a primary and an auxiliary fuel source
- [`fev_fuel_fill_gaps()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_fill_gaps.md)
  : Repair rasterisation gaps in a categorical fuel layer
- [`fev_fuel_profile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_profile.md)
  : Profile fuel classes against an independent measurement
- [`fev_fuel_binary()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_binary.md)
  : Burnable / non-burnable mask
- [`fev_fuel_type()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_type.md)
  : Structural fuel type
- [`fev_fuel_availability()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_availability.md)
  : Weighted fuel availability
- [`fev_fuel_lookup()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lookup.md)
  : Fuel correspondence tables
- [`fev_fuel_types()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_types.md)
  : The vocabulary of fuel types
- [`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md)
  : Default fuel availability weights
- [`fev_fuel_registers()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md)
  [`fev_fuel_categorical()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md)
  [`fev_fuel_continuous()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_registers.md)
  : Which registers of a fuel source are populated
- [`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
  : Fuel metrics from a LiDAR point cloud
- [`fev_fuel_attach()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_attach.md)
  : Attach continuous fuel metrics to a categorical fuel source
- [`fev_lidar_density()`](https://pobsteta.github.io/firexpovulnR/reference/fev_lidar_density.md)
  : Effective pulse and point density of a point cloud

## Danger météorologique

Le cœur méthodologique est la calibration en percentiles : un seuil FWI
absolu redessine surtout la climatologie, alors qu’un rang percentile
dit la même chose dans le Var et en Bretagne. La météo elle-même
s’obtient sans aucun jeton via
[`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md).

- [`fev_fetch_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_weather.md)
  : Fire weather from the open Open-Meteo archive
- [`fev_fwi_from_weather()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_from_weather.md)
  : Fire Weather Index from open weather, as a dated raster
- [`fev_fwi_calc()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_calc.md)
  : Fire Weather Index from weather forcings
- [`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
  : Percentile rank against a reference climatology
- [`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
  : Danger thresholds derived from a climatology
- [`fev_fwi_classes()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_classes.md)
  : Fire danger classes for the Fire Weather Index
- [`fev_danger_class()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_class.md)
  : Classify fire danger into named classes
- [`fev_danger_index()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_index.md)
  : Composite fire danger

## Exposition et vulnérabilité

Fraction focale de combustible autour de chaque cellule, vulnérabilité
directionnelle depuis un enjeu ponctuel, et normalisation des couches
d’enjeux. Aucune source d’enjeux n’est imposée.

- [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  : Fire exposure from surrounding fuel
- [`fev_directional()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional.md)
  : Directional vulnerability from a point
- [`fev_exposure_radii()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_radii.md)
  : Fire exposure transmission distances
- [`fev_exposure_cost()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure_cost.md)
  : What a focal exposure pass will cost, before committing to it
- [`fev_directional_defaults()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional_defaults.md)
  : Directional vulnerability defaults
- [`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md)
  : Normalise a layer of assets to a 0-1 vulnerability
- [`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md)
  : Combine vulnerability dimensions

## Combinaison, risque et validation

[`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
est la seule fonction du package autorisée à changer une grille ; toutes
les autres refusent des entrées de grilles différentes et y renvoient.
[`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
traite le biais temporel comme du code, pas comme une réserve de bas de
page.

- [`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
  : Put layers on a common grid, explicitly
- [`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
  : Composite fire risk
- [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
  : Validate a risk map against observed burnt areas

## Méthodes

- [`plot(`*`<fev_stack>`*`)`](https://pobsteta.github.io/firexpovulnR/reference/plot.fev_stack.md)
  :

  Plot the layers of a `fev_stack`
