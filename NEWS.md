# firexpovulnR 0.24.0 (2026-08-18)

### `fev_lidar_batch()` — le traitement par lots que la phase 8 réclamait

Le brief de phase 8 le demandait — *« prévois un mode de reprise après
interruption »* — et il n'avait jamais été écrit. Les chronométrages de la
0.23.0 l'ont rendu indispensable plutôt qu'agréable : une dalle peut prendre des
heures, et un traitement qui perd tout quand la machine se met en veille n'est
pas un traitement.

La fonction parcourt les dalles une à une : téléchargement, inversion par
`fev_fuel_lidar()`, écriture d'un raster par dalle, suppression du nuage avant
de passer à la suivante.

* **La reprise se fait par présence de la sortie**, pas par un fichier d'état
  qui peut mentir : une dalle dont le raster est sur le disque est faite. Chaque
  raster est écrit sous un nom temporaire puis renommé, donc une écriture
  interrompue n'est jamais prise pour une dalle terminée.
* **Une dalle qui échoue n'arrête pas la campagne.** Un lot qui meurt à la
  troisième dalle sur quarante gâche les deux qui avaient réussi.
* Le **manifeste est réécrit après chaque dalle**, donc une interruption laisse
  un relevé lisible de ce qui a été tenté et de ce qui a échoué.
* `window` traite un carré centré plutôt que la dalle entière. C'est ce qui rend
  une campagne abordable : huit fenêtres de 250 m échantillonnent huit contextes
  là où une dalle entière n'en échantillonne qu'un, pour une fraction du coût.
  Pour comparer à une classification, la dispersion vaut mieux que la contiguïté.
* Le délai de téléchargement est porté à une heure. Le défaut de 60 s fait
  échouer chaque dalle au quart téléchargé — c'est ainsi que la première
  tentative a été perdue.

**Ce que la documentation refuse explicitement :** réduire la densité du nuage
pour aller plus vite. La strate de sous-étage est la première à disparaître
quand la densité baisse, donc éclaircir fausse exactement ce que ces métriques
servent à mesurer. Réduire `window`, ou traiter moins de dalles.

### Un script prêt à lancer

`inst/scripts/batch_lidar.R`, exécutable, avec `--dry-run` pour voir le plan
avant d'engager quoi que ce soit :

```sh
Rscript batch_lidar.R maures.gpkg out/lidar --window=250 --dry-run
Rscript batch_lidar.R maures.gpkg out/lidar --window=250 --max=8
```

Relancer la même commande le lendemain reprend où l'on s'était arrêté.

# firexpovulnR 0.23.0 (2026-08-18)

### Élargir la mesure au-delà des deux placettes : tenté, et hors de portée

Le résultat est négatif et vaut d'être consigné. Traiter davantage de dalles
LiDAR HD pour élargir l'échantillon a échoué non par manque de donnée — 505
dalles sont disponibles sur le massif, et une dalle de 248 Mo arrive en 42 s —
mais sur le **coût d'inversion** de `fev_fuel_lidar()`.

Trois tentatives, toutes des bornes inférieures puisqu'aucune n'a abouti :
250 m et 3,0 M de points, plus de 25 min ; 500 m et 11,1 M de points, plus de
40 min ; une dalle entière, plus de 90 min.

Ces chiffres sont désormais dans la documentation de `fev_fuel_lidar()`, avec
les deux conséquences qu'ils imposent : un traitement départemental est un
travail par lots avec reprise, pas une commande interactive ; et **on n'achète
pas de la vitesse en éclaircissant le nuage**, puisque la strate de sous-étage
est la première à disparaître quand la densité baisse — ce serait fausser
précisément la grandeur mesurée.

La mesure reste donc ce qu'elle était : deux placettes, 566 cellules, un massif.
Un ordre de grandeur et une méthode, ce que le code, NEWS et l'article disaient
déjà.


### La BD Forêt décide désormais la classe

`.FEV_FUEL_PRIORITY` suit la mesure publiée en 0.22.0 au lieu de la contredire.
L'ordre est maintenant **BD Forêt v2, puis WorldCover, puis CORINE** ; il était
WorldCover en tête en 0.19.0 et 0.20.0, sur un jugement porté avant que les
chiffres n'existent.

Rappel de ce qui a tranché : sur la même grille de 25 m, les mêmes cellules et le
même LiDAR, la BD Forêt explique davantage de **chacune** des cinq métriques de
sous-étage — jusqu'à 43,0 % contre 7,8 % sur le couvert de houppier — tout en
étant la plus ancienne des trois sources.

**Ce que ce choix coûte**, et il faut le dire : la mesure neutralise
volontairement le 10 m et le millésime 2021, c'est-à-dire ce qui fait l'intérêt
de WorldCover. Pour une étude hors de France, ou une étude où la fraîcheur prime
sur l'essence, passer `hierarchy` explicitement à l'appel.

Le coût est moindre qu'il ne l'aurait été avant la 0.20.0 : depuis que
`fev_fuel_attach()` accepte une source catégorielle, celle qui perd voyage à
côté au lieu d'être jetée.

Deux tests ont changé de sens plutôt que d'être supprimés. Celui qui vérifiait
que l'essence survit à une fusion gagnée par WorldCover demande désormais ce cas
explicitement — c'est devenu le scénario d'un utilisateur qui veut le 10 m sans
payer en botanique, et c'est précisément ce pour quoi l'attache existe.

# firexpovulnR 0.22.0 (2026-08-18)

### `fev_exposure(trim = )` — le cadre blanc de 500 m disparaît

L'anneau extérieur d'un résultat focal n'est pas une mesure : c'est la fenêtre
qui déborde du bord de la donnée. Avec `na_rm = FALSE` il revient vide, et c'est
le cadre blanc de toutes les cartes d'exposition publiées jusqu'ici.

Le paquet donnait déjà la moitié du remède, dans le message
`fev_extent_too_small` : calculer sur plus grand qu'on ne publie. `trim` fournit
l'autre moitié.

```r
fuel <- fev_fuel_source(bdforet, aoi = sf::st_buffer(study, 500), ...)
expo <- fev_exposure(fuel, radius = 500, trim = study)
```

Mesuré sur l'emprise des Maures : **9,3 % de cellules vides sans recadrage,
0,3 % avec**. Le cadre est toujours calculé — il le faut, pour que l'intérieur
soit juste — puis coupé au lieu d'être publié. Les valeurs conservées sont
exactement celles qui avaient été calculées, un test le vérifie cellule par
cellule.

Une marge insuffisante est **refusée bruyamment** : recadrer sur une zone que le
tampon n'a jamais couverte fait entrer une partie du cadre dans la surface
rapportée, ce qui est pire que de le laisser visible.

### La hiérarchie des sources est mesurée, et la mesure la contredit

`.FEV_FUEL_PRIORITY` portait un commentaire admettant que son ordre était un
jugement. Il ne l'est plus. Les trois sources placées sur la même grille de 25 m,
sur les mêmes cellules, confrontées au même LiDAR — part de variance expliquée
par l'appartenance de classe :

| Source | classes | `H_Bush` | `FL_0_1` | `FL_1_3` | `Cover` | `PAI_tot` |
|---|---|---|---|---|---|---|
| **BD Forêt v2** | 6 | **18,2** | **15,0** | **8,2** | **43,0** | **15,1** |
| CORINE 2018 | 3 | 8,8 | 4,7 | 0,6 | 25,0 | 5,3 |
| WorldCover 2021 | 5 | 4,0 | 8,4 | 5,2 | 7,8 | 8,2 |

La BD Forêt gagne les cinq, en étant **la plus ancienne des trois** — millésime
2014, antérieur au feu. La récence n'explique donc pas l'écart ; la profondeur
thématique le fait.

L'ordre livré n'est pas modifié : WorldCover reste en tête, sur décision
explicite, parce que la mesure **neutralise volontairement** ce qui fait son
intérêt — 10 m et un millésime 2021 partout. Mais le commentaire porte désormais
les chiffres et dit comment inverser en une ligne.

### Les deux articles au niveau du code

* Combustible construit sur l'emprise **tamponnée de 500 m**, exposition
  recadrée par `trim` : plus de cadre blanc sur aucune carte.
* L'article des Maures gagne la comparaison des trois sources, avec le code
  WorldCover montré mais **non exécuté** — une vignette ne doit pas dépendre
  d'un service distant, sinon le `R CMD check` rougit le jour d'une panne de
  bucket.

# firexpovulnR 0.21.0 (2026-08-18)

### CLCplus Backbone retiré

Le périmètre est la France, et dans ce périmètre CLCplus n'apportait plus rien.

Son seul avantage irremplaçable était de séparer le feuillu **sempervirent** du
**caducifolié** — ce que CORINE ne fait pas (311 les confond), ni WorldCover (une
seule classe *Tree cover*), ni la HRL *Dominant Leaf Type* (feuillu/résineux
seulement, vérifié). Mais **la BD Forêt le fait**, et plus finement :
`FF1G06-06` chêne sempervirent contre `FF1G01-01` chêne décidu, soit l'essence
et non la seule phénologie foliaire.

Ce qui a rendu l'argument décisif est la version précédente :
`fev_fuel_attach()` accepte désormais une source catégorielle, donc la BD Forêt
survit **à côté** d'une classe décidée par un raster à 10 m au lieu d'être
écrasée. Avant cela, mettre WorldCover au-dessus coûtait l'essence et CLCplus
gardait un intérêt. Après, non.

S'y ajoutait un défaut de fond : le produit est derrière EU Login, ce paquet ne
manipule pas de jeton personnel, et **aucun raster réel n'est jamais passé dans
ce code**. Il était testé contre des rasters synthétiques et rien d'autre.

Retirés : `fev_fetch_clcplus()`, `fev_clcplus_tiles()`, la table de
correspondance des 12 classes, les entrées de type, d'UMC et de priorité, et
leurs 50 tests.

**Conservé, parce que CLCplus n'en était que l'occasion :** le champ `native` de
`.FEV_FUEL_MMU` et le refus distinct de `fev_fuel_fill_gaps()` pour une source
nativement raster, le drapeau `grid_driver`, `fev_fuel_profile()`,
`fev_exposure_cost()`, et le rapport de phase 10 — qui reste le compte rendu de
l'instruction, branche non retenue comprise.

**Ce qu'on renonce à pouvoir faire :** analyser hors de France avec la séparation
sclérophylle. Hors BD Forêt, aucune source du paquet ne distingue le chêne vert
du hêtre. Le rapport de phase 10 dit où retrouver le produit si le périmètre
change un jour.

# firexpovulnR 0.20.0 (2026-08-18)

### `fev_fuel_attach()` garde les deux, au lieu d'en sacrifier une

Réponse à la conséquence livrée en 0.19.0 : WorldCover placé au-dessus prend
**tous** les pixels, et l'essence et le taux de couvert de la BD Forêt
disparaissent avec elle.

La fonction accepte désormais une source **catégorielle** en second argument, et
non plus seulement un registre continu. Ce qu'elle porte décide où elle atterrit
— des métriques continues vont au registre continu, une couche de classes
devient une couche nommée du registre catégoriel. Dans les deux cas elle
**n'arbitre aucun pixel**, ce qui est toute la différence avec
`fev_fuel_merge()`.

```r
fuel <- fev_fuel_merge(bdforet, worldcover)   # WorldCover décide `class`
fuel <- fev_fuel_attach(fuel, bdforet)        # l'essence survit à côté
```

Mesuré sur les Maures : `class` reste à WorldCover au 10 m, et la couche
`bdforet_v2` attachée conserve **27 classes TFV sur 81,1 % des cellules
cartographiées** — dont le chêne vert, `FF1G06-06`, sur 1 520 475 cellules, que
la nomenclature WorldCover ne sait pas exprimer.

* La couche attachée ne décide rien : `fev_fuel_binary()`, `fev_fuel_type()` et
  toute la chaîne d'exposition lisent `class` et l'ignorent.
* `fev_fuel_fill_gaps()` la laisse intacte. Ses `NA` signifient « pas de forêt
  ici », ce qui est une information ; les combler depuis un voisin modal
  inventerait des essences.
* Un nom déjà pris est refusé plutôt que doublé silencieusement.

**Changement de contrat.** Attacher une source catégorielle levait auparavant
`fev_missing_register` ; c'est maintenant la fonctionnalité. Le second paramètre
est renommé `lidar` → `extra`, l'usage positionnel étant inchangé.

# firexpovulnR 0.19.0 (2026-08-18)

### `fev_fetch_worldcover()` — la première source 10 m que le paquet sait chercher

ESA WorldCover, 11 classes à 10 m dérivées de Sentinel-1 et Sentinel-2, sous
CC-BY 4.0. La différence avec CLCplus n'est pas thématique, elle est d'accès :
CLCplus est derrière EU Login et a dû devenir un import manuel ; WorldCover est
sur un bucket public.

**Et la fonction ne télécharge pas de tuile.** Une tuile WorldCover fait 3° de
côté — 36 000 × 36 000 cellules — quand une analyse en veut une fraction. GDAL
lisant les GeoTIFF nuage-optimisés par requête de plage, seule la fenêtre
demandée traverse le réseau.

Les onze codes ont été vérifiés **contre la table de couleurs embarquée dans le
raster lui-même**, les onze triplets RVB correspondant à la légende publiée.
C'est une vérification depuis la donnée plutôt que depuis un document sur la
donnée, et c'est la route la plus solide qu'ait employée ce paquet pour une
nomenclature. Le nodata — la valeur 0, d'alpha nul dans cette même table — en
vient aussi.

### `fev_fuel_merge(hierarchy = "auto")`, et WorldCover au-dessus

Le nouveau défaut classe les sources par **type** au lieu de faire confiance à
l'ordre des arguments, qui n'enregistre que l'objet nommé en premier. Du plus
fort au plus faible : **WorldCover, BD Forêt v2, CLCplus, CORINE**. À rang égal
ou inconnu, retour à l'ordre des arguments — donc `fev_fuel_merge(bdforet,
corine)` est inchangé.

**Ce que ce choix coûte, mesuré et non supposé.** WorldCover achète le 10 m et un
millésime 2021 partout, contre 25 m et 2008-2018 pour la BD Forêt. Il paie en
profondeur thématique : pas d'essence, pas de taux de couvert, et une classe
*Shrubland* qui ne sépare le sous-étage mesuré qu'à 0,688 au mieux sur les deux
placettes des Maures — ses cellules *Shrubland* et *Tree cover* portant
pratiquement le même sous-étage. Pour renverser :
`fev_fuel_merge(bdforet, worldcover, hierarchy = "primary_first")`.

### Un empilement complet n'est pas une fusion, et le dit

Conséquence directe et facile à manquer : WorldCover ayant une couverture
complète, placé au-dessus il ne laisse **rien** à combler. Sur les Maures, la BD
Forêt ne contribue plus une seule des 7 160 572 cellules. Le mot « merge » rend
cela invisible, donc `fev_fuel_merge()` avertit désormais quand une source
n'apporte aucune cellule : ce n'est plus une fusion mais un remplacement.

# firexpovulnR 0.18.1 (2026-08-18)

### Les libellés CLCplus sont vérifiés chez le producteur

Le `GetLegendGraphic` du WMS rend les onze libellés, plus 253 et 254, directement
depuis le style publié. Ils correspondent à la table livrée. C'était le point
ouvert le plus gênant de la phase 10 — les libellés venaient d'un résultat de
recherche — et deux routes indépendantes concordent désormais. Une seule
correction, de ponctuation : « Non and sparsely vegetated ».

La légende donne aussi la clé de lecture du produit : **la classe 5, le maquis,
est le brun**.

### `fev_clcplus_tiles()` ne rend plus de fausse tuile outre-mer

CLCplus couvre les départements d'outre-mer, mais comme **produits séparés dans
leur propre zone UTM** — la liste des couches WMS nomme `GF/32622`, `GP/32620`,
`MQ/32620`, `RE/32740` et `YT/32738`. Ils ne sont pas sur la grille EEA.

La fonction projetait pourtant tout en EPSG:3035, une projection centrée sur
l'Europe. La Réunion en ressortait avec le code `E99N-31` : arithmétiquement
correct, géographiquement absurde, et surtout **plausible**. Un code qui
ressemble à une tuile et n'en nomme aucune est pire qu'un refus. Elle refuse
maintenant, et dit où chercher les produits d'outre-mer.

### Il n'existe pas de route ouverte vers les valeurs

Vérifié : le WCS du GeoServer répond `Service WCS is disabled`. Le WMS reste
ouvert mais rend des images. Inverser la palette d'un PNG indexé pour en tirer
des codes de classe produirait un rendu déguisé en donnée — résolution
rééchantillonnée, provenance mensongère — et le paquet ne le fera pas. Le
téléchargement passe par EU Login, et c'est le seul geste de la phase 10 qui
demande une main humaine.

# firexpovulnR 0.18.0 (2026-08-18)

### `fev_clcplus_tiles()` — quelles tuiles télécharger

CLCplus est diffusé en tuiles de **100 x 100 km** en GeoTIFF nuage-optimisé sur
la grille de référence EEA. Puisque le téléchargement est manuel — le produit est
derrière EU Login — le moins que ce paquet puisse faire est de dire exactement
quelles tuiles prendre, plutôt que de laisser le calcul à faire sur une carte.

Le code de cellule EEA est la taille suivie du coin inférieur gauche exprimé en
unités de cette taille, en EPSG:3035 : une tuile de 100 km dont le coin est à
4 000 000 m est et 2 200 000 m nord s'appelle `E40N22`.

Pour les deux emprises embarquées : **les Maures tiennent dans une seule tuile,
`E40N22`** ; **Couchey en chevauche deux**, `E39N26` et `E39N27`, parce que
l'emprise traverse le northing 2 700 000 — une seule tuile y laisserait un trou.

Le refus de `fev_fetch_clcplus()` nomme désormais ces tuiles quand un `aoi` lui
est passé. Nommer la tuile est la chose la plus utile qu'un refus puisse faire
quand la récupération doit se faire à la main.

L'arithmétique est le système de codage documenté de la grille EEA ; **le préfixe
exact que le CLMS met devant dans ses noms de fichiers n'a pas été vérifié**,
donc cherchez la partie `E..N..` dans la liste de téléchargement.

# firexpovulnR 0.17.0 (2026-08-18)

### `fev_fetch_forms()` — la hauteur de canopée pour toute la France

Étape 4 de la phase 10, débloquée par la réussite de l'étape 3, et délibérément
un **import** plutôt qu'un calcul. Coupler GEDI à Sentinel-2 pour obtenir la
hauteur de canopée est une méthode valide — y compris par krigeage de régression,
avec l'anisotropie des traces GEDI modélisée. Mais Schwartz et al. l'ont fait
pour la France entière à 10 m sous CC-BY. Le refaire coûterait une phase pour
retrouver un résultat gratuit, dont nous devrions ensuite la validation.

Ce que cela apporte concrètement : `fev_fuel_profile()` dispose enfin d'une
référence **au-delà de l'emprise LiDAR**. Une classification peut être confrontée
à une hauteur mesurée n'importe où en France, et plus seulement sur les deux
placettes embarquées.

Trois mises en garde voyagent avec le produit, et la fonction les répète au lieu
de supposer qu'on les a lues : modèle entraîné sur un composite **2020** unique ;
**forêts méditerranéennes sous-représentées dans la validation**, ce qui vise les
Maures ; et une fiabilité très inégale selon la variable — hauteur MAE 2,94 m et
R² 0,69 contre placettes IFN, biomasse R² 0,18 contre Renecofor. Les deux ne se
lisent pas de la même façon, et le paquet refuse de publier un chiffre unique
pour « FORMS ».

Ce que cela ne fait pas : lever la limite centrale. FORMS donne le **houppier**.
Le sous-étage reste au LiDAR HD.

### Les classes régionalement faibles de CLCplus sont trois, pas deux

Correction. Le paquet enregistrait 5 (ligneux bas) et 8 (lichens et mousses). Les
producteurs en nomment **trois** : s'y ajoute la 9 (non et peu végétalisé). La
cible est d'au moins 85 % de précision par classe, atteinte partout ailleurs.

**De combien elles manquent la cible n'est pas public.** L'ATBD a été lu
directement et ne contient aucun chiffre par classe ; les rapports de validation
sont annoncés à paraître. Le paquet enregistre donc *quelles* classes sont
faibles, pas *à quel point* — c'est la limite honnête de ce qui est connu.

### L'article des Maures met un chiffre sur son propre argument

La page démontrait sur deux carrés que la BD Forêt ne distingue pas un sous-bois
dense d'un sol nu. `fev_fuel_profile()` le généralise aux neuf classes présentes
et 566 cellules : l'appartenance de classe explique **42,6 %** de la variance du
couvert de houppier et **8,4 %** de celle de la charge 1-3 m — la strate qui porte
le feu de surface, laissée indéterminée à 92 %.

Ce n'est pas une critique de la BD Forêt, qui fait ce pour quoi elle est faite.
C'est le prix chiffré de son emploi seule pour du combustible, et la raison
d'être du registre continu.

# firexpovulnR 0.16.0 (2026-08-18)

### `fev_fuel_profile()` — ce qu'une classification ne peut pas dire d'elle-même

Étape 2 de la phase 10. Une classification ne peut pas se valider elle-même : la
question doit être posée à quelque chose qui a *mesuré* le sol. Le LiDAR HD de la
phase 8 le fait, et c'est tout son intérêt.

La fonction résume des métriques continues sur les cellules de chaque classe
catégorielle, et rapporte deux choses : la **part de variance** que
l'appartenance de classe explique, et la **séparabilité** d'une classe donnée —
la statistique de Mann-Whitney, celle que `fev_validate()` publie comme AUC, dont
l'implémentation est réutilisée plutôt que redoublée.

Rien n'y est propre à CLCplus : la même confrontation vérifie si la « forêt
fermée » de la BD Forêt l'est vraiment, ou si CORINE 323 porte du sous-étage.

### La cécité au sous-étage, chiffrée pour la première fois

Le brief désigne cette cécité depuis l'origine comme la principale faiblesse du
paquet. Elle n'avait jamais été mesurée. Sur les deux placettes LiDAR des Maures,
566 cellules et 9 classes :

| Métrique | Variance expliquée par la classe |
|---|---|
| `Cover` — couvert de houppier | **42,6 %** |
| `H_Bush` | 17,5 % |
| `FL_0_1` | 16,5 % |
| `PAI_tot` | 14,8 % |
| `FL_1_3` — **la strate du maquis** | **8,4 %** |

L'écart est l'argument entier : la classification restitue ce que ses sources
enregistrent, le couvert, et laisse la charge du maquis indéterminée à 92 %.

Plus net encore, dans la donnée brute : les deux placettes portent le **même code
TFV dominant**, `FF1-00-00`, pour des hauteurs arbustives moyennes de 0,86 m et
4,44 m. Le brief écrivait « une futaie de chêne vert avec sous-bois dense et la
même sans sont identiques dans les deux bases » ; c'est maintenant un chiffre.

Deux placettes et un seul massif : démonstration de méthode et ordre de grandeur,
pas validation générale. Et cela ne mesure pas CLCplus, faute de donnée — cela
mesure la base que CLCplus devra battre, avec l'outil qui servira à le vérifier.

### `fev_exposure_cost()` — ce que coûtera la passe focale, avant de la lancer

Étape 3. Le coût croît comme la **puissance quatrième** de l'inverse de la taille
de cellule, le nombre de cellules et la surface de fenêtre variant chacun en
`res^-2`. Passer de 25 m à 10 m n'est donc pas un facteur 2,5 mais quarante.

Mesuré sur l'emprise réelle des Maures, 677 846 cellules à 25 m :

| Rayon | 25 m | 10 m | rapport |
|---|---|---|---|
| 30 m | *inatteignable* | 1,19 × 10⁸ | — |
| 100 m | 3,25 × 10⁷ | 1,34 × 10⁹ | **41,1×** |
| 500 m | 8,51 × 10⁸ | 3,32 × 10¹⁰ | **39,0×** |

**Et le 10 m est abordable**, contrairement à ce que le rapport supposait avant
de mesurer : le pire cas reste sous le seuil d'alerte de `fev_check_focal_cost()`,
qui de toute façon avertit et ne refuse pas. Les Maures à 10 m représentent de
l'ordre de trois minutes de travail focal.

La fonction rapporte aussi, pour chaque rayon, s'il est **atteignable** à la
résolution demandée — car un maillage grossier ne coûte pas seulement moins, il
met les petits rayons hors de portée.

### Le rayonnement thermique tourne, pour la première fois

Vérifié de bout en bout sur les Maures : `fev_exposure(type = "radiant")` produit
une carte en **0,06 s à 10 m** sur 160 801 cellules, là où le même appel à 25 m
lève `fev_res_too_coarse`. C'était le livrable qui devait prouver l'intérêt de la
phase, et une des trois échelles du modèle n'avait jamais tourné.

# firexpovulnR 0.15.0 (2026-08-18)

### `fev_fetch_clcplus()` — CLCplus Backbone, raster 10 m issu de Sentinel-2

Première livraison de la phase 10, dont le rapport de faisabilité
(`specs/phase10-rapport-sentinel.md`) écarte les autres voies satellitaires.

* **Ce n'est pas un téléchargeur, et c'est délibéré.** Le Copernicus Land
  Monitoring Service sert ce produit derrière EU Login et un échange de jeton
  OAuth2, et le brief interdit au paquet de manipuler un jeton personnel — la
  règle même qui avait envoyé la phase 9 vers Open-Meteo. La fonction importe
  donc un fichier récupéré à la main et l'enregistre comme tel dans la
  provenance. La forme honnête d'une source sous jeton est un bon message
  d'erreur, pas un gestionnaire d'identifiants.
* **L'absence n'est pas une classe.** Les codes 254 (hors zone du produit) et
  255 (pas de donnée) deviennent `NA` à l'import. Leur donner un type de
  combustible affirmerait que le sol inconnu est non-combustible, ce que le
  paquet refuse partout ailleurs. Le code 253, tampon d'eau côtière, est une
  surface et reste une classe — l'extrait des Maures atteint la mer.
* Le raster arrive **catégoriel**, étiqueté depuis la table de correspondance,
  sinon `fev_fuel_source(register = "auto")` lirait la classe 5 comme la mesure
  de cinq de quelque chose.

### Ce que ce produit échange contre CORINE

Il ne la remplace pas, il l'échange — d'où l'intérêt que `fev_fuel_merge()`
garde les deux.

* **Gain sur l'arboré :** CORINE 311 mettait chêne vert et hêtre dans la même
  classe, limite que la table CORINE de ce paquet énonçait déjà. CLCplus sépare
  feuillu caducifolié (classe 3) et sempervirent (classe 4), et autour de la
  Méditerranée le second *est* le type sclérophylle.
* **Perte sur l'arbustif :** là où CORINE distingue 322, 323 et 324, CLCplus
  fond tout dans la classe 5. Maquis, lande et régénération post-incendie
  deviennent une seule valeur.
* **Et la classe faible est celle qui brûle.** La validation indépendante donne
  85,2 % et 85,3 % de précision globale pour 2018 et 2021, mais les producteurs
  déclarent des tolérances d'erreur *supérieures* pour la classe 5. La fonction
  le dit à l'import plutôt que de le laisser dans un PDF, et chaque ligne de
  végétation de la table est marquée `ambiguous`.

### `fev_fuel_fill_gaps()` distingue deux refus qu'il confondait

Une source nativement raster n'a pas d'esquille : les esquilles viennent du
chemin vectoriel, un centre de cellule ne tombant dans aucun de deux polygones
mitoyens. Et son plus petit objet représentable étant le pixel, aucun trou ne
peut passer sous son unité minimale. Les deux faits disent la même chose —
ne jamais combler — mais pour une raison opposée à celle de la BD Forêt, dont
le silence est une information. Le message le dit désormais, au lieu de servir
« aucune composante ne couvre son emprise entière » à un produit qui, lui, la
couvre.

### `fev_check_res()` ne cite plus la BD Forêt en dur

Le plancher sous lequel une résolution n'apporte rien est une propriété de la
source, pas une constante : 20 m pour la BD Forêt v2, 10 m pour CLCplus. La
fonction lit maintenant `min_width_m` dans `.FEV_FUEL_MMU`. Annoncer à un
utilisateur de CLCplus que 10 m est plus fin que le détail de la BD Forêt était
faux et déroutant.

### La raison de descendre à 10 m

Documentée dans `fev_fuel_source()`, et ce n'est pas la finesse du contour.
`fev_exposure()` garde `res <= radius / 3` : à 25 m le rayon de rayonnement
thermique de 30 m est **refusé**, à 10 m il passe tout juste, puisque
10 = 30 / 3. Une source à 10 m est donc le seul moyen d'atteindre cette échelle,
et elle coûte environ **39 fois** le travail focal du 25 m.

# firexpovulnR 0.14.0 (2026-08-17)

### `fev_fuel_fill_gaps()` — réparer les esquilles de rastérisation

Rastériser une couverture polygonale par appartenance du centre de cellule laisse
des trous : là où deux polygones CORINE partagent une frontière, le centre peut ne
tomber dans ni l'un ni l'autre. 42 cellules sur 469 989 à Couchey, 18 sur 677 846
aux Maures — un dix-millième de la grille.

Ce n'était pas anodin. `fev_exposure()` propage tout vide à travers sa fenêtre
focale, donc **chaque cellule vide isolée en effaçait un disque du rayon de la
fenêtre** : amplification mesurée de **626**, et 17,5 % de la carte de risque de
Couchey blanche.

* **Ce qui autorise la réparation est l'unité minimale de cartographie.** CORINE
  ne peut rien représenter sous 25 ha — le plus petit polygone des deux extraits
  mesure 24,92 et 24,93 ha, donc la spécification est *observée*, pas seulement
  affirmée. Un trou de 0,25 ha à l'intérieur de l'emprise CORINE ne peut pas être
  un objet réel. Le seuil est donc une propriété de la donnée et non un réglage,
  ce qu'exige le brief de tout seuil du paquet.
* Au-dessus de l'UMC, la fonction **refuse, signale et passe** : un trou de cette
  taille peut être une vraie lacune, et le combler serait une hypothèse.
* Une source à **couverture partielle** ne peut jamais justifier un comblement.
  BD Forêt v2 ne cartographie que les formations végétales : son silence signifie
  « pas de forêt », ce qui est une information. Son UMC de 0,5 ha n'est donc jamais
  utilisée, et la fonction le dit.
* Les cellules réparées **restent identifiables dans la donnée** : la couche
  `source` du registre les note `gap_filled` au lieu de prétendre qu'un jeu de
  données les a cartographiées.
* `.FEV_FUEL_MMU` enregistre par source l'UMC, la largeur minimale et la
  complétude de couverture, avec leurs références.

### `fev_exposure()` annonce ce que les vides vont coûter

* Un avertissement avant le calcul : combien de cellules vides, en combien d'amas
  distincts — un amas coûte une fenêtre, cent singletons en coûtent cent — et une
  borne supérieure du nombre de cellules qui reviendront vides.
* Le comportement ne change pas : propager est le bon défaut. `na_rm = TRUE`
  calcule des fenêtres tronquées au bord de l'emprise, ce qui sous-estime
  l'exposition d'environ 30 % (mesuré 0,32 contre 0,46) **et invisiblement**. Le
  trou blanc est plus honnête que ce chiffre-là.

### Les deux articles

* Les deux appellent `fev_fuel_fill_gaps()` après la fusion. Les disques blancs
  disparaissent, et laissent voir ce qu'ils masquaient : les dégradés circulaires
  doux sont la signature de l'anneau d'exposition autour des taches de combustible
  isolées — du contenu, pas des trous.
* Vérifié : l'écart avec la carte non réparée est **exactement nul** partout où
  celle-ci produisait une valeur. La réparation ne déplace aucun nombre existant,
  sinon ce serait une interpolation.
* Reste le cadre de bord de 500 m, qui est un effet de bord réel et documenté
  comme tel.

# firexpovulnR 0.13.0 (2026-08-17)

### L'AUC publié était `NA`, par débordement d'entier

* `sum()` d'un vecteur logique renvoie un **entier**, donc `n1 * n0` et
  `n1 * (n1 + 1)` dans `fev_auc()` débordaient l'entier 32 bits. Avec un demi-
  million de cellules non brûlées, cela arrive au-delà d'environ **4 400
  cellules brûlées — 275 ha à 25 m**, seuil que tout échantillon de feu réel
  franchit. R répond `NA` sans erreur.
* Conséquence concrète : `vignette("maures")` **publiait `NA` comme AUC**.
  Couchey, dont les feux totalisent environ 150 ha, passait juste sous le seuil,
  ce qui explique que le défaut soit resté invisible. Corrigé en calculant en
  double ; l'AUC réel des Maures est **0,53**.
* La méthode `print()` faisait `if (x$auc < 0.55)`, or `if (NA < 0.55)` est une
  erreur et non `FALSE` : afficher l'objet échouait donc précisément sur ceux
  qu'il fallait inspecter. Gardé, et un AUC non fini est désormais signalé comme
  une validation *ratée*, pas réussie.

### Article « Les Maures » — la carte de risque manquait

* `risque` était calculé puis utilisé seulement par `fev_validate()` : la **carte
  de risque composite n'était jamais tracée**. Elle l'est désormais, avec les
  onze périmètres d'incendie et les deux placettes LiDAR.
* La carte est cohérente — risque moyen 0,32 sur combustible brûlable contre 0,05
  en dehors, un facteur 6,5.
* Et la conclusion est plus dure qu'avant, parce qu'elle a maintenant un chiffre :
  AUC 0,53, ratios par classe 0,93 / 1,05 / 1,00. La carte ne distingue pas ce
  qui a brûlé de ce qui n'a pas brûlé. Ce n'est pas un échec de la météo, qui
  place le jour du feu premier sur 1 096 jours — c'est ce qu'il advient quand on
  module un danger juste par un combustible qui a treize ans de retard.
* Les disques blancs des deux cartes sont documentés : **18 cellules non
  cartographiées** aux Maures (42 à Couchey), esquilles de rastérisation sur les
  liserés entre polygones CORINE, amplifiées par la fenêtre focale de 500 m qui
  propage tout vide. 11,8 % de la carte des Maures, 17,5 % de celle de Couchey.

# firexpovulnR 0.12.1 (2026-08-17)

### Correctif : les tests réseau ne tournaient pas là où on croyait

* `skip_unless_network()` testait `nzchar()` sur `FIREXPOVULNR_TEST_NETWORK`,
  alors que le workflow y pose `"0"` pour dire « désactivé » — et `nzchar("0")`
  est vrai. **Tous les tests réseau tournaient donc dans le CI**, et n'étaient
  verts que tant que l'IGN et EFFIS l'étaient. Le premier délai DNS sur
  `data.geopf.fr` a fait rougir le check, ce que le brief interdit précisément.
  L'activation demande désormais une valeur explicite (`1`, `true`, `yes`),
  comme le faisait déjà la garde du test de charge.

# firexpovulnR 0.12.0 (2026-08-17)

### La météo n'est plus inventée — et sans aucun jeton

Les deux articles du site tournaient sur une série `rnorm()`, parce que le
produit historique CEMS demande un jeton Copernicus personnel que le package
s'interdit de manipuler. Pour un package dont la première exigence est la
traçabilité, livrer deux exemples travaillés reposant sur des nombres inventés
était le défaut le plus visible qui restait.

* **`fev_fetch_weather()`** lit l'archive Open-Meteo, qui re-sert ERA5 et
  ERA5-Land **sans aucune authentification**. Elle rend les quatre variables du
  système canadien — température, humidité relative, vent, pluie — au pas
  horaire, donc l'observation de **midi** que le système exige est disponible et
  non approximée par un maximum journalier. Grille à 0,1°, soit **2,5 fois plus
  fine que les 0,25° du CEMS**, et l'archive remonte à 1940.
* **`fev_fwi_from_weather()`** fait tourner le système sur la table point par
  point et assemble un `SpatRaster` daté. La voie tabulaire de `cffdrs` accumule
  les codes d'humidité **indépendamment par point** ; la voie raster ne sait
  porter que des codes de départ scalaires et lisserait la sécheresse en moyenne
  spatiale.
* Le vent est servi en **km/h**, l'unité que le système attend — contrairement au
  `FG` d'E-OBS, en m/s, qui est la manière classique de se tromper d'un facteur
  3,6 sur l'ISI.
* `fev_fetch_fwi()` reste la voie de référence quand on a un jeton. Le paquet
  avertit une fois par session qu'Open-Meteo est un **tiers** entre ECMWF et
  vous, et l'inscrit dans la provenance à chaque appel : les indices obtenus sont
  du `cffdrs` sur entrées Open-Meteo, comparables au produit CEMS, pas
  identiques.

### Deux pièges mesurés, et corrigés

* **La pluie est un cumul, pas une observation.** Le système canadien prend la
  pluie **cumulée sur les 24 heures** précédant midi. La première version lisait
  la pluie de l'heure de midi, ce qui jette 23 heures par jour. Conséquence
  mesurée sur trois ans dans les Maures : 10 % de jours de pluie au lieu de
  39 %, et un DC de 1 949 le 16 août 2021 au lieu de 619. Un jour supplémentaire
  est désormais récupéré en tête de chaque tranche pour remplir la fenêtre.
* **Et le FWI ne le montre pas.** Le facteur de durée sature :
  `1000 / (25 + 108.64 * exp(-0.023 * BUI))` vaut 38,3 à BUI 200 et 39,8 à BUI
  300, pour une asymptote de 40. Au-delà d'un BUI de 250 environ, un DC dérivé
  au double de sa valeur physique **ne fait pas paraître le FWI faux**. Les deux
  articles le documentent, et `fev_fwi_from_weather()` renvoie n'importe quel
  code du système pour qu'on puisse le vérifier directement.
* Corollaire : `reset = "annual"` existe pour redémarrer les codes chaque année,
  mais **n'est pas le défaut**. Avec la pluie correcte, les pluies d'hiver
  vidangent le DC d'elles-mêmes — 643 en intégration continue contre 619
  redémarré, soit 4 %. Ce qui ressemblait à un redémarrage saisonnier manquant
  était la pluie jetée.

### Robustesse de la voie réseau

* Le point demandé, et non la maille servie, est l'identité de station.
  Plusieurs points peuvent tomber dans la même maille de réanalyse sans partager
  la même série : Open-Meteo corrige la température de l'altitude du point
  demandé (trois points de la maille 43,40949 / 6,341829, à 274, 221 et 77 m, ont
  rendu 34,8, 34,8 et 35,4 °C le 16 août 2021). La maille servie et son altitude
  voyagent dans la provenance comme diagnostic.
* Les séries sont appariées aux points **par position** — rien dans la réponse ne
  les y ramène. Un écart de compte est donc une erreur, pas un cas à recycler
  silencieusement.
* HTTP 429 est réessayé avec attente croissante ; HTTP 400 ne l'est pas, parce
  qu'attendre ne répare pas une requête malformée. Une courte pause sépare les
  tranches annuelles — le service est gratuit.
* Une période qui dépasse aujourd'hui est **bornée** avec un message, au lieu
  d'échouer sur la dernière tranche après avoir téléchargé toutes les autres.
  Vérifié : l'archive sert 24 heures valides pour aujourd'hui même, en
  complétant les derniers jours par un modèle de prévision — ce ne sont donc pas
  des jours ERA5.
* La clé de cache porte un marqueur de schéma : la table stockée est un produit
  dérivé, donc un changement de sens doit invalider les entrées existantes alors
  que la requête qui les a produites n'a pas bougé.
* `fev_period_bounds()` accepte les années en caractères — `c("2021", "2021")`
  mourait dans `as.Date()`.
* Le cache sait stocker une table, pas seulement un `sf` ou un `SpatRaster`.
* L'avertissement `NaNs produced` de `cffdrs` — un `ifelse()` qui évalue ses deux
  branches — est étouffé nommément, et la sortie est vérifiée à la place : un NaN
  réel est signalé au lieu d'être caché derrière du bruit.

### Les deux articles, refaits sur météo réelle

* `vignette("couchey")` : le **29 juillet 2026**, jour où la commune a brûlé,
  sort **2e sur 960 jours** en FWI médian. 34–36 °C et 20 % d'humidité relative
  en Côte-d'Or.
* `vignette("maures")` : le **16 août 2021**, jour du feu de 6 510 ha du
  Cannet-des-Maures, sort **1er sur 1 096 jours**. 35 °C, 22 % d'humidité,
  24 km/h et pas une goutte sur les 24 heures précédentes.
* Aucune donnée de feu n'entre dans le calcul du FWI. Ce n'est pas une validation
  du modèle de risque — un feu ne fait pas un échantillon, et un jour de canicule
  est aussi un jour de plus de départs — mais c'est un signal qui tombe au bon
  endroit sur les deux seuls événements que ces territoires offrent, ce qu'une
  série `rnorm()` ne pouvait par construction jamais montrer.
* Trois ans de référence et non trente : la normale de l'OMM est de trente ans,
  et c'est une limite de ce qu'il est raisonnable d'embarquer dans
  `inst/extdata`, pas du paquet. Un seul appel l'élargit.
* `vignette("firexpovulnR")` et le README présentent désormais les **deux
  voies** — sans jeton via Open-Meteo, avec jeton via le CEMS — et le caveat du
  tiers.
* Les tables météo voyagent avec le package
  (`inst/extdata/{couchey,maures}_weather.csv.gz`, 134 et 187 Ko), construites
  par `data-raw/build_weather_extracts.R`.

# firexpovulnR 0.11.0 (2026-08-17)

### Article « Les Maures » — le LiDAR voit ce que la classe ignore

* `vignette("maures")` fait tourner la chaîne là où le package a été conçu pour
  travailler, sur données réelles : 2 333 formations BD Forêt, 201 polygones
  CORINE, **11 incendies EFFIS dont celui du Cannet-des-Maures du 16 août 2021,
  6 510 ha**, et surtout **505 dalles LiDAR HD couvrant 100 % de l'emprise** —
  contre zéro à Couchey.
* Le combustible est enfin méditerranéen : `LA4`, la lande, est la classe
  dominante, devant pin maritime et chêne vert. C'est ici que les poids par
  défaut et les rayons d'exposition sont le plus près de leur base de preuves.
* **La démonstration centrale.** Deux carrés de 500 m, l'un dans le périmètre
  brûlé de 2021, l'autre 2 km plus loin, choisis pour que la BD Forêt leur donne
  **la même classe** (`FF1-00-00`, même type de combustible, même poids 0,95,
  même valeur dans le masque brûlable). Le LiDAR mesure entre eux :

  | Métrique | Rapport témoin / brûlé |
  |---|---|
  | `Height` hauteur de canopée | **1,0** |
  | `TFL` charge totale | 3,8 |
  | `MFL` charge de sous-étage | 4,5 |
  | `H_Bush` sommet de la strate arbustive | 5,1 |
  | `FL_1_3` charge entre 1 et 3 m | **6,7** |

  La hauteur de canopée est identique — donc un CHM issu d'ortho ou de satellite,
  la solution qu'on propose souvent pour rafraîchir un inventaire, aurait conclu
  que ces deux endroits se valent. Tout l'écart est dans la strate basse, celle
  où un feu de surface se propage.
* Trois raisons cumulées pour lesquelles la couche catégorielle ne pouvait pas
  le savoir, et aucune n'est un défaut de la BD Forêt : son millésime est 2008,
  le feu est de 2021 ; sa nomenclature ne contient pas le sous-étage, même à
  jour ; et la hauteur de canopée n'aurait pas suffi.

### Données livrées

* `inst/extdata/maures.gpkg` (3,6 Mo, sept couches) et deux GeoTIFF de
  métriques LiDAR réelles à 25 m, construits par
  `data-raw/build_maures_extract.R`. Les nuages de points, 120 et 205 Mo, ne
  sont pas embarqués — les métriques qu'ils produisent pèsent quelques dizaines
  de kilooctets, ce qui est tout l'argument pour les dériver une fois dans le
  script.
* Traitement par carrés de 500 m et non par dalle entière : `fPCpretreatment`
  sur 24 millions de points a épuisé 31 Go de RAM. Un quart de dalle à densité
  intacte est la réduction honnête — une surface plus petite, pas un nuage
  éclairci.

### Corrections

* La taille des dalles LiDAR HD annoncée dans la documentation était fausse :
  « de l'ordre du gigaoctet » alors que la mesure donne **120 à 260 Mo**.
  Corrigé partout, y compris dans le refus de `fev_fetch_lidarhd()` au-delà de
  `max_tiles`, qui estimait donc un téléchargement quatre fois trop lourd.
* Densités réelles constatées : 24 à 27 impulsions/m², largement au-dessus des
  10 spécifiées. Le rapport points/impulsions vaut 1,06 dans le brûlé contre
  1,25 dans le témoin — la végétation intercepte à plusieurs niveaux, le sol nu
  renvoie une fois. C'est un signal de végétation avant tout traitement.

# firexpovulnR 0.10.0 (2026-08-17)

Phase 8 — LiDAR HD. Le registre continu, en place et testé depuis la phase 4,
reçoit enfin un producteur. Rien du module combustible n'a eu besoin d'être
réécrit, ce qui était l'objet de la contrainte posée avant la phase 4.

864 tests hors ligne, aucun échec, aucun avertissement. `R CMD check` en statut
OK. **Aucun test de cette phase ne touche le réseau ni une dalle réelle** : un
nuage synthétique construit avec `lidR` traverse les vraies fonctions de
`lidarforfuel`.

### Ce que le LiDAR apporte et que rien d'autre ici ne peut

Le sous-étage. Ni CORINE ni la BD Forêt ne le décrivent — c'est la faiblesse
méthodologique n° 1 que les deux vignettes énoncent. Un profil vertical de
densité apparente le décrit, et la hauteur de base de houppier et le *fuel
strata gap* qui s'en déduisent sont les deux nombres dont dépend le passage du
feu de surface au houppier.

### Acquisition

* `fev_lidarhd_available()` interroge l'index de dalles de l'IGN **avant tout
  téléchargement**, comme le brief l'exige. Le WFS sert une entité par dalle de
  1 km avec son `url`, son `timestamp` et son `id_chantier` — le millésime par
  bloc d'acquisition.
* La couverture est réellement partielle, et c'est constaté : au 2026-08-17,
  210 blocs et 505 294 dalles en France, **1 016 sur les Maures et zéro sur
  Couchey**. Une zone non survolée rend un index vide, pas une erreur.
* Le message d'absence nomme le piège d'axes, parce qu'ici l'explication
  innocente est la plus probable : un BBOX latitude d'abord rend aussi zéro
  entité avec un HTTP 200.
* `fev_fetch_lidarhd()` reprend une exécution interrompue en sautant les dalles
  déjà présentes, refuse un travail plus gros que `max_tiles`, et ne
  parallélise rien — marteler un service public est la façon d'en perdre
  l'accès pour tout le monde. Les dalles étant en **COPC**, lisible par plage
  HTTP, la doc renvoie vers la lecture directe quand quelques hectares
  suffisent.

### Métriques de combustible

* `fev_fuel_lidar()` enveloppe `lidarforfuel` (équipe Olivier Martin, INRAE),
  évalué par ses auteurs sur des placettes de terrain en France, en Espagne et
  au Portugal — ce qui justifie de l'employer ici plutôt qu'un outil
  nord-américain.
* **Le README amont se trompe sur la structure de sortie.** Il annonce 173
  bandes dont 23 métriques ; le code en produit **175 dont 25**. Lire le profil
  à partir de la bande 24 sur cette base prend `Cover_4` et `Cover_6` pour de la
  densité apparente et décale tout de deux bandes. Rien ici n'indexe par
  position : la fonction vérifie les noms obtenus contre ceux attendus et
  **refuse** en cas d'écart.
* **La valeur nulle est `-1`, pas `NA`.** Laissée telle quelle elle donne des
  hauteurs de base de houppier et des charges de combustible négatives, qui
  passent tout contrôle de plausibilité naïf. Convertie à la lecture.
* `fev_lidar_density()` mesure des **impulsions**, pas des points, parce que la
  spécification LiDAR HD est écrite en impulsions : au moins 10/m², et 5
  au-dessus de 3200 m. L'avertissement dit le **sens** du biais : quand la
  densité baisse, la strate de sous-étage disparaît la première, donc la charge
  est sous-estimée tandis que la hauteur de base de houppier et l'écart entre
  strates sont surestimés. Une dalle maigre décrit un paysage plus sûr qu'il
  n'est.
* Le repli silencieux de `lidarforfuel` sur une hauteur de vol nominale de
  1 400 m, quand la trajectoire est irrécupérable, est intercepté et inscrit
  dans la provenance. Il change la correction d'angle de balayage.
* `lma = 140` g/m² et `wd = 591` kg/m³ sont les défauts amont. Ce sont des
  valeurs d'espèce, elles n'ont pas été retrouvées à une source primaire, et
  elles mettent les charges à l'échelle directement. Enregistrées avec
  `lma_wd_sourced = FALSE`.

### Greffe sur le registre catégoriel

* `fev_fuel_attach()` verse le registre continu sur une source catégorielle.
  Ce n'est pas `fev_fuel_merge()` : celle-ci arbitre entre sources qui se
  disputent le même pixel, le LiDAR ne dispute rien. Il apporte des grandeurs
  que ni CORINE ni la BD Forêt ne portent, sur le même sol.
* La part de cellules catégorielles effectivement couverte est rapportée, parce
  que le programme est en cours et que les deux registres décrivent des
  sous-ensembles différents de la carte.

### Repli documenté

Quand le LiDAR manque — la majorité de la France en 2026, et Couchey — les
cartes satellitaires pan-européennes de CBH et CBD à ~100 m pour 2020
(*Geo-spatial Information Science* 28(4), serveur FIRE-RES). Leurs corrélations
sont **faibles** et le rapport le dit : r = 0,445 pour la CBH et **0,330** pour
la CBD, soit environ 11 % de variance expliquée.

### specs/phase8-rapport-lidar.md

Le rapport de vérification, sur le modèle de celui de la phase 2 : ce qui a été
constaté, comment, et ce qui reste incertain.

# firexpovulnR 0.9.3 (2026-08-17)

* Vignette Couchey : une section explique les grands rectangles visibles sur la
  carte de risque. Ce ne sont pas des dalles de calcul mal raccordées — les
  trois couches sont sur exactement la même grille de 25 m, et `fev_risk()`
  aurait refusé sinon. Ce sont les **mailles de la grille météo**, 3,2 × 3,9 km,
  descendues à 25 m au plus proche voisin : un rapport de 126 pour 1. Le
  bilinéaire aurait lissé l'escalier en dessinant une variation que la donnée
  n'a jamais mesurée.
* La section ajoute la comparaison qui remet l'échelle en place : avec le vrai
  produit CEMS à 0,25°, les mailles font environ 19 × 28 km et **toute l'emprise
  de l'étude tiendrait dans une seule**. La carte ne serait alors plus pavée du
  tout, ce qui est le même aveu sous une forme moins visible.
* Un graphique côte à côte montre le danger météo et la disponibilité en
  combustible à la même résolution, pour que la différence de contenu soit
  lisible.

# firexpovulnR 0.9.2 (2026-08-17)

* Vignette Couchey : les périmètres d'incendie sont tracés en **rouge** et non
  plus en noir, sur les trois cartes. Le noir se confondait avec les traits de
  contour du raster ; le rouge se lit sur la palette continue comme sur le
  masque binaire, et c'est la convention à laquelle un lecteur s'attend pour
  une surface brûlée.

# firexpovulnR 0.9.1 (2026-08-16)

### L'incendie du 29 juillet 2026 à Couchey

* L'extrait Couchey est reconstruit sur la période 2016-2026 et contient
  désormais **trois** incendies, dont celui qui a brûlé la commune elle-même :
  **124 ha, déclaré le 29 juillet 2026 à 13 h 42, éteint le lendemain à 2 h 15**.
  `PERCNA2K = 100` — la totalité en site Natura 2000 — et l'occupation du sol
  brûlée est à 60 % de feuillus et 17 % de forêt mixte, c'est-à-dire le
  combustible que les poids par défaut du package classent en bas de leur
  échelle.
* L'emprise passe de 160 à 292 km² pour couvrir les trois feux, ce qui fait
  entrer un second département : le millésime y compte maintenant **trois**
  campagnes candidates, 2007, 2010 et 2014, à un tiers de surface chacune.
* Le contrôle de biais temporel n'a jamais été aussi net : **100 % de la
  surface brûlée postdate le millésime de plus de cinq ans**, et l'incendie de
  Couchey de dix-neuf ans. L'article conclut donc que la carte ne peut pas être
  validée avec cette donnée, plutôt que de publier un AUC.
* Les attributs EFFIS utiles sont conservés dans l'extrait — `COMMUNE`,
  `CLASS`, `PERCNA2K` et la ventilation par occupation du sol — pour que
  l'article n'affirme rien qu'il ne puisse sourcer.

# firexpovulnR 0.9.0 (2026-08-16)

Un exemple sur données réelles, et il ne se passe pas bien — ce qui est le
sujet.

### Article « Couchey »

* `vignette("couchey")` déroule la chaîne complète sur **Couchey**
  (Côte-d'Or), territoire de référence du projet voisin `nemetonshiny`, à
  partir de données réelles : BD Forêt v2 (568 formations), CORINE 2018
  (99 polygones) et une surface brûlée EFFIS. Seule la météo est synthétique,
  faute de jeton Copernicus, et l'article le dit.
* Le terrain est l'inverse de celui pour lequel le package a été conçu :
  chênaie, hêtraie et charmaie de plaine, avec des vignes là où un exemple
  varois aurait de la garrigue. C'est délibéré — un exemple complaisant
  n'apprend rien sur les limites des valeurs par défaut.
* **Le millésime y est ambigu à 50/50** : deux campagnes BD ORTHO, 2010 et
  2014, à 49,9 % et 50,1 % de la surface. Cas d'école de ce que
  `fev_bdforet_millesime()` refuse de trancher.
* **La validation échoue, et c'est le résultat.** L'endpoint public EFFIS sert
  un seul feu sur 160 km² et neuf ans — 26 ha, 31 juillet 2020 — qui postdate
  le millésime prudent de dix ans. Le contrôle de biais temporel rapporte
  100 % de surface brûlée au-delà du seuil, et `max_lag_years = 5` vide
  l'échantillon. La conclusion honnête n'est pas un AUC mais « cette carte ne
  peut pas être validée avec cette donnée », et l'article la formule ainsi.
* L'AUC est montré quand même, avec la mention explicite qu'il n'a pas de
  valeur probante ici — par omission il aurait été plus flatteur.

### Données livrées

* `inst/extdata/couchey.gpkg` (1,3 Mo, six couches) est construit par
  `data-raw/build_couchey_extract.R`, qui contacte les services réels. L'article
  lit le disque : une documentation rouge ne doit pas être un bulletin de
  disponibilité de l'IGN.
* Les géométries sont simplifiées à 10 m, bien sous la grille de travail de
  25 m, ce qui conserve 99,89 % de la surface et ramène le fichier de 5,0 à
  1,3 Mo. Décision d'empaquetage, pas d'analyse.

# firexpovulnR 0.8.0 (2026-08-16)

Le dernier blocage du rapport de faisabilité tombe. Le millésime de la
BD Forêt v2 est récupérable, et pas par un contournement.

759 tests hors ligne, aucun échec. `R CMD check` sans erreur, avertissement ni
note. Tests d'intégration passés contre le service IGN réel.

### Le millésime BD Forêt v2, retrouvé

* **L'IGN définit le millésime comme la date de la prise de vue.** *Descriptif
  de contenu BD Forêt® Version 2*, septembre 2014, §2.3 : « La date de
  validation est celle de la prise de vues de la BD ORTHO® servant à la
  production des données. » Ce n'est donc pas un proxy : la base décrit le
  peuplement tel que le photo-interprète l'a vu sur l'image infrarouge, et la
  date du vol est la date de l'état de paysage enregistré.
* `fev_bdforet_millesime()` va chercher ces dates dans le graphe de mosaïquage
  de la BD ORTHO, dont l'IGN archive des tranches par période. Le champ
  `date_vol` y est une vraie date, par polygone, avec le département et la
  campagne.
* `fev_fetch_bdforet(millesime = "auto")` enchaîne le tout.
* **La réserve est réelle et elle est portée par le code.** Un département est
  revolé tous les cinq ans environ, donc la fenêtre 2007-2018 en contient
  généralement deux — le Var a 2008 et 2014 — et l'IGN ne publie pas laquelle a
  alimenté quelle production. La fonction rend les candidats avec la part de
  surface de chacun et **refuse de trancher**. `strategy = "oldest"` donne la
  lecture conservatrice : supposer la campagne la plus ancienne maximise
  l'écart que `fev_validate()` rapporte, ce qui penche du côté de signaler le
  biais plutôt que de le masquer.
* Le schéma WFS de la BD Forêt v2 a été revérifié : aucun champ de date, ce qui
  confirme le constat de phase 2 et fait du graphe de mosaïquage la seule voie
  qui ne relève pas de la conjecture.
* `specs/phase2-rapport-faisabilite.md` passe le point 2 bis de « bloqué » à
  « résolu », en addendum daté — le constat d'origine reste lisible.

# firexpovulnR 0.7.0 (2026-08-16)

Dernière phase du brief. La chaîne cible s'exécute désormais de bout en bout,
et la vignette la déroule sans réseau.

729 tests hors ligne, aucun échec. `R CMD check` sans erreur, avertissement ni
note.

### Combinaison et risque

* `fev_risk()` livre les trois méthodes du brief, et elles ne répondent pas à
  la même question. `"effis_mean"` normalise puis fait la moyenne à poids
  égaux. `"pareto"` rend le **front de Pareto** — un ensemble, pas un score :
  les cellules qu'on ne peut améliorer sur une dimension sans dégrader l'autre.
  `"weighted"` exige ses poids et les inscrit, faute de défaut défendable.
* Les deux premières viennent du workflow CLIMAAX, dont le carnet a été lu le
  2026-08-16 plutôt que paraphrasé : `danger_index=(clim_norm+burn_norm)/2` et
  `paretoset(..., sense=[max,...])` sont recopiés de son propre code.
* La normalisation min-max par défaut **réétire** une couche déjà mise à
  l'échelle : c'est ce que fait CLIMAAX, la doc le dit, et `normalise = "none"`
  existe pour l'éviter.
* Le balayage de dominance est quadratique dans le nombre de combinaisons
  distinctes. Il travaille donc sur les tuples arrondis et **refuse** au-delà
  d'un seuil, plutôt que de tourner une après-midi.

### Validation, et le biais temporel

* `fev_validate()` rend une AUC, une courbe ROC et la répartition
  observé/attendu par classe de risque — cette dernière dans la forme de
  `fireexposuR::fire_exp_validate()`, dont les bornes par défaut sont reprises.
* **Le contrôle de biais temporel tourne avant toute statistique de skill.**
  Chaque feu est comparé au millésime du combustible, lu dans la provenance, et
  la fonction avertit avec un chiffre : « 28,6 % de la surface brûlée postdate
  le millésime de plus de 5 ans ». `max_lag_years` filtre.
* Le millésime n'a pas à être redonné quand la couche vient de la chaîne : il
  voyage depuis `fev_fuel_source()`. Quand il est inconnu, le contrôle ne peut
  pas tourner — la fonction refuse si on demandait un filtrage, et avertit
  bruyamment sinon.
* Aucun intervalle de confiance n'est rendu sur l'AUC, et la doc dit pourquoi :
  les cellules ne sont pas des observations indépendantes, un feu est contigu,
  et un intervalle bâti sur le nombre de cellules serait très trop étroit.

### Coût de l'exposition

* Découverte reprise du projet nemeton, qui a rencontré le problème en
  production avec la même métrique : la fenêtre focale est exprimée en mètres
  mais matérialisée en cellules, donc le coût varie comme l'inverse de la
  puissance quatrième de la maille. `fev_exposure()` estime ce coût **avant**
  de commencer et propose une taille de maille, plutôt que de sembler bloqué.
* `filename` et `wopt` sont passés à `terra`, ce qui rend un traitement
  départemental possible par blocs.
* **Test de charge documenté sur une emprise réaliste**, comme le demande le
  brief : 6 006 km² à 25 m avec un rayon de 500 m — la taille du Var — en 61 à
  83 secondes, 155 Mo de pointe, débit d'environ 170 millions d'opérations
  pondérées par seconde. Le test vit dans la suite, désactivé sauf
  `FIREXPOVULNR_TEST_LOAD=1`.

### Vignette

* `vignette("firexpovulnR")` déroule la chaîne complète sur un paysage
  synthétique, sans réseau, avec les appels réels montrés à leur place dans des
  blocs non exécutés. Elle se termine par ce que la chaîne ne sait pas, par
  ordre d'importance décroissante — le sous-étage d'abord.

# firexpovulnR 0.6.0 (2026-08-16)

Première version numérotée. Elle couvre les phases 0 à 6 du brief de
développement : l'objet et sa provenance, l'acquisition, le combustible, le
danger, l'exposition et la vulnérabilité. La phase 7 — combinaison en risque,
validation contre les surfaces brûlées, vignette de bout en bout — reste à
faire, et le workflow cible du brief n'est donc pas encore exécutable
intégralement.

640 tests hors ligne, aucun échec. `R CMD check` sans erreur, avertissement ni
note.

### Objet, provenance et contrôles

* `fev_stack()` transporte les couches d'une analyse sans les forcer sur une
  grille commune. Danger kilométrique et exposition décamétrique gardent leur
  grille native jusqu'à un appel explicite à `fev_align()`.
* `fev_provenance()` exporte en YAML les sources, millésimes, période de
  calibration et l'intégralité des paramètres réellement utilisés — y compris
  les défauts que l'appelant n'a jamais tapés.
* `fev_check_crs()` refuse une entrée en latitude/longitude et signale un écart
  entre `crs_work` et le CRS natif de la source primaire.

### Acquisition et cache

* `fev_fetch_fwi()`, `fev_fetch_bdforet()`, `fev_fetch_corine()` et
  `fev_fetch_burnt()`. Tout endpoint, nom de couche et seuil numérique est
  centralisé dans `R/constants.R` avec sa date et sa voie de vérification ;
  `specs/phase2-rapport-faisabilite.md` porte les preuves.
* Le cache disque est indexé par empreinte de la requête normalisée : deux
  appels de paramètres différents ne peuvent pas entrer en collision. Chaque
  entrée est deux fichiers, données et provenance ; une donnée sans provenance
  est traitée comme un défaut de cache.
* **BD Forêt v2 ne sert pas son millésime** et aucune table par département n'a
  été trouvée. Il est enregistré `NA` et jamais inféré.
* **EFFIS couvre 2016 et après, pas 2006.** `fev_fetch_burnt()` compare la
  période demandée à celle réellement servie et avertit avec des chiffres.

### Combustible

* `fev_fuel_source()` porte **deux registres**, catégoriel et continu, et ne
  suppose jamais que l'information est une classe. Seul le premier a des
  producteurs aujourd'hui ; le second attend le LiDAR HD de la phase 8. Chaque
  fonction aval déclare le registre qu'elle consomme.
* `fev_fuel_merge()` est une fusion strictement intra-registre, avec une couche
  de provenance par pixel. Elle est idempotente : re-fusionner ne relabellise
  pas les pixels déjà attribués.
* Les tables de correspondance vivent dans `data-raw/`, sont justifiées ligne
  par ligne et sont livrées en CSV surchargeables : 32 postes TFV, 44 classes
  CORINE de niveau 3. 4 lignes ambiguës sur 32 côté BD Forêt, 17 sur 44 côté
  CORINE, chacune disant où est le doute.
* Le millésime BD Forêt est **obligatoire** dans `fev_fuel_source()`. Sans lui
  le contrôle de biais temporel de `fev_validate()` ne pourra pas tourner ;
  `millesime = NA` explicite est accepté et averti.
* `fev_fuel_weights()` livre dix-neuf poids de disponibilité qui ne viennent
  d'aucune publication. Ils avertissent à chaque appel et partent dans la
  provenance avec `weights_sourced = FALSE`.

### Danger météorologique

* `fev_fwi_percentile()` est le cœur méthodologique : rang percentile contre
  une climatologie de référence locale, par pixel ou par région. Une couche
  sans dates est refusée — une climatologie sur une période inconnue n'en est
  pas une.
* `fev_fwi_thresholds()` réimplémente `get_fire_danger_levels()` de caliver,
  archivé du CRAN en octobre 2021 : médiane des 98es percentiles annuels puis
  inversion par la relation d'intensité canadienne.
* `fev_fwi_classes()` livre **deux jeux de seuils publiés qui diffèrent d'un
  facteur trois** — EFFIS opérationnels, et ceux dérivés d'une réanalyse par
  Vitolo et al. 2018. Un FWI de 40 est « Very High » chez l'un et « Extreme »
  chez l'autre. `fev_danger_class()` inscrit dans la provenance lequel a
  produit la carte.
* `fev_fwi_calc()` exige la latitude au lieu de laisser `cffdrs` substituer
  55°N. L'ajustement de longueur du jour est par bandes, donc la substitution
  est inoffensive en France métropolitaine et fausse ailleurs — un défaut juste
  là où l'on écrit le script et faux là où on le recopie.

### Exposition et vulnérabilité

* `fev_exposure()` reproduit la géométrie de `fireexposuR::fire_exp()` : anneau
  focal d'une cellule au rayon de transmission, cellule évaluée exclue. Un test
  croisé compare les deux fenêtres cellule par cellule et les sorties à `1e-4`,
  tolérance qui est exactement l'arrondi de `fire_exp()`.
* `fev_directional()` suit Beverly et Forbes 2023. Les relèvements sont des
  relèvements de boussole, et un test le fige : l'erreur produit une carte
  plausible tournée de 90 degrés.
* `fev_vuln_layer()` et `fev_vuln_stack()`. Aucune source d'enjeux n'est
  imposée ; les poids d'agrégation sont un jugement de valeur, la fonction le
  dit et l'inscrit.
* **Une réserve du brief est levée.** Khan et al. 2025 ont validé la métrique
  d'exposition sur le Portugal continental : environ 80 % des surfaces brûlées
  en exposition ≥ 80 %. La métrique transpose donc à un contexte ibérique. Le
  rayon, lui, n'est toujours pas calibré sur chêne vert, garrigue ou maquis.

### Alignement des échelles

* `fev_align()` est la seule fonction autorisée à changer une grille ; toutes
  les autres refusent des entrées de grilles différentes et y renvoient. Le
  rapport d'échelle part dans un avertissement et dans la provenance.
* Le rééchantillonnage vers une grille plus fine se fait au plus proche voisin,
  pas en bilinéaire : interpoler entre deux centres de mailles de 25 km dessine
  un gradient que la réanalyse n'a jamais résolu, et c'est très convaincant.

### Infrastructure

* Intégration continue : cohérence `DESCRIPTION` / `NEWS.md` / `CITATION.cff`,
  `R CMD check`, couverture via covr et Codecov, site pkgdown, tag et release
  automatiques pilotés par la version de `DESCRIPTION`.
* Aucun test unitaire ne touche le réseau. Les tests d'intégration contre les
  API réelles vivent dans un fichier séparé, activés par
  `FIREXPOVULNR_TEST_NETWORK=1`.
