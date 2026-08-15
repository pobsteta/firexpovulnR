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
  ewds_api = "https://ewds.climate.copernicus.eu/api"
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

#' Data source registry
#'
#' Returns the endpoints and layer names the package contacts, so they can be
#' inspected without reading the source, and overridden when a provider moves
#' something.
#'
#' All values were verified on 2026-08-15 by real network calls. See
#' `specs/phase2-rapport-faisabilite.md` in the repository for the evidence
#' behind each one.
#'
#' @return A named list with `endpoints` and `layers`.
#'
#' @examples
#' fev_sources()$endpoints$ign_wfs
#' fev_sources()$layers$bdforet_v2
#'
#' @export
fev_sources <- function() {
  list(endpoints = .FEV_ENDPOINTS, layers = .FEV_LAYERS, verified = "2026-08-15")
}

# Scientific thresholds -------------------------------------------------------

#' EFFIS fire danger classes
#'
#' The six danger classes EFFIS maps the Fire Weather Index into, as published
#' on the EFFIS *Fire Danger Forecast* page (verified 2026-08-15).
#'
#' @section On the missing "very low" class:
#' A threshold of `5.2` for a "Very Low" class circulates widely in the
#' literature and on third-party sites. **It does not appear on the current
#' EFFIS page**, which defines six classes starting at *Low*. The default here
#' follows the official page. Do not add the 5.2 break on the grounds that it
#' is common — if you need it, pass your own `breaks`, and say so in your
#' methods.
#'
#' @section On using these at all:
#' These are operational service thresholds calibrated for European-scale
#' forecasting, not physical constants. The whole point of
#' `fev_fwi_percentile()` is that raw FWI breaks mean different things in
#' different climates: an FWI of 25 is exceptional in Brittany and ordinary in
#' the Var. Prefer percentile ranks over these classes for cross-regional
#' comparison.
#'
#' @param breaks Numeric vector of the five interior class boundaries.
#'   Defaults to the EFFIS values.
#' @param labels Character vector of six class labels.
#'
#' @return A data frame with columns `class`, `lower`, `upper`.
#'
#' @source
#' EFFIS, *Fire Danger Forecast*,
#' <https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/fire-danger-forecast>.
#' The "Very Extreme" class was introduced in June 2021 to discriminate within
#' the large areas classified *Extreme* around the Mediterranean in summer.
#'
#' @examples
#' fev_fwi_classes()
#'
#' @export
fev_fwi_classes <- function(breaks = c(11.2, 21.3, 38.0, 50.0, 70.0),
                            labels = c("Low", "Moderate", "High",
                                       "Very High", "Extreme", "Very Extreme")) {
  if (length(breaks) != length(labels) - 1L) {
    fev_abort(c(
      "{.arg labels} must have exactly one more element than {.arg breaks}.",
      x = "Got {length(breaks)} break{?s} and {length(labels)} label{?s}."
    ))
  }
  if (is.unsorted(breaks, strictly = TRUE)) {
    fev_abort("{.arg breaks} must be strictly increasing.")
  }
  data.frame(
    class = factor(labels, levels = labels),
    lower = c(-Inf, breaks),
    upper = c(breaks, Inf),
    stringsAsFactors = FALSE
  )
}

#' Fire exposure transmission distances
#'
#' Default radii for the focal exposure metrics, with the source of each.
#'
#' @section These are Canadian values, and that matters:
#' The distances come from Beverly et al. (2010), derived on four communities
#' in Alberta — boreal and coniferous fuels. Their transposition to holm oak,
#' garrigue or maquis is **not established**. Ember transport distance depends
#' on firebrand mass, plume dynamics and canopy structure, none of which are
#' comparable between a black spruce stand and a Mediterranean shrubland.
#'
#' Use them as a documented starting point, not as a validated parameter. If
#' your study area is Mediterranean, either justify them explicitly or
#' recalibrate against local burnt-area data. `fev_exposure()` emits a warning
#' on first use for exactly this reason.
#'
#' @section What is not sourced here:
#' Beverly et al. (2021), *A simple metric of landscape fire exposure*
#' (Landscape Ecology), defines transmission distances per fuel type. That
#' article is behind a paywall and **has not been read**, so no per-fuel-type
#' radii are shipped. Do not infer them from the 2010 values.
#'
#' @return A data frame with columns `type`, `min_m`, `max_m`, `process`,
#'   `source`.
#'
#' @source
#' Beverly, J.L., Bothwell, P., Conner, J.C.R., Herd, E.P.K. (2010).
#' Assessing the exposure of the built environment to potential ignition
#' sources generated from vegetative fuel. *International Journal of Wildland
#' Fire* 19(3): 299-313. \doi{10.1071/WF09071}
#'
#' Cross-check values from `fireexposuR` 1.2.0 defaults (`fire_exp(t_dist =
#' 500)`), read from the installed package on 2026-08-15.
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
    source  = rep("Beverly et al. 2010 (Alberta, boreal/coniferous fuels)", 3L),
    stringsAsFactors = FALSE
  )
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

# The IGN WFS expects BBOX easting-first for EPSG:2154, contrary to what WFS
# 2.0 prescribes for projected CRS. Requesting the "correct" northing-first
# order returns zero features with HTTP 200 -- a silent empty result, which is
# why the package requests in EPSG:4326 where the axis convention is
# unambiguous. Determined experimentally on 2026-08-15.
.FEV_WFS_REQUEST_CRS <- 4326L
