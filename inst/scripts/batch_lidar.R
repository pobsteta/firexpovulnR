#!/usr/bin/env Rscript
#
# Inversion LiDAR HD par lots, avec reprise.
# ---------------------------------------------------------------------------
#
#   Rscript batch_lidar.R <emprise.gpkg> <dossier_sortie> [options]
#
# Exemples
#
#   # 1. Voir ce qui serait fait, sans rien telecharger
#   Rscript batch_lidar.R maures.gpkg out/lidar --window=250 --dry-run
#
#   # 2. Une nuit de calcul, huit dalles
#   Rscript batch_lidar.R maures.gpkg out/lidar --window=250 --max=8
#
#   # 3. Le lendemain : relancer la meme commande, les dalles faites sont
#   #    sautees. On peut l'interrompre par Ctrl-C a tout moment.
#   Rscript batch_lidar.R maures.gpkg out/lidar --window=250 --max=8
#
# Options
#
#   --layer=NOM    couche du gpkg a lire            (defaut : study_area)
#   --window=M     cote du carre centre traite, en metres. NULL = dalle entiere.
#                  250 est un bon depart : une dalle entiere prend des heures.
#   --res=M        taille de cellule                (defaut : 25)
#   --max=N        nombre de dalles pour CETTE session (defaut : toutes)
#   --keep-las     garder les nuages telecharges    (defaut : supprimes)
#   --dry-run      afficher le plan et s'arreter
#
# Ce que ca produit dans <dossier_sortie>
#
#   <dalle>_fuel.tif   un raster de metriques par dalle traitee
#   manifest.csv       reecrit apres CHAQUE dalle : etat, points, secondes
#   las/               nuages en cours ; vide en fin de course sauf --keep-las
#
# Duree a prevoir. Mesure sur les dalles des Maures, bornes inferieures car
# aucune de ces trois n'a abouti : 3,0 M de points en plus de 25 min, 11,1 M en
# plus de 40 min, une dalle entiere en plus de 90 min. Le telechargement n'est
# pas le goulot -- 248 Mo en 42 s -- c'est l'inversion.
#
# NE REDUISEZ PAS la densite du nuage pour aller plus vite. La strate de
# sous-etage est la premiere a disparaitre quand la densite baisse : vous
# fausseriez exactement ce que ces metriques servent a mesurer. Reduisez
# --window, ou traitez moins de dalles.

suppressMessages({
  library(firexpovulnR)
  library(sf)
})

args <- commandArgs(trailingOnly = TRUE)
pos <- args[!startsWith(args, "--")]
opt <- args[startsWith(args, "--")]

if (length(pos) < 2) {
  cat("usage: Rscript batch_lidar.R <emprise.gpkg> <dossier_sortie> [options]\n")
  cat("       voir l'en-tete de ce fichier pour les options\n")
  quit(status = 1)
}

get <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), opt, value = TRUE)
  if (!length(hit)) default else sub(paste0("^--", name, "="), "", hit[1])
}
flag <- function(name) any(opt == paste0("--", name))

gpkg <- pos[1]
out_dir <- pos[2]
layer <- get("layer", "study_area")
window <- get("window")
window <- if (is.null(window)) NULL else as.numeric(window)
res <- as.numeric(get("res", "25"))
max_tiles <- get("max")
max_tiles <- if (is.null(max_tiles)) NULL else as.integer(max_tiles)

if (!file.exists(gpkg)) {
  cat("emprise introuvable :", gpkg, "\n")
  quit(status = 1)
}

aoi <- st_read(gpkg, layer, quiet = TRUE)
cat("emprise :", gpkg, "/", layer, "\n")
cat("sortie  :", out_dir, "\n\n")

plan <- fev_lidar_batch(
  aoi,
  out_dir   = out_dir,
  res       = res,
  window    = window,
  max_tiles = max_tiles,
  keep_las  = flag("keep-las"),
  dry_run   = flag("dry-run")
)

if (flag("dry-run")) {
  cat("\n--- plan ---\n")
  print(utils::head(plan[plan$status == "todo", c("tile", "status")], 20))
  cat(sum(plan$status == "todo"), "dalle(s) a traiter,",
      sum(plan$status == "done"), "deja faite(s)\n")
}
