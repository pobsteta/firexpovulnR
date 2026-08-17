# Build inst/extdata/maures.gpkg and the LiDAR fuel rasters beside it.
#
# Run with:  Rscript data-raw/build_maures_extract.R
# Needs network, several hundred megabytes of download, and about half an hour.
#
# ---------------------------------------------------------------------------
# Why the Maures, after Couchey
# ---------------------------------------------------------------------------
#
# The Couchey article runs the chain where the package is least at home:
# Burgundian oak and beech, vineyards, no LiDAR coverage at all, and a
# validation that fails honestly. This one runs it where it was designed to
# work, and where the two things Couchey could not show are available.
#
#   Maquis and holm oak     LA4 is the commonest TFV class here, where Couchey's
#                           was mixed broadleaf. The fuel weights and the
#                           exposure radii are closest to their evidence base.
#   LiDAR HD, 100% covered  Couchey: zero tiles. Here: 505 over the study area,
#                           flown 2025 -- so the understorey, the package's
#                           stated blind spot, is finally measurable.
#   A real fire sample      11 fires and 6 927 ha, including the 6 510 ha
#                           Cannet-des-Maures fire of 16 August 2021.
#
# ---------------------------------------------------------------------------
# What is in it, and when it was fetched
# ---------------------------------------------------------------------------
#
# Fetched 2026-08-17. Study area: the 2021 fire buffered by 2 km, 423 km2.
#
#   study_area   the extent
#   bdforet_v2   2 333 vegetation formations
#   clc_2018     201 land cover polygons
#   burnt_areas  11 EFFIS fires, 2017-2026
#   lidar_tiles  the 505-tile index footprint, dissolved
#   millesime_candidates   BD ORTHO campaigns: 2008 and 2014
#
# Plus two GeoTIFFs of real LiDAR fuel metrics at 25 m, one square kilometre
# each, computed from the point clouds by fev_fuel_lidar():
#
#   lidar_burnt.tif    500 m square inside the 2021 burn
#   lidar_control.tif  500 m square outside it, 3 km away
#
# The two squares are chosen so that BD Forêt gives them the SAME dominant TFV
# class -- Foret fermee de pin maritime pur, FF2-51-51, availability weight
# 0.95. That is the whole demonstration: everything the categorical layer can
# say about these two places is identical, and the LiDAR measures a thirteenfold
# difference in fuel load between them.
#
# 500 m rather than the full kilometre because fPCpretreatment on 24 million
# points exhausted 31 GB of RAM. A quarter tile at full density is the honest
# reduction -- a smaller area, not a thinned cloud. Roughly 100 to 200 s each.
#
# The point clouds themselves are 120 MB and 242 MB and are NOT shipped. The
# metrics they produce are a few tens of kilobytes, which is the whole argument
# for deriving them once here rather than in the article.
#
# NOT included: fire weather, for the same reason as Couchey -- the CEMS
# product needs a personal token the package refuses to handle.

library(sf)
library(terra)
library(lidR)
library(firexpovulnR)

stopifnot("run from the package root" = file.exists("DESCRIPTION"))

BUFFER <- 2000
PERIOD <- c("2016", "2026")
RES <- 25
OUT <- file.path("inst", "extdata", "maures.gpkg")
CLIP <- 250              # half-side of the processed square, metres
# Stable rather than tempdir(): these are hundreds of megabytes and a rebuild
# should not refetch them.
TILE_DIR <- file.path(tools::R_user_dir("firexpovulnR", "cache"),
                      "maures_tiles")

# --- the fires, and the study area they define -------------------------------
# Searched over a wide box first: the Maures burn often, and framing the study
# area on the biggest fire rather than on an arbitrary rectangle is what makes
# the validation sample worth having.
wide <- st_as_sf(st_as_sfc(st_bbox(
  c(xmin = 940000, ymin = 6225000, xmax = 1000000, ymax = 6265000),
  crs = st_crs(2154)
)))
all_fires <- fev_data(fev_fetch_burnt(wide, period = PERIOD, cache = FALSE))
gonfaron <- all_fires[which.max(all_fires$area_ha), ]
message(sprintf("largest fire: %s, %.0f ha, %s", gonfaron$COMMUNE,
                gonfaron$area_ha, gonfaron$fire_date))

study <- st_as_sf(st_as_sfc(st_bbox(
  st_buffer(st_geometry(gonfaron), BUFFER)
)))
fires <- all_fires[lengths(st_intersects(all_fires, study)) > 0, ]
message(sprintf("study area: %.0f km2, %d fires, %.0f ha",
                as.numeric(st_area(study)) / 1e6, nrow(fires),
                sum(fires$area_ha)))

# --- fuel --------------------------------------------------------------------
bdforet <- fev_data(fev_fetch_bdforet(study, millesime = "auto", cache = FALSE))
corine <- fev_data(fev_fetch_corine(study, year = 2018, cache = FALSE))
millesime <- fev_bdforet_millesime(study, cache = FALSE)
message(sprintf("bdforet: %d, corine: %d", nrow(bdforet), nrow(corine)))

# --- LiDAR HD ----------------------------------------------------------------
# The availability check the brief insists on comes before anything is fetched.
# Here it answers yes, which is the whole point of choosing this terrain.
idx <- fev_lidarhd_available(study, cache = FALSE)
stopifnot("expected full LiDAR coverage over the Maures" = nrow(idx) > 0)

# One square inside the 2021 burn and one outside it, matched on the class BD
# Forêt gives them. Matching matters: without it the comparison is between two
# different forests, and the point is that the categorical layer cannot tell
# these two apart.
idx$burnt <- lengths(st_intersects(idx, gonfaron)) > 0
covered <- as.numeric(st_area(st_intersection(
  st_geometry(idx[idx$burnt, ]), st_geometry(gonfaron)
)))
burnt_tile <- idx[idx$burnt, ][which.max(covered), ]

dominant_tfv <- function(tile) {
  hit <- bdforet[lengths(st_intersects(bdforet, tile)) > 0, ]
  if (!nrow(hit)) return(NA_character_)
  names(sort(table(hit$code_tfv), decreasing = TRUE))[1]
}

inside_study <- idx[!idx$burnt, ]
inside_study <- inside_study[
  lengths(st_within(st_centroid(st_geometry(inside_study)),
                    st_geometry(study))) > 0, ]
inside_study$dom <- vapply(seq_len(nrow(inside_study)),
                           function(i) dominant_tfv(inside_study[i, ]),
                           character(1))
target <- dominant_tfv(burnt_tile)
same_class <- inside_study[!is.na(inside_study$dom) &
                             inside_study$dom == target, ]
stopifnot("no unburnt tile shares the burnt tile's class" = nrow(same_class) > 0)
d_km <- as.numeric(st_distance(st_centroid(st_geometry(same_class)),
                               st_centroid(st_geometry(burnt_tile))))
control_tile <- same_class[which.min(d_km), ]
message(sprintf("matched on %s; control is %.1f km from the burnt tile",
                target, min(d_km) / 1000))

tiles <- list(burnt = burnt_tile, control = control_tile)

dir.create(TILE_DIR, recursive = TRUE, showWarnings = FALSE)
lidar <- list()
for (nm in names(tiles)) {
  url <- as.character(tiles[[nm]]$url)
  f <- file.path(TILE_DIR, basename(url))
  if (!file.exists(f) || file.size(f) < 1e7) {
    message(sprintf("downloading %s tile ...", nm))
    download.file(url, f, mode = "wb", quiet = TRUE)
  }
  message(sprintf("%s tile: %.0f MB", nm, file.size(f) / 1e6))

  bb <- st_bbox(tiles[[nm]])
  cx <- (bb[["xmin"]] + bb[["xmax"]]) / 2
  cy <- (bb[["ymin"]] + bb[["ymax"]]) / 2
  las <- readLAS(f)
  sub <- clip_rectangle(las, cx - CLIP, cy - CLIP, cx + CLIP, cy + CLIP)
  rm(las)
  invisible(gc())

  # Density first, and reported: the specification is 10 pulses/m2 and these sit
  # well above it. The returns-per-pulse ratio is itself a vegetation signal --
  # canopy intercepts at several levels, bare ground returns once.
  d <- fev_lidar_density(sub)
  message(sprintf("  %.1f pulses/m2, %.1f points/m2 (%.2f returns per pulse)",
                  d$pulses_per_m2, d$points_per_m2,
                  d$points_per_m2 / d$pulses_per_m2))

  out_tif <- file.path("inst", "extdata", paste0("lidar_", nm, ".tif"))
  fuel <- fev_fuel_lidar(sub, res = RES, millesime = 2025)
  writeRaster(fev_fuel_continuous(fuel), out_tif, overwrite = TRUE)
  lidar[[nm]] <- list(density = d, tile = tiles[[nm]], tfv = target)
}

# --- write -------------------------------------------------------------------
simplify <- function(x, tol = 10) {
  st_make_valid(st_simplify(x, dTolerance = tol, preserveTopology = TRUE))
}

unlink(OUT)
st_write(st_sf(geometry = st_geometry(study)), OUT, layer = "study_area",
         quiet = TRUE)
st_write(simplify(bdforet[, c("code_tfv", "tfv_g11", "essence")]),
         OUT, layer = "bdforet_v2", append = TRUE, quiet = TRUE)
st_write(simplify(corine[, "code_18"]), OUT, layer = "clc_2018",
         append = TRUE, quiet = TRUE)
st_write(fires[, intersect(c("FIREDATE", "FINALDATE", "fire_date", "fire_year",
                             "area_ha", "COMMUNE", "PROVINCE", "CLASS",
                             "PERCNA2K", "BROADLEA", "CONIFER", "MIXED",
                             "SCLEROPH", "OTHERNATLC"), names(fires))],
         OUT, layer = "burnt_areas", append = TRUE, quiet = TRUE)

# The tile footprints are dissolved: 505 rectangles are not information, the
# extent of coverage is.
st_write(st_sf(n_tiles = nrow(idx),
               chantiers = paste(sort(unique(as.character(idx$id_chantier))),
                                 collapse = ", "),
               timestamp = as.character(idx$timestamp[1]),
               geometry = st_union(st_geometry(idx))),
         OUT, layer = "lidar_coverage", append = TRUE, quiet = TRUE)

# The two tiles kept, with their measured density, so the article can quote it
# without recomputing.
# The processed squares, not the whole tiles: what the rasters actually cover.
squares <- lapply(tiles, function(t) {
  bb <- st_bbox(t)
  cx <- (bb[["xmin"]] + bb[["xmax"]]) / 2
  cy <- (bb[["ymin"]] + bb[["ymax"]]) / 2
  st_polygon(list(cbind(c(cx - CLIP, cx + CLIP, cx + CLIP, cx - CLIP, cx - CLIP),
                        c(cy - CLIP, cy - CLIP, cy + CLIP, cy + CLIP, cy - CLIP))))
})
st_write(st_sf(
  role = names(tiles),
  tile = vapply(tiles, function(t) as.character(t$name), character(1)),
  tfv_dominant = vapply(lidar, function(l) l$tfv, character(1)),
  pulses_per_m2 = vapply(lidar, function(l) l$density$pulses_per_m2, numeric(1)),
  points_per_m2 = vapply(lidar, function(l) l$density$points_per_m2, numeric(1)),
  n_points = vapply(lidar, function(l) as.numeric(l$density$n_points), numeric(1)),
  geometry = st_sfc(squares, crs = 2154)
), OUT, layer = "lidar_squares", append = TRUE, quiet = TRUE)

st_write(st_sf(as.data.frame(unclass(millesime)),
               geometry = st_sfc(st_point(c(NA_real_, NA_real_)), crs = 2154)),
         OUT, layer = "millesime_candidates", append = TRUE, quiet = TRUE)

message(sprintf("wrote %s (%.0f KB)", OUT, file.size(OUT) / 1024))
print(st_layers(OUT))
