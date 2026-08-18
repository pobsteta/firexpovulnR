# Phase 10 — rapport de faisabilité : Sentinel, GEDI et le combustible

Vérifications faites le **2026-08-18**. Contrairement aux rapports des phases 8
et 9, **aucun appel réel n'a été passé ici** : ce rapport instruit des sources et
des méthodes, pas des endpoints. Le niveau de lecture est indiqué source par
source, et rien de ce qui suit ne doit entrer dans le code sans une vérification
à la source, conformément au brief (§ *« Aucune URL, aucun nom de dataset, aucun
code de nomenclature, aucun seuil numérique… »*).

## 1. Les deux questions

1. Peut-on récupérer le combustible avec Sentinel-1 ou Sentinel-2 ?
2. Le couplage GEDI × Sentinel-2 par krigeage est-il envisageable ?

La réponse courte est **oui à la première, oui mais pas pour ce qui nous manque à
la seconde**. Le détail tient à ce que « le combustible » recouvre trois sorties
distinctes dans ce paquet, et que les capteurs ne répondent pas aux trois.

## 2. Ce dont le paquet a besoin, précisément

| Sortie | Fonction | Registre | État actuel |
|---|---|---|---|
| Masque brûlable | `fev_fuel_binary()` | catégoriel | BD Forêt + CORINE |
| Type structural | `fev_fuel_type()` | catégoriel | BD Forêt TFV + CLC niveau 3 |
| Charge, CBD, CBH, FSG | `fev_fuel_lidar()` | **continu** | LiDAR HD, couverture partielle |

Le troisième est le nerf de l'affaire. Le brief le désigne comme la principale
faiblesse méthodologique du paquet (`brief-fireexpovulnR.md:110`) : *« une futaie
de chêne vert avec sous-bois dense et la même sans sous-bois sont identiques dans
les deux bases »*. Toute source candidate doit donc être jugée d'abord sur cette
question-là, pas sur sa résolution.

L'architecture est prête à recevoir une source continue : `fev_fuel_source()`
porte deux registres coexistants depuis la phase 4, exigence explicite du brief
(`:98`).

## 3. Voie A — Sentinel-2 par produit dérivé : CLCplus Backbone

Lu au niveau des fiches produit et du catalogue EEA, **pas** du manuel
utilisateur ni de l'ATBD.

| Élément | Valeur |
|---|---|
| Producteur | Copernicus Land Monitoring Service |
| Entrée | séries temporelles Sentinel-2 |
| Résolution | **10 m**, raster |
| Classes | **11** classes de couverture, nomenclature dérivée des EAGLE Land Cover Components |
| Projection | **EPSG:3035** |
| Millésimes | 2018, 2021, 2023 — passage de triennal à **biennal** à partir de 2023 |
| Accès | WMS, téléchargement par emprise, WEkEO |
| Statut | « Validated » |

Les 11 classes, telles que listées par la fiche produit :

```
1  Sealed                              7  Periodically herbaceous
2  Woody – needle leaved trees         8  Lichens and mosses
3  Woody – broadleaved deciduous       9  Non- and sparsely-vegetated
4  Woody – broadleaved evergreen      10  Water
5  Low-growing woody (bushes, shrubs) 11  Snow and ice
6  Permanent herbaceous
```

### Ce que cela réglerait

**Les esquilles de rastérisation disparaissent par construction.** Elles
existaient parce que CORINE est une couverture *polygonale* rastérisée par
appartenance du centre de cellule : deux polygones voisins laissent un liséré
sans attributaire. Un produit nativement raster n'a pas de frontière partagée,
donc pas d'esquille. `fev_fuel_fill_gaps()` n'aurait rien à réparer — et,
cohérence à noter, rien pour autoriser un comblement non plus, puisque l'UMC d'un
raster est le pixel lui-même.

**Le biais temporel se réduit à sa cause.** Aujourd'hui `fev_validate()` ne peut
que chiffrer le décalage entre le millésime du combustible et la date des
incendies. Aux Maures, le grand feu est de 2021 contre une BD Forêt de 2008-2014.
Un produit biennal ramène l'écart maximal à deux ans.

**La résolution devient honnête à 10 m.** Voir § 6.

### La réserve, et elle porte exactement sur nous

La fiche produit 2023 signale que **la classe 5 — *low-growing woody plants
(bushes, shrubs)* — peut être régionalement en deçà de la précision cible**, la
difficulté étant de la séparer des arbres et de l'herbacé.

C'est la classe du maquis et de la garrigue. Autrement dit, la classe la plus
faible du produit est celle qui porte le plus de danger dans le Var. Cela
n'invalide pas la voie A, mais interdit de la présenter comme un gain uniforme :
il faudra une validation locale sur l'extrait des Maures avant de faire de CLC+
la source primaire, et probablement conserver la BD Forêt en primaire là où elle
est renseignée, CLC+ prenant la place de CORINE en auxiliaire.

### Alternatives non instruites

ESA WorldCover et Dynamic World couvrent le même besoin à 10 m. Non vérifiées
ici. CLC+ a l'avantage d'être le produit de la même filière que CORINE, donc le
moins coûteux à raccorder au vocabulaire de `fev_fuel_types()`.

## 4. Voie B — Sentinel-1

Traitée au niveau de la connaissance de domaine, **sans source vérifiée dans ce
rapport**. À instruire avant tout engagement.

La bande C est sensible à la structure et à la biomasse, et traverse les nuages —
ce qui en fait un complément tout-temps utile. Mais elle sature à biomasse
aérienne modérée et pénètre mal un couvert méditerranéen fermé. Elle ne produit
ni CBH ni FSG.

Nuance en sa faveur : garrigue et maquis se situent **sous** le seuil de
saturation, là où la bande C reste informative. Sentinel-1 est donc plus
prometteur sur les formations basses des Maures que sur la futaie — l'inverse de
l'intuition courante. À retenir comme covariable dans un modèle, pas comme source
autonome.

## 5. Voie C — GEDI × Sentinel-2

### 5.1 Ce qu'est GEDI

Lu au niveau des fiches NASA Earthdata, ORNL DAAC et du site mission.

| Élément | Valeur |
|---|---|
| Porteur | **ISS** — donc couverture entre **51,6° N et 51,6° S** |
| Empreinte | **25 m** de diamètre |
| Échantillonnage | **60 m** le long de la trace, **600 m** entre traces, 8 traces, fauchée 4,2 km |
| Nature | **échantillonnage**, jamais une couverture continue |
| Géolocalisation | incertitude moyenne **~10,3 m** en version 2 |
| Produits | L2A (métriques RH), L2B (couvert, PAI, **PAVD**, FHD), L4A (biomasse) |
| Interruption | aucune donnée du **17 mars 2023 au 24 avril 2024** ; reprise le 26 avril 2024 |

Les deux emprises du paquet sont couvertes : Maures ~43,3° N, Couchey ~47,2° N,
toutes deux sous 51,6°.

Ordre de grandeur de la densité utile — **calcul à moi, pas un chiffre publié** :
une étude citée dénombre environ 1,3 M d'échantillons feuillus et 0,5 M de
résineux sur la France entière ; rapporté à ~17 Mha de forêt, cela donne ~10
empreintes/km², soit de l'ordre de **4 000 empreintes sur les 424 km² de
l'extrait des Maures**. C'est un échantillon confortable pour une interpolation
spatiale. La densité n'est pas le problème.

### 5.2 Le krigeage : ce que dit la littérature

L'intuition est géostatistiquement juste, et elle a été publiée. **Lahssini, le
Maire, Baghdadi & Fayad (2025)**, *Residual Kriging for Regional-Scale Canopy
Height Mapping: Insights into GEDI-Induced Anisotropies and Sparse Sampling*,
arXiv:2510.15572 — lu au niveau du résumé.

Trois enseignements, et ils déplacent la question :

1. **Le krigeage n'y est pas la méthode principale mais une correction.** Les
   auteurs krigent les **résidus** d'un modèle de régression (U-Net et forêt
   aléatoire), pas la variable elle-même. Sentinel-2 fournit la dérive, le
   krigeage récupère l'autocorrélation résiduelle. C'est du krigeage de
   régression, et c'est la forme correcte de l'idée.
2. **Le gain est réel et inégal** : il améliore les deux modèles, plus nettement
   la forêt aléatoire que le réseau profond — signe que les modèles d'apprentissage
   n'exploitent pas pleinement la structure spatiale.
3. **GEDI introduit une anisotropie propre à son acquisition.** La variabilité
   d'énergie des faisceaux combinée à l'azimut des traces produit des motifs
   périodiques. Le variogramme n'est donc **pas isotrope**, et un krigeage naïf
   modéliserait la géométrie du capteur autant que la végétation. Les auteurs
   restreignent l'analyse aux faisceaux de puissance et étudient
   l'autocorrélation dans la direction des traces.

Le résumé ne publie pas les gains chiffrés ni la portée du variogramme. À lire en
texte intégral avant tout engagement.

Conclusion sur la méthode : **envisageable, et sous la bonne forme — krigeage de
régression avec anisotropie modélisée le long des traces.** Ce n'est pas là que
se situe la difficulté.

### 5.3 L'objection décisive : le sous-étage

C'est ici que la voie C achoppe, et il faut le dire nettement.

Ce dont le paquet manque n'est pas la hauteur de houppier — c'est le sous-étage.
Or **GEDI est mauvais précisément là**, et précisément dans notre végétation.

Une évaluation en forêt tempérée du sud-est australien (MDPI, *Remote Sensing*
14(15):3615 — lu au niveau du résumé et des extraits de recherche) rapporte que
les profils PAVD de GEDI **ne suivent pas ceux du LiDAR aéroporté sous une
hauteur de canopée d'environ 30 m**, et que la saturation est marquée sous
couvert dense à sous-étage stratifié.

La futaie méditerranéenne des Maures — chêne-liège, chêne vert, pin — culmine
typiquement entre 5 et 15 m. Elle est **entièrement dans le domaine où GEDI ne
restitue pas le sous-étage.**

Il existe une méthode qui contourne cela, et elle est intéressante :
**Quantifying understory vegetation density using multi-temporal Sentinel-2 and
GEDI LiDAR data**, *GIScience & Remote Sensing* 59(1), 2022 — lu au niveau du
résumé. La densité de sous-étage y est dérivée de la **différence de PAVD entre
saison de végétation et saison de repos**, un modèle SVR étant ensuite entraîné
sur des métriques Sentinel-2. Résultats : R² = 0,89 et 0,93 pour les cartes PAVD
saisonnières contre échantillons GEDI indépendants, et **R² = 0,52, rRMSE = 21 %**
pour la densité de sous-étage contre 86 placettes de terrain.

Mais la méthode **repose entièrement sur un contraste phénologique entre strates**
— le site d'étude est une forêt résineuse sempervirente du sud de la Chine avec
un sous-étage qui, lui, marque les saisons.

**Aux Maures, ce contraste n'existe pas.** Le couvert est sempervirent
sclérophylle (chêne-liège, chêne vert, pin) et le sous-étage l'est aussi (bruyère,
arbousier, ciste). Les deux strates gardent leur feuillage. Le signal sur lequel
repose toute la méthode disparaît.

On ne peut donc pas emprunter cette voie telle quelle sur nos emprises. Elle
resterait à examiner pour Couchey, où le feuillu caducifolié domine — mais
Couchey n'est pas la zone à enjeu.

### 5.4 Le travail est déjà fait pour la hauteur, et gratuitement

Si l'on renonce au sous-étage et qu'on se contente de la structure de houppier,
il n'y a aucune raison de refaire le calcul : deux produits nationaux existent.

**FORMS** — Schwartz et al. (2023), *Earth System Science Data* 15:4927. Lu au
niveau de la page d'article.

| Élément | Valeur |
|---|---|
| Entrées | Sentinel-1, Sentinel-2, GEDI (métrique **RH95**) |
| Modèle | **U-Net**, pas un krigeage |
| Sorties | hauteur **10 m**, biomasse et volume **30 m** |
| Hauteur vs placettes IFN 2020 | MAE **2,94 m**, R² **0,69** |
| Hauteur vs ALS | MAE 3,54 et 4,51 m, R² 0,61 et 0,53 |
| Biomasse vs Renecofor | MAE 59,7 Mg/ha, **R² 0,18** |
| Diffusion | Zenodo `10.5281/zenodo.7840108`, **CC-BY 4.0** |

Limites déclarées par les auteurs, et la dernière nous vise directement :
moindre précision en pente forte ; modèle entraîné sur composite 2020, donc
transposition à d'autres années risquée ; saturation au-delà de 400 Mg/ha ;
allométries hauteur→biomasse peu spécifiques ; **forêts méditerranéennes
sous-représentées dans la validation.**

Le R² de 0,18 sur la biomasse Renecofor mérite d'être lu pour ce qu'il est :
la hauteur est bien restituée, la biomasse beaucoup moins.

**Morin, Planells, Mermoz & Mouret (2023)**, arXiv:2310.14662 (CESBIO) — lu au
niveau du résumé. Même géographie, entrées Sentinel-1/2 + ALOS-2 PALSAR-2 + GEDI,
hauteur MAE 3,7-4,3 m, biomasse MAE 75-93 Mg/ha par placette et 23 Mg/ha après
agrégation régionale. Cartes diffusées librement.

Une troisième piste, non instruite, mérite d'être notée parce qu'elle croise la
phase 8 : *Super-Resolved Canopy Height Mapping from Sentinel-2 Time Series Using
LiDAR HD Reference Data across Metropolitan France* (arXiv:2512.11524) — elle
utilise le LiDAR HD comme référence, exactement la source de la phase 8.

### 5.5 Rappel du plafond déjà établi

Le rapport de phase 8 (`phase8-rapport-lidar.md:255`) avait déjà instruit le
repli satellitaire pour les variables de houppier : produit pan-européen CBH/CBD
à 100 m, millésime 2020, avec **r = 0,445 (CBH)** et **r = 0,330 (CBD)**, soit
environ 11 % de variance expliquée sur la CBD. Rien de ce qui a été trouvé ici ne
relève ce plafond pour les variables de combustible de houppier.

## 6. Effet sur la résolution du paquet

Le 25 m n'est pas une obligation : `res` est un paramètre explicite
(`fuel_source.R:108`). Sa valeur est calée sur la largeur minimale cartographiée
de la BD Forêt v2, 20 m, enregistrée dans `.FEV_FUEL_MMU`. Avec une source
nativement à 10 m, descendre à 10 m cesse d'être une invention.

L'argument le plus fort n'est pas la finesse du contour mais **le rayon de 30 m**.
Le paquet expose trois rayons (`constants.R:303`) : 30 m rayonnement thermique,
100 m brandons courts, 500 m brandons longs. Et `fev_exposure()` garde déjà
`res <= radius / 3` (`exposure.R:132`, condition `fev_res_too_coarse`), au motif
que sous ce rapport l'anneau ne fait plus qu'une poignée de cellules et que la
proportion se quantifie en quelques valeurs — même contrainte que `fireexposuR`.

| Rayon | `radius / 3` | 25 m | 10 m |
|---|---|---|---|
| 30 m | 10 m | **refusé** | **10 m — passe tout juste** |
| 100 m | 33,3 m | passe | passe |
| 500 m | 166,7 m | passe | passe |

Le constat n'est donc pas que le rayonnement thermique est mal échantillonné à
25 m : **il est indisponible.** `fev_exposure(type = "radiant")` s'arrête sur une
erreur tant que la grille est à 25 m.

Et le seuil tombe exactement sur 10 m. **10 m est la grille la plus grossière sur
laquelle le rayon de rayonnement thermique devient calculable selon la règle que
le paquet s'est lui-même donnée.** C'est le seul argument de résolution qui ne
soit pas une préférence : il débloque une des trois échelles du modèle, aujourd'hui
hors d'atteinte. À 500 m au contraire la fraction focale converge, et le gain du
10 m y est marginal.

Le prix est de ×6,25 cellules et ×6,25 surface de fenêtre. **Mesuré** le
2026-08-18 par `fev_exposure_cost()` sur l'emprise réelle des Maures
(677 846 cellules à 25 m) :

| Rayon | ops à 25 m | ops à 10 m | rapport |
|---|---|---|---|
| 30 m | *inatteignable* | 1,19 × 10⁸ | — |
| 100 m | 3,25 × 10⁷ | 1,34 × 10⁹ | **41,1×** |
| 500 m | 8,51 × 10⁸ | 3,32 × 10¹⁰ | **39,0×** |

**Correction d'une supposition de la première version de ce rapport.** Il y était
écrit que `fev_check_focal_cost()` refuserait vraisemblablement l'emprise des
Maures à 10 m. C'est faux sur deux points : cette fonction *avertit*, elle ne
refuse pas ; et son seuil est à 5 × 10¹⁰, que le pire cas ci-dessus — 3,32 × 10¹⁰
— ne franchit même pas. Elle reste donc silencieuse. Les Maures à 10 m coûtent de
l'ordre de **trois minutes** de travail focal au débit mesuré, ce qui est
abordable. Le 39× était juste, la conclusion qu'on en tirait ne l'était pas.

Vérifié de bout en bout sur données réelles : `fev_exposure(type = "radiant")`
sur un carré de 4 km au centre du massif tourne en **0,06 s à 10 m** sur
160 801 cellules, et le même appel à 25 m lève `fev_res_too_coarse`.

À noter enfin que Beverly et al. ont validé leur métrique sur une grille à 100 m :
à 25 m nous sommes déjà plus fins que la méthodologie d'origine.

## 6 bis. Ce que les sources actuelles savent du sous-étage, mesuré

Ajouté le 2026-08-18, avec `fev_fuel_profile()`.

Le brief désigne depuis l'origine la cécité au sous-étage comme la principale
faiblesse du paquet, mais elle n'avait jamais été chiffrée. Les deux placettes
LiDAR HD des Maures le permettent : elles *mesurent* la strate basse que toute
classification optique devine.

Confrontation des 9 classes présentes sur les deux placettes — 566 cellules à
25 m — aux métriques LiDAR, part de variance expliquée par l'appartenance de
classe :

| Métrique | Ce qu'elle décrit | Variance expliquée |
|---|---|---|
| `Cover` | couvert de houppier | **42,6 %** |
| `H_Bush` | hauteur de la strate arbustive | 17,5 % |
| `FL_0_1` | charge 0-1 m | 16,5 % |
| `PAI_tot` | indice de surface végétale | 14,8 % |
| `FL_1_3` | **charge 1-3 m — la strate du maquis** | **8,4 %** |

L'écart entre 42,6 % et 8,4 % est l'argument entier. La classification restitue
ce que ses sources enregistrent — le couvert — et ne dit presque rien de la
strate qui porte le feu de surface. Connaître la classe d'une cellule laisse la
charge du maquis à 92 % indéterminée.

La forme la plus nette du problème est dans la donnée elle-même : **les deux
placettes portent le même code TFV dominant**, `FF1-00-00`, et leur hauteur
arbustive moyenne diffère d'un facteur 5 — 0,86 m sur la brûlée contre 4,44 m sur
le témoin. Le brief l'écrivait ainsi : *« une futaie de chêne vert avec sous-bois
dense et la même sans sous-bois sont identiques dans les deux bases »*. C'est
maintenant un chiffre.

**Ce que cela ne dit pas.** Deux placettes, 566 cellules, un seul massif : c'est
une démonstration de méthode et un ordre de grandeur, pas une validation
générale. Et cela ne mesure pas CLCplus, faute de donnée — cela mesure la base
que CLCplus devra battre, avec l'outil qui servira à le vérifier.

## 7. Ce qu'il faudrait changer dans le code

Voie A, la seule recommandée à court terme :

- une entrée `clcplus_2018/2021/2023` dans `.FEV_FUEL_TYPES` (`fuel_source.R:212`) ;
- une entrée correspondante dans `.FEV_FUEL_MMU` — `complete = TRUE`, et une UMC
  égale à la surface du pixel, ce qui neutralise proprement
  `fev_fuel_fill_gaps()` sans cas particulier dans le code ;
- une table de correspondance des 11 classes vers le vocabulaire de
  `fev_fuel_types()`, à construire depuis le manuel utilisateur et non depuis la
  liste ci-dessus ;
- attention au CRS : le produit est en **EPSG:3035**, le paquet travaille en 2154.
  La règle du brief interdit de reprojeter la source primaire ; c'est donc CLC+
  qui se reprojette si la BD Forêt reste primaire, en `method = "near"` et
  journalisé.

Voie C, si elle était retenue un jour : ingérer FORMS-H comme
`fev_fuel_source(register = "continuous")` plutôt que recalculer. Aucune
dépendance nouvelle, un simple raster.

Accès, si l'on devait descendre au niveau des scènes — non recommandé :
paquets R `CDSE` et client `openEO` (endpoint `openeo.dataspace.copernicus.eu`)
pour Sentinel, `rGEDI` pour GEDI. Tous non testés ici.

## 8. Recommandation

| Voie | Verdict | Motif |
|---|---|---|
| **A — CLC+ Backbone en auxiliaire** | **à faire** | supprime les esquilles et le biais de millésime, coût faible, machinerie catégorielle réutilisée |
| B — Sentinel-1 | à instruire | covariable plausible sur formations basses, jamais source autonome |
| C — GEDI × S2 pour la hauteur | **ingéré, non recalculé** | `fev_fetch_forms()`, 10 m, CC-BY ; étend `fev_fuel_profile()` hors emprise LiDAR |
| C' — GEDI × S2 pour le sous-étage | **non** | GEDI aveugle sous ~30 m de canopée ; le contournement phénologique s'effondre en sempervirent |
| Descente à 10 m | **motivée**, si source native 10 m | seule grille où `type = "radiant"` cesse d'être refusé ; prix ~39× le coût focal |

**Le sous-étage méditerranéen reste le domaine du LiDAR HD.** Rien dans ce qui a
été instruit ne permet de retirer à la phase 8 ce rôle-là, ni d'atténuer la limite
que le brief demande d'afficher dans la vignette.

Sur la question posée — le krigeage GEDI × Sentinel-2 est une **méthode valide,
sous sa forme de krigeage de régression avec anisotropie modélisée**, mais
appliquée à une variable que nous savons déjà obtenir autrement, et incapable de
livrer celle qui nous manque.

## 9. Ce qui n'a pas été vérifié

- Aucun appel réel. Aucun endpoint testé, aucune emprise téléchargée.
- Liste des 11 classes CLC+ : **désormais vérifiée**. Le `GetLegendGraphic` du
  WMS producteur rend les onze libellés plus 253 et 254 directement depuis le
  style publié, et ils correspondent à la table. Une seule correction, de
  ponctuation. Deux routes indépendantes concordent, catalogue EEA et légende.
- Précisions par classe de CLC+ : **cherchées et introuvables**. L'ATBD 2023 a été
  lu directement et n'en contient aucune ; le manuel utilisateur n'était pas
  atteignable ; les rapports de validation sont annoncés à paraître. Ce qui est
  su : la cible est d'au moins 85 % par classe, atteinte partout sauf pour trois
  classes régionalement plus faibles — 5 (ligneux bas), 8 (lichens et mousses) et
  9 (non et peu végétalisé). De combien, personne ne le publie encore.
- Lahssini et al. 2025 : résumé seul. Gains chiffrés et portée du variogramme
  inconnus.
- L'évaluation australienne de GEDI : résumé et extraits. Le seuil de « ~30 m »
  est à confirmer en texte intégral, et sa transposabilité au bassin
  méditerranéen n'est pas établie.
- Sentinel-1 : aucune source vérifiée, section rédigée de mémoire et signalée
  comme telle.
- ESA WorldCover, Dynamic World : non instruits.

## 10. Ce que le WMS a appris, et ce qu'il ne remplace pas

Ajouté le 2026-08-18, après sondage des services publics du produit.

**Le WCS est désactivé.** `service=WCS` sur le GeoServer répond
`Service WCS is disabled`. Il n'existe donc aucune route ouverte vers les
*valeurs* de classe : le téléchargement passe obligatoirement par EU Login.

**Le WMS reste ouvert, et rend des images.** On pourrait inverser la palette d'un
PNG indexé pour en tirer des chiffres. Il ne faut pas : ce serait un rendu
déguisé en donnée, avec une résolution rééchantillonnée et une provenance
mensongère. Le brief l'interdit nommément.

Ce que le WMS a tout de même donné :

* **La légende officielle vérifie les libellés.** C'était le point le plus faible
  de ce rapport ; il est levé.
* **La clé de lecture** : la classe 5 est le brun. Sur l'extrait des Maures, le
  tiers nord en est largement couvert, ce qui recoupe grossièrement l'emprise du
  feu de 2021 — la régénération post-incendie étant du ligneux bas. **Hypothèse à
  tester, pas résultat** : c'est de l'œil sur un rendu.
* **CLCplus couvre aussi les DOM, en UTM et hors grille EEA.** La liste des
  couches nomme `GF/32622`, `GP/32620`, `MQ/32620`, `RE/32740`, `YT/32738`. Cela
  a révélé un défaut réel : `fev_clcplus_tiles()` rendait `E99N-31` pour La
  Réunion — un code qui ressemble à une tuile et n'en nomme aucune. Il refuse
  désormais.

## Sources

- [CLCplus Backbone — Copernicus Land Monitoring Service](https://land.copernicus.eu/en/products/clc-backbone)
- [CLCplus Backbone 2023 (raster 10 m), Europe, 2-yearly](https://land.copernicus.eu/en/products/clc-backbone/clcplus-backbone-2023-raster-10-m-europe-2-yearly)
- [CLCplus Backbone 2023 — Product User Manual](https://land.copernicus.eu/en/technical-library/product-user-manual-clcplus-backbone-2023/@@download/file) (non lu)
- [CLCplus Backbone 2023 — ATBD](https://library.land.copernicus.eu/products/CLCplus_Backbone_2023_ATBD_v1.pdf) (non lu)
- [GEDI L2B Canopy Cover and Vertical Profile Metrics V002 — NASA Earthdata](https://www.earthdata.nasa.gov/data/catalog/lpcloud-gedi02-b-002)
- [GEDI L2A Elevation and Height Metrics V002 — NASA Earthdata](https://www.earthdata.nasa.gov/data/catalog/lpcloud-gedi02-a-002)
- [GEDI — Specifications](https://gedi.umd.edu/instrument/specifications/)
- [GEDI L4A Footprint Level Aboveground Biomass Density V3 — ORNL DAAC](https://daac.ornl.gov/GEDI/guides/GEDI_L4A_AGB_Density_V3.html)
- [Lahssini, le Maire, Baghdadi & Fayad (2025), *Residual Kriging for Regional-Scale Canopy Height Mapping*](https://arxiv.org/abs/2510.15572)
- [*Quantifying understory vegetation density using multi-temporal Sentinel-2 and GEDI LiDAR data*, GIScience & Remote Sensing 59(1)](https://www.tandfonline.com/doi/full/10.1080/15481603.2022.2148338)
- [*Performance of GEDI Space-Borne LiDAR for Quantifying Structural Variation in the Temperate Forests of South-Eastern Australia*, Remote Sensing 14(15):3615](https://www.mdpi.com/2072-4292/14/15/3615)
- [Schwartz et al. (2023), *FORMS*, Earth System Science Data 15:4927](https://essd.copernicus.org/articles/15/4927/2023/)
- [Morin, Planells, Mermoz & Mouret (2023), arXiv:2310.14662](https://arxiv.org/abs/2310.14662)
- [*Super-Resolved Canopy Height Mapping from Sentinel-2 Time Series Using LiDAR HD Reference Data*, arXiv:2512.11524](https://arxiv.org/html/2512.11524v1) (non lu)
- [CDSE — paquet R](https://search.r-project.org/CRAN/refmans/CDSE/html/CDSE.html)
- [openEO — client R, Copernicus Data Space Ecosystem](https://documentation.dataspace.copernicus.eu/APIs/openEO/R_Client/R.html)
- [rGEDI — paquet R](https://github.com/carlos-alberto-silva/rGEDI)
