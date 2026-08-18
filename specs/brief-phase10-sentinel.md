# Brief — Phase 10 : CLCplus Backbone comme source de combustible

> **Périmé le 2026-08-18.** Ce brief a été exécuté en entier, puis CLCplus a été
> retiré du paquet : le périmètre est la France, et la BD Forêt y fait la
> séparation sempervirent/caducifolié plus finement, par l'essence. Depuis que
> `fev_fuel_attach()` la garde vivante à côté d'une classe décidée par un raster
> à 10 m, CLCplus n'apportait plus rien. Le rôle de source 10 m est tenu par
> `fev_fetch_worldcover()`. Voir l'épilogue du rapport de phase 10 et NEWS 0.21.0.
>
> Conservé comme document de travail : il dit ce qui a été exigé et pourquoi,
> et les étapes 2, 3 et 4 ont produit des fonctions qui, elles, sont restées.

Fait suite à `phase10-rapport-sentinel.md`, qui instruit les voies satellitaires
et écarte les autres. Ce brief ne retient que ce que ce rapport recommande.

**Ne démarre pas cette phase sans accord explicite.** Elle touche au module le
plus structurant du paquet.

## Objectif

Brancher **CLCplus Backbone** comme source de combustible catégorielle à 10 m, en
remplacement de CORINE dans le rôle auxiliaire, et rendre le paquet réellement
utilisable à 10 m.

Deux gains, et un seul est cosmétique :

1. Les esquilles de rastérisation disparaissent par construction — un raster natif
   n'a pas de frontière partagée entre polygones. `fev_fuel_fill_gaps()` devient
   sans objet sur cette source.
2. **`fev_exposure(type = "radiant")` devient calculable.** Aujourd'hui il est
   refusé : le garde `res <= radius / 3` (`exposure.R:132`) rejette 25 m pour un
   rayon de 30 m. À 10 m il passe tout juste. C'est la vraie raison de descendre,
   et elle débloque une des trois échelles du modèle.

Le biais de millésime tombe par ailleurs de treize ans à deux sur les Maures.

## Étape 0 — vérifier à la source, avant toute ligne de code

**Obligatoire.** Le rapport de phase 10 a lu des fiches produit et des résumés,
pas les documents normatifs. Sa liste des 11 classes vient d'un résultat de
recherche : **ne code pas depuis cette liste.**

À établir dans le manuel utilisateur CLCplus Backbone 2023 et l'ATBD :

- les **codes et libellés exacts** des 11 classes ;
- les **précisions par classe**, en particulier la classe des ligneux bas, que la
  fiche produit annonce comme régionalement en deçà de la cible ;
- l'UMC déclarée, si le produit en déclare une ;
- le CRS de diffusion (annoncé EPSG:3035) et les millésimes réellement publiés ;
- la **licence** et la formule de citation exigée ;
- l'endpoint de téléchargement par emprise, et s'il existe un WCS exploitable
  autrement qu'à la main.

Si l'egress bloque `land.copernicus.eu`, dis-le immédiatement — ne conclus pas
que le produit est inaccessible.

## Étape 1 — la source

- `fev_fetch_clcplus(aoi, year)` sur le modèle de `fev_fetch_corine()`, avec le
  cache et la provenance existants. Millésime **obligatoire** dans la provenance,
  comme pour la BD Forêt.
- Entrées `clcplus_2018`, `clcplus_2021`, `clcplus_2023` dans `.FEV_FUEL_TYPES`
  (`fuel_source.R:212`).
- Entrées correspondantes dans `.FEV_FUEL_MMU` : `complete = TRUE`,
  `mmu_ha = 0.01` et `min_width_m = 10`, c'est-à-dire le pixel lui-même. Cela
  neutralise `fev_fuel_fill_gaps()` **sans cas particulier dans le code** — un
  trou plus petit qu'un pixel n'existe pas. Vérifie que c'est bien ce qui se
  produit, plutôt que de l'affirmer.
- Table de correspondance des 11 classes vers `fev_fuel_types()`.

**Point favorable à exploiter :** la nomenclature CLC+ est déjà structurelle —
aiguilles, feuillu caducifolié, feuillu sempervirent, ligneux bas — là où CLC
niveau 3 mélange couverture et usage. La correspondance vers le vocabulaire du
paquet devrait être **plus directe et moins lossy que celle de CORINE**. Dis-le
dans la documentation de la table si tu le constates.

**CRS :** le produit est en EPSG:3035, le paquet travaille en 2154. La règle du
brief initial tient — jamais de reprojection de la source primaire. Si la BD
Forêt reste primaire, c'est CLC+ qui se reprojette, en `method = "near"` et
journalisé dans la provenance.

## Étape 2 — valider la classe des ligneux bas, sur les Maures

C'est la condition de confiance, et c'est la partie que je ne veux pas voir
sautée. La classe la plus faible du produit est celle du maquis et de la
garrigue, donc celle qui porte le danger dans le Var.

Nous disposons d'une référence indépendante que peu de gens ont : **le LiDAR HD
de la phase 8 sur les deux placettes des Maures**, qui mesure le sous-étage que
toute classification optique devine.

- Confronte la classe CLC+ à ce que le LiDAR HD dit de la strate basse sur ces
  emprises. Chiffre l'accord, ne conclus pas « cohérent ».
- Second contrôle, moins direct : les onze périmètres d'incendie de l'extrait.
- **Si la classe est mauvaise localement, ne l'enterre pas** : documente le
  chiffre et propose un repli — n'utiliser CLC+ que pour le masque brûlable et
  garder CORINE pour le type, par exemple. Une source partiellement fiable dont
  on sait *où* elle l'est vaut mieux qu'un choix binaire.

L'échantillon est petit — deux placettes. Dis-le, et ne présente pas le résultat
comme une validation générale.

## Étape 3 — rendre le 10 m viable

- **Ne change pas le défaut `res = 25`.** Il reste correct pour la BD Forêt, dont
  la largeur minimale cartographiée est de 20 m. Le 10 m est légitime pour une
  source nativement à 10 m, pas en général.
- Passer de 25 à 10 m multiplie les cellules par 6,25 et la surface de fenêtre par
  6,25, soit **~39× le coût focal**. Mesure-le plutôt que de me le supposer :
  `fev_check_focal_cost()` existe pour ça, et le test de charge documenté exigé
  par le brief initial doit être rejoué à 10 m.
- Si l'emprise des Maures ne passe pas à 10 m sur un poste ordinaire, c'est un
  résultat, pas un échec : rapporte le chiffre et propose le traitement par
  tuiles.
- **Livrable qui prouve l'intérêt de la phase :** un exemple `type = "radiant"`
  qui tourne. Il est aujourd'hui impossible à produire.

## Étape 4 — optionnelle : FORMS dans le registre continu

À ne faire que si l'étape 3 aboutit.

Ingérer **FORMS-H** (hauteur de canopée France, 10 m, Zenodo
`10.5281/zenodo.7840108`, CC-BY 4.0) comme
`fev_fuel_source(register = "continuous")`. C'est un raster, aucune dépendance
nouvelle.

Trois avertissements à porter dans la doc, sur le modèle de ce que le paquet fait
déjà pour les rayons de Beverly :

- millésime **2020 unique** ; les auteurs signalent que la transposition à
  d'autres années est risquée ;
- **forêts méditerranéennes sous-représentées dans leur validation** — ce qui vise
  directement les Maures ;
- la hauteur est bien restituée (MAE 2,94 m, R² 0,69 contre placettes IFN), **la
  biomasse beaucoup moins** (R² 0,18 contre Renecofor). N'utilise pas FORMS-B
  comme s'il valait FORMS-H.

Citer les auteurs : Schwartz et al. (2023), *Earth System Science Data* 15:4927.

## Ce qu'il ne faut pas faire

- **Ne construis pas un classifieur Sentinel-2 maison.** Le résultat serait un
  modèle non validé qu'il faudrait valider nous-mêmes.
- **Ne tente pas le sous-étage par GEDI en contexte méditerranéen.** GEDI ne
  restitue pas le sous-étage sous ~30 m de hauteur de canopée, ce qui couvre toute
  la futaie des Maures ; et le contournement phénologique publié suppose un
  contraste de saison entre strates qui n'existe pas entre couvert et maquis
  sempervirents. Le rapport § 5.3 détaille.
- **Ne krige pas GEDI toi-même pour la hauteur.** La méthode est valide sous forme
  de krigeage de régression avec anisotropie modélisée le long des traces, mais
  FORMS livre déjà le résultat pour la France, gratuitement.
- Ne retire pas au LiDAR HD son rôle sur le sous-étage, et ne retire pas de la
  vignette la limite que le brief initial demande d'afficher.

## Adjacent, hors périmètre

Le cadre blanc de 500 m au pourtour des cartes d'exposition. Le remède est déjà
écrit dans le message d'erreur `fev_extent_too_small` — tamponner l'AOI du rayon,
puis recadrer après le calcul focal — et la vignette des Maures le mentionne. Un
utilitaire pourrait l'automatiser. **À traiter dans un chantier séparé**, il n'a
rien à voir avec Sentinel.

## Discipline, inchangée depuis le brief initial

- Aucun code de nomenclature, aucun endpoint, aucun seuil dans le code sans
  vérification à sa source. Un endpoint inventé qui échoue silencieusement reste
  le pire résultat possible.
- Tout seuil doit être une **propriété de la donnée**, pas un réglage — c'est ce
  qui a fait de `fev_fuel_fill_gaps()` une réparation et non une interpolation.
- Provenance sur chaque opération, reprojections comprises.
- Aucun test ne dépend du réseau : rasters synthétiques, mocks `httptest2`,
  `skip_if_offline()` pour l'intégration.
- Signale l'incertitude plutôt que de combler. Conteste ce brief s'il te paraît
  faux au contact du code.
