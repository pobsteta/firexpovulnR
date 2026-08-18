# Fuel correspondence tables: reading, validating, overriding.
#
# The tables themselves are built and justified in data-raw/build_fuel_lookups.R
# and shipped as CSV in inst/extdata/. Nothing in this file invents a value; it
# reads them, checks their shape, and lets the user substitute their own.

#' The vocabulary of fuel types
#'
#' The closed set of structural fuel types the shipped correspondence tables
#' map onto, with what each one means. Both nomenclatures — BD Forêt v2 TFV
#' and CORINE level 3 — resolve to this single vocabulary, which is what makes
#' a merged layer interpretable when its pixels come from two sources.
#'
#' @section Why structural, and not a fuel model:
#' These types describe stand structure, because structure is what the two
#' databases actually record. They are **not** fuel models: no correspondence
#' to Anderson 13, Scott & Burgan 40 or the Prometheus models is shipped,
#' because none was verified at a source. Deriving a fuel model needs
#' understorey and load information neither database contains — that is the
#' `medfate` extension point, and in the longer run the LiDAR one.
#'
#' @return A data frame with columns `fuel_type` and `description`.
#'
#' @seealso [fev_fuel_lookup()] for the tables that use this vocabulary.
#'
#' @examples
#' fev_fuel_types()
#'
#' @export
fev_fuel_types <- function() {
  data.frame(
    fuel_type = c(
      "sclerophyll_closed", "broadleaf_closed", "conifer_closed",
      "mixed_closed", "broadleaf_open", "conifer_open", "mixed_open",
      "poplar_plantation", "unstocked", "shrubland", "transitional_shrub",
      "grassland", "agroforestry", "mosaic_agri_natural", "sparse_vegetation",
      "burnt_regrowth", "urban_vegetation", "cropland", "non_fuel"
    ),
    description = c(
      "Closed evergreen sclerophyllous forest (holm oak, cork oak)",
      "Closed broadleaf forest, predominantly deciduous",
      "Closed coniferous forest",
      "Closed broadleaf/conifer mixture",
      "Open broadleaf forest, 10-40% tree cover",
      "Open coniferous forest, 10-40% tree cover",
      "Open mixed forest, 10-40% tree cover",
      "Poplar plantation on alluvial ground, managed floor",
      "Forest land with no current tree cover (clearcut, disturbance)",
      "Heath, moor, maquis, garrigue",
      "Regeneration and encroachment shrub, a transient state",
      "Herbaceous formation",
      "Scattered trees over grazed grassland (dehesa, montado)",
      "Agriculture with significant areas of natural vegetation",
      "Under 50% vegetation cover",
      "Burnt at the vintage of the source",
      "Parks, campsites and leisure grounds inside urban fabric",
      "Worked agricultural land",
      "Sealed, mineral, water or ice"
    ),
    stringsAsFactors = FALSE
  )
}

# Required columns of any lookup, shipped or user-supplied. `code`,
# `fuel_type` and `burnable` are what the downstream functions read; the rest
# is what makes the table reviewable, and is filled with NA when a user table
# omits it.
.FEV_LOOKUP_REQUIRED <- c("code", "fuel_type", "burnable")
.FEV_LOOKUP_OPTIONAL <- c("nomenclature", "label", "crown_cover",
                          "confidence", "notes")

#' Fuel correspondence tables
#'
#' Returns the table that maps a land cover nomenclature onto the package's
#' fuel vocabulary: which classes are burnable, and what structural fuel type
#' each one is.
#'
#' @section What is sourced here and what is not:
#' `code` and `label` are the producers' own values, verified at their source
#' (phase 2 report, sections 3 and 7). `crown_cover` is read off the BD Forêt
#' v2 nomenclature itself — *forêt fermée* is above 40% tree cover, *forêt
#' ouverte* between 10 and 40%.
#'
#' `fuel_type` and `burnable` are **this package's reading**, not an imported
#' classification. Every row carries a `confidence` flag (`"clear"` or
#' `"ambiguous"`) and a `notes` sentence stating what the doubt is. 4 of the 32
#' BD Forêt rows and 17 of the 44 CORINE rows are flagged ambiguous — read them
#' before running an analysis you intend to publish.
#'
#' @section The rows most likely to be wrong for you:
#' Agricultural CORINE classes (211, 221, 222, 223, 231, 241, 242) default to
#' `burnable = FALSE`, on the grounds that a worked field neither carries fire
#' nor throws embers for most of the year. Stubble fires, abandoned olive
#' groves and ungrazed pasture all break that assumption. Override the table if
#' your study area sits on a crop-forest interface.
#'
#' CORINE 334 (burnt areas) is burnable at the vintage of the CORINE layer, not
#' at your analysis date — Mediterranean shrubland regrowth is among the most
#' flammable states there is by year five.
#'
#' @param type Nomenclature to load: `"bdforet_v2"`, `"clc"` or `"clcplus"`.
#'   Both land cover tables are vintage-independent, so `"clc_2018"` and
#'   `"clcplus_2023"` resolve to `"clc"` and `"clcplus"`.
#' @param file Optional path to a CSV of your own, replacing the shipped table
#'   entirely. It must have columns `code`, `fuel_type` and `burnable`;
#'   `nomenclature`, `label`, `crown_cover`, `confidence` and `notes` are
#'   filled with `NA` when absent. `fuel_type` values must come from
#'   [fev_fuel_types()].
#'
#' @return A data frame with columns `nomenclature`, `code`, `label`,
#'   `crown_cover`, `fuel_type`, `burnable`, `confidence`, `notes`.
#'
#' @seealso [fev_fuel_types()] for the vocabulary, [fev_fuel_binary()] and
#'   [fev_fuel_type()] for the functions that consume these tables.
#'
#' @source
#' BD Forêt v2 TFV codes and labels: IGN, the 32 posts published by
#' cartes.gouv.fr, cross-checked against the attributes served by the
#' Géoplateforme WFS on 2026-08-15.
#'
#' CORINE level 3 codes and labels: Copernicus Land Monitoring Service,
#' CLC nomenclature guidelines,
#' <https://land.copernicus.eu/content/corine-land-cover-nomenclature-guidelines/html/>,
#' verified 2026-08-16 against the 2019 illustrated guidelines, which agree on
#' all 44 rows.
#'
#' CLCplus Backbone codes and labels: European Environment Agency catalogue
#' record for the 2023 vintage,
#' \doi{10.2909/b0bd43c6-1fa1-4d88-9c45-98b13a95d0b2}, verified 2026-08-18.
#' Nomenclature derived from the EAGLE Land Cover Components.
#'
#' @examples
#' bdf <- fev_fuel_lookup("bdforet_v2")
#' nrow(bdf)
#' bdf[bdf$confidence == "ambiguous", c("code", "label", "notes")]
#'
#' clc <- fev_fuel_lookup("clc")
#' table(clc$fuel_type, clc$burnable)
#'
#' # CLCplus splits what CORINE 311 could not: deciduous from evergreen
#' # broadleaf, which is the sclerophyll distinction the Mediterranean needs.
#' cpl <- fev_fuel_lookup("clcplus")
#' cpl[cpl$code %in% c("3", "4"), c("code", "label", "fuel_type")]
#'
#' @export
fev_fuel_lookup <- function(type = c("bdforet_v2", "clc", "clcplus"),
                            file = NULL) {
  if (!is.null(file)) {
    if (!file.exists(file)) {
      fev_abort("Lookup file {.file {file}} does not exist.")
    }
    tab <- utils::read.csv(file, stringsAsFactors = FALSE,
                           colClasses = "character", encoding = "UTF-8")
    return(fev_lookup_validate(tab, origin = file))
  }

  type <- match.arg(type[1], c(
    "bdforet_v2",
    "clc", paste0("clc_", c(1990, 2000, 2006, 2012, 2018)),
    "clcplus", paste0("clcplus_", c(2018, 2021, 2023))
  ))
  # Neither nomenclature's fuel semantics change with the vintage: CORINE 323 is
  # sclerophyllous vegetation in 1990 as in 2018, and CLCplus class 4 is
  # evergreen broadleaf in 2018 as in 2023. Only the mapped extent does.
  #
  # Order matters here: "clcplus_2023" starts with "clc" too, so the longer stem
  # has to be tested first or every CLCplus request would silently read the
  # CORINE table -- 44 unrelated codes, and not one of them matching.
  stem <- if (startsWith(type, "clcplus")) {
    "clcplus"
  } else if (startsWith(type, "clc")) {
    "clc"
  } else {
    type
  }

  path <- system.file("extdata", paste0("fuel_lookup_", stem, ".csv"),
                      package = "firexpovulnR")
  if (!nzchar(path)) {
    fev_abort(c(
      "No shipped lookup table for {.val {type}}.",
      i = "Rebuild it with {.file data-raw/build_fuel_lookups.R}, or pass \\
           {.arg file}."
    ))
  }
  tab <- utils::read.csv(path, stringsAsFactors = FALSE,
                         colClasses = "character", encoding = "UTF-8")
  fev_lookup_validate(tab, origin = path)
}

#' Check a lookup table's shape and vocabulary
#'
#' Read as character throughout and coerced here, so that a `burnable` column
#' written as `"true"`, `"1"` or `"TRUE"` all mean the same thing rather than
#' silently becoming NA in a user-supplied file.
#'
#' @noRd
fev_lookup_validate <- function(tab, origin = "<supplied>") {
  missing <- setdiff(.FEV_LOOKUP_REQUIRED, names(tab))
  if (length(missing)) {
    fev_abort(c(
      "Lookup table is missing required column{?s} {.field {missing}}.",
      i = "Read from {.file {origin}}. Found: {.field {names(tab)}}.",
      i = "See {.fn fev_fuel_lookup} for the expected schema."
    ), class = "fev_bad_lookup")
  }

  for (col in setdiff(.FEV_LOOKUP_OPTIONAL, names(tab))) {
    tab[[col]] <- NA_character_
  }

  tab$burnable <- fev_as_logical(tab$burnable)
  if (anyNA(tab$burnable)) {
    bad <- unique(tab$code[is.na(tab$burnable)])
    fev_abort(c(
      "{.field burnable} must be readable as TRUE or FALSE for every row.",
      x = "Unreadable for code{?s} {.val {bad}}.",
      i = "Accepted: TRUE/FALSE, true/false, T/F, 1/0, yes/no."
    ), class = "fev_bad_lookup")
  }

  if (anyDuplicated(tab$code)) {
    dup <- unique(tab$code[duplicated(tab$code)])
    fev_abort(c(
      "Lookup codes must be unique.",
      x = "Duplicated: {.val {dup}}.",
      i = "A duplicated code makes the mapping order-dependent."
    ), class = "fev_bad_lookup")
  }

  known <- fev_fuel_types()$fuel_type
  unknown <- setdiff(unique(tab$fuel_type), known)
  if (length(unknown)) {
    fev_abort(c(
      "Unknown fuel type{?s} {.val {unknown}}.",
      i = "The vocabulary is closed so that merged layers stay comparable. \\
           See {.fn fev_fuel_types} for the {length(known)} accepted values."
    ), class = "fev_bad_lookup")
  }

  tab[, c("nomenclature", "code", "label", "crown_cover",
          "fuel_type", "burnable", "confidence", "notes")]
}

#' Coerce the spellings of TRUE/FALSE people actually write in CSVs
#' @noRd
fev_as_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  x <- trimws(tolower(as.character(x)))
  out <- rep(NA, length(x))
  out[x %in% c("true", "t", "1", "yes", "y")] <- TRUE
  out[x %in% c("false", "f", "0", "no", "n")] <- FALSE
  out
}
