# Build inst/extdata/couchey.gpkg, the real-data example shipped with the
# package.
#
# Run with:  Rscript data-raw/build_couchey_extract.R
# Needs network: it contacts IGN and EFFIS.
#
# ---------------------------------------------------------------------------
# Why an extract rather than live calls in the article
# ---------------------------------------------------------------------------
#
# The brief forbids network-dependent tests, and the same reasoning applies to
# the documentation: an article that fetched from IGN would turn a red pkgdown
# build into a statement about someone else's uptime. So the data is fetched
# once, here, and the article reads it from disk.
#
# The cost is that the extract ages. Everything in it is dated below, and
# re-running this script is what refreshes it.
#
# ---------------------------------------------------------------------------
# Why Couchey
# ---------------------------------------------------------------------------
#
# Couchey (Côte-d'Or, INSEE 21200) is the reference territory of the sibling
# nemetonshiny project, so the two packages can be read against the same
# ground. It is also the opposite of the Mediterranean case the package was
# designed around, which is what makes it worth shipping: deciduous oak,
# beech and hornbeam rather than Aleppo pine and maquis, and vineyards where a
# Var example would have garrigue. Several of the package's defaults are
# visibly less at home here, and the article says so rather than hiding it.
#
# Note the INSEE code. The nemetonshiny test fixture uses 21189, which is a
# mock value -- 21189 is Corberon. Couchey is 21200, confirmed against
# ADMINEXPRESS.
#
# ---------------------------------------------------------------------------
# What is in it, and when it was fetched
# ---------------------------------------------------------------------------
#
# Fetched 2026-08-16:
#   commune      ADMINEXPRESS-COG.2021, Couchey (21200), 1267 ha
#   study_area   the commune and the 2020 fire, buffered 1.5 km: 12.6 x 12.6 km
#   bdforet_v2   568 vegetation formations, IGN Géoplateforme WFS
#   clc_2018     99 land cover polygons, same WFS
#   burnt_areas  1 fire, 2020-07-31, 26 ha, EFFIS -- the only one the public
#                endpoint serves within 20 km
#
# Geometries are simplified to a 10 m tolerance, which keeps 99.89% of the
# mapped area and is well below the 25 m working grid of the article. That is
# what brings the file from 5.0 MB to 1.2 MB. It is a packaging decision, not
# an analytical one: refetch without simplification for real work.
#
# NOT included: fire weather. The CEMS historical product needs a personal
# Copernicus token, which the brief forbids this package from handling, so the
# article generates a synthetic FWI series and labels it as the one invented
# ingredient.

library(sf)
library(firexpovulnR)

stopifnot("run from the package root" = file.exists("DESCRIPTION"))

WFS <- "https://data.geopf.fr/wfs/ows"
TOLERANCE <- 10          # metres, well under the 25 m working grid
BUFFER <- 1500           # metres of margin around commune + fire
OUT <- file.path("inst", "extdata", "couchey.gpkg")

# --- the commune ------------------------------------------------------------
# Queried by name: the INSEE code is exactly the thing that was wrong in the
# fixture this example is modelled on, so it is read back rather than assumed.
commune_url <- paste0(
  WFS, "?service=WFS&version=2.0.0&request=GetFeature",
  "&typename=ADMINEXPRESS-COG.2021:commune",
  "&outputformat=application/json&count=5",
  "&cql_filter=", utils::URLencode("nom='Couchey'", reserved = TRUE)
)
commune <- st_transform(st_read(commune_url, quiet = TRUE), 2154)
stopifnot("expected exactly one Couchey" = nrow(commune) == 1L,
          "unexpected INSEE code" = commune$insee_com == "21200")
message(sprintf("commune: %s (%s), %.0f ha", commune$nom, commune$insee_com,
                as.numeric(st_area(commune)) / 10000))

# --- the fire ---------------------------------------------------------------
# Searched over a 20 km buffer because EFFIS only maps fires above roughly
# 30 ha and Burgundy has few of them: over the commune alone there is nothing.
around <- st_buffer(st_geometry(commune), 20000)
burnt <- fev_data(fev_fetch_burnt(around, period = c("2016", "2024"),
                                  cache = FALSE))
message(sprintf("fires within 20 km: %d", nrow(burnt)))

# --- the study area ---------------------------------------------------------
study <- st_as_sf(st_as_sfc(st_bbox(
  st_buffer(st_union(st_geometry(burnt), st_geometry(commune)), BUFFER)
)))

# --- fuel -------------------------------------------------------------------
bdforet <- fev_data(fev_fetch_bdforet(study, millesime = "auto",
                                      cache = FALSE))
corine <- fev_data(fev_fetch_corine(study, year = 2018, cache = FALSE))
message(sprintf("bdforet: %d, corine: %d", nrow(bdforet), nrow(corine)))

# --- the vintage, recorded rather than resolved ------------------------------
# Couchey has two BD ORTHO campaigns inside the BD Forêt v2 window, 2010 and
# 2014, at almost exactly half the area each. The article uses that as its
# worked example of an ambiguity the package refuses to settle, so the table
# is written out with the rest.
millesime <- fev_bdforet_millesime(study, cache = FALSE)
print(millesime)

simplify <- function(x) {
  st_make_valid(st_simplify(x, dTolerance = TOLERANCE, preserveTopology = TRUE))
}

unlink(OUT)
st_write(st_sf(nom = commune$nom, insee = commune$insee_com,
               geometry = st_geometry(commune)),
         OUT, layer = "commune", quiet = TRUE)
st_write(st_sf(geometry = st_geometry(study)),
         OUT, layer = "study_area", append = TRUE, quiet = TRUE)
st_write(simplify(bdforet[, c("code_tfv", "tfv_g11", "essence")]),
         OUT, layer = "bdforet_v2", append = TRUE, quiet = TRUE)
st_write(simplify(corine[, "code_18"]),
         OUT, layer = "clc_2018", append = TRUE, quiet = TRUE)
st_write(burnt[, c("FIREDATE", "fire_date", "fire_year", "area_ha")],
         OUT, layer = "burnt_areas", append = TRUE, quiet = TRUE)
st_write(st_sf(as.data.frame(unclass(millesime)),
               geometry = st_sfc(st_point(c(NA_real_, NA_real_)), crs = 2154)),
         OUT, layer = "millesime_candidates", append = TRUE, quiet = TRUE)

message(sprintf("wrote %s (%.0f KB)", OUT, file.size(OUT) / 1024))
print(st_layers(OUT))
