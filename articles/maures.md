# Les Maures : le LiDAR voit le sous-étage que la BD Forêt ignore

``` r

library(firexpovulnR)
library(terra)
library(sf)
```

L’article
[Couchey](https://pobsteta.github.io/firexpovulnR/articles/couchey.md)
fait tourner la chaîne là où le package est le moins à son aise :
chênaie bourguignonne, vignes, **aucune couverture LiDAR**, et une
validation qui échoue honnêtement. Celui-ci la fait tourner là où il a
été conçu pour travailler — le **massif des Maures** — et montre les
deux choses que Couchey ne pouvait pas montrer.

D’abord un vrai échantillon de feux, dont celui du **Cannet-des-Maures
du 16 août 2021, 6 510 hectares**. Ensuite, et c’est l’objet de la page,
du LiDAR HD sur toute l’emprise, ce qui rend enfin mesurable le
**sous-étage** — l’angle mort que les deux vignettes désignent comme la
faiblesse méthodologique numéro un de tout l’édifice.

## Les données

``` r

gpkg <- system.file("extdata", "maures.gpkg", package = "firexpovulnR")
st_layers(gpkg)$name
#> [1] "study_area"           "bdforet_v2"           "clc_2018"            
#> [4] "burnt_areas"          "lidar_coverage"       "lidar_squares"       
#> [7] "millesime_candidates"

study   <- st_read(gpkg, "study_area", quiet = TRUE)
bdforet <- st_read(gpkg, "bdforet_v2", quiet = TRUE)
corine  <- st_read(gpkg, "clc_2018", quiet = TRUE)
feux    <- st_read(gpkg, "burnt_areas", quiet = TRUE)
lidar_cov <- st_read(gpkg, "lidar_coverage", quiet = TRUE)
carres  <- st_read(gpkg, "lidar_squares", quiet = TRUE)
```

``` r

c(km2 = round(as.numeric(st_area(study)) / 1e6),
  bdforet = nrow(bdforet), corine = nrow(corine),
  feux = nrow(feux), ha_brules = round(sum(feux$area_ha)))
#>       km2   bdforet    corine      feux ha_brules 
#>       423      2333       201        11      6927
```

Constitué le 2026-08-17 par `data-raw/build_maures_extract.R`. L’emprise
est cadrée sur le feu de 2021 tamponné de 2 km, ce qui donne un
échantillon de feux plutôt qu’un rectangle arbitraire.

### Le combustible méditerranéen, enfin

``` r

sort(table(bdforet$code_tfv), decreasing = TRUE)[1:6]
#> 
#>       LA4       FO1      FF31 FF2-51-51      FF32 FF1G06-06 
#>       359       349       275       210       207       170
```

`LA4` en tête — la **lande**, c’est-à-dire maquis et garrigue. Puis
forêt ouverte de feuillus, mélanges, **pin maritime** (`FF2-51-51`),
**chêne vert** (`FF1G06-06`). À Couchey la classe dominante était le
mélange de feuillus de plaine et il n’y avait pas une seule lande.

C’est ici que les valeurs par défaut du package sont le plus près de
leur base de preuves : le maquis reçoit le poids 1,00, le conifère fermé
0,95, et les rayons d’exposition ont au moins une validation
méditerranéenne derrière eux.

``` r

mil <- st_drop_geometry(st_read(gpkg, "millesime_candidates", quiet = TRUE))
mil[, c("dep", "year", "pct_area")]
#>   dep year pct_area
#> 1  83 2008     48.4
#> 2  83 2014     51.6

primaire <- fev_fuel_source(bdforet, type = "bdforet_v2", res = 25,
                            aoi = study, millesime = min(mil$year))
auxiliaire <- fev_fuel_source(corine, type = "clc_2018", res = 25,
                              aoi = study, millesime = 2018)
fuel <- fev_fuel_merge(primaire, auxiliaire)
#> "clc_2018" filled 128472 cells (19%) that
#> "bdforet_v2" left unmapped.
```

Deux campagnes BD ORTHO, **2008 et 2014**. Retenez ce chiffre : le grand
feu est de 2021.

``` r

brulable <- fev_fuel_binary(fuel)
round(100 * terra::global(fev_data(brulable), "mean", na.rm = TRUE)[[1]], 1)
#> [1] 85.1
```

``` r

par(mar = c(2, 2, 2, 4))
plot(fev_data(brulable), main = "Combustible brûlable — massif des Maures")
plot(st_geometry(feux), add = TRUE, border = "red", lwd = 2)
plot(st_geometry(carres), add = TRUE, border = "blue", lwd = 3)
```

![](maures_files/figure-html/plot-fuel-1.png)

Traits rouges, les onze incendies. Carrés bleus, les deux emplacements
dont il sera question en section 4.

## Exposition

``` r

expo <- fev_exposure(brulable, radius = 500, type = "ember", quiet = TRUE)
terra::global(fev_data(expo), c("mean", "max"), na.rm = TRUE)
#>               mean max
#> exposure 0.8719655   1
```

``` r

par(mar = c(2, 2, 2, 4))
plot(fev_data(expo), main = "Exposition, rayon 500 m")
plot(st_geometry(feux), add = TRUE, border = "red", lwd = 2)
```

![](maures_files/figure-html/plot-expo-1.png)

## LiDAR HD : couvert, contrairement à Couchey

``` r

st_drop_geometry(lidar_cov)
#>   n_tiles chantiers  timestamp
#> 1     505  106, 117 2025-05-01
round(100 * as.numeric(st_area(lidar_cov)) / as.numeric(st_area(study)), 1)
#> [1] 119.5
```

**505 dalles, deux blocs d’acquisition, survol de 2025.** Le contrôle de
disponibilité que le brief impose avant tout téléchargement répond ici
oui, là où il répondait non sur Couchey :

``` r

fev_lidarhd_available(study)
#> 505 LiDAR HD points tiles found.
#> i They cover 100% of the area.
#> i 2 acquisition blocks: "106", "117".
#> i 1 vintage: "2025".
```

Les dalles font 1 km de côté, en COPC — lisible par plage HTTP, donc
sans téléchargement quand quelques hectares suffisent. Mesuré : entre
120 et 260 Mo la dalle, pas le gigaoctet qu’une première rédaction
annonçait.

## La démonstration : deux endroits que la BD Forêt ne distingue pas

C’est le cœur de cette page. Deux carrés de 500 m, l’un **dans** le
périmètre brûlé de 2021, l’autre 2 km plus loin **hors** du feu, choisis
pour que la BD Forêt leur donne **la même classe**.

``` r

st_drop_geometry(carres)[, c("role", "tfv_dominant", "pulses_per_m2",
                             "points_per_m2")]
#>      role tfv_dominant pulses_per_m2 points_per_m2
#> 1   burnt    FF1-00-00         24.28         25.77
#> 2 control    FF1-00-00         25.59         31.87
```

Même classe dominante — `FF1-00-00`, forêt fermée à mélange de feuillus.
Donc, pour tout ce que la couche catégorielle sait exprimer, ces deux
endroits sont identiques :

``` r

lk <- fev_fuel_lookup("bdforet_v2")
w <- fev_fuel_weights(quiet = TRUE)
ligne <- lk[lk$code == "FF1-00-00", c("code", "label", "fuel_type", "burnable")]
ligne
#>        code                              label        fuel_type burnable
#> 9 FF1-00-00 Forêt fermée à mélange de feuillus broadleaf_closed     TRUE
w[[ligne$fuel_type]]
#> [1] 0.6
```

Même code, même type de combustible, même poids de disponibilité, même
valeur dans le masque brûlable. Un pare-feu placé sur cette carte les
traiterait de la même façon.

Voici ce que le LiDAR mesure :

``` r

brule <- rast(system.file("extdata", "lidar_burnt.tif",
                          package = "firexpovulnR"))
temoin <- rast(system.file("extdata", "lidar_control.tif",
                           package = "firexpovulnR"))

vb <- terra::global(brule, "mean", na.rm = TRUE)[, 1]
vt <- terra::global(temoin, "mean", na.rm = TRUE)[, 1]
data.frame(
  metrique = names(brule),
  brule = round(vb, 3),
  temoin = round(vt, 3),
  rapport = round(ifelse(vb > 0, vt / vb, NA), 1)
)
#>    metrique brule temoin rapport
#> 1    Height 9.723 10.142     1.0
#> 2       CBH 0.849  1.575     1.9
#> 3       FSG 0.766  1.102     1.4
#> 4    H_Bush 0.863  4.440     5.1
#> 5   CBD_max 0.034  0.155     4.5
#> 6       CFL 0.076  0.283     3.7
#> 7       TFL 0.081  0.312     3.8
#> 8       MFL 0.051  0.227     4.5
#> 9    FL_0_1 0.032  0.147     4.5
#> 10   FL_1_3 0.015  0.103     6.7
#> 11     GSFL 0.011  0.023     2.1
#> 12    Cover 0.102  0.297     2.9
#> 13  PAI_tot 0.424  1.640     3.9
```

Lisez la colonne `rapport` de haut en bas. **`Height` vaut 1,0** : les
deux endroits ont la même hauteur de canopée, 9,7 et 10,1 m. Un modèle
numérique de hauteur, un CHM, dirait donc lui aussi qu’ils se
ressemblent.

Puis tout le reste s’écarte, et ce qui s’écarte le plus est ce qui est
bas :

| Métrique  | Ce que c’est                  | Rapport |
|-----------|-------------------------------|---------|
| `FL_1_3`  | charge entre 1 et 3 m         | **6,7** |
| `H_Bush`  | sommet de la strate arbustive | **5,1** |
| `MFL`     | charge de sous-étage          | **4,5** |
| `FL_0_1`  | charge sous 1 m               | **4,5** |
| `CBD_max` | densité apparente maximale    | **4,5** |
| `TFL`     | **charge totale**             | **3,8** |

La charge de combustible totale passe de **0,081 à 0,312 kg/m²**. Quatre
ans après le feu, le carré brûlé a reconstitué une canopée de hauteur
comparable mais ne porte encore qu’un quart du combustible, et l’écart
est concentré dans la strate basse — celle où un feu de surface se
propage.

``` r

par(mfrow = c(1, 2), mar = c(2, 2, 3, 4))
plot(brule[["TFL"]], main = "Charge totale — brûlé 2021",
     range = c(0, 0.8))
plot(temoin[["TFL"]], main = "Charge totale — témoin",
     range = c(0, 0.8))
```

![](maures_files/figure-html/plot-lidar-1.png)

### Pourquoi la couche catégorielle ne pouvait pas le savoir

Trois raisons qui se cumulent, et aucune n’est un défaut de la BD Forêt.

**Son millésime est 2008 ou 2014**, et le feu est de 2021. Dans le carré
brûlé, elle décrit le peuplement d’avant.

**Sa nomenclature ne contient pas le sous-étage.** Même à jour,
`FF1-00-00` resterait `FF1-00-00` : le poste décrit la strate arborée et
l’essence dominante, pas ce qui pousse dessous.

**Et la hauteur de canopée n’aurait pas suffi.** C’est le résultat le
plus utile de cette comparaison : `Height` est identique. Un CHM issu
d’ortho ou de satellite — la solution qu’on propose souvent pour
rafraîchir un inventaire — aurait conclu que ces deux endroits se
valent.

## Greffe sur le registre catégoriel

``` r

lidar_src <- fev_fuel_source(temoin, type = "custom", register = "continuous",
                             units = c(TFL = "kg/m2"))
#> Warning: `units` does not cover every continuous layer.
#> ℹ Missing for "Height", "CBH", "FSG", "H_Bush", "CBD_max", "CFL", "MFL",
#>   "FL_0_1", "FL_1_3", "GSFL", "Cover", and "PAI_tot". An unlabelled metric is
#>   not reproducible.
```

En pratique on emploierait
[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md)
sur la dalle elle-même ; ici la sortie est relue depuis l’extrait, faute
d’embarquer 200 Mo de nuage de points.

``` r

fuel_lidar <- fev_fuel_lidar("LHD_FXX_0972_6253_PTS_LAMB93_IGN69.copc.laz",
                             res = 25, millesime = 2025)
complet <- fev_fuel_attach(fuel, fuel_lidar)
fev_fuel_registers(complet)
#> [1] "categorical" "continuous"
```

[`fev_fuel_attach()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_attach.md)
n’est pas
[`fev_fuel_merge()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_merge.md).
La fusion arbitre entre sources qui se disputent le même pixel ; le
LiDAR ne dispute rien, il apporte des grandeurs que ni CORINE ni la BD
Forêt ne portent. La fonction rapporte la part de cellules catégorielles
effectivement couverte, parce que le programme est en cours et que les
deux registres décrivent des sous-ensembles différents de la carte.

## Validation

``` r

d <- st_drop_geometry(feux)
d[order(-d$area_ha), c("fire_date", "area_ha", "COMMUNE", "PERCNA2K")][1:6, ]
#>    fire_date area_ha           COMMUNE           PERCNA2K
#> 1 2021-08-16    6510 Cannet-des-Maures 61.070134045748695
#> 4 2024-06-11     273          Vidauban   56.2797473123125
#> 2 2021-08-16     116     Garde-Freinet  0.906368344753725
#> 5 2024-06-12       8     Garde-Freinet                  0
#> 8 2024-06-11       7     Garde-Freinet                  0
#> 3 2021-08-17       5     Garde-Freinet  77.95814762665916
```

Onze incendies, dont le 6 510 ha de 2021 — un échantillon, cette fois,
là où Couchey n’en avait qu’un.

``` r

meteo <- rast(nrows = 8, ncols = 8, extent = ext(vect(study)),
              crs = "EPSG:2154", nlyr = 730)
values(meteo) <- matrix(abs(rnorm(64 * 730, mean = 18, sd = 11)), nrow = 64)
time(meteo) <- seq(as.Date("2019-01-01"), by = "day", length.out = 730)
danger_pct <- fev_fwi_percentile(meteo, ref_period = c(2019, 2020))

dernier <- fev_data(danger_pct)[[terra::nlyr(fev_data(danger_pct))]]
dispo <- fev_fuel_availability(fuel, weights = fev_fuel_weights(quiet = TRUE))
pile <- fev_align(danger = dernier, disponibilite = fev_data(dispo),
                  exposition = fev_data(expo))
danger <- fev_danger_index(pile$danger, pile$disponibilite,
                           normalise = "percentile")
vuln <- fev_vuln_layer(pile$exposition, method = "percentile_rank",
                       name = "expo")
risque <- fev_risk(danger, vuln, normalise = "none")
```

La météo est synthétique, comme à Couchey et pour la même raison : le
produit CEMS demande un jeton personnel que le package refuse de
manipuler.

``` r

val <- fev_validate(risque, feux, millesime = min(mil$year))
val$temporal$table
#>                        lag_years n_fires area_ha pct_area
#> 1 <= 0 (fire before the vintage)       0       0        0
#> 2                         1 to 5       0       0        0
#> 3                            > 5      11    6927      100
val$auc
#> [1] NA
```

``` r

val$classes[, c("class", "pct_of_area", "pct_of_burnt", "ratio")]
#>       class pct_of_area pct_of_burnt ratio
#> 1   0 - 0.2       18.61         8.67  0.47
#> 2 0.2 - 0.4       20.96        28.92  1.38
#> 3 0.4 - 0.6       36.66        37.31  1.02
#> 4 0.6 - 0.8       21.27        22.23  1.05
#> 5   0.8 - 1        2.50         2.86  1.14
```

Le biais temporel est le même qu’à Couchey, et pour la même raison : le
combustible est de 2008, les feux vont de 2017 à 2026. Onze incendies
valent mieux qu’un, mais ils ont tous brûlé au moins neuf ans après la
photographie aérienne qui fonde la couche — et l’AUC ci-dessus est
calculé sur une météo inventée. Il décrit la géométrie du combustible,
pas une performance de prévision.

## Ce que cette page ajoute à Couchey

|  | Couchey | Les Maures |
|----|----|----|
| Combustible dominant | mélange de feuillus, vignes | **maquis**, pin maritime, chêne vert |
| Poids par défaut | mal à l’aise (0,60) | proches de leur base de preuves |
| LiDAR HD | **0 dalle** | **505 dalles, 100 %** |
| Échantillon de feux | 1 feu, 26 ha | **11 feux, 6 927 ha** |
| Millésime | 2007 / 2010 / 2014 | 2008 / 2014 |
| Validation | impossible, et c’est le résultat | possible, mais sur météo inventée |

Et une chose que ni l’une ni l’autre ne résout : le LiDAR HD est de
**2025**, la BD Forêt de 2008. Le registre continu et le registre
catégoriel d’un même objet `fev_fuel_source` peuvent donc décrire le
même sol à dix-sept ans d’écart. Le package les tient séparés et
journalise les deux millésimes plutôt que de les mélanger — c’est tout
ce qu’il peut faire, et c’est mieux que de laisser croire qu’il s’agit
d’une seule description.

Enfin, une réserve sur les chiffres de la section 4. Ils viennent de
deux carrés de 25 hectares. Ils illustrent un mécanisme — la strate
basse porte l’écart que la classe ne voit pas — ils ne mesurent pas
l’effet d’un incendie sur un massif. Pour cela il faudrait les 505
dalles, ce qui est un travail de calcul, pas de démonstration.
