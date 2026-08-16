# Phase 2 — Rapport de faisabilité des sources externes

**Date de vérification : 2026-08-15.** Toutes les valeurs ci-dessous ont été
constatées à leur source ce jour-là, soit par appel réseau réel depuis la
machine de développement, soit par lecture de la documentation officielle,
soit par lecture du code source du package concerné. La colonne « Constaté
comment » précise laquelle de ces trois voies a servi.

Ce document est la référence de traçabilité des constantes du package. Toute
valeur codée en dur ailleurs que dans un défaut d'argument documenté est un
bug. Toute valeur qui change côté fournisseur doit être re-vérifiée ici, et la
date ci-dessus mise à jour.

---

## 1. CEMS fire danger / EWDS — RÉSOLU

**`ecmwfr` supporte bien l'EWDS.** Pas besoin du client `httr2` de repli
qu'envisageait le brief.

| Élément | Valeur vérifiée | Constaté comment |
|---|---|---|
| Version CRAN d'`ecmwfr` | `2.0.3` | `available.packages()` |
| Identifiant de service EWDS | `"cems"` | code source, `R/wf_datasets.R:29` : `service = c("cds","ads","cems")` |
| URL de l'API | `https://ewds.climate.copernicus.eu/api` | code source, `R/zzz.R:22` : `cems_url <- "https://ewds.climate.copernicus.eu/api"` |
| Identifiant du dataset | `cems-fire-historical-v1` | page dataset EWDS + user guide ECMWF |
| Couverture temporelle | 1940 à aujourd'hui, pas de temps journalier | page dataset EWDS |
| Résolution | 0,25° (réanalyse) / 0,5° (membres d'ensemble) | page dataset EWDS |

Noms de variables exacts pour le système canadien FWI (user guide ECMWF) :

```
fine_fuel_moisture_code   duff_moisture_code       drought_code
initial_spread_index      build_up_index           fire_weather_index
fire_daily_severity_index
```

Autres clés de requête relevées dans les exemples du user guide :
`product_type = 'reanalysis'`, `dataset_type = 'consolidated_dataset'`,
`system_version = '4_1'`, `grid = '0.5/0.5'`, `format = 'grib'`.

**Réserves.**

- La page de présentation du dataset annonce 0,25° pour la réanalyse, alors que
  les exemples du user guide utilisent `grid = '0.5/0.5'`. Divergence non
  résolue : `grid` doit rester un argument explicite, jamais un défaut caché.
- Aucun appel réel n'a été effectué : l'EWDS exige une clé API personnelle,
  et le brief interdit toute manipulation de token de mon côté. Le client
  devra donc être testé par mock `httptest2` et par un test d'intégration
  `skip_if_offline()` + `skip_if(is.na(Sys.getenv("ECMWF_KEY", NA)))`.
- `system_version = '4_1'` est un numéro de version de système susceptible de
  changer. Argument explicite obligatoire.

---

## 2. BD Forêt v2 — RÉSOLU, sauf les millésimes

**L'ancienne voie Géoservices est morte.**
`https://geoservices.ign.fr/documentation/donnees/vecteur/bdforet` répond
`301 Moved Permanently` vers `https://cartes.gouv.fr/rechercher-une-donnee/search`.
La page d'aide cartes.gouv.fr ne documente ni URL de téléchargement, ni
endpoint, ni nomenclature, ni millésime.

**Mais le WFS de la Géoplateforme expose BD Forêt v2 directement, sans
authentification.** C'est une bien meilleure voie que le téléchargement
département par département envisagé par le brief : on filtre par emprise
côté serveur, donc on ne télécharge que l'AOI.

| Élément | Valeur vérifiée |
|---|---|
| Endpoint | `https://data.geopf.fr/wfs/ows` |
| Couche | `LANDCOVER.FORESTINVENTORY.V2:formation_vegetale` |
| Attributs | `id`, `code_tfv`, `tfv`, `tfv_g11`, `essence`, `geom` |
| Authentification | aucune |
| Ordre des axes du BBOX | **easting-first** en `EPSG:2154` |
| Formats | `application/json` (GeoJSON) confirmé |

Constaté par appel réel : `DescribeFeatureType` pour le schéma, puis
`GetFeature` sur une emprise de 10 × 10 km dans le massif des Maures →
`numberMatched = 755`. L'ordre des axes a été déterminé expérimentalement :
`BBOX=970000,6243000,982000,6253000,EPSG:2154` renvoie 755 entités, l'ordre
inverse en renvoie 0. À ne pas déduire de la spécification WFS 2.0, qui
prescrit l'inverse pour les CRS projetés — **le serveur ne la respecte pas**.

CORINE Land Cover est exposé sur le **même** endpoint :
`LANDCOVER.CLC18_FR:clc18_fr`, attributs `id`, `code_18`, `area_ha`, `remark`,
`shape_leng`, `shape_area`, `geom`. Voir le point 3.

### 2 bis. Millésimes par département — NON TROUVÉ en phase 2, RÉSOLU en phase 7

> **Mise à jour du 2026-08-16.** Ce point n'est plus un blocage : l'IGN définit
> le millésime comme la date de prise de vue de la BD ORTHO, et cette date est
> publiée dans le graphe de mosaïquage archivé. Voir l'addendum (2) en fin de
> document. Le constat d'origine est conservé tel quel ci-dessous.

Le millésime **n'est pas un attribut de la couche WFS**. Il est absent du
schéma `DescribeFeatureType`, donc indisponible par la voie d'acquisition
retenue. Il est également absent des pages IGN consultées
(cartes.gouv.fr/aide, inventaire-forestier.ign.fr article 646), qui se bornent
à indiquer que la base est « un assemblage de millésimes de 2007 à 2018 »,
élaborée par couverture départementale.

**Vérifié aussi dans les projets existants de l'auteur**, sur indication
explicite : `foretaccess/inst/datasources/FR.json` déclare `bdforet_v2` avec
seulement `service`, `typename` et `description` — pas de champ millésime ;
`grep -rniE "millesime|vintage"` sur `foretaccess/R/` et `foretaccess/inst/`
ne renvoie rien. Dans `nemeton`, la notion de `millesime` existe bien, mais
**uniquement pour l'IFN** (`R/ifn_source.R`, `R/ifn_tables.R`), pas pour la
BD Forêt. Aucun des projets nemeton ne porte donc cette table.

Conformément à la consigne du brief — aller chercher cette table, ne pas la
reconstituer — **elle n'est pas reconstituée ici**. Le contrôle de biais
temporel de `fev_validate()` est donc bloqué sur sa donnée d'entrée, et le
package doit se comporter honnêtement en son absence : voir « Décisions à
prendre » plus bas.

### 2 ter. Acquisition WFS — patron à réutiliser, et un piège à éviter

`foretaccess::acquire_foret()` (projet local de l'auteur) confirme
indépendamment la voie WFS retenue ici, et fournit un patron d'acquisition
mûr, directement transposable aux exigences de provenance du brief :

- **tuilage de l'emprise** avec chevauchement de 5 % entre tuiles, puis
  déduplication (`.fetch_wfs()`, `.tuiles_bbox()`, `.dedupe_features()`), via
  `happign::get_wfs()` qui gère la pagination du serveur IGN ;
- **cache avec provenance et politique explicite** : `.provenance_ecrire()`,
  `cache_utilisable()`, et un argument `politique_cache` à quatre valeurs
  (`"reacquerir"`, `"avertir"`, `"echouer"`, `"ignorer"`) qui traite le cas
  d'un cache produit avec d'autres paramètres.

À l'inverse, `nemetonshiny:::download_ign_bdforet()` construit l'URL WFS à la
main avec `COUNT=10000` **sans pagination** : au-delà de 10 000 entités, la
troncature est silencieuse. Sur le seul massif des Maures, une emprise de
120 × 120 km renvoie `numberMatched = 49069`. Ce plafond ne doit pas être
reproduit ici.

**Piège sémantique à ne pas hériter.** `acquire_foret()` exclut par défaut
(`exclure_landes = TRUE`) les codes `LA4` (landes ligneuses) et `LA6` (landes
herbacées), conformément au masque forêt d'ACCESSFOR, au motif qu'« une lande
n'est pas une ressource à mobiliser ». Pour une chaîne de risque incendie,
**c'est exactement le contraire qu'il faut** : `LA4` recouvre le maquis et la
garrigue, parmi les combustibles les plus inflammables du bassin
méditerranéen, et `LA6` porte la strate herbacée qui gouverne la propagation
de surface. La sémantique « forêt exploitable » et la sémantique
« combustible » sont ici opposées. Réutiliser cette fonction telle quelle
retirerait silencieusement du masque le combustible le plus dangereux.

---

## 3. CORINE Land Cover — CONTOURNÉ pour la France

L'accès CLMS avec authentification manuelle qu'anticipait le brief **n'est pas
nécessaire pour la France métropolitaine** : la Géoplateforme rediffuse CORINE
sur le WFS déjà utilisé pour la BD Forêt, sans authentification.

| Élément | Valeur vérifiée |
|---|---|
| Endpoint | `https://data.geopf.fr/wfs/ows` |
| Couche CLC 2018 France | `LANDCOVER.CLC18_FR:clc18_fr` |
| Attribut de classe | `code_18` (nomenclature CORINE niveau 3) |
| Autres millésimes | `CLC90_FR`, `CLC00_FR`, `CLC06_FR`, `CLC12_FR`, `CLC18_FR` (+ variantes `_DOM` et révisées `R`) |
| Couches de changement | `CHA00_FR`, `CHA06_FR`, `CHA12_FR`, `CHA18_FR` |

Conséquence sur l'API : `fev_fetch_corine()` peut être un vrai client pour la
France, et non l'assistant guidé de validation de fichier local qu'envisageait
le brief. **Pour une étude multi-pays, en revanche, la voie CLMS reste
nécessaire et n'a pas été vérifiée.** Le mode « fichier local validé » doit
donc exister quand même, en repli documenté.

---

## 4. Aires brûlées EFFIS/GWIS — RÉSOLU, avec une réserve de couverture

Le WFS EFFIS fonctionne, mais pas comme le suggéraient les recherches
initiales : la couche s'appelle `ms:modis.ba.poly`, et non `nrt.ba.poly`.
Les couches `nrt.ba.*` existent en **WMS uniquement** (rendu image) et ne sont
pas interrogeables en WFS. Le WFS de `ies-ows.jrc.ec.europa.eu/gwis` n'expose
que des couches administratives et FWI par région GADM, pas les aires brûlées.

```
https://maps.effis.emergency.copernicus.eu/effis
  ?service=WFS&version=1.1.0&request=getfeature
  &typename=ms:modis.ba.poly
  &outputformat=SHAPEZIP
  &bbox=<xmin>,<ymin>,<xmax>,<ymax>
```

Constaté par téléchargement réel sur le Var (`bbox=6.0,43.0,7.0,43.7`) :
`HTTP 200`, 415 630 octets, 0,52 s, archive ZIP valide contenant
`modis.ba.poly.{shp,shx,dbf,prj}`, relue avec succès par `sf` → 63 entités.

Attributs (`DescribeFeatureType`) :

```
id  FIREDATE  FINALDATE  LASTUPDATE  COUNTRY  PROVINCE  COMMUNE  AREA_HA
BROADLEA  CONIFER  MIXED  SCLEROPH  TRANSIT  OTHERNATLC  AGRIAREAS
ARTIFSURF  OTHERLC  PERCNA2K  CLASS
```

`FIREDATE` est la donnée qui rend possible le contrôle de biais temporel
demandé par le brief — à condition d'avoir les millésimes en face (point 2 bis).
`PERCNA2K` (pourcentage Natura 2000) et la ventilation par occupation du sol
sont un bonus directement exploitable côté vulnérabilité.

**Deux réserves à traiter dans le code, pas seulement à documenter.**

1. **Couverture temporelle réelle : 2016 → 2026**, pas 2006. Sur l'échantillon
   du Var, `min(FIREDATE) = 2016-07-18`. Le workflow cible du brief demande
   `period = c("2006", "2023")` : **cette période n'est pas servie par
   l'endpoint public**. La documentation EFFIS le confirme : « For any request
   of data which is not available through the EFFIS Web services (e.g. historic
   data, extracts of the fire database, or raw burned area perimeters) we
   kindly ask you to use our DATA REQUEST FORM. » `fev_fetch_burnt()` doit
   donc comparer la période demandée à la période réellement retournée et
   avertir chiffré, sans quoi l'utilisateur croira valider sur 18 ans alors
   qu'il valide sur 10.
2. **Le `.prj` livré déclare `GCS_unknown`** :
   `GEOGCS["GCS_unknown",DATUM["D_WGS_1984",...]]`. `sf::st_crs()` renvoie
   `unknown`. C'est du WGS84 géographique non déclaré : le CRS devra être
   forcé explicitement à `EPSG:4326` et l'opération journalisée dans la
   provenance, jamais appliquée en silence.

---

## 5. Rayons d'exposition Beverly et al. — PARTIEL

**Beverly et al. 2010**, *Assessing the exposure of the built environment to
potential ignition sources generated from vegetative fuel*, Int. J. Wildland
Fire 19:299–313. Distances de transmission par processus d'allumage :

| Processus | Distance |
|---|---|
| Chaleur radiante | 0,1 – 30 m |
| Brandons courte portée | 0,1 – 100 m |
| Brandons longue portée | 100,1 – 500 m |

Terrain : quatre communautés de l'Alberta, Canada.

**`fireexposuR` 1.2.0**, valeurs par défaut relevées directement sur les
signatures du package installé :

```r
fire_exp(hazard, t_dist = 500, no_burn, tdist)
fire_exp_dir(exposure, value, t_lengths = c(5000, 5000, 5000),
             interval = 1, thresh_exp = 0.6, thresh_viable = 0.8,
             table = FALSE)
fire_exp_validate(burnableexposure, fires, aoi,
                  class_breaks = c(0.2, 0.4, 0.6, 0.8, 1),
                  samplesize = 0.005)
```

**Non vérifié : Beverly et al. 2021** (*A simple metric of landscape fire
exposure*, Landscape Ecology) — l'article est derrière l'authentification
Springer. Les distances par type de combustible qu'il définit n'ont donc
**pas** été lues à la source. Beverly et al. 2023 n'a pas été localisé de
façon certaine. Tant que ces deux références ne sont pas lues, les seuls
rayons que le package peut citer avec une source sont ceux de 2010 et les
défauts de `fireexposuR` — et c'est ce qu'il doit dire.

Rappel du brief, à faire porter par un message `cli` au premier appel de
`fev_exposure()` : ces rayons proviennent de combustibles boréaux et
conifériens canadiens ; sur chêne vert, garrigue ou maquis ils doivent être
justifiés ou recalibrés.

---

## 6. Classes de danger FWI EFFIS — RÉSOLU

Relevé sur la page officielle EFFIS *Fire Danger Forecast* :

| Classe | Bornes FWI |
|---|---|
| Low | < 11,2 |
| Moderate | 11,2 – 21,3 |
| High | 21,3 – 38,0 |
| Very High | 38,0 – 50,0 |
| Extreme | 50,0 – 70,0 |
| Very Extreme | > 70,0 |

La classe *Very Extreme* a été introduite en juin 2021 pour discriminer à
l'intérieur des vastes zones classées *Extreme* en Méditerranée l'été.

**Point de vigilance.** Une valeur de seuil « Very Low < 5,2 » circule
largement dans la littérature et les sites tiers. **Elle n'apparaît pas sur la
page EFFIS actuelle**, qui ne définit que six classes à partir de *Low*. Le
défaut du package suit la page officielle ; le seuil 5,2 ne doit pas être
ajouté au motif qu'il est répandu.

EFFIS fait tourner deux modèles météo déterministes : ECMWF à ~8 km (prévision
1 à 9 jours) et Météo-France à ~10 km (jusqu'à 3 jours). À rapprocher des
0,25°/0,5° du produit historique EWDS du point 1 : **ce ne sont pas les mêmes
résolutions**, et une carte opérationnelle EFFIS n'est donc pas directement
comparable à une climatologie EWDS.

---

## 7. Nomenclature BD Forêt v2 (TFV) — RÉSOLU

**La table complète des 32 postes existe déjà dans les projets de l'auteur** :
`nemeton/inst/extdata/bdforet_v2_mapping.csv`, 32 lignes, exposée par
`nemeton::bdforet_v2_mapping()`. Le compte correspond exactement aux « 32
postes » annoncés par cartes.gouv.fr. Colonnes : `tfv_code`, `label_fr`,
`species_class`, `context_key`, `confidence` (`"clear"` / `"ambiguous"`),
`alt_context_key`, `notes_fr`, `label_key`.

C'est de surcroît le patron exact que le brief demande pour les tables de
correspondance du module combustible : une justification par ligne
(`notes_fr`), un marqueur de confiance explicite (`confidence`), une
alternative pour les cas ambigus (`alt_context_key`), et une surcharge
utilisateur par argument `file`.

Codes relevés :

```
FF0  FF1-00  FF1G01-01  FF1G06-06  FF1-09-09  FF1-10-10  FF1-14-14
FF1-49-49  FF1-00-00  FF2-00  FF2-51-51  FF2-52-52  FF2G53-53  FF2-57-57
FF2G58-58  FF2-81-81  FF2-80-80  FF2G61-61  FF2-63-63  FF2-64-64  FF2-91-91
FF2-90-90  FF2-00-00  FF31  FF32  FO0  FO1  FO2  FO3  FP  LA4  LA6
```

La table de correspondance combustible de `firexpovulnR` reprendra cette
liste de codes — **mais pas ses valeurs cibles** : `species_class` et
`context_key` encodent une sémantique sylvicole (structure de peuplement,
coefficient de variation d'échantillonnage) sans rapport avec l'inflammabilité.
La colonne cible sera reconstruite de zéro, avec sa propre justification par
ligne, et re-vérifiée contre le WFS.

Confirmation indépendante par la donnée elle-même : la nomenclature est aussi
lisible **dans les attributs servis** — chaque entité porte `code_tfv`, son
libellé `tfv` et son regroupement `tfv_g11`. Une requête
`GetFeature` avec `PROPERTYNAME=code_tfv,tfv,tfv_g11,essence` sur le
Var/Maures (5 000 entités sur 49 069 correspondantes, 1,2 s) a livré 25 codes
distincts, dont ceux qui comptent en contexte méditerranéen :

| `code_tfv` | `tfv_g11` | `tfv` |
|---|---|---|
| `FF1G06-06` | Forêt fermée feuillus | Forêt fermée de chênes sempervirents purs |
| `FF1G01-01` | Forêt fermée feuillus | Forêt fermée de chênes décidus purs |
| `FF2-57-57` | Forêt fermée conifères | Forêt fermée de pin d'Alep pur |
| `FF2-51-51` | Forêt fermée conifères | Forêt fermée de pin maritime pur |
| `FF2G53-53` | Forêt fermée conifères | Forêt fermée de pin laricio ou pin noir pur |
| `LA4` | Lande | Lande |
| `LA6` | Formation herbacée | Formation herbacée |
| `FO1` / `FO2` / `FO3` | Forêt ouverte … | Forêt ouverte feuillus / conifères / mixte |
| `FF0` / `FO0` | … sans couvert arboré | Forêt fermée / ouverte sans couvert arboré |

Cette extraction **n'est pas une reconstitution** : les libellés sont ceux que
le producteur sert avec la donnée. La table complète (annoncée à 32 postes par
cartes.gouv.fr) sera construite en `data-raw/` par balayage de la France
entière, avec le script d'extraction versionné à côté — donc reproductible et
vérifiable, ce qui est l'exigence du brief.

La distinction *forêt fermée* / *forêt ouverte* est directement pertinente pour
le combustible : `FO*` correspond à un couvert arboré de 10 à 40 %, donc à une
strate herbacée ou arbustive continue sous les arbres. C'est l'information la
plus proche du sous-étage que la base contienne — et elle reste très en deçà de
ce que la propagation de surface demanderait.

---

## Synthèse

| # | Point | État | Effet sur l'architecture |
|---|---|---|---|
| 1 | CEMS / EWDS | ✅ résolu | `ecmwfr` retenu, `service = "cems"`. Pas de client `httr2` maison. Non testé en réel (clé requise). |
| 2 | BD Forêt v2 | ✅ résolu | WFS Géoplateforme filtré par AOI. **Meilleur** que le téléchargement départemental prévu. |
| 2b | Millésimes | ✅ résolu en phase 7 | Le millésime **est** la date de prise de vue BD ORTHO, dit par l'IGN. Récupérable par le graphe de mosaïquage archivé. Voir l'addendum du 2026-08-16 (2). |
| 3 | CORINE | ✅ contourné (France) | Vrai client possible, pas seulement un assistant. Multi-pays non vérifié. |
| 4 | EFFIS burnt areas | ✅ résolu | `ms:modis.ba.poly` en SHAPEZIP. **Couverture 2016+, pas 2006.** CRS à forcer. |
| 5 | Rayons Beverly | ✅ résolu en phase 6 | Distances 2021 et paramètres 2023 constatés via la doc `fireexposuR` ; validation portugaise trouvée. Voir l'addendum du 2026-08-16. |
| 6 | Seuils FWI EFFIS | ✅ résolu | 6 classes officielles. Pas de « Very Low ». |
| 7 | Nomenclature TFV | ✅ résolu | 32 postes dans `nemeton::bdforet_v2_mapping()`, recoupés avec le WFS. |

---

## Décisions à prendre avant la Phase 3

1. **Millésimes BD Forêt.** Sans cette table, `fev_validate(max_lag_years=)`
   ne peut pas produire l'avertissement chiffré demandé. Trois options, par
   ordre de préférence décroissante : (a) fournir la table nous-mêmes si elle
   existe hors ligne, dans la doc produit livrée avec les données ; (b) exposer
   `millesime` comme argument obligatoire de `fev_fuel_source()`, sans défaut,
   de sorte que l'utilisateur qui ne le renseigne pas obtienne un refus
   explicite et non un résultat faux ; (c) désactiver le contrôle temporel et
   émettre un avertissement à chaque appel. L'option (c) est la pire : elle
   rend la fonction silencieusement inutile sur le point que le brief juge
   important.
2. **Période de validation.** Le workflow cible demande 2006–2023 ; l'accès
   public sert 2016+. Soit on réduit la période cible, soit on prévoit un
   chemin d'import d'un fichier obtenu par le formulaire de demande EFFIS.
3. **Beverly 2021 / 2023.** Si un accès à ces articles est disponible, les
   rayons par type de combustible en seront tirés. Sinon, le package ne citera
   que 2010 et les défauts `fireexposuR`, et le dira.
4. **Dépendance à `happign`.** Le tuilage WFS de `foretaccess` s'appuie sur
   `happign::get_wfs()` pour la pagination. Soit `firexpovulnR` prend la même
   dépendance, soit il réimplémente la pagination sur `httr2` avec
   `STARTINDEX`/`COUNT`. Le brief autorise les dépendances GitHub et ne
   contraint pas la taille : réutiliser `happign` évite de réécrire une
   pagination déjà éprouvée, et c'est la voie recommandée.

---

## Addendum du 2026-08-16 (2) — point 2 bis résolu : le millésime est la date de prise de vue

Le point 2 bis était le blocage le plus gênant du rapport : sans millésime par
département, le contrôle de biais temporel de `fev_validate()` n'avait pas de
donnée d'entrée. Il tombe, et pas par un contournement.

**L'IGN définit le millésime comme la date de la prise de vue.** *Descriptif de
contenu BD Forêt® Version 2*, septembre 2014, §2.3 « Actualité et mise à jour »,
lu le 2026-08-16 :

> « La réalisation de la BD Forêt® version 2 est prévue pour une couverture
> complète du territoire métropolitain début 2016. **La date de validation est
> celle de la prise de vues de la BD ORTHO® servant à la production des
> données.** »

Ce n'est donc pas un proxy. La base décrit le peuplement tel que le
photo-interprète l'a vu sur l'image infrarouge ; la date du vol est la date de
l'état de paysage enregistré — ce que le contrôle de biais temporel demande, et
sans doute mieux qu'une date de publication ne le donnerait.

**Et cette date est publiée, par polygone.** Le graphe de mosaïquage de la
BD ORTHO porte un champ `date_vol`, et l'IGN en archive des tranches par
période. Schéma constaté par `DescribeFeatureType` le 2026-08-16 :

```
dep (string)  pva (int)  res (int)  echelle (int)  date_vol (date)  geom
```

| Couche | Ce qu'elle couvre |
|---|---|
| `ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2006-2010:graphe_bdortho` | tranche 2006-2010 |
| `ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2011-2015:graphe_bdortho` | tranche 2011-2015 |
| `ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2016-2020:graphe_bdortho` | tranche 2016-2020 |

Les trois recouvrent la fenêtre de construction 2007-2018. Constaté par
`GetFeature` réel sur le Var (bbox `6.0,43.0,7.0,43.7`) :

| Département | Campagnes dans la fenêtre |
|---|---|
| 83 (Var) | 2008, 2014 |
| 06 (Alpes-Maritimes) | 2009, 2014 |
| 04 (Alpes-de-Haute-Provence) | 2009, 2015 |

**Réserve, et elle est réelle.** Un département est revolé tous les cinq ans
environ, donc la fenêtre 2007-2018 en contient généralement deux, et **l'IGN ne
publie pas laquelle a alimenté la production de quel département**.
`fev_bdforet_millesime()` rend donc les candidats avec la part de surface que
chacun couvre, et refuse de trancher. `strategy = "oldest"` donne la lecture
conservatrice : supposer la campagne la plus ancienne maximise l'écart que
`fev_validate()` rapportera, ce qui penche du côté de signaler le biais plutôt
que de le masquer.

Le schéma WFS de la BD Forêt v2 a été revérifié au passage : `id`, `code_tfv`,
`tfv`, `tfv_g11`, `essence`, `geom`. **Aucun champ de date**, ce qui confirme
le constat de phase 2 et fait du graphe de mosaïquage la seule voie qui ne
relève pas de la conjecture.

Piège rencontré : ces couches veulent un BBOX **en longitude d'abord** même en
EPSG:4326. Demander latitude d'abord rend zéro entité avec un HTTP 200 — le
même résultat vide silencieux que la phase 2 avait documenté ailleurs.

---

## Addendum du 2026-08-16 — point 5 résolu, et une réserve du brief levée

Le point 5 était marqué **⚠️ partiel** : Beverly et al. 2021 derrière
authentification Springer, 2023 non localisé, donc aucun rayon citable au-delà
de 2010. Trois vérifications faites en phase 6 changent cet état.

**Beverly et al. 2021 — distances confirmées par source secondaire.** L'article
reste payant et n'a **pas** été lu. Mais les trois distances y figurant sont
énoncées explicitement dans la documentation de référence de `fireexposuR`
1.2.0, paquet relu par rOpenSci et écrit par la même équipe :

| Processus | Distance | Constaté comment |
|---|---|---|
| Chaleur radiante | 30 m | `docs.ropensci.org/fireexposuR/reference/fire_exp.html` |
| Brandons courte portée | 100 m | idem |
| Brandons longue portée | 500 m | idem |

C'est une source secondaire, et le package la nomme comme telle. Le critère de
combustible dangereux de Beverly 2021 (une teneur en conifères) n'a **pas** été
constaté à sa source et n'est donc pas repris.

**Beverly et Forbes 2023 — localisé et paramétré.** *Assessing directional
vulnerability to wildfire*, Natural Hazards 117:831-849. Paramètres relevés dans
la même documentation : transects tous les 1°, trois segments de 5000 m,
`thresh_exp = 0,6` parce que les feux observés brûlaient préférentiellement
au-delà de 60 % d'exposition, `thresh_viable = 0,8` parce que les couloirs
brûlés recoupaient les taches de forte exposition antérieure à 80 % en moyenne.
Ce sont des valeurs mesurées, pas des conventions.

**Khan et al. 2025 — une validation méditerranéenne existe.** *Validating a
landscape metric to map fire exposure to hazardous fuels in Portugal*, Natural
Hazards 121:16273-16295, DOI 10.1007/s11069-025-07424-8. Résumé lu le
2026-08-16. La métrique canadienne a été appliquée au Portugal continental sur
1995-2018, grille 100 m, et validée sur cinq années de feux : environ 80 % des
surfaces brûlées se trouvaient en exposition ≥ 80 %. Les auteurs concluent que
la métrique « aligned well with wildfires modulated by Portuguese climate and
vegetation ».

Conséquence sur le brief. Celui-ci affirme que les rayons « doivent être
justifiés ou recalibrés » sur chêne vert, garrigue ou maquis. Ce n'est plus
exact tel quel : la **métrique** transpose à un contexte ibérique. Ce que
Khan et al. ne règlent pas, c'est le **rayon** — leur résumé donne la résolution
de grille, pas la distance de transmission — ni le passage du pin maritime et de
l'eucalyptus atlantiques au chêne vert et au maquis provençaux. La formulation
retenue dans `fev_exposure_radii()` et dans le message de premier appel de
`fev_exposure()` est donc : point de départ défendable, avec une validation
méditerranéenne derrière lui, pas une valeur calibrée pour le Var.

**Géométrie de la fenêtre — vérifiée par le code.** `fireexposuR::fire_exp()`
utilise un anneau allant d'une cellule au rayon de transmission, la cellule
évaluée étant exclue, avec des poids normalisés, et impose `res <= t_dist / 3`.
Constaté par lecture du source du paquet installé. `fev_exposure()` reproduit
cette géométrie ; un test compare les deux fenêtres cellule par cellule et les
sorties à 1e-4, tolérance qui est exactement l'arrondi à quatre décimales de
`fire_exp()`.

---

## Sources

- [Fire danger indices historical data (CEMS) — EWDS](https://ewds.climate.copernicus.eu/datasets/cems-fire-historical-v1?tab=overview)
- [User Guide — Fire danger indices historical data (CEMS), ECMWF Confluence](https://confluence.ecmwf.int/display/CEMS/User+Guide+for++Fire+danger+indices+historical+data+from+the+Copernicus+Emergency+Management+Service)
- [ecmwfr — Interface to ECMWF and CDS Data Web Services](https://bluegreen-labs.github.io/ecmwfr/) (et code source CRAN 2.0.3)
- [BD Forêt v2 — aide cartes.gouv.fr](https://cartes.gouv.fr/aide/fr/partenaires/ign/referentiels-description-territoire/foret/bd-foret-v2/)
- [BD Forêt® — data.gouv.fr](https://www.data.gouv.fr/datasets/bd-foret-r)
- [BD Forêt version 2 — Inventaire forestier IGN](https://inventaire-forestier.ign.fr/spip.php?article646)
- [EFFIS — Fire Danger Forecast](https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/fire-danger-forecast)
- [EFFIS — Data and Services](https://forest-fire.emergency.copernicus.eu/applications/data-and-services)
- [Beverly et al. 2010, Int. J. Wildland Fire 19:299–313](https://www.publish.csiro.au/wf/fulltext/wf09071)
- [Beverly et al. 2021, Landscape Ecology — non lu (accès restreint)](https://link.springer.com/article/10.1007/s10980-020-01173-8)
- [fireexposuR — fire_exp reference](https://docs.ropensci.org/fireexposuR/reference/fire_exp.html)
- [fireexposuR — fire_exp_dir reference](https://docs.ropensci.org/fireexposuR/reference/fire_exp_dir.html)
- [Khan et al. 2025, Natural Hazards 121:16273-16295](https://doi.org/10.1007/s11069-025-07424-8)
- [Vitolo et al. 2018, PLoS ONE 13(1):e0189419](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0189419)
- [caliver — get_fire_danger_levels.R](https://github.com/ecmwf/caliver/blob/master/R/get_fire_danger_levels.R)
- [WMO Guidelines on the Calculation of Climate Normals, WMO-No. 1203](https://library.wmo.int/records/item/55797-wmo-guidelines-on-the-calculation-of-climate-normals)
- [BD Forêt® Version 2 — Descriptif de contenu (septembre 2014)](https://inventaire-forestier.ign.fr/IMG/pdf/DC_BDFORET_v2.pdf)
- [BD Forêt v2 — documentation cartes.gouv.fr](https://ignf.github.io/cartes.gouv.fr-documentation/fr/partenaires/ign/referentiels-description-territoire/foret/bd-foret-v2/)
