# Changelog

## firexpovulnR 0.9.3 (2026-08-17)

- Vignette Couchey : une section explique les grands rectangles visibles
  sur la carte de risque. Ce ne sont pas des dalles de calcul mal
  raccordées — les trois couches sont sur exactement la même grille de
  25 m, et
  [`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
  aurait refusé sinon. Ce sont les **mailles de la grille météo**, 3,2 ×
  3,9 km, descendues à 25 m au plus proche voisin : un rapport de 126
  pour 1. Le bilinéaire aurait lissé l’escalier en dessinant une
  variation que la donnée n’a jamais mesurée.
- La section ajoute la comparaison qui remet l’échelle en place : avec
  le vrai produit CEMS à 0,25°, les mailles font environ 19 × 28 km et
  **toute l’emprise de l’étude tiendrait dans une seule**. La carte ne
  serait alors plus pavée du tout, ce qui est le même aveu sous une
  forme moins visible.
- Un graphique côte à côte montre le danger météo et la disponibilité en
  combustible à la même résolution, pour que la différence de contenu
  soit lisible.

## firexpovulnR 0.9.2 (2026-08-17)

- Vignette Couchey : les périmètres d’incendie sont tracés en **rouge**
  et non plus en noir, sur les trois cartes. Le noir se confondait avec
  les traits de contour du raster ; le rouge se lit sur la palette
  continue comme sur le masque binaire, et c’est la convention à
  laquelle un lecteur s’attend pour une surface brûlée.

## firexpovulnR 0.9.1 (2026-08-16)

#### L’incendie du 29 juillet 2026 à Couchey

- L’extrait Couchey est reconstruit sur la période 2016-2026 et contient
  désormais **trois** incendies, dont celui qui a brûlé la commune
  elle-même : **124 ha, déclaré le 29 juillet 2026 à 13 h 42, éteint le
  lendemain à 2 h 15**. `PERCNA2K = 100` — la totalité en site Natura
  2000 — et l’occupation du sol brûlée est à 60 % de feuillus et 17 % de
  forêt mixte, c’est-à-dire le combustible que les poids par défaut du
  package classent en bas de leur échelle.
- L’emprise passe de 160 à 292 km² pour couvrir les trois feux, ce qui
  fait entrer un second département : le millésime y compte maintenant
  **trois** campagnes candidates, 2007, 2010 et 2014, à un tiers de
  surface chacune.
- Le contrôle de biais temporel n’a jamais été aussi net : **100 % de la
  surface brûlée postdate le millésime de plus de cinq ans**, et
  l’incendie de Couchey de dix-neuf ans. L’article conclut donc que la
  carte ne peut pas être validée avec cette donnée, plutôt que de
  publier un AUC.
- Les attributs EFFIS utiles sont conservés dans l’extrait — `COMMUNE`,
  `CLASS`, `PERCNA2K` et la ventilation par occupation du sol — pour que
  l’article n’affirme rien qu’il ne puisse sourcer.

## firexpovulnR 0.9.0 (2026-08-16)

Un exemple sur données réelles, et il ne se passe pas bien — ce qui est
le sujet.

#### Article « Couchey »

- [`vignette("couchey")`](https://pobsteta.github.io/firexpovulnR/articles/couchey.md)
  déroule la chaîne complète sur **Couchey** (Côte-d’Or), territoire de
  référence du projet voisin `nemetonshiny`, à partir de données réelles
  : BD Forêt v2 (568 formations), CORINE 2018 (99 polygones) et une
  surface brûlée EFFIS. Seule la météo est synthétique, faute de jeton
  Copernicus, et l’article le dit.
- Le terrain est l’inverse de celui pour lequel le package a été conçu :
  chênaie, hêtraie et charmaie de plaine, avec des vignes là où un
  exemple varois aurait de la garrigue. C’est délibéré — un exemple
  complaisant n’apprend rien sur les limites des valeurs par défaut.
- **Le millésime y est ambigu à 50/50** : deux campagnes BD ORTHO, 2010
  et 2014, à 49,9 % et 50,1 % de la surface. Cas d’école de ce que
  [`fev_bdforet_millesime()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdforet_millesime.md)
  refuse de trancher.
- **La validation échoue, et c’est le résultat.** L’endpoint public
  EFFIS sert un seul feu sur 160 km² et neuf ans — 26 ha, 31 juillet
  2020 — qui postdate le millésime prudent de dix ans. Le contrôle de
  biais temporel rapporte 100 % de surface brûlée au-delà du seuil, et
  `max_lag_years = 5` vide l’échantillon. La conclusion honnête n’est
  pas un AUC mais « cette carte ne peut pas être validée avec cette
  donnée », et l’article la formule ainsi.
- L’AUC est montré quand même, avec la mention explicite qu’il n’a pas
  de valeur probante ici — par omission il aurait été plus flatteur.

#### Données livrées

- `inst/extdata/couchey.gpkg` (1,3 Mo, six couches) est construit par
  `data-raw/build_couchey_extract.R`, qui contacte les services réels.
  L’article lit le disque : une documentation rouge ne doit pas être un
  bulletin de disponibilité de l’IGN.
- Les géométries sont simplifiées à 10 m, bien sous la grille de travail
  de 25 m, ce qui conserve 99,89 % de la surface et ramène le fichier de
  5,0 à 1,3 Mo. Décision d’empaquetage, pas d’analyse.

## firexpovulnR 0.8.0 (2026-08-16)

Le dernier blocage du rapport de faisabilité tombe. Le millésime de la
BD Forêt v2 est récupérable, et pas par un contournement.

759 tests hors ligne, aucun échec. `R CMD check` sans erreur,
avertissement ni note. Tests d’intégration passés contre le service IGN
réel.

#### Le millésime BD Forêt v2, retrouvé

- **L’IGN définit le millésime comme la date de la prise de vue.**
  *Descriptif de contenu BD Forêt® Version 2*, septembre 2014, §2.3 : «
  La date de validation est celle de la prise de vues de la BD ORTHO®
  servant à la production des données. » Ce n’est donc pas un proxy : la
  base décrit le peuplement tel que le photo-interprète l’a vu sur
  l’image infrarouge, et la date du vol est la date de l’état de paysage
  enregistré.
- [`fev_bdforet_millesime()`](https://pobsteta.github.io/firexpovulnR/reference/fev_bdforet_millesime.md)
  va chercher ces dates dans le graphe de mosaïquage de la BD ORTHO,
  dont l’IGN archive des tranches par période. Le champ `date_vol` y est
  une vraie date, par polygone, avec le département et la campagne.
- `fev_fetch_bdforet(millesime = "auto")` enchaîne le tout.
- **La réserve est réelle et elle est portée par le code.** Un
  département est revolé tous les cinq ans environ, donc la fenêtre
  2007-2018 en contient généralement deux — le Var a 2008 et 2014 — et
  l’IGN ne publie pas laquelle a alimenté quelle production. La fonction
  rend les candidats avec la part de surface de chacun et **refuse de
  trancher**. `strategy = "oldest"` donne la lecture conservatrice :
  supposer la campagne la plus ancienne maximise l’écart que
  [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
  rapporte, ce qui penche du côté de signaler le biais plutôt que de le
  masquer.
- Le schéma WFS de la BD Forêt v2 a été revérifié : aucun champ de date,
  ce qui confirme le constat de phase 2 et fait du graphe de mosaïquage
  la seule voie qui ne relève pas de la conjecture.
- `specs/phase2-rapport-faisabilite.md` passe le point 2 bis de « bloqué
  » à « résolu », en addendum daté — le constat d’origine reste lisible.

## firexpovulnR 0.7.0 (2026-08-16)

Dernière phase du brief. La chaîne cible s’exécute désormais de bout en
bout, et la vignette la déroule sans réseau.

729 tests hors ligne, aucun échec. `R CMD check` sans erreur,
avertissement ni note.

#### Combinaison et risque

- [`fev_risk()`](https://pobsteta.github.io/firexpovulnR/reference/fev_risk.md)
  livre les trois méthodes du brief, et elles ne répondent pas à la même
  question. `"effis_mean"` normalise puis fait la moyenne à poids égaux.
  `"pareto"` rend le **front de Pareto** — un ensemble, pas un score :
  les cellules qu’on ne peut améliorer sur une dimension sans dégrader
  l’autre. `"weighted"` exige ses poids et les inscrit, faute de défaut
  défendable.
- Les deux premières viennent du workflow CLIMAAX, dont le carnet a été
  lu le 2026-08-16 plutôt que paraphrasé :
  `danger_index=(clim_norm+burn_norm)/2` et
  `paretoset(..., sense=[max,...])` sont recopiés de son propre code.
- La normalisation min-max par défaut **réétire** une couche déjà mise à
  l’échelle : c’est ce que fait CLIMAAX, la doc le dit, et
  `normalise = "none"` existe pour l’éviter.
- Le balayage de dominance est quadratique dans le nombre de
  combinaisons distinctes. Il travaille donc sur les tuples arrondis et
  **refuse** au-delà d’un seuil, plutôt que de tourner une après-midi.

#### Validation, et le biais temporel

- [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
  rend une AUC, une courbe ROC et la répartition observé/attendu par
  classe de risque — cette dernière dans la forme de
  [`fireexposuR::fire_exp_validate()`](https://docs.ropensci.org/fireexposuR/reference/fire_exp_validate.html),
  dont les bornes par défaut sont reprises.
- **Le contrôle de biais temporel tourne avant toute statistique de
  skill.** Chaque feu est comparé au millésime du combustible, lu dans
  la provenance, et la fonction avertit avec un chiffre : « 28,6 % de la
  surface brûlée postdate le millésime de plus de 5 ans ».
  `max_lag_years` filtre.
- Le millésime n’a pas à être redonné quand la couche vient de la chaîne
  : il voyage depuis
  [`fev_fuel_source()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_source.md).
  Quand il est inconnu, le contrôle ne peut pas tourner — la fonction
  refuse si on demandait un filtrage, et avertit bruyamment sinon.
- Aucun intervalle de confiance n’est rendu sur l’AUC, et la doc dit
  pourquoi : les cellules ne sont pas des observations indépendantes, un
  feu est contigu, et un intervalle bâti sur le nombre de cellules
  serait très trop étroit.

#### Coût de l’exposition

- Découverte reprise du projet nemeton, qui a rencontré le problème en
  production avec la même métrique : la fenêtre focale est exprimée en
  mètres mais matérialisée en cellules, donc le coût varie comme
  l’inverse de la puissance quatrième de la maille.
  [`fev_exposure()`](https://pobsteta.github.io/firexpovulnR/reference/fev_exposure.md)
  estime ce coût **avant** de commencer et propose une taille de maille,
  plutôt que de sembler bloqué.
- `filename` et `wopt` sont passés à `terra`, ce qui rend un traitement
  départemental possible par blocs.
- **Test de charge documenté sur une emprise réaliste**, comme le
  demande le brief : 6 006 km² à 25 m avec un rayon de 500 m — la taille
  du Var — en 61 à 83 secondes, 155 Mo de pointe, débit d’environ 170
  millions d’opérations pondérées par seconde. Le test vit dans la
  suite, désactivé sauf `FIREXPOVULNR_TEST_LOAD=1`.

#### Vignette

- [`vignette("firexpovulnR")`](https://pobsteta.github.io/firexpovulnR/articles/firexpovulnR.md)
  déroule la chaîne complète sur un paysage synthétique, sans réseau,
  avec les appels réels montrés à leur place dans des blocs non
  exécutés. Elle se termine par ce que la chaîne ne sait pas, par ordre
  d’importance décroissante — le sous-étage d’abord.

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
  Sans lui le contrôle de biais temporel de
  [`fev_validate()`](https://pobsteta.github.io/firexpovulnR/reference/fev_validate.md)
  ne pourra pas tourner ; `millesime = NA` explicite est accepté et
  averti.
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
