#' @keywords internal
#'
#' @section Design principles:
#' Four rules govern the whole package, and every function is expected to
#' honour them:
#'
#' \describe{
#'   \item{No hard-coded thresholds}{Every radius, class break and lookup
#'     table imported from a publication or an external service is an
#'     argument with a sourced default, fully overridable.}
#'   \item{One reprojection}{The working CRS (`crs_work`, default `2154`) is
#'     that of the primary fuel source. Auxiliary layers are reprojected as
#'     late as possible; the primary source never is.}
#'   \item{Provenance everywhere}{Every [fev_stack()] carries its sources,
#'     vintages, calibration period and the full set of parameters used.
#'     [fev_provenance()] exports the record as YAML.}
#'   \item{Explicit scale changes}{Resampling between kilometric danger and
#'     decametric exposure goes through `fev_align()`, which warns and logs.
#'     There is no implicit alignment anywhere else.}
#' }
#'
#' @section Imported parameters that are not validated for Europe:
#' The package draws defaults from work calibrated outside temperate and
#' Mediterranean Europe. They are usable, but their transposition is not
#' established: exposure radii come from boreal and coniferous Canadian
#' fuels, and FWI danger classes are operational service thresholds rather
#' than physical constants. Neither CORINE nor BD Forêt v2 describes the
#' understorey or the fuel load, although surface spread depends on it
#' directly.
#'
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

# Point-cloud attribute names, declared so R CMD check does not read them as
# undefined globals.
#
# fev_fuel_lidar() builds an expression for lidR::pixel_metrics(), which
# evaluates it inside data.table where these are COLUMNS of the LAS, not
# variables of this package. They are exactly the argument names
# lidarforfuel::fCBDprofile_fuelmetrics() expects, and renaming them to silence
# the note would break the call -- so they are declared instead.
utils::globalVariables(c(
  "X", "Y", "Z", "Zref", "ReturnNumber",
  "Easting", "Northing", "Elevation",
  "LMA", "WD", "gpstime"
))
