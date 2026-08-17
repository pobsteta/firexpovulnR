# Phase 9 — rapport de vérification : météo d'incendie sans jeton

Vérifications faites le **2026-08-17** par appels réels. Chaque chiffre cité ici
a été mesuré, pas estimé.

## 1. Le problème

Les deux articles du site (`couchey`, `maures`) fabriquaient leur météo avec
`rnorm()`. La raison était réelle — le produit historique CEMS
(`fev_fetch_fwi()`) demande un jeton Copernicus personnel, et le brief interdit
au package de manipuler un jeton — mais le résultat ne l'était pas : un package
dont la première exigence est la traçabilité livrait deux exemples travaillés
reposant sur des nombres inventés, et qui ne pouvaient rien dire des incendies
autour desquels ils étaient construits.

## 2. La source retenue

**Open-Meteo, archive historique**, `https://archive-api.open-meteo.com/v1/archive`.

| Point vérifié | Résultat |
|---|---|
| Authentification | **aucune** — HTTP 200 sans en-tête ni clé |
| Variables | `temperature_2m`, `relative_humidity_2m`, `wind_speed_10m`, `precipitation` |
| Unités | °C, %, **km/h**, mm |
| Pas de temps | horaire — donc l'observation de **midi** est disponible |
| Résolution | ~0,1° (ERA5-Land), contre 0,25° pour le CEMS |
| Profondeur | 1940 à aujourd'hui ; 1991 vérifié, donc la normale OMM 1991-2020 est atteignable |
| Latence | **nulle** — 24 heures valides servies pour le jour même |
| Volume | 1,3 Mo pour 4 points × 1 an horaire ; 195 Ko pour 30 ans journaliers en 1 point |

Le vent en **km/h** est l'unité que le système canadien attend. C'est le
contraste avec E-OBS, dont le `FG` est en m/s : la manière classique de se
tromper d'un facteur 3,6 sur l'ISI.

La latence nulle a une contrepartie qu'il faut dire : Open-Meteo complète les
derniers jours par un modèle de prévision. Le bout de l'enregistrement n'est
donc pas de l'ERA5.

### Ce qui a été écarté

* **CEMS / `fev_fetch_fwi()`** — reste la voie de référence, mais demande un
  jeton. Conservée, non remplacée.
* **EFFIS / GWIS WMS** (`ms:fwi_gadm_admin1.fwi`, `ms:fwi_gadm_admin2.fwi`) —
  sert le FWI et l'ISI sans jeton, mais **agrégé par région GADM**. Inutilisable
  pour une carte à 25 m.

## 3. Deux pièges mesurés

### 3.1 La pluie est un cumul, pas une observation

Le système canadien prend la pluie **cumulée sur les 24 heures précédant midi**.
La première version lisait la pluie de l'heure de midi.

| | pluie horaire à 12 h | cumul 24 h |
|---|---|---|
| Jours-points avec pluie (Maures, 3 ans) | 10 % | **39 %** |
| DC le 2021-08-16 | 1 949 | **619** |
| DMC le 2021-08-16 | 252 | **127** |

Corrigé en sommant les 24 heures et en récupérant **un jour supplémentaire en
tête de chaque tranche annuelle**, sans quoi chaque limite de tranche perdrait
la pluie de la veille au soir.

### 3.2 Et le FWI ne le montre pas

Le facteur de durée `fD = 1000 / (25 + 108.64 × exp(−0.023 × BUI))` sature :

| BUI | 150 | 200 | 250 | 300 | asymptote |
|---|---|---|---|---|---|
| fD | 35,2 | 38,3 | 39,5 | 39,8 | 40 |

Au-delà d'un BUI de 250 environ, le FWI est presque aveugle à la sécheresse
supplémentaire. Un DC dérivé au **double** de sa valeur physique ne fait donc pas
paraître le FWI faux — mesuré : FWI médian identique à 85,4 sous les deux
régimes, avant correction de la pluie. Le contrôle doit porter sur DC et BUI
directement.

**Conséquence sur un choix de conception.** Le DC gonflé ressemblait à un
redémarrage saisonnier manquant. Il ne l'était pas : la pluie corrigée, les
pluies d'hiver vidangent le DC d'elles-mêmes — 643 en intégration continue contre
619 redémarré chaque janvier, soit 4 %. `reset = "annual"` existe donc, mais le
défaut est l'intégration continue.

## 4. La maille servie n'est pas une clé

Le service renvoie les coordonnées de la maille qu'il a lue, et plusieurs points
demandés peuvent y tomber ensemble **sans partager la même série** : la
température est corrigée de l'altitude du point demandé.

Mesuré le 2021-08-16, maille 43,40949 / 6,341829 :

| Point demandé | Altitude rendue | Température |
|---|---|---|
| 43,4 / 6,30 | 274 m | 34,8 °C |
| 43,4 / 6,35 | 221 m | 34,8 °C |
| 43,4 / 6,40 | 77 m | 35,4 °C |

Le vent, lui, est identique (29,9 km/h) : la correction porte sur la température
seule. L'identité de station suit donc le **point demandé** ; la maille servie et
son altitude voyagent dans la provenance.

Corollaire à ne pas perdre de vue : ce n'est pas une extraction brute de
réanalyse. La correction altitudinale aide en relief et s'écarte du CEMS, qui lit
sa maille et s'arrête.

## 5. Appariement et limites de service

* Les séries reviennent **dans l'ordre de la requête** et rien dans la réponse ne
  les y ramène. L'ordre est donc porteur ; seul le compte est vérifiable, et un
  écart est traité en erreur.
* **HTTP 429** observé sur 20 points × 1 an : réessai avec attente croissante,
  plus une pause entre tranches.
* **HTTP 400** pour toute date de fin postérieure à aujourd'hui. La veille passe.
  Une période qui dépasse est bornée avec message plutôt que de faire échouer la
  dernière tranche après le téléchargement de toutes les autres.
* Les réponses d'erreur JSON (`{"error":true,...}`) arrivent en HTTP 400, donc
  hors de portée de `readLines()`. La branche existe par prudence et le dit.

## 6. `cffdrs` : ce qui a été vérifié

* `fwi(batch = TRUE)` accumule les codes **indépendamment par `id`** — vérifié :
  deux stations aux mêmes valeurs de départ mais météo différente divergent
  correctement (DC 57,0 contre 48,0 sur 5 jours).
* `fwiRaster()` ne prend que des codes de départ **scalaires** : la voie raster
  porterait la sécheresse en moyenne spatiale. C'est la raison de passer par la
  table.
* `fwi()` exige que toutes les stations d'un lot couvrent **les mêmes dates**, ce
  qui interdit d'implémenter le redémarrage annuel par un `id` par point-année.
  Il est fait par un appel `cffdrs` par saison.
* L'avertissement `NaNs produced` vient d'un `ifelse()` qui évalue ses deux
  branches. Vérifié sur 1 836 jours-points : **aucun NaN** n'atteint les sept
  colonnes de sortie. Étouffé nommément, et la sortie vérifiée à la place.

## 7. Résultat sur les deux territoires

Aucune donnée de feu n'entre dans le calcul du FWI.

| | Couchey | Les Maures |
|---|---|---|
| Période livrée | 2024-2026, 16 points, 15 360 jours-points | 2019-2021, 20 points, 21 920 jours-points |
| Jour de l'incendie | 2026-07-29 | 2021-08-16 |
| Météo ce jour-là | 34–36 °C, 19-21 % HR, 13-16 km/h | 35 °C, 22 % HR, 24 km/h |
| Pluie sur 24 h | 0 mm | 0 mm |
| FWI médian | 50,8 | 84,2 |
| DC / BUI | 439-577 / 88-139 | 522-656 / 169-223 |
| **Rang du jour** | **2e sur 960** | **1er sur 1 096** |

Ce que cela vaut, et ce que cela ne vaut pas : ce n'est pas une validation du
modèle de risque. Un incendie ne fait pas un échantillon, et un jour de canicule
est aussi un jour où l'on allume plus de départs. Ce que cela montre est que la
voie Open-Meteo → `cffdrs` produit un signal qui tombe au bon endroit sur les
deux seuls événements que ces territoires offrent — ce qu'une série `rnorm()` ne
pouvait par construction jamais montrer.

## 8. À refaire si un test réseau tombe

Les valeurs épinglées dans `tests/testthat/test-integration-network.R` sont les
quatre variables du 2021-08-16 au point 43,3 N / 6,4 E (33,8 °C, 21 %,
25,6 km/h, 0 mm) et le rang du 16 août dans la saison 2021. Une dérive signifie
que l'archive a été révisée : régénérer les tables par
`data-raw/build_weather_extracts.R` et refaire les figures des deux articles,
plutôt que de laisser les légendes contredire les chiffres.
