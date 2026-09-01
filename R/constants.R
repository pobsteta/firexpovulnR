# Every endpoint, layer name and numeric threshold the package ships.
#
# The brief's rule: no URL, dataset name, nomenclature code or numeric
# threshold appears in the code without having been verified at its source. So
# they all live here, each with the date and route of verification, and
# specs/phase2-rapport-faisabilite.md holds the full evidence. Anything a user
# might legitimately disagree with is exposed as an overridable argument
# default rather than buried in a function body.
#
# When a provider changes something, this file and the phase 2 report are the
# two places to update -- not a dozen call sites.

# Service endpoints -----------------------------------------------------------

# Verified 2026-08-15 by real network calls; see specs/phase2-rapport-faisabilite.md.
.FEV_ENDPOINTS <- list(
  # IGN Géoplateforme. Replaces geoservices.ign.fr, which since March 2026
  # returns 301 to cartes.gouv.fr and no longer documents an access route.
  # No authentication required.
  ign_wfs = "https://data.geopf.fr/wfs/ows",

  # EFFIS burnt areas. The layer is ms:modis.ba.poly -- NOT nrt.ba.poly, which
  # exists in WMS only (rendered images) and is not queryable through WFS.
  effis_wfs = "https://maps.effis.emergency.copernicus.eu/effis",

  # CEMS Early Warning Data Store, reached through ecmwfr's "cems" service.
  # Confirmed in ecmwfr 2.0.3 source, R/zzz.R.
  ewds_api = "https://ewds.climate.copernicus.eu/api",

  # Open-Meteo historical archive, re-serving ERA5 and ERA5-Land. NO API KEY,
  # which is the whole reason it is here: the CEMS route needs a personal
  # Copernicus token, and that barrier is why both shipped articles ran on an
  # invented weather series until phase 9.
  #
  # Verified 2026-08-17 by real calls: HTTP 200 without credentials, hourly
  # temperature_2m (C), relative_humidity_2m (%), wind_speed_10m (KM/H -- the
  # unit the FWI system wants) and precipitation (mm); 1991 available, so a WMO
  # 30-year normal is reachable; multi-point requests return a JSON array, one
  # object per point.
  open_meteo = "https://archive-api.open-meteo.com/v1/archive",

  # data.gouv.fr catalogue API, the route to BDIFF. BDIFF publishes no API of
  # its own: its search interface takes URL parameters and is therefore
  # scriptable, but scraping a form is not a contract and there would be no way
  # to tell a changed layout from an empty result.
  #
  # UNLIKE EVERY OTHER ENDPOINT IN THIS LIST, this one was NOT verified by a
  # real call -- the environment it was written in cannot reach data.gouv.fr.
  # fev_sources() reports it separately for that reason, and
  # fev_fetch_bdiff() records endpoint_verified = FALSE on every result it
  # produces through this route.
  data_gouv_api = "https://www.data.gouv.fr/api/1/"
)

# WFS layer names, verified by DescribeFeatureType on 2026-08-15.
.FEV_LAYERS <- list(
  bdforet_v2 = "LANDCOVER.FORESTINVENTORY.V2:formation_vegetale",
  bdforet_v1 = "LANDCOVER.FORESTINVENTORY.V1:resu_bdv1_shape",
  clc_2018   = "LANDCOVER.CLC18_FR:clc18_fr",
  clc_2012   = "LANDCOVER.CLC12_FR:clc12_fr",
  clc_2006   = "LANDCOVER.CLC06_FR:clc06_fr",
  clc_2000   = "LANDCOVER.CLC00_FR:clc00_fr",
  clc_1990   = "LANDCOVER.CLC90_FR:clc90_fr",
  effis_ba   = "ms:modis.ba.poly"
)

# BD ORTHO mosaicking graphs, period-sliced and archived.
#
# These are what makes the BD For\u00eat v2 vintage recoverable at all. IGN's own
# content description (DC_BDFORET_v2.pdf, September 2014, section 2.3) states:
# "La date de validation est celle de la prise de vues de la BD ORTHO servant a
# la production des donnees." The vintage IS the aerial survey date, and the
# mosaicking graph carries that date per polygon in `date_vol`, with the
# department in `dep` and the campaign in `pva`.
#
# Schema verified by DescribeFeatureType on 2026-08-16:
#   dep (string), pva (int), res (int), echelle (int), date_vol (date)
#
# Note the axis order: this WFS wants BBOX easting-first even in EPSG:4326.
# Requesting lat-first returns zero features with HTTP 200 -- the same silent
# empty result documented for the other layers in phase 2.
.FEV_ORTHO_GRAPHS <- list(
  `2000-2005` = "ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2000-2005:graphe_bdortho",
  `2006-2010` = "ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2006-2010:graphe_bdortho",
  `2011-2015` = "ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2011-2015:graphe_bdortho",
  `2016-2020` = "ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2016-2020:graphe_bdortho",
  `2021-2023` = "ORTHOIMAGERY.ORTHOPHOTOS.GRAPHE.2021-2023:graphe_bdortho"
)

# BD For\u00eat v2 was built department by department across this window, stated
# by IGN on cartes.gouv.fr. The content description adds that full metropolitan
# coverage was planned for early 2016, so a survey flown after that cannot have
# fed the initial production of any department -- only an update.
.FEV_BDFORET_V2_WINDOW <- c(2007L, 2018L)

# ESA WorldCover -------------------------------------------------------------
#
# The package's 10 m land cover: a cloud-optimised GeoTIFF on a public bucket,
# so the window an analysis needs can be read over HTTP without downloading a
# tile and without an account.
#
# Verified 2026-08-18, and the last of these from the product file itself:
#   - bucket and path pattern: real listing of the v200/2021/map prefix;
#   - 3 x 3 degree tiles in EPSG:4326, named by their SOUTH-WEST corner --
#     N42E006 was read and its extent is exactly 6-9 E, 42-45 N;
#   - uint8, and NODATA IS 0: the file's own colour table gives value 0 an
#     alpha of 0, and Digital Earth Africa's specification states it outright;
#   - the eleven class codes were confirmed against the colour table EMBEDDED IN
#     THE RASTER, every one of the eleven RGB triplets matching the published
#     legend. That is verification from the data rather than from a document
#     about the data.
.FEV_WORLDCOVER_BUCKET <-
  "https://esa-worldcover.s3.eu-central-1.amazonaws.com"

# v100 is the 2020 map, v200 the 2021 one. They are separate products rather
# than a time series: the producers warn against differencing them for change
# detection, because method changes dominate real change.
.FEV_WORLDCOVER_VERSIONS <- list(
  `2020` = list(version = "v100", accuracy_pct = 74.4, margin_pct = 0.1),
  `2021` = list(version = "v200", accuracy_pct = 76.7, margin_pct = 0.5)
)

.FEV_WORLDCOVER_TILE_DEG <- 3L
.FEV_WORLDCOVER_NODATA <- 0L

# Minimum mapping unit per source, with whether the source claims COMPLETE
# coverage of its extent. Both matter for repairing rasterisation gaps.
#
# The reasoning: a source cannot represent an object smaller than its own minimum
# mapping unit. So a hole smaller than the MMU, inside the extent of a source that
# claims complete coverage, cannot be a real land-cover unit -- it is a
# sub-cell topological gap left by rasterising polygons that share a boundary.
# Above the MMU the hole may be genuine and must stay empty.
#
# This is what makes fev_fuel_fill_gaps() a repair rather than a guess, and why
# the threshold is a property of the data rather than a tuning knob.
#
# Verified on the shipped extracts 2026-08-17: the smallest CORINE polygon is
# 24.92 ha (Couchey) and 24.93 ha (Maures), against a specified 25 ha -- so the
# figure below is not merely documented, it is observed. The largest residual gap
# was 0.25 ha, a hundredfold smaller.
#
# `grid_driver` records whether a source is one the working grid is chosen FOR.
# BD Forêt v2 and WorldCover can be primary, so asking for a cell finer than their
# own mapped width wastes work and is worth saying. CORINE cannot: it exists here
# to fill what the primary leaves empty, which means it must be rasterised onto
# whatever grid the primary chose. Warning that 25 m is finer than CORINE's 100 m
# width would fire on the package's own normal workflow and be wrong about it --
# matching the primary's grid is mandatory, not waste.
#
# `native` records whether the source is a POLYGON coverage or already a raster,
# and it is not a detail: rasterisation slivers are an artefact of the vector
# path. A natively raster source has no shared polygon boundary to fall between,
# so it has no slivers to repair -- and, symmetrically, any hole it does carry is
# real. Its smallest representable object is one pixel, so no hole can ever be
# below its minimum mapping unit. Both facts point the same way: never fill.
#
# That is a different reason from BD Foret's, and fev_fuel_fill_gaps() says which
# one applies rather than collapsing the two into one message.
#
#   CORINE Land Cover: MMU 25 ha, minimum width 100 m, complete coverage of the
#     EEA area. Copernicus Land Monitoring Service product specification.
#   BD Foret v2: MMU 0.5 ha, minimum mapped width 20 m -- but it maps FORMATIONS
#     VEGETALES ONLY, so its silence means "not forest", which is information
#     rather than a gap. Never used to justify a fill.
#   ESA WorldCover: a 10 m RASTER from Sentinel-1 and Sentinel-2, 11 classes,
#     complete coverage, EPSG:4326. No MMU applies -- see `native` above.
.FEV_FUEL_MMU <- list(
  bdforet_v2   = list(mmu_ha = 0.5, min_width_m = 20, complete = FALSE,
                      native = "vector", grid_driver = TRUE),
  clc          = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  clc_1990     = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  clc_2000     = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  clc_2006     = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  clc_2012     = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  clc_2018     = list(mmu_ha = 25,  min_width_m = 100, complete = TRUE,
                      native = "vector", grid_driver = FALSE),
  worldcover_2020 = list(mmu_ha = NA_real_, min_width_m = 10, complete = TRUE,
                         native = "raster", grid_driver = TRUE),
  worldcover_2021 = list(mmu_ha = NA_real_, min_width_m = 10, complete = TRUE,
                         native = "raster", grid_driver = TRUE),
  lidarhd      = list(mmu_ha = NA_real_, min_width_m = NA_real_, complete = FALSE,
                      native = "raster", grid_driver = FALSE),
  custom       = list(mmu_ha = NA_real_, min_width_m = NA_real_, complete = FALSE,
                      native = NA_character_, grid_driver = FALSE)
)

# LiDAR HD, verified 2026-08-17 by GetCapabilities, DescribeFeatureType and real
# GetFeature requests. See specs/phase8-rapport-lidar.md.
#
# The `dalle` layer is what makes an availability check possible before any
# download: it carries one feature per 1 km tile, with the download `url`, the
# `timestamp`, and `id_chantier` identifying the acquisition block -- the
# per-block vintage the brief asks for.
#
# Coverage is genuinely partial. On 2026-08-17: 210 blocks and 505 294 tiles
# nationally, 1 016 tiles over the Maures, and ZERO over Couchey. An empty
# result is a legitimate answer here, which is exactly why the axis-order trap
# matters more than elsewhere -- a lat-first BBOX also returns zero.
.FEV_LIDARHD_LAYERS <- list(
  points_dalle = "IGNF_NUAGES-DE-POINTS-LIDAR-HD:dalle",
  points_bloc  = "IGNF_NUAGES-DE-POINTS-LIDAR-HD:bloc",
  metadata     = "IGNF_LIDAR-HD_METADONNEE:metadata",
  mnt_dalle    = "IGNF_MNT-LIDAR-HD:dalle",
  mns_dalle    = "IGNF_MNS-LIDAR-HD:dalle",
  mnh_dalle    = "IGNF_MNH-LIDAR-HD:dalle"
)

# Tiles are 1 km squares in Lambert-93, delivered as Cloud Optimized Point
# Cloud. COPC is octree-indexed and readable by HTTP range request, so an
# extent can be read without pulling the whole tile -- which matters when one
# tile runs 120 to 260 MB (measured on two Maures tiles, 2026-08-17) and the
# Maures need five hundred of them.
.FEV_LIDARHD_TILE_M <- 1000L

# Canonical output of lidarforfuel::fCBDprofile_fuelmetrics(), read from the
# body of the function on 2026-08-17 and confirmed by running it on a synthetic
# cloud: 25 named metrics then 150 bulk-density layers, 175 bands in total.
#
# THE UPSTREAM README IS WRONG. It states "173 bands, the first 23 being
# metrics". Trusting it would read the profile from band 24 and silently take
# Cover_4 and Cover_6 for bulk density values, shifting the whole profile by
# two. Nothing in this package indexes these bands positionally; it names them.
.FEV_LIDAR_METRICS <- c(
  "Profil_Type", "Profil_Type_L", "threshold", "Height", "CBH", "FSG",
  "Top_Fuel", "H_Bush", "continuity", "VCI_PAD", "VCI_lidr", "entropy_lidr",
  "PAI_tot", "CBD_max", "CFL", "TFL", "MFL", "FL_1_3", "GSFL", "FL_0_1",
  "FMA", "date", "Cover", "Cover_4", "Cover_6"
)
.FEV_LIDAR_CBD_LAYERS <- 150L

# Every metric is -1 when the computation does not complete -- not NA. Left as
# it comes, that yields negative crown base heights and negative fuel loads,
# which pass any naive plausibility check. Converted on read.
.FEV_LIDAR_NULL_VALUE <- -1

#' Data source registry
#'
#' Returns the endpoints and layer names the package contacts, so they can be
#' inspected without reading the source, and overridden when a provider moves
#' something.
#'
#' All values were verified on 2026-08-15 by real network calls, **except**
#' those named in `unverified`. See `specs/phase2-rapport-faisabilite.md` in the
#' repository for the evidence behind each verified one.
#'
#' @section One endpoint is not verified:
#' `data_gouv_api`, the route [fev_fetch_bdiff()] uses to reach BDIFF, was
#' written without ever being called: the environment it was added in has no
#' egress to data.gouv.fr. Listing it beside the others without saying so would
#' make the whole registry mean less, so it is named in `unverified` and every
#' result obtained through it carries `endpoint_verified = FALSE`.
#'
#' @return A named list with `endpoints`, `layers`, `verified` (the date the
#'   rest were confirmed) and `unverified` (the endpoints that were not).
#'
#' @examples
#' fev_sources()$endpoints$ign_wfs
#' fev_sources()$layers$bdforet_v2
#' fev_sources()$unverified
#'
#' @export
fev_sources <- function() {
  list(endpoints = .FEV_ENDPOINTS, layers = .FEV_LAYERS,
       verified = "2026-08-15", unverified = .FEV_UNVERIFIED_ENDPOINTS)
}

# Scientific thresholds -------------------------------------------------------

#' Fire danger classes for the Fire Weather Index
#'
#' The six classes a Fire Weather Index value is mapped into, under one of two
#' published schemes. Both are shipped because they disagree by a factor of
#' three, and which one you use changes what your maps say.
#'
#' @section The two schemes disagree, and that is worth knowing:
#' | Class | EFFIS | caliver / Vitolo et al. 2018 |
#' |---|---|---|
#' | Very Low | — | < 2 |
#' | Low | < 11.2 | 2–5 |
#' | Moderate | 11.2–21.3 | 5–10 |
#' | High | 21.3–38.0 | 10–19 |
#' | Very High | 38.0–50.0 | 19–33 |
#' | Extreme | 50.0–70.0 | ≥ 33 |
#' | Very Extreme | > 70.0 | — |
#'
#' They are not two estimates of one quantity. The EFFIS breaks are
#' operational forecast thresholds for a European-scale warning service, tuned
#' so that the top classes stay rare enough to be actionable. The caliver
#' breaks were **derived from a reanalysis record** — the median of yearly 98th
#' percentiles over ERA-Interim 1980–2016, April to October, put through the
#' Canadian intensity relation — and describe the distribution of that record.
#'
#' An FWI of 40 is *Very High* under EFFIS and comfortably *Extreme* under
#' caliver. Say which you used.
#'
#' @section On the missing "very low" EFFIS class:
#' A threshold of `5.2` for a "Very Low" EFFIS class circulates widely in the
#' literature and on third-party sites. **It does not appear on the current
#' EFFIS page**, which defines six classes starting at *Low*. It is not added
#' here on the grounds that it is common — pass your own `breaks` if you need
#' it, and say so in your methods.
#'
#' @section On using absolute breaks at all:
#' These are service thresholds and record statistics, not physical constants.
#' The point of [fev_fwi_percentile()] is that raw FWI breaks mean different
#' things in different climates: an FWI of 25 is exceptional in Brittany and
#' ordinary in the Var. Prefer percentile ranks for cross-regional comparison,
#' and [fev_fwi_thresholds()] to derive breaks from your own record rather than
#' import someone else's.
#'
#' @param scheme `"effis"` (default) or `"caliver_europe"`. Ignored when
#'   `breaks` is given.
#' @param breaks Numeric vector of the five interior class boundaries,
#'   overriding `scheme`. [fev_fwi_thresholds()] returns one.
#' @param labels Character vector of six class labels.
#'
#' @return A data frame with columns `class`, `lower`, `upper`, and a `scheme`
#'   attribute.
#'
#' @source
#' EFFIS, *Fire Danger Forecast*,
#' <https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/fire-danger-forecast>,
#' verified 2026-08-15. The "Very Extreme" class was introduced in June 2021 to
#' discriminate within the large areas classified *Extreme* around the
#' Mediterranean in summer.
#'
#' Vitolo, C., Di Giuseppe, F., D'Andrea, M. (2018), *Caliver: An R package for
#' CALIbration and VERification of forest fire gridded model outputs*, PLoS ONE
#' 13(1): e0189419. \doi{10.1371/journal.pone.0189419}. European thresholds
#' `2, 5, 10, 19, 33` read from the paper on 2026-08-16.
#'
#' @examples
#' fev_fwi_classes()
#' fev_fwi_classes("caliver_europe")
#'
#' @export
fev_fwi_classes <- function(scheme = c("effis", "caliver_europe"),
                            breaks = NULL, labels = NULL) {
  scheme <- match.arg(scheme)
  preset <- switch(
    scheme,
    effis = list(
      breaks = c(11.2, 21.3, 38.0, 50.0, 70.0),
      labels = c("Low", "Moderate", "High", "Very High", "Extreme",
                 "Very Extreme")
    ),
    caliver_europe = list(
      breaks = c(2, 5, 10, 19, 33),
      labels = c("Very Low", "Low", "Moderate", "High", "Very High", "Extreme")
    )
  )
  breaks <- breaks %||% preset$breaks
  labels <- labels %||% preset$labels

  if (length(breaks) != length(labels) - 1L) {
    fev_abort(c(
      "{.arg labels} must have exactly one more element than {.arg breaks}.",
      x = "Got {length(breaks)} break{?s} and {length(labels)} label{?s}."
    ))
  }
  if (is.unsorted(breaks, strictly = TRUE)) {
    fev_abort("{.arg breaks} must be strictly increasing.")
  }
  structure(
    data.frame(
      class = factor(labels, levels = labels),
      lower = c(-Inf, breaks),
      upper = c(breaks, Inf),
      stringsAsFactors = FALSE
    ),
    scheme = scheme
  )
}

#' Fire exposure transmission distances
#'
#' Default radii for the focal exposure metrics, with the source of each and
#' the process it stands for.
#'
#' @section Where these come from:
#' The three distances are the ones the exposure literature uses throughout:
#' 30 m for radiant heat, 100 m for short-range embers, 500 m for long-range
#' embers. They originate in Beverly et al. (2010), derived on four Alberta
#' communities, and are carried forward unchanged in Beverly et al. (2021),
#' which is the landscape-scale formulation this package implements.
#'
#' Beverly et al. (2021) is paywalled and **has not been read directly**. The
#' distances above were instead verified on 2026-08-16 against the reference
#' documentation of `fireexposuR` 1.2.0 — an rOpenSci peer-reviewed package
#' written by the same group — which states them explicitly and cites both
#' papers. That is a secondary source, and it is named as one.
#'
#' @section On transposing them to Mediterranean fuels:
#' The brief that governs this package assumed these radii were unvalidated
#' outside boreal and coniferous Canadian fuels. That is no longer quite true,
#' and the change is worth stating precisely.
#'
#' Khan et al. (2025) applied the metric to mainland Portugal over 1995–2018 on
#' a 100 m grid and validated it against burned area in five fire years:
#' roughly 80% of burned area fell in sites with exposure of 80% or more, and
#' the authors conclude the Canadian metric "aligned well with wildfires
#' modulated by Portuguese climate and vegetation". So the **metric**
#' transposes to an Iberian Mediterranean-Atlantic context.
#'
#' What that paper does not settle is the **radius**: its abstract states the
#' grid resolution but not the transmission distance used, and it was read at
#' abstract level only. Nor does Portugal — maritime pine, eucalyptus, Atlantic
#' shrubland — stand in for holm oak, garrigue and maquis. Treat 500 m as a
#' defensible starting point with one Mediterranean validation behind it, not
#' as a calibrated value for the Var. [fev_exposure()] says so on first use.
#'
#' @section What is still not sourced:
#' No radius **per fuel type** is shipped. Beverly et al. (2021) is reported to
#' define hazardous fuel by conifer content, but the criterion was not read at
#' its source, so nothing is derived from it here. Do not infer per-fuel-type
#' distances from the three values below.
#'
#' @return A data frame with columns `type`, `min_m`, `max_m`, `process`,
#'   `source`.
#'
#' @seealso [fev_exposure()], which consumes these.
#'
#' @source
#' Beverly, J.L., Bothwell, P., Conner, J.C.R., Herd, E.P.K. (2010). Assessing
#' the exposure of the built environment to potential ignition sources
#' generated from vegetative fuel. *International Journal of Wildland Fire*
#' 19(3): 299-313. \doi{10.1071/WF09071}
#'
#' Beverly, J.L., McLoughlin, N., Chapman, E. (2021). A simple metric of
#' landscape fire exposure. *Landscape Ecology* 36: 785-801. Not read directly;
#' distances verified through the `fireexposuR` 1.2.0 reference documentation
#' on 2026-08-16.
#'
#' Khan, S.I., Colaço, M.C., Sequeira, A.C., Rego, F.C., Beverly, J.L. (2025).
#' Validating a landscape metric to map fire exposure to hazardous fuels in
#' Portugal. *Natural Hazards* 121: 16273-16295.
#' \doi{10.1007/s11069-025-07424-8}. Read at abstract level on 2026-08-16.
#'
#' @examples
#' fev_exposure_radii()
#'
#' @export
fev_exposure_radii <- function() {
  data.frame(
    type    = c("radiant", "ember_short", "ember"),
    min_m   = c(0.1, 0.1, 100.1),
    max_m   = c(30, 100, 500),
    process = c("radiant heat", "short-range embers", "long-range embers"),
    source  = c(
      rep("Beverly et al. 2010 (Alberta); carried forward in Beverly et al. 2021", 2L),
      "Beverly et al. 2010/2021; validated in Portugal by Khan et al. 2025"
    ),
    stringsAsFactors = FALSE
  )
}

#' Directional vulnerability defaults
#'
#' Parameters of the directional assessment of Beverly and Forbes (2023):
#' radial transects drawn outward from a value, each split into three segments,
#' and judged viable where they intersect enough high-exposure ground.
#'
#' @section These two thresholds are empirical, not conventional:
#' `thresh_exp = 0.6` comes from the observation that fires burned
#' preferentially where exposure exceeded 60%. `thresh_viable = 0.8` comes from
#' observed burned pathways, whose average intersection with pre-fire
#' high-exposure patches was 80%. Both were measured on Canadian landscapes.
#' Unlike the fuel availability weights of [fev_fuel_weights()], they are
#' sourced — they are simply sourced from somewhere else.
#'
#' @return A named list of the defaults.
#'
#' @source
#' Beverly, J.L., Forbes, A.M. (2023). Assessing directional vulnerability to
#' wildfire. *Natural Hazards* 117: 831-849. Not read directly; parameters and
#' their empirical justification verified against the `fireexposuR` 1.2.0
#' reference documentation on 2026-08-16.
#'
#' @examples
#' fev_directional_defaults()
#'
#' @export
fev_directional_defaults <- function() {
  list(
    seg_lengths   = c(5000, 5000, 5000),
    interval      = 1,
    thresh_exp    = 0.6,
    thresh_viable = 0.8,
    source        = "Beverly & Forbes 2023 (Natural Hazards 117:831-849)"
  )
}

#' Default fuel availability weights
#'
#' A continuous weight in `[0, 1]` per structural fuel type, used by
#' [fev_fuel_availability()] to turn a class layer into a graded one.
#'
#' @section These numbers are not sourced, and that is the point of this page:
#' Unlike [fev_fwi_classes()] and [fev_exposure_radii()], **nothing here comes
#' from a publication or a service**. No fuel-availability weighting for BD
#' Forêt or CORINE classes was verified at a source during phase 2, and none is
#' invented in the tables. These are a convention: an ordering the package can
#' defend qualitatively — Mediterranean shrubland above closed conifer above
#' closed broadleaf, worked cropland at zero — with the actual numbers chosen
#' to be round rather than measured.
#'
#' Treat them as a starting point you are expected to replace. Whatever you
#' pass to [fev_fuel_availability()] is written into the provenance record, so
#' a reader can see which numbers produced your results. If you keep these,
#' say so in your methods, and say that they are conventional.
#'
#' @section Consistency with the burnable mask:
#' A fuel type whose classes are non-burnable in the shipped lookups carries a
#' weight of exactly 0, so [fev_fuel_availability()] and [fev_fuel_binary()]
#' cannot contradict each other. If you override one, check the other.
#'
#' @param weights Optional named numeric vector overriding some or all of the
#'   defaults. Names must be values of [fev_fuel_types()].
#' @param quiet Suppress the warning that these values are conventional. Use
#'   it only once you have made that clear elsewhere.
#'
#' @return A named numeric vector, one weight per fuel type.
#'
#' @seealso [fev_fuel_availability()], [fev_fuel_types()].
#'
#' @examples
#' fev_fuel_weights(quiet = TRUE)
#'
#' # Down-weight closed broadleaf for a study where it is largely beech.
#' fev_fuel_weights(c(broadleaf_closed = 0.4), quiet = TRUE)
#'
#' @export
fev_fuel_weights <- function(weights = NULL, quiet = FALSE) {
  base <- c(
    shrubland           = 1.00,
    conifer_closed      = 0.95,
    sclerophyll_closed  = 0.95,
    conifer_open        = 0.90,
    transitional_shrub  = 0.90,
    mixed_closed        = 0.80,
    mixed_open          = 0.80,
    grassland           = 0.70,
    burnt_regrowth      = 0.70,
    broadleaf_open      = 0.65,
    broadleaf_closed    = 0.60,
    unstocked           = 0.60,
    agroforestry        = 0.50,
    mosaic_agri_natural = 0.35,
    sparse_vegetation   = 0.30,
    poplar_plantation   = 0.30,
    urban_vegetation    = 0.25,
    cropland            = 0.00,
    non_fuel            = 0.00
  )

  if (!is.null(weights)) {
    if (is.null(names(weights)) || any(!nzchar(names(weights)))) {
      fev_abort("{.arg weights} must be a named numeric vector.")
    }
    unknown <- setdiff(names(weights), names(base))
    if (length(unknown)) {
      fev_abort(c(
        "Unknown fuel type{?s} in {.arg weights}: {.val {unknown}}.",
        i = "See {.fn fev_fuel_types} for the accepted names."
      ))
    }
    if (any(weights < 0 | weights > 1, na.rm = TRUE)) {
      fev_abort("{.arg weights} must lie in {.val {c(0, 1)}}.")
    }
    base[names(weights)] <- weights
  }

  if (!isTRUE(quiet)) {
    fev_warn(c(
      "Fuel availability weights are a package convention, not a sourced \\
       parameter.",
      i = "No weighting of BD For\u00eat or CORINE classes was found at a \\
           verifiable source. The ordering is defensible; the numbers are \\
           round, not measured.",
      i = "Override them, or state in your methods that you kept the \\
           defaults. They are recorded in the provenance either way.",
      i = "Silence this with {.code quiet = TRUE}."
    ), class = "fev_unsourced_default")
  }

  base
}

# Provider quirks the code must handle ----------------------------------------

# EFFIS ships a .prj declaring GEOGCS["GCS_unknown", DATUM["D_WGS_1984",...]],
# so sf::st_crs() reads "unknown" although the coordinates are plain WGS84.
# The CRS is therefore forced, and the operation logged in provenance -- never
# applied silently. Verified by downloading and reading the shapefile on
# 2026-08-15.
.FEV_EFFIS_CRS <- 4326L

# Earliest FIREDATE observed on the public EFFIS endpoint (Var sample,
# 2026-08-15). The workflow in the brief asks for 2006 onward; the public
# service does not serve it. Anything earlier requires the EFFIS data request
# form. Used to warn with a number rather than a vague caveat.
.FEV_EFFIS_MIN_YEAR <- 2016L

# Endpoints in .FEV_ENDPOINTS that were NOT confirmed by a real call. Kept as
# data rather than as a comment so that fev_sources() can report it and a test
# can assert it -- a caveat that only lives in a comment is one nobody reads.
.FEV_UNVERIFIED_ENDPOINTS <- c("data_gouv_api")

# Folding accented letters onto their ASCII base, keyed by Unicode code point.
#
# Needed to compare CSV headers -- "Date de premiere alerte" as published,
# accents and all -- without depending on the session locale. Every obvious
# route is locale-dependent and CI runs under C:
#
#   iconv(to = "ASCII//TRANSLIT")  returns "premi?re"
#   chartr("\u00e8", "e", x)       errors, "'old' is longer than 'new'": it
#                                  treats a UTF-8 string as bytes
#   c("\u00e8" = "e")              is worse than either, because it looks like
#                                  it works: under a non-UTF-8 locale R turns
#                                  the escape into the seven-character text
#                                  <U+00E8> at PARSE time, so the table silently
#                                  matches nothing
#
# Keying on the integer code point sidesteps all three, and keeps this file
# pure ASCII into the bargain. Letters only: everything else non-alphanumeric
# is collapsed to an underscore by the caller.
.FEV_ACCENT_FOLD <- c(
  "224" = "a", "225" = "a", "226" = "a", "227" = "a", "228" = "a", "229" = "a",
  "231" = "c", "232" = "e", "233" = "e", "234" = "e", "235" = "e", "236" = "i",
  "237" = "i", "238" = "i", "239" = "i", "241" = "n", "242" = "o", "243" = "o",
  "244" = "o", "245" = "o", "246" = "o", "249" = "u", "250" = "u", "251" = "u",
  "252" = "u", "253" = "y", "255" = "y",
  "192" = "A", "193" = "A", "194" = "A", "195" = "A", "196" = "A", "197" = "A",
  "199" = "C", "200" = "E", "201" = "E", "202" = "E", "203" = "E", "204" = "I",
  "205" = "I", "206" = "I", "207" = "I", "209" = "N", "210" = "O", "211" = "O",
  "212" = "O", "213" = "O", "214" = "O", "217" = "U", "218" = "U", "219" = "U",
  "220" = "U", "221" = "Y",
  "198" = "AE", "223" = "ss", "230" = "ae", "338" = "OE", "339" = "oe"
)

# BDIFF -----------------------------------------------------------------------

# data.gouv.fr slug of the BDIFF dataset. Read from the published dataset URL on
# 2026-08-31; the dataset itself was not downloaded (no egress).
.FEV_BDIFF_DATAGOUV_SLUG <-
  "base-de-donnees-sur-les-incendies-de-forets-en-france-bdiff"

# BDIFF centralises the whole country from 2006. Mediterranean departments
# reach further back through the Promethee records merged into it in early 2023,
# so this is the national floor, not an absolute one. Used to warn with a number
# rather than a vague caveat, exactly as .FEV_EFFIS_MIN_YEAR is.
.FEV_BDIFF_MIN_YEAR <- 2006L

# Fiches for campaign year Y are validated by the deconcentrated services
# between December Y and April Y+1, then published and passed to EFFIS. So year
# Y becomes consolidated during month 5 of Y+1, and anything after that is
# provisional. Read from the BDIFF help pages on 2026-08-31.
.FEV_BDIFF_CONSOLIDATION_MONTH <- 5L

# Date formats an export can carry. The BDIFF interface serves ISO; the slash
# variants cover a file that has been through a spreadsheet, which is how most
# of them arrive.
.FEV_BDIFF_DATE_FORMATS <- c("%Y-%m-%d", "%d/%m/%Y", "%Y/%m/%d", "%d-%m-%Y")

# Plausibility bounds for the area columns, in the units the file declares.
# Not thresholds on the science -- a guard against the one silent error that
# scales every area by 10 000. A median declared fire is of the order of a
# hectare, i.e. ~1e4 m2: a median below 50 cannot be square metres, and one
# above 5000 cannot be hectares. Deliberately loose; they exist to catch a unit
# swap, not to judge a distribution.
.FEV_BDIFF_AREA_SANITY <- list(m2_min = 50, ha_max = 5000)

# Column names that carry an INSEE commune code in the layers people actually
# have: ADMIN EXPRESS uses INSEE_COM, the IGN WFS and most open-data extracts
# use code_insee, and a hand-built layer uses whatever its author chose.
# Compared after the same normalisation the CSV headers get.
.FEV_BDIFF_COMMUNE_KEYS <- c("insee_com", "code_insee", "insee", "code_commune",
                             "com_code", "codgeo", "code")

# Above this ratio between the equivalent diameter of the median commune and
# the cell size, fev_fire_occurrence() warns that the grid is finer than the
# observation. 4 is deliberately low: a communal count on cells four times
# smaller than the commune already reads as structure that is not there, and
# the realistic case is far worse -- a 25 m cell inside a 15 km2 commune is a
# ratio near 170. It is a reporting threshold, not a scientific one, and the
# ratio itself goes into the provenance whether or not the warning fires.
.FEV_OCC_SCALE_WARN <- 4

# The IGN WFS expects BBOX easting-first for EPSG:2154, contrary to what WFS
# 2.0 prescribes for projected CRS. Requesting the "correct" northing-first
# order returns zero features with HTTP 200 -- a silent empty result, which is
# why the package requests in EPSG:4326 where the axis convention is
# unambiguous. Determined experimentally on 2026-08-15.
.FEV_WFS_REQUEST_CRS <- 4326L


# Which source wins a pixel when two of them map it -------------------------
#
# `fev_fuel_merge(hierarchy = "auto")` reads this instead of trusting argument
# order. Higher wins. Equal or unknown ranks fall back to argument order, which
# is the behaviour every earlier version had.
#
# The ordering below was a judgement when it was written. It is now MEASURED,
# and the measurement contradicts it.
#
# Method: the three sources put on the same 25 m grid over the two Maures LiDAR
# plots -- resolution deliberately held constant, so this compares thematic
# content per class and nothing else -- then each confronted with the LiDAR by
# fev_fuel_profile(). Share of variance in the measured metric explained by
# class membership, 2026-08-18:
#
#     source            classes  H_Bush  FL_0_1  FL_1_3  Cover  PAI_tot
#     bdforet_v2              6    18.2    15.0     8.2   43.0     15.1
#     clc_2018                3     8.8     4.7     0.6   25.0      5.3
#     worldcover_2021         5     4.0     8.4     5.2    7.8      8.2
#
# BD Foret wins every metric, and it is the OLDEST of the three -- a 2014
# vintage, predating the 2021 fire -- so recency does not explain the gap.
# Thematic depth does: species and crown cover are real information about
# structure, and a single "Tree cover" class is not.
#
# The ranking below FOLLOWS that measurement: BD Foret decides the class, and
# WorldCover fills what it leaves unmapped. It was the other way round in 0.19.0
# and 0.20.0, on a judgement made before the figures existed.
#
# What the measurement deliberately holds constant is exactly what WorldCover is
# for: 10 m instead of 25, and a 2021 vintage everywhere instead of 2008-2018 in
# France only. Ranking BD Foret first therefore buys thematic depth and gives up
# resolution and recency -- a real trade, now made with the numbers in hand. For
# a study outside France, or one where the vintage matters more than the species,
# pass hierarchy explicitly at the call site.
#
# It costs less than it used to: since fev_fuel_attach() takes a categorical
# source, whichever loses still travels alongside instead of being discarded.
#
# Two caveats on the figures: two plots of one massif, 566 cells; and the class
# counts differ (6, 3, 5), which mechanically favours the richer nomenclature --
# though 6 against 5 does not explain a factor of four.
.FEV_FUEL_PRIORITY <- c(
  bdforet_v2      = 40L,
  worldcover_2021 = 30L,
  worldcover_2020 = 30L,
  clc             = 10L,
  clc_2018        = 10L,
  clc_2012        = 10L,
  clc_2006        = 10L,
  clc_2000        = 10L,
  clc_1990        = 10L
)
