# Note — ce qui a été essayé le 2026-08-20, et ce que ça a donné

Écrite parce que ces essais ont coûté une demi-journée et qu'ils ne laissent
aucune trace dans le code : **tout ce qui suit est un résultat négatif**. Sans
cette note, la prochaine personne qui cherchera une donnée de dommage refera
exactement le même chemin.

Rien ici n'est un jugement sur la qualité des produits. Ce sont des constats
d'accessibilité et de performance, datés, et qui peuvent changer.

## 1. Les quatre produits forêt de THEIA sont catalogués et fermés

Le CDS THEIA-MTD diffuse quatre produits forêt, tous décrits en STAC :

| Produit | Mesure | Résolution | Période |
|---|---|---|---|
| **SUFOSAT** | coupes rases, Sentinel-1 | 10 m | 2018-01-01 → 2025-09-01 |
| **FORMS-T** | hauteur, biomasse, volume | 10–30 m | 2018 → 2024 |
| **FORMSpoT** | hauteur de canopée, SPOT 6/7 | 1,5 m | 2014 → 2024 |
| **GeoGEDI** | empreintes GEDI relocalisées | ~25 m | 2019 → 2023 |

Catalogues : `https://api.stac.teledetection.fr` et
`https://api.datastore-mtd.theia.data-terra.org`. **Les deux façades pointent
sur les mêmes objets.**

Les métadonnées sont publiques, riches et directement exploitables — pour
SUFOSAT, deux COG en EPSG:2154, 119 159 × 126 813 pixels à 10 m, valeurs
`YYDDD` (année et jour de la coupe estimée), plus un raster de probabilité.

**Les assets ne sont pas lisibles anonymement.** HTTP 403 sur trois buckets
distincts du StorageGRID de Montpellier :

- `sm1-gdc-ext` (SUFOSAT, FORMS-T, FORMSpoT)
- `sm1-gdc-geogedi` (GeoGEDI)
- `sm1-gdc-carto-nat-incendies` (cartofeux-lidarhd)

La page catalogue de THEIA affiche « No links available » à la section
téléchargement, ce qui est cohérent.

### Les clés S3 essayées ne l'ouvrent pas

`TLD_ACCESS_KEY` / `TLD_SECRET_KEY` du `.Renviron` local ont été essayées sur
l'endpoint `s3-data.meso.umontpellier.fr`, en adressage par chemin puis virtuel,
région `us-east-1`, sur deux buckets. Réponse constante :

```
403  InvalidAccessKeyId
     The AWS Access Key Id you provided does not exist in our records.
```

Vérifié **hors GDAL**, avec une signature SigV4 écrite à la main, pour écarter
un défaut d'outillage : même code, même message. C'est un refus au niveau du
compte — une région erronée aurait donné `SignatureDoesNotMatch`, une permission
manquante un `AccessDenied`.

Ces clés visent donc un autre service, ou ont été révoquées. **Aucun autre
endpoint n'a été essayé, délibérément** : envoyer une clé secrète à un hôte
auquel elle n'appartient peut-être pas est une mauvaise pratique.

### Ce que SUFOSAT apporterait, si l'accès s'ouvre

Une **date de coupe par pixel à 10 m**. Cela corrigerait le biais de millésime
qui pèse sur le paquet depuis la phase 2 : une BD Forêt de 2014 ne sait rien de
ce qui a été coupé avant les feux de 2021, et `fev_validate()` ne peut que
chiffrer le décalage sans le corriger.

L'intégration serait directe — le STAC donne tout, et le paquet lit déjà des COG
par fenêtre. Il ne manque que le droit de lire.

## 2. GEODES et THEIA sont des archives glissantes

Les collections **annoncent** 2015 → 2026. Ce qui est réellement servi sur
l'emprise des Maures, vérifié année par année :

| Collection | Années détenues |
|---|---|
| THEIA Sentinel-2 L2A | 2025–2026 |
| THEIA Sentinel-2 L3A | 2024–2026 |
| PEPS Sentinel-2 L1C | 2023–2026 |
| OSO raster | 2026 |

L'étendue temporelle d'une collection STAC est celle du **produit**, pas du
stock. Rien n'atteint l'incendie de 2021, ce qui a décidé
`fev_fetch_severity()` à passer par le miroir Sentinel-2 d'Element 84 sur AWS :
complet depuis 2015, sans compte, en COG.

## 3. La requête bornée sur COPC fonctionne et n'apporte rien

`fev_lidar_batch(window = 250)` télécharge 250 Mo pour exploiter un carré de
250 m, ce qui semble absurde. `lasR::reader_rectangles()` sait interroger une
emprise sur un COPC distant. Essayé jusqu'au bout sur une dalle IGN, trois fois :

| Essai | Points | Durée |
|---|---|---|
| 1 | 2 307 874 | 90,9 s |
| 2 | 2 307 874 | 39,0 s |
| 3 | 2 307 865 | 72,6 s |

Le compte est juste — 2 307 679 points par téléchargement complet puis découpe,
soit 0,008 % d'écart dû aux bornes. Mais :

- **Ce n'est pas plus rapide.** 39 à 91 s contre **34 s** pour télécharger les
  187 Mo de la dalle.
- **Ce n'est pas déterministe.** Neuf points d'écart entre deux exécutions
  identiques. La cause est visible : `lasR` ne descend pas l'octree COPC, il
  parcourt les chunks séquentiellement — 8,1 millions de points lus sur 32,6
  millions — perd la connexion (`chunk with index 842 is corrupt`) et rend un
  résultat quand même.

### Et la raison de fond

Le gain envisagé était un facteur cinquante. **C'était faux** : facteur
cinquante sur les octets, mais les octets n'ont jamais été la contrainte. Les
chronométrages de la 0.23.0, écrits dans l'en-tête de `inst/scripts/batch_lidar.R`,
le disaient déjà :

> Le téléchargement n'est pas le goulot — 248 Mo en 42 s — c'est l'inversion.

Sur les 32 dalles traitées, 47 à 213 s par dalle dont ~35 de téléchargement.
Une requête d'octree parfaite ferait gagner un quart du temps, au prix du
déterminisme.

**PDAL descendrait vraiment l'octree** — c'est lui qui a défini le format — mais
il n'est installé ni en CLI ni en Python ici, et le gain plafonne au même quart.
Le levier sur le coût de la campagne est l'inversion `lidarforfuel`, pas le
transport : fenêtre plus petite, ou moins de dalles.

## 4. Ce qui reste ouvert

- **Un champ `licence` de premier rang** dans la provenance. Aujourd'hui la
  licence est du texte libre dans `provider`. Tant que toutes les sources
  étaient permissives c'était de la documentation ; une source non commerciale
  se propage aux résultats dérivés et mérite d'être interrogeable.
- **La fonction de dommage.** `fev_fetch_severity()` livre l'observable qui
  manquait ; il reste à caler sévérité contre mortalité sur des placettes, et
  cela ne s'invente pas depuis un bureau.
- **Le test CBH → sévérité** attendra un feu postérieur à mai 2025 : le LiDAR HD
  des Maures est postérieur de quatre ans à l'incendie de 2021, et prédire la
  cause par l'effet n'a pas de sens.
