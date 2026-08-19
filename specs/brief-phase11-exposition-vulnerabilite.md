# Phase 11 — Exposition anisotrope, calibration des rayons, enjeux et interface

Fait suite au constat dressé le 2026-08-19 en relisant `exposure.R` (830 lignes)
et `vulnerability.R` (276, dont l'essentiel est de la normalisation). Quatre
manques, traités ici dans l'ordre où ils changent les résultats.

Ce document est écrit **avant** le code. Ce qu'il annonce a été vérifié à la
source ; ce qui ne l'a pas été est signalé comme tel.

## Ce qui a été vérifié à la source, et ce que ça donne

Le brief interdit qu'une URL, un nom de jeu ou une grille entrent dans le code
sans vérification. Fait le 2026-08-19 :

| Élément | Vérifié | Résultat |
|---|---|---|
| Copernicus DEM GLO-30 | `HEAD` + lecture d'en-tête | tuiles 1° × 1°, 1 arc-seconde, WGS 84, nommage `Copernicus_DSM_COG_10_N{lat}_00_E{lon}_00_DEM`, lecture distante en 5,9 s |
| GHS-POP R2023A | `HEAD` + lecture de deux tuiles | Mollweide ESRI:54009, **tuiles de 1 000 000 m de côté**, 100 m de résolution |
| Grille de tuilage GHSL | déduite de `R4_C19` et `R5_C19` | `R4_C19` = `x ∈ [-41000, 959000]`, `y ∈ [5e6, 6e6]` ; `R5_C19` = même `x`, `y ∈ [4e6, 5e6]` |
| Lecture par fenêtre GHSL | crop réel sur les Maures | 208 × 213 cellules en 17,3 s, **35 039 habitants**, maximum 106,8 par cellule |

La grille se déduit donc, et l'offset de −41 000 m est constant entre deux
tuiles de colonnes identiques :

```
C = floor((x + 41000) / 1e6) + 19
R = floor((10e6 - y) / 1e6)
```

**Cet offset n'est pas documenté dans la fiche produit : il est mesuré.** Il
doit être re-vérifié si le millésime change, et le code doit échouer bruyamment
plutôt que de deviner si une tuile calculée n'existe pas.

## 1 — Calibrer les rayons plutôt que les subir

### Le problème

30, 100 et 500 m viennent de Beverly et al. sur combustibles boréaux et
conifériens canadiens, avec une validation portugaise (Khan et al. 2025).
`fev_exposure()` le dit à chaque session, et s'arrête là. Or le paquet possède
déjà tout ce qu'il faut pour trancher : `fev_auc()` et un historique de feux.

### Ce qui est écrit

`fev_exposure_calibrate(fuel, burnt_areas, radii, type, ...)` balaie une série
de rayons, calcule l'exposition pour chacun, et confronte chacune aux surfaces
brûlées par l'AUC déjà utilisée par `fev_validate()`. Retourne un tableau
`radius, reachable, auc, n_cells, note` et le rayon d'AUC maximale.

### Ce qu'il ne faut pas lui faire dire

- **Un maximum d'AUC n'est pas une validation.** C'est un ajustement sur les
  feux fournis, et rien n'est mis de côté pour le tester. Le résultat porte la
  mention explicite qu'il s'agit d'un ajustement, pas d'une validation croisée.
- Le contrôle de biais temporel de `fev_validate()` s'applique ici aussi : un
  rayon ajusté sur des feux postérieurs au millésime du combustible est ajusté
  sur autre chose que ce qu'on croit.
- Un rayon inatteignable à la résolution donnée (`res > radius / 3`) est
  **déclaré sauté**, jamais retiré en silence.
- Les cellules sont contiguës et les feux aussi : pas d'intervalle de
  confiance, pour la raison déjà écrite dans `fev_validate()`.

## 2 — Des enjeux, et l'interface habitat-forêt

### Le problème

Tous les modules ont leurs fonctions d'acquisition — BD Forêt, CORINE,
WorldCover, FORMS, LiDAR HD, Open-Meteo, EFFIS. La vulnérabilité n'en a aucune.
Et l'interface habitat-forêt, que le brief et `fev_risk()` désignent tous deux
comme la dimension attendue, n'est calculée nulle part.

### Ce qui est écrit

`fev_fetch_ghsl(aoi, epoch, ...)` — GHS-POP, 100 m, mondial, sans compte, lu par
fenêtre à travers `/vsizip//vsicurl/` comme WorldCover l'est déjà. Millésime
obligatoire dans la provenance.

`fev_wui(built, fuel, distance, ...)` — l'interface : les cellules bâties dont
le voisinage contient du combustible brûlable à moins de `distance`. Sortie en
`fev_layer` de rôle `"wui"`, directement consommable comme dimension
supplémentaire de `fev_risk()`.

### Ce que ça ne fait pas

GHS-POP donne une **densité de population**, pas une susceptibilité. Le paquet
gagne une source d'enjeux ; il ne gagne pas de fonction de dommage, et la
distinction doit rester lisible dans la documentation. Un hôpital et un hangar à
même densité continuent de sortir au même score.

## 3 — L'exposition devient anisotrope

### Le problème

L'anneau de `fev_exposure()` pèse toutes les directions à l'identique. Les
Maures brûlent au mistral et en montant. `fev_directional()` existe mais opère
*sur* le champ isotrope, depuis un enjeu ponctuel : elle décrit des voies
d'approche, elle ne rend pas l'exposition directionnelle.

### Ce qui est écrit

Décomposition de l'anneau en **secteurs angulaires**. Une passe focale par
secteur, puis une combinaison par cellule :

```
exposition(c) = somme_k alpha_k(c) * e_k(c),   somme_k alpha_k(c) = 1
```

- `e_k(c)` : fraction brûlable dans le secteur `k` autour de `c` ;
- `alpha_k(c)` : poids du secteur, fonction du vent et de la pente locale.

**Invariant à tester** : avec des poids proportionnels au nombre de cellules de
chaque secteur, on doit retrouver `fev_exposure()` isotrope à la tolérance
numérique près. C'est le seul garde-fou qui empêche l'anisotropie de dériver en
métrique arbitraire.

Deux pondérations, cumulables :

- **Vent** — le feu approche de la direction d'où souffle le vent. Poids de type
  von Mises, `exp(kappa * cos(delta))`, `delta` étant l'écart angulaire entre la
  direction du secteur et celle du vent. `kappa` réglable, nul par défaut.
- **Pente** — le feu monte. Le côté aval d'une cellule est celui qui l'expose,
  c'est-à-dire la direction que donne `terra::terrain(v = "aspect")`. `kappa`
  proportionnel à `tan(pente)` : plus la pente est forte, plus l'anisotropie
  est marquée. Nul sur terrain plat, ce qui est le comportement voulu.

`fev_fetch_dem(aoi, ...)` importe le Copernicus DEM GLO-30 pour alimenter la
seconde.

### Ce qu'il faut assumer

Ce n'est **pas la métrique publiée**. Beverly la définit isotrope ; Khan l'a
validée isotrope. L'anisotropie est donc **hors défaut**, elle est inscrite dans
la provenance à chaque usage, et la documentation dit qu'elle n'a pas de
validation propre. Le coût est d'environ `n_sectors` passes focales, chacune sur
une fraction de l'anneau : même volume d'opérations, plus l'encombrement de
`n_sectors` couches intermédiaires.

## 4 — L'exposition pondérée par le combustible mesuré

### Le problème

`fev_exposure()` consomme un masque **binaire**. La campagne LiDAR vient de
montrer que dans une seule classe TFV — les chênes sempervirents, 520 cellules —
la charge de houppier va de 0,05 à 1,98 kg/m². Un masque binaire compte ces
cellules à l'identique.

### Ce qui est écrit

`fev_fuel_load_weight(x, metric, method, clamp, ...)` transforme une métrique
continue du registre LiDAR — `CBD_max`, `CFL`, `TFL`, ce que l'utilisateur veut
— en une couche de rôle `"availability"` sur [0, 1]. `fev_exposure()` la
consomme alors **par le chemin gradué qui existe déjà**, sans machinerie
nouvelle.

C'est délibérément le plus petit ajout possible : le registre continu et le
chemin gradué existaient tous deux, il manquait le pont entre les deux.

### Le piège à documenter

Le LiDAR ne couvre pas tout. Une cellule sans mesure est `NA`, et `NA` dans
l'anneau n'est pas « zéro combustible » — c'est « on ne sait pas ». Le
comportement par défaut (`na_rm = FALSE`) propage donc l'ignorance au lieu de
la maquiller, et la documentation doit dire pourquoi c'est le bon choix : sur
32 fenêtres de 250 m couvrant 2 km², une exposition calculée en traitant
l'absence de mesure comme une absence de combustible serait fausse partout
sauf sur ces 2 km².

## Ce que cette phase ne fait pas

- **Aucune fonction de dommage.** La vulnérabilité reste une densité d'enjeux
  normalisée. C'est le manque de fond, il n'est pas comblé ici, et le prétendre
  serait pire que de l'admettre.
- **Aucune validation de la moitié vulnérabilité.** Il y faudrait des relevés de
  dommage — bâtiments détruits, victimes — que le paquet ne sait ni chercher ni
  consommer.
- **Aucune calibration de l'anisotropie.** Les deux `kappa` sont des paramètres
  de l'analyse, pas des propriétés mesurées, exactement comme les poids de
  `fev_vuln_stack()`. Ils sont écrits dans la provenance pour cette raison.
