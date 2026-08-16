# Changelog

## firexpovulnR 0.6.0 (2026-08-16)

Première version numérotée. Elle couvre les phases 0 à 6 du brief de
développement : l’objet et sa provenance, l’acquisition, le combustible,
le danger, l’exposition et la vulnérabilité. La phase 7 — combinaison en
risque, validation contre les surfaces brûlées, vignette de bout en bout
— reste à faire, et le workflow cible du brief n’est donc pas encore
exécutable intégralement.

640 tests hors ligne, aucun échec. `R CMD check` sans erreur,
avertissement ni note.

#### Objet, provenance et contrôles

- [`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md)
  transporte les couches d’une analyse sans les forcer sur une grille
  commune. Danger kilométrique et exposition décamétrique gardent leur
  grille native jusqu’à un appel explicite à
  [`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md).
- [`fev_provenance()`](https://pobsteta.github.io/firexpovulnR/reference/fev_provenance.md)
  exporte en YAML les sources, millésimes, période de calibration et
  l’intégralité des paramètres réellement utilisés — y compris les
  défauts que l’appelant n’a jamais tapés.
- [`fev_check_crs()`](https://pobsteta.github.io/firexpovulnR/reference/fev_check_crs.md)
  refuse une entrée en latitude/longitude et signale un écart entre
  `crs_work` et le CRS natif de la source primaire.

#### Acquisition et cache

- [`fev_fetch_fwi()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_fwi.md),
  [`fev_fetch_bdforet()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_bdforet.md),
  [`fev_fetch_corine()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_corine.md)
  et
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md).
  Tout endpoint, nom de couche et seuil numérique est centralisé dans
  `R/constants.R` avec sa date et sa voie de vérification ;
  `specs/phase2-rapport-faisabilite.md` porte les preuves.
- Le cache disque est indexé par empreinte de la requête normalisée :
  deux appels de paramètres différents ne peuvent pas entrer en
  collision. Chaque entrée est deux fichiers, données et provenance ;
  une donnée sans provenance est traitée comme un défaut de cache.
- **BD Forêt v2 ne sert pas son millésime** et aucune table par
  département n’a été trouvée. Il est enregistré `NA` et jamais inféré.
- **EFFIS couvre 2016 et après, pas 2006.**
  [`fev_fetch_burnt()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fetch_burnt.md)
  compare la période demandée à celle réellement servie et avertit avec
  des chiffres.

#### Combustible

- [`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md)
  porte **deux registres**, catégoriel et continu, et ne suppose jamais
  que l’information est une classe. Seul le premier a des producteurs
  aujourd’hui ; le second attend le LiDAR HD de la phase 8. Chaque
  fonction aval déclare le registre qu’elle consomme.
- [`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md)
  est une fusion strictement intra-registre, avec une couche de
  provenance par pixel. Elle est idempotente : re-fusionner ne
  relabellise pas les pixels déjà attribués.
- Les tables de correspondance vivent dans `data-raw/`, sont justifiées
  ligne par ligne et sont livrées en CSV surchargeables : 32 postes TFV,
  44 classes CORINE de niveau 3. 4 lignes ambiguës sur 32 côté BD Forêt,
  17 sur 44 côté CORINE, chacune disant où est le doute.
- Le millésime BD Forêt est **obligatoire** dans
  [`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md).
  Sans lui le contrôle de biais temporel de `fev_validate()` ne pourra
  pas tourner ; `millesime = NA` explicite est accepté et averti.
- [`fev_fuel_weights()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_weights.md)
  livre dix-neuf poids de disponibilité qui ne viennent d’aucune
  publication. Ils avertissent à chaque appel et partent dans la
  provenance avec `weights_sourced = FALSE`.

#### Danger météorologique

- [`fev_fwi_percentile()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_percentile.md)
  est le cœur méthodologique : rang percentile contre une climatologie
  de référence locale, par pixel ou par région. Une couche sans dates
  est refusée — une climatologie sur une période inconnue n’en est pas
  une.
- [`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
  réimplémente `get_fire_danger_levels()` de caliver, archivé du CRAN en
  octobre 2021 : médiane des 98es percentiles annuels puis inversion par
  la relation d’intensité canadienne.
- [`fev_fwi_classes()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_classes.md)
  livre **deux jeux de seuils publiés qui diffèrent d’un facteur trois**
  — EFFIS opérationnels, et ceux dérivés d’une réanalyse par Vitolo et
  al. 2018. Un FWI de 40 est « Very High » chez l’un et « Extreme » chez
  l’autre.
  [`fev_danger_class()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_class.md)
  inscrit dans la provenance lequel a produit la carte.
- [`fev_fwi_calc()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_calc.md)
  exige la latitude au lieu de laisser `cffdrs` substituer 55°N.
  L’ajustement de longueur du jour est par bandes, donc la substitution
  est inoffensive en France métropolitaine et fausse ailleurs — un
  défaut juste là où l’on écrit le script et faux là où on le recopie.

#### Exposition et vulnérabilité

- [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  reproduit la géométrie de
  [`fireexposuR::fire_exp()`](https://docs.ropensci.org/fireexposuR/reference/fire_exp.html)
  : anneau focal d’une cellule au rayon de transmission, cellule évaluée
  exclue. Un test croisé compare les deux fenêtres cellule par cellule
  et les sorties à `1e-4`, tolérance qui est exactement l’arrondi de
  `fire_exp()`.
- [`fev_directional()`](https://pobsteta.github.io/firexpovulnR/reference/fev_directional.md)
  suit Beverly et Forbes 2023. Les relèvements sont des relèvements de
  boussole, et un test le fige : l’erreur produit une carte plausible
  tournée de 90 degrés.
- [`fev_vuln_layer()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_layer.md)
  et
  [`fev_vuln_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_vuln_stack.md).
  Aucune source d’enjeux n’est imposée ; les poids d’agrégation sont un
  jugement de valeur, la fonction le dit et l’inscrit.
- **Une réserve du brief est levée.** Khan et al. 2025 ont validé la
  métrique d’exposition sur le Portugal continental : environ 80 % des
  surfaces brûlées en exposition ≥ 80 %. La métrique transpose donc à un
  contexte ibérique. Le rayon, lui, n’est toujours pas calibré sur chêne
  vert, garrigue ou maquis.

#### Alignement des échelles

- [`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
  est la seule fonction autorisée à changer une grille ; toutes les
  autres refusent des entrées de grilles différentes et y renvoient. Le
  rapport d’échelle part dans un avertissement et dans la provenance.
- Le rééchantillonnage vers une grille plus fine se fait au plus proche
  voisin, pas en bilinéaire : interpoler entre deux centres de mailles
  de 25 km dessine un gradient que la réanalyse n’a jamais résolu, et
  c’est très convaincant.

#### Infrastructure

- Intégration continue : cohérence `DESCRIPTION` / `NEWS.md` /
  `CITATION.cff`, `R CMD check`, couverture via covr et Codecov, site
  pkgdown, tag et release automatiques pilotés par la version de
  `DESCRIPTION`.
- Aucun test unitaire ne touche le réseau. Les tests d’intégration
  contre les API réelles vivent dans un fichier séparé, activés par
  `FIREXPOVULNR_TEST_NETWORK=1`.
