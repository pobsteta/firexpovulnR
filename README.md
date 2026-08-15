# firexpovulnR

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

Chaîne de traitement R reproductible pour l'évaluation du **risque d'incendie
de forêt en Europe**, avec la France métropolitaine comme terrain primaire.
Le package combine quatre briques :

1. **Danger météorologique** — Fire Weather Index (FWI), calibré en percentiles
   régionaux sur une climatologie de référence.
2. **Exposition** — fraction de combustible brûlable dans un voisinage focal,
   et vulnérabilité directionnelle depuis un enjeu ponctuel.
3. **Vulnérabilité** — normalisation et agrégation pondérée de couches d'enjeux
   (population, bâti, habitats protégés).
4. **Risque composite** — croisement des trois.

## Statut

**Expérimental.** Package de recherche interne. Il n'est pas destiné au CRAN
ni à rOpenSci : la conformité aux policies CRAN n'est pas un objectif. En
revanche la **reproductibilité et la traçabilité des paramètres sont
l'exigence numéro un**, parce que les sorties servent à appuyer des résultats
publiés.

## Principes de conception

- **Aucun seuil en dur.** Tout seuil, rayon ou table de correspondance importé
  d'une publication ou d'un service externe est un argument avec valeur par
  défaut sourcée, entièrement surchargeable.
- **Une seule reprojection.** Le CRS de travail (`crs_work`, défaut `2154`)
  est celui de la source de combustible primaire. Les couches d'appoint sont
  reprojetées le plus tard possible ; la source primaire ne l'est jamais.
- **Provenance systématique.** Tout objet `fev_stack` transporte ses sources,
  millésimes, période de calibration et l'intégralité des paramètres utilisés.
  `fev_provenance()` exporte le tout en YAML.
- **Décalage d'échelle explicite.** Le rééchantillonnage entre danger
  kilométrique et exposition décamétrique passe obligatoirement par
  `fev_align()`, qui avertit et journalise. Aucun alignement implicite ailleurs.

## Avertissements méthodologiques

Le package importe des paramètres calibrés hors du contexte européen tempéré
et méditerranéen. Ils sont utilisables, mais leur transposition n'est pas
validée :

- Les **rayons d'exposition** par défaut proviennent de travaux sur
  combustibles boréaux et conifériens canadiens. Sur chêne vert, garrigue ou
  maquis, ils doivent être justifiés ou recalibrés.
- Les **classes de danger FWI** sont des seuils de service opérationnel, pas
  des constantes physiques.
- Ni CORINE ni la BD Forêt v2 ne décrivent le **sous-étage** ni la charge de
  combustible. Deux peuplements de structure verticale radicalement différente
  y sont identiques, alors que la propagation de surface en dépend directement.

Ces limites sont détaillées dans la vignette.

## Installation

```r
# install.packages("pak")
pak::pak("pobsteta/firexpovulnR")
```

Le toolchain géospatial (GDAL, GEOS, PROJ) doit être présent sur la machine :
le package s'appuie sur `terra` et `sf` exclusivement (ni `raster`, ni `sp`).

## Licence

GPL-3.
