# firexpovulnR

Chaîne de traitement R reproductible pour l’évaluation du **risque
d’incendie de forêt en Europe**, avec la France métropolitaine comme
terrain primaire. Le package combine quatre briques :

1.  **Danger météorologique** — Fire Weather Index (FWI), calibré en
    percentiles régionaux sur une climatologie de référence.
2.  **Exposition** — fraction de combustible brûlable dans un voisinage
    focal, et vulnérabilité directionnelle depuis un enjeu ponctuel.
3.  **Vulnérabilité** — normalisation et agrégation pondérée de couches
    d’enjeux (population, bâti, habitats protégés).
4.  **Risque composite** — croisement des trois.

## Statut

**Expérimental.** Package de recherche interne. Il n’est pas destiné au
CRAN ni à rOpenSci : la conformité aux policies CRAN n’est pas un
objectif. En revanche la **reproductibilité et la traçabilité des
paramètres sont l’exigence numéro un**, parce que les sorties servent à
appuyer des résultats publiés.

## Principes de conception

- **Aucun seuil en dur.** Tout seuil, rayon ou table de correspondance
  importé d’une publication ou d’un service externe est un argument avec
  valeur par défaut sourcée, entièrement surchargeable.
- **Une seule reprojection.** Le CRS de travail (`crs_work`, défaut
  `2154`) est celui de la source de combustible primaire. Les couches
  d’appoint sont reprojetées le plus tard possible ; la source primaire
  ne l’est jamais.
- **Provenance systématique.** Tout objet `fev_stack` transporte ses
  sources, millésimes, période de calibration et l’intégralité des
  paramètres utilisés.
  [`fev_provenance()`](https://pobsteta.github.io/firexpovulnR/reference/fev_provenance.md)
  exporte le tout en YAML.
- **Décalage d’échelle explicite.**
  [`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md)
  est la seule fonction du package autorisée à changer une grille ;
  toutes les autres refusent des entrées de grilles différentes et y
  renvoient. Le rapport d’échelle entre danger kilométrique et
  exposition décamétrique part dans un avertissement et dans la
  provenance. Aucun alignement implicite ailleurs.
- **Combustible catégoriel *et* continu.** Un objet `fev_fuel_source`
  porte deux registres : un registre catégoriel (classe TFV ou CORINE)
  et un registre continu (charge par strate, densité apparente, hauteur
  de base de houppier). BD Forêt et CORINE alimentent le premier ; le
  second attend les métriques dérivées du LiDAR HD. Chaque fonction aval
  déclare celui qu’elle consomme et refuse explicitement quand il est
  vide.

## Avertissements méthodologiques

Le package importe des paramètres calibrés hors du contexte européen
tempéré et méditerranéen. Ils sont utilisables, mais leur transposition
n’est pas validée :

- Les **rayons d’exposition** par défaut proviennent de travaux sur
  combustibles boréaux et conifériens canadiens. La métrique elle-même a
  été validée au Portugal continental (Khan et al. 2025), donc elle
  transpose à un contexte ibérique ; le rayon, lui, n’est pas calibré
  sur chêne vert, garrigue ou maquis. Point de départ défendable, pas
  valeur calibrée.
- Les **classes de danger FWI** ne sont pas des constantes physiques. Le
  package livre deux jeux de seuils publiés — EFFIS, opérationnels, et
  ceux dérivés d’une réanalyse par Vitolo et al. 2018 — qui diffèrent
  d’un facteur trois : un FWI de 40 est « Very High » chez l’un et «
  Extreme » chez l’autre.
  [`fev_danger_class()`](https://pobsteta.github.io/firexpovulnR/reference/fev_danger_class.md)
  inscrit dans la provenance lequel a produit la carte, et
  [`fev_fwi_thresholds()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fwi_thresholds.md)
  permet de les dériver de votre propre série plutôt que de les
  importer.
- Ni CORINE ni la BD Forêt v2 ne décrivent le **sous-étage** ni la
  charge de combustible. Deux peuplements de structure verticale
  radicalement différente y sont identiques, alors que la propagation de
  surface en dépend directement.

Ces limites sont détaillées dans la vignette.

## Installation

``` r

# install.packages("pak")
pak::pak("pobsteta/firexpovulnR")
```

Le toolchain géospatial (GDAL, GEOS, PROJ) doit être présent sur la
machine : le package s’appuie sur `terra` et `sf` exclusivement (ni
`raster`, ni `sp`).

## Documentation

Le site de référence est publié à
<https://pobsteta.github.io/firexpovulnR/>. `NEWS.md` porte l’historique
des versions.

## Développement

L’intégration continue tient quatre choses :

| Workflow | Ce qu’il garantit |
|----|----|
| `R-CMD-check.yaml` | `DESCRIPTION` = `NEWS.md` = `CITATION.cff`, puis `R CMD check` tests compris, puis la couverture envoyée à Codecov |
| `release.yml` | Tag `vX.Y.Z` et release GitHub, pilotés par `Version:` dans `DESCRIPTION` — **seulement après un check vert** |
| `pkgdown.yaml` | Le site de référence, et la vignette de bout en bout qui n’est montée que là |

Aucun test unitaire ne touche le réseau. Les tests d’intégration contre
les API réelles (IGN, EFFIS, Copernicus) sont désactivés sauf
`FIREXPOVULNR_TEST_NETWORK=1` : une CI rouge doit signifier une
régression du code, pas l’indisponibilité d’un tiers.

### Poser une version

Le cycle de développement porte une version `X.Y.Z.9000`, que les
garde-fous ignorent. Pour publier :

1.  `Version:` dans `DESCRIPTION` passe à `X.Y.Z` ;
2.  `NEWS.md` gagne une section `# firexpovulnR X.Y.Z (AAAA-MM-JJ)` ;
3.  `version:` et `date-released:` dans `CITATION.cff` suivent ;
4.  push sur `main`.

Le reste est automatique. Les trois fichiers doivent s’accorder, sinon
le premier job échoue avant que quoi que ce soit ne soit taggué — c’est
ce qui empêche de publier une release dont les notes décrivent une autre
version.

## Licence

GPL-3.
