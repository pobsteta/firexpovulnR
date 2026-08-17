# Phase 8 — Rapport de vérification LiDAR HD

**Date de vérification : 2026-08-17.** Toutes les valeurs ci-dessous ont été
constatées ce jour-là, soit par appel réseau réel, soit par lecture du code
source du paquet installé, soit par exécution sur un nuage de points
synthétique. La colonne « Constaté comment » précise laquelle de ces trois
voies a servi.

Le brief impose deux vérifications avant toute ligne de code (points 8 et 9).
Les deux sont résolues, et la seconde a livré une **erreur dans la
documentation amont** qu'il valait mieux trouver avant d'indexer des bandes.

---

## 8. Couverture LiDAR HD et contrôle de disponibilité — RÉSOLU

Le brief demande « une carte de progression de la diffusion » et « une fonction
de contrôle de disponibilité **avant** toute tentative de téléchargement ».
Mieux qu'une carte : le WFS de la Géoplateforme sert la grille de dalles
elle-même, avec l'URL de téléchargement de chacune.

| Couche | Contenu | Constaté comment |
|---|---|---|
| `IGNF_NUAGES-DE-POINTS-LIDAR-HD:bloc` | emprises des blocs d'acquisition | GetCapabilities + comptage |
| `IGNF_NUAGES-DE-POINTS-LIDAR-HD:dalle` | dalles individuelles, avec `url` | DescribeFeatureType + GetFeature réel |
| `IGNF_LIDAR-HD_METADONNEE:metadata` | métadonnées | GetCapabilities |
| `IGNF_MNT-LIDAR-HD:dalle` | modèle numérique de terrain dérivé | GetCapabilities |
| `IGNF_MNS-LIDAR-HD:dalle` | modèle numérique de surface | GetCapabilities |
| `IGNF_MNH-LIDAR-HD:dalle` | **modèle numérique de hauteur** (canopée) | GetCapabilities |

Schéma de `dalle`, constaté par `DescribeFeatureType` :

```
id  name  url  name_download  timestamp  legend  type_produit
projection  zoom_start  zoom_stop  format  bbox  width  height
id_chantier  metadata  geom
```

`url` donne le téléchargement direct, `timestamp` la date de mise à
disposition, et `id_chantier` identifie le bloc d'acquisition — c'est-à-dire le
**millésime par bloc** que le brief demande.

### Couverture constatée le 2026-08-17

| Requête | `numberMatched` |
|---|---|
| blocs, France entière | **210** |
| dalles, France entière | **505 294** |
| dalles sur les Maures (Var) | **1 016** |
| dalles sur Couchey (Côte-d'Or) | **0** |

La couverture est donc réellement partielle, et le contrôle de disponibilité
n'est pas une précaution théorique : le terrain méditerranéen primaire du
package est couvert, celui de la vignette Couchey ne l'est pas. C'est
exactement le cas que la fonction doit savoir refuser proprement.

### Format des dalles

Constaté par `GetFeature` réel sur le Var (bbox `6.30,43.20,6.35,43.25`) :

| Élément | Valeur |
|---|---|
| Taille | **1 000 m × 1 000 m** |
| Projection | EPSG:2154 (Lambert-93), altitudes IGN69 |
| Format | **COPC** — `.copc.laz` |
| Nommage | `LHD_FXX_<Xkm>_<Ykm>_PTS_C_LAMB93_IGN69` |
| Exemple d'URL | `https://data.geopf.fr/telechargement/download/LiDARHD-NUALID/NUALHD_1-0__LAZ_LAMB93_QQ_2025-03-24/LHD_FXX_0968_6240_PTS_LAMB93_IGN69.copc.laz` |
| `timestamp` | `2025-05-01` |
| `id_chantier` | `106` |

**Le format COPC change la stratégie.** Cloud Optimized Point Cloud est indexé
en octree et lisible par plages HTTP : on peut lire une emprise ou un niveau de
détail sans télécharger la dalle entière. Une dalle LiDAR HD pèse de l'ordre du
gigaoctet ; à 1 016 dalles pour les Maures, le téléchargement intégral n'est pas
une option raisonnable et la lecture partielle en est une.

**Piège d'axes, encore.** Ces couches veulent un BBOX **longitude d'abord** même
en EPSG:4326, comme toutes les autres de cette Géoplateforme. Demander latitude
d'abord rend zéro entité avec un HTTP 200 — indiscernable d'une absence de
couverture, ce qui est ici particulièrement fâcheux puisque l'absence de
couverture est un résultat légitime.

---

## 9. `LidarForFuel` — RÉSOLU, et la documentation amont est fausse

### Le paquet ne s'appelle pas comme son dépôt

| | |
|---|---|
| Dépôt | `oliviermartin7/LidarForFuel` |
| **Nom du paquet** | **`lidarforfuel`** (minuscules) |
| Version installée | 1.0.0.9001 |
| Portage IGN | `IGNF/lidar-for-fuel` |

`requireNamespace("LidarForFuel")` rend donc `FALSE` alors que le paquet est
installé. Constaté en installant.

### Fonctions exportées

Constaté par `getNamespaceExports()` :

```
fPCpretreatment  fCBDprofile_fuelmetrics  ffuelmetrics
get_traj         add_traj_to_las
```

Les deux que le brief nomme existent bien.

### Signatures, lues dans les fichiers `.Rd` du dépôt

```r
fPCpretreatment(chunk, classify = FALSE, LMA = 140, WD = 591,
                WD_bush = 591, LMA_bush = 140, H_strata_bush = 2,
                Height_filter = 60, start_date = "2011-09-14 01:46:40",
                season_filter = 1:12, deviation_days = Inf,
                plot_hist_days = FALSE, traj = NULL)

fCBDprofile_fuelmetrics(datatype = "Pixel", X, Y, Z, Zref, ReturnNumber,
                        Easting, Northing, Elevation, LMA, gpstime,
                        height_cover = 2, threshold = 0.02,
                        scanning_angle = TRUE, use_cover = FALSE, WD,
                        limit_N_points = 400, limit_flight_height = 800,
                        limit_vegetation_height = 0.1, H_PAI = 0,
                        omega = 0.77, d = 1, G = 0.5)
```

Paramètres importés qui devront être explicites et surchargeables côté
`firexpovulnR`, conformément à la règle du brief :

| Paramètre | Défaut | Ce que c'est |
|---|---|---|
| `LMA` | 140 | masse surfacique foliaire, g/m² |
| `WD` | 591 | densité du bois, kg/m³ |
| `LMA_bush`, `WD_bush` | 140, 591 | idem sous 2 m |
| `H_strata_bush` | 2 | limite arbuste / houppier, m |
| `threshold` | 0,02 | seuil de densité apparente définissant le combustible, kg/m³ |
| `omega` | 0,77 | facteur d'agrégation du feuillage |
| `G` | 0,5 | ratio de projection foliaire (distribution sphérique) |
| `d` | 1 | épaisseur de couche du profil, m |
| `limit_N_points` | 400 | **points minimum par pixel** |
| `limit_flight_height` | 800 | hauteur de vol maximale admise, m |

`LMA = 140` et `WD = 591` sont des valeurs d'espèce. Elles n'ont **pas** été
retrouvées à une source primaire : ce sont les défauts du paquet amont, et le
package les traitera comme tels — surchargeables, journalisés, et signalés comme
non validés pour une essence donnée.

### Structure de sortie — la documentation amont se trompe

Le README annonce « 173 bandes, dont les 23 premières sont des métriques ». **Le
code dit autre chose**, et une exécution le confirme.

Lu dans le corps de `fCBDprofile_fuelmetrics` :

```r
null_VVP_metrics_CBD <- rep(-1, 150)
names(null_VVP_metrics_CBD) <- paste0("CBD_", rep(1:150))
null_VVP_metrics <- c(Profil_Type = -1, Profil_Type_L = -1, threshold = -1,
  Height = -1, CBH = -1, FSG = -1, Top_Fuel = -1, H_Bush = -1,
  continuity = -1, VCI_PAD = -1, VCI_lidr = -1, entropy_lidr = -1,
  PAI_tot = -1, CBD_max = -1, CFL = -1, TFL = -1, MFL = -1, FL_1_3 = -1,
  GSFL = -1, FL_0_1 = -1, FMA = -1, date = date, Cover = -1,
  Cover_4 = -1, Cover_6 = -1)
```

Soit **25 métriques nommées puis 150 bandes de profil = 175 bandes**, pas 173.
Confirmé par exécution sur nuage synthétique via `lidR::pixel_metrics()` :
`nlyr = 175`, bande 25 = `Cover_6`, bande 26 = `CBD_1`, bande 175 = `CBD_150`.

**Conséquence pratique.** Se fier au README et lire les bandes 24 à 173 comme le
profil de densité apparente décalerait tout de deux bandes et ferait passer
`Cover_4` et `Cover_6` pour des valeurs de densité. Le brief avait raison
d'écrire « ne suppose rien sur l'ordre des bandes » — et lire le code plutôt que
la doc est ce qui a trouvé l'écart. Le package n'indexera jamais
positionnellement : il nommera.

### La valeur nulle est `-1`, pas `NA`

Toutes les métriques valent `-1` quand le calcul n'aboutit pas, sauf `date` qui
reste `mean(gpstime)`. Traiter ces `-1` comme des valeurs donnerait des hauteurs
de base de houppier négatives et des charges de combustible négatives, qui
passeraient tous les contrôles de plausibilité naïfs. La conversion en `NA` est
obligatoire et sera faite à la lecture.

### Le chemin nul est le contrôle qualité que le brief demande

```r
if (length(Z) < limit_N_points) {
  warning("NULL return: The number of point < limit_N_points: ...")
```

Avec `limit_N_points = 400` par défaut et un pixel de 50 m (2 500 m²), cela
correspond à une densité minimale de 0,16 pt/m² — très permissif. Le brief
demande d'émettre un **avertissement chiffré** sous un seuil paramétrable de
densité d'impulsions ; c'est donc un contrôle à ajouter en amont, pas à déléguer
à ce garde-fou.

### Trois avertissements observés à l'exécution, dont un repli silencieux

Sur nuage synthétique, `fPCpretreatment()` a émis :

1. « Computing trajectory from LAS file... Trajectory would better be computed
   outside pretreatment, with a buffer (e.g. 500m) to avoid border effects. »
   → **contrainte de conception** : la trajectoire doit être calculée sur un
   catalogue tamponné, pas dalle par dalle. À respecter dans le
   `catalog_apply()`.
2. « Trajectory computed with lidR::track_sensor is empty. »
3. « **Setting default trajectory to 1400m above of the ground points.** »
   → repli sur une hauteur de vol nominale de 1 400 m quand la trajectoire est
   irrécupérable. Cela affecte la correction d'angle de balayage. Ce repli ne
   doit pas être avalé : il change le résultat et doit apparaître dans la
   provenance.

Colonnes ajoutées par le prétraitement, constatées :
`Time, Easting, Northing, Elevation, LMA, WD, Zref`.

### Le pipeline est exerçable hors ligne

C'est le point qui décide de la testabilité de toute la phase. Un nuage
synthétique construit avec `lidR::LAS()` — sol, strate basse, houppier, 12
pts/m² sur un hectare — traverse `fPCpretreatment()` puis
`fCBDprofile_fuelmetrics()` via `pixel_metrics()` et rend des valeurs
plausibles :

| Métrique | Valeur obtenue |
|---|---|
| `Height` | 18,5 m |
| `CBH` | 3,5 m |
| `FSG` | 2,0 m |
| `H_Bush` | 1,5 m |
| `CBD_max` | 0,229 kg/m³ |
| `CFL` | 0,431 kg/m² |
| `TFL` | 0,672 kg/m² |
| `MFL` | 0,229 kg/m² |
| `Cover` | 0,42 |
| `PAI_tot` | 2,837 |

Aucun test de cette phase n'a donc besoin du réseau ni d'une dalle réelle.

---

## Repli documenté — produits satellitaires pan-européens

Le brief demande un repli quand le LiDAR est indisponible sur la zone, ce qui
est le cas de la majorité de la France en 2026 et, par exemple, de Couchey.

**Vaquero-Pinto, Botequim et al. (2024-2025)**, *Satellite-based mapping of
canopy fuels at the pan-European scale*, *Geo-spatial Information Science*
28(4), diffusé par le serveur de cartes de combustible du projet FIRE-RES.

| Élément | Valeur |
|---|---|
| Variables | hauteur de base de houppier (CBH) et densité apparente de houppier (CBD) |
| Résolution | ~100 m |
| Millésime | 2020 |
| Emprise | pan-européenne |
| Méthode | observation de la Terre → biomasse aérienne par IA → modèles allométriques |
| **Corrélation CBH** | **r = 0,445** |
| **Corrélation CBD** | **r = 0,330** |

Ces corrélations sont **faibles** et doivent être dites comme telles : r = 0,33
sur la CBD, c'est environ 11 % de variance expliquée. Le repli existe, il est
homogène sur toute l'Europe, et il ne remplace pas une mesure. Lu au niveau du
résumé et de la fiche produit seulement.

---

## Synthèse

| # | Point | État | Effet sur l'architecture |
|---|---|---|---|
| 8 | Couverture et disponibilité | ✅ résolu | WFS `dalle` avec `url` par dalle. Couverture partielle constatée : Var oui, Côte-d'Or non. Format COPC → lecture partielle possible. |
| 9 | Signatures `lidarforfuel` | ✅ résolu | Paquet en minuscules. Signatures lues dans les `.Rd`. |
| 9 bis | Ordre des bandes | ✅ résolu, **README faux** | 175 bandes et 25 métriques, pas 173 et 23. Jamais d'indexation positionnelle. |
| 9 ter | Valeur nulle | ✅ constaté | `-1`, pas `NA`. Conversion obligatoire. |
| 9 quater | Trajectoire | ⚠️ à surveiller | Repli silencieux à 1 400 m de hauteur de vol si irrécupérable. À journaliser. |
| — | Testabilité hors ligne | ✅ démontré | Nuage synthétique `lidR` → pipeline complet → valeurs plausibles. |
| — | Repli satellitaire | ✅ trouvé | CBH/CBD 100 m 2020 pan-européen, mais r = 0,45 et 0,33. |

## Sources

- [LiDAR HD — Géoplateforme WFS](https://data.geopf.fr/wfs/ows) (`GetCapabilities`, `DescribeFeatureType`, `GetFeature` réels, 2026-08-17)
- [oliviermartin7/LidarForFuel](https://github.com/oliviermartin7/LidarForFuel)
- [IGNF/lidar-for-fuel](https://github.com/IGNF/lidar-for-fuel) — portage IGN de la solution INRAE
- [Unlocking the potential of Airborne LiDAR for direct assessment of fuel bulk density and load distributions for wildfire hazard mapping — HAL INRAE](https://hal.inrae.fr/hal-04908881v1)
- [Satellite-based mapping of canopy fuels at the pan-European scale — Geo-spatial Information Science 28(4)](https://www.tandfonline.com/doi/full/10.1080/10095020.2024.2429376)
- [Pan-European fuel map server — FIRE-RES](https://fire-res.eu/)
