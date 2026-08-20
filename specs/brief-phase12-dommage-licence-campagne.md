# Brief — Phase 12 : la fonction de dommage, la licence, la campagne, et ce qui attend

Écrit le 2026-08-20, après la 0.32.0. Quatre chantiers restants, très inégaux :
l'un est petit et net, l'un est opérationnel, l'un est le manque de fond du
paquet, et le dernier ne dépend pas de nous.

Ils sont donnés dans l'ordre où je les ferais, qui n'est pas l'ordre
d'importance : le plus important est le troisième et il est le plus lent à
mûrir.

**Ne démarre aucun de ces chantiers sans accord explicite.** Le premier touche à
la provenance, qui est le cœur du paquet ; le troisième engage une campagne de
terrain.

---

## 1 — Le champ `licence` de premier rang

### Pourquoi maintenant

Jusqu'à la 0.31.0 la licence était de la documentation : toutes les sources
étaient permissives, et l'information vivait en texte libre à l'intérieur du
champ `provider` :

```r
provider = "ESA WorldCover (public bucket, CC-BY 4.0)"
```

Deux constats de cette semaine rendent cela intenable.

**FORMS-T** est annoncé CC-BY-NC sur la page THEIA et `cc-by-4.0` dans les
métadonnées structurées de Zenodo. Une licence non commerciale se propage aux
œuvres dérivées : une carte de risque calculée à partir d'une telle source l'est
aussi, et rien dans le paquet ne le dirait.

**SUFOSAT** est pire, ou plus instructif : la **même donnée** porte trois
réponses selon l'endroit où on la demande — 403 sur le bucket que le catalogue
STAC désigne, CC-BY-NC sur la version Zenodo supersédée, CC-BY 4.0 sur la
version courante. Une licence n'est donc pas un attribut du jeu de données mais
du **chemin d'acquisition**, ce qui est exactement ce qu'une provenance doit
enregistrer.

### Ce qu'il faut écrire

- Un champ `licence` explicite dans l'enregistrement de source, à côté de
  `dataset`, `provider`, `millesime`. Les sources existantes se remplissent au
  passage, en reprenant ce qui est déjà écrit dans leur `provider` et leur
  `@source`.
- Un accesseur qui répond à la question réelle, du genre `fev_licences(x)` :
  lister chaque licence rencontrée dans une pile et **désigner la plus
  restrictive**. Une analyse combinant BD Forêt, WorldCover, GHS-POP, LiDAR HD,
  Sentinel-2 et SUFOSAT produit un résultat dont le régime est celui de la plus
  contraignante, et personne ne peut le savoir aujourd'hui sans relire six
  fiches produit.
- Quand deux canaux se contredisent, **enregistrer la contradiction** plutôt que
  de trancher en silence, et retenir la plus restrictive par défaut.

### Ce qu'il ne faut pas faire

Ne pas transformer cela en conseil juridique. Le paquet enregistre ce que les
producteurs déclarent et signale les conflits ; il ne dit pas à l'utilisateur ce
qu'il a le droit de faire.

### Effort

Petit. Une demi-journée, l'essentiel étant de remplir les sources existantes
sans se tromper — donc en relisant chaque `@source`, pas de mémoire.

---

## 2 — La campagne LiDAR

### Où elle en est

32 dalles inversées et valides, 430 restantes, 43 écartées faute de fenêtre
tenant dans l'emprise. Les 13 rasters produits hors emprise avant la correction
de la 0.26.0 sont dans `hors_emprise/`, conservés au cas où l'emprise
s'élargirait.

La reprise est prête et déterministe :

```
Rscript inst/scripts/batch_lidar.R inst/extdata/maures.gpkg \
  /home/pascal/dev/firexpovulnR-lidar/maures --window=250 --max=8 --keep-las
```

### Ce qui est déjà tranché, et qu'il ne faut pas rouvrir

**Le coût est l'inversion, pas le transport.** Mesuré : 47 à 213 s par dalle,
dont environ 35 de téléchargement. La requête bornée sur COPC distant a été
essayée jusqu'au bout — elle fonctionne, n'est pas plus rapide, et n'est pas
déterministe. Voir `note-sources-2026-08-20.md`. Les leviers sont donc la
**taille de la fenêtre** et le **nombre de dalles**, rien d'autre.

**Ne pas réduire la densité du nuage.** C'est écrit dans l'en-tête du script et
mérite d'être répété : la strate de sous-étage est la première à disparaître
quand la densité baisse, et c'est précisément ce que ces métriques mesurent.

### La question ouverte

Combien de dalles suffisent ? À 32 fenêtres, la comparaison BD Forêt × LiDAR
donnait déjà des étendues couvrant un ordre de grandeur sur presque toutes les
métriques. Entre 12 et 32 fenêtres, le pouvoir explicatif de la classe TFV a
**baissé** sur les six métriques — le tableau est dans la vignette. Rien ne dit
que c'est stabilisé.

Une manière honnête de le savoir : refaire la décomposition tous les huit
ajouts et **arrêter quand les R² cessent de bouger**, plutôt que de viser un
nombre décidé d'avance. Cela vaut d'être écrit dans la vignette comme critère,
pas seulement appliqué.

---

## 3 — La fonction de dommage

C'est le manque de fond du paquet, et le seul chantier qui ne peut pas être
mené depuis un bureau.

### L'état des lieux

`fev_vuln_layer()` normalise une densité d'enjeux, `fev_vuln_stack()` en fait
une moyenne pondérée. Il n'y a **aucune fonction de dommage** : rien ne dit
quelle fraction de la valeur est perdue pour une intensité donnée. Un hôpital et
un hangar à même densité sortent au même score.

Et `fev_validate()` note le risque contre des surfaces brûlées, qui sont un
résultat de **l'aléa**. Ajouter de la vulnérabilité ne peut que baisser l'AUC,
puisque les enjeux ne sont pas là où le feu va : la seule métrique de validation
du paquet pénalise structurellement ce qu'elle devrait valider.

### Ce que la 0.31.0 débloque

`fev_fetch_severity()` fournit l'observable qui manquait : une sévérité
**continue à l'intérieur du périmètre**. Sur le Cannet-des-Maures, dNBR médian
0,576 dans le périmètre contre 0,000 dehors, 41,9 % au-dessus du seuil de
sévérité forte.

C'est une cible de calage, pas une mesure de dommage. **Le dNBR est un
changement de réflectance.** Le relier à une mortalité, à une perte de biomasse
ou à une perte économique demande des placettes de terrain, et rien ne remplace
cela.

### Ce qu'il faut d'abord établir, avant toute ligne de code

1. **Quel dommage ?** Il n'y en a pas un mais plusieurs, et chacun a sa variable
   d'intensité et sa donnée de calage : mortalité des arbres, passage en cime,
   perte économique, échec de régénération, érosion. Le paquet ne doit pas
   prétendre les couvrir tous.
2. **Une intensité physique.** Une courbe de dommage prend en entrée une
   intensité de Byram en kW/m ou une longueur de flamme, pas un indice sans
   dimension. `fev_risk()` sort un nombre entre 0 et 1 : rien ne s'y branche.
   Le paquet est à un pas — la charge est mesurée en kg/m² par
   `fev_fuel_lidar()`, il manque une vitesse de propagation. **Vérifier à la
   source** la formulation de Byram et celle de Van Wagner pour l'initiation de
   feu de cime, qui consomme précisément le CBH et la CBD que la campagne
   mesure.
3. **Des placettes.** Sans mortalité observée, le calage dNBR → dommage est une
   supposition. Où les trouver, et pour quelles essences, est la première
   question à poser — pas la dernière.

### La particularité méditerranéenne à ne pas manquer

Le massif des Maures est un massif de **chêne-liège**. L'arbre survit très bien
au feu — l'écorce est un isolant, c'est sa fonction — mais **le liège est
détruit et l'arbre inécorçable une dizaine d'années**. Mortalité proche de zéro,
perte économique majeure. Une fonction de dommage fondée sur la mortalité
donnerait ici presque zéro, et une fondée sur le volume aussi : **les deux se
tromperaient**.

### Et un terme que SUFOSAT vient de rendre visible

Les 599 ha détectés dans le périmètre de 2021 au cours de 2022 sont de la
**récupération sanitaire**. Le bois brûlé qui part en exploitation cesse d'être
du combustible et cesse d'être une perte sèche. Une fonction de dommage
économique qui l'ignore surestime la perte, et elle est maintenant mesurable.

### Ce que ce brief refuse par avance

**Importer une courbe nord-américaine et l'appliquer au chêne-liège.** Si les
placettes manquent, la bonne réponse est de le dire et de s'arrêter, comme
`fev_rain_gradient()` refuse d'ajuster un gradient que les données ne portent
pas.

---

## 4 — Le test CBH → sévérité, qui attend

### Pourquoi il est impossible aujourd'hui

Les 32 fenêtres LiDAR recoupent les feux de 2021 sur 5 d'entre elles, soit
27,5 ha et environ 440 cellules. Mais le LiDAR HD des Maures a été acquis le
**1er mai 2025**, quatre ans après l'incendie : la structure qu'il mesure est
celle qui a repoussé. Prédire la sévérité de 2021 à partir de là serait prédire
une cause par son effet.

C'est une contrainte de calendrier, pas de méthode. **Aucune quantité de code ne
la lève.**

### Ce qui l'ouvrirait

Un feu **postérieur à mai 2025** recoupant des fenêtres inversées. Les données
EFFIS livrées contiennent déjà un feu de 2026 ; aucune fenêtre ne le recoupe
aujourd'hui, mais la campagne continue et l'intersection peut apparaître.

À faire, et c'est peu de chose : **vérifier l'intersection après chaque
session** de campagne, plutôt que de découvrir dans un an qu'elle existait.

### Ce qui reste possible entre-temps

La comparaison de structure après feu, déjà faite sur 440 cellules : quatre ans
après, la hauteur est à 0,76 de la valeur hors feu mais la hauteur des buissons
à **0,07** et la charge de houppier à **0,14**. Les tiges sont debout et ne
portent presque rien.

C'est une mesure de reconstitution du combustible, utile en soi — un secteur
brûlé récemment porte beaucoup moins de feu — et elle mérite d'entrer dans la
vignette avec sa réserve : 399 cellules issues de 5 fenêtres, donc
pseudo-réplication spatiale, et un test de Wilcoxon optimiste.

---

## Ordre proposé

1. **La licence** — petit, net, et le besoin est démontré par deux cas de cette
   semaine.
2. **La campagne** — opérationnel, avec le critère d'arrêt à écrire.
3. **Le dommage** — le vrai sujet, à commencer par les placettes et non par le
   code.
4. **Le test CBH** — rien à faire qu'une vérification d'intersection après
   chaque session.

Et une règle qui a servi toute la semaine, à garder : **presque tous les défauts
trouvés l'ont été en exécutant, jamais en testant.** Le nom de fichier que terra
refuse, la fenêtre centrée sur la dalle, le téléchargement tronqué, la carte de
risque d'un 31 décembre, la scène satellite prise deux heures avant la fin du
sinistre, la couverture mesurée sur le mauvais raster. Aucun n'a provoqué
d'erreur ; tous rendaient un résultat plausible. La suite était verte du début
à la fin.
