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

# The IGN WFS expects BBOX easting-first for EPSG:2154, contrary to what WFS
# 2.0 prescribes for projected CRS. Requesting the "correct" northing-first
# order returns zero features with HTTP 200 -- a silent empty result, which is
# why the package requests in EPSG:4326 where the axis convention is
# unambiguous. Determined experimentally on 2026-08-15.
.FEV_WFS_REQUEST_CRS <- 4326L
