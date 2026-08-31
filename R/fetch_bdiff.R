# BDIFF: where fires START, which is the half of the hazard the package never
# had.
#
# Everything acquired so far says where fire WENT -- EFFIS perimeters, dNBR
# severity, SUFOSAT disturbance. The CCTP definition the package works to, and
# the standard one, has two terms: the probability that a fire IGNITES and that
# it SPREADS. fev_danger_index() combines fuel, exposure and weather, all three
# of which are spread. Nothing in the package has ever carried an ignition.
#
# BDIFF is the national record of French forest and vegetation fires since 2006,
# hosted by IGN and fed by declaration from DDT, SDIS and the deconcentrated
# services under the coordination of the ministries for forests and the
# interior. Promethee -- the Mediterranean base -- was merged into it in early
# 2023, so there is now one base rather than two.
#
# Two properties make it worth a connector rather than a note in a vignette:
#
#   NO AREA THRESHOLD. A fiche is filed whatever the size. EFFIS, being remote
#   sensing, sees roughly 30 ha and up. On a territory of emerging risk --
#   Bourgogne-Franche-Comte is the case in point -- EFFIS returns a handful of
#   events and an AUC computed on them means nothing, while BDIFF returns
#   hundreds.
#
#   AREAS SPLIT BY VEGETATION TYPE. Forest, other wooded land, and the rest.
#   Nothing else in the package can separate an agricultural fire from a forest
#   fire, and the two are not the same phenomenon.
#
# And one property that has to be stated every time rather than buried: the
# entry is DECLARATIVE and the base itself says exhaustivity is not guaranteed.
# The bias is almost certainly spatially structured -- some departments file
# better than others -- which for an occurrence map is far worse than noise. A
# commune with no recorded fire is not a commune with no fire. That goes in the
# provenance on every call and in a warning once per session.

#' Fetch BDIFF fire records (France, 2006 onward)
#'
#' Reads the *Base de Donnees sur les Incendies de Forets en France*: one record
#' per declared fire, with the commune it started in, its date, the area it ran
#' through split by vegetation type, and its cause when known.
#'
#' @section What this brings that nothing else in the package does:
#' [fev_fetch_burnt()] gives perimeters, from remote sensing, from roughly 2016,
#' and only for fires large enough to be seen from orbit. BDIFF is declarative
#' and has **no area threshold at all**, so it is the only source here that can
#' answer "how often does a fire start in this commune". That is the ignition
#' term of the hazard, and the package has never had it.
#'
#' It is also the only source that separates burnt area by vegetation type, so
#' agricultural and non-forest vegetation fires can be told apart from forest
#' fires rather than pooled.
#'
#' @section Geolocation is the commune of departure, not a perimeter:
#' BDIFF records the **commune where the fire started**, not where it went and
#' not a contour. Passing `communes` joins the commune polygons and returns an
#' `sf`; the geometry is then a commune, and a 3 ha fire carries the shape of
#' the 40 km2 commune it started in.
#'
#' The consequence is not cosmetic. You can build an occurrence density per
#' commune from this. You cannot build a 50 m occurrence raster from it, and
#' anything that reads like one is an artefact of the join. For perimeters, use
#' [fev_fetch_burnt()] and accept its size threshold, or derive them from
#' [fev_fetch_severity()]. The two sources are complementary, and neither
#' substitutes for the other.
#'
#' @section Exhaustivity is not guaranteed, and the gap is not random:
#' Entry is collaborative. BDIFF states that the base may contain imprecision
#' and lack exhaustivity despite verification. Nothing here can correct that,
#' and the failure mode worth naming is that the under-reporting is very
#' probably **spatially structured**: departments differ in how completely they
#' file. For a map of occurrence that is worse than random noise, because it
#' looks like signal. **A commune with no recorded fire is not a commune with no
#' fire.**
#'
#' The caveat is warned once per session and written into the provenance record
#' on every call.
#'
#' @section Consolidation runs a year behind:
#' Fiches for campaign year `Y` are validated by the deconcentrated services
#' between December `Y` and April `Y+1`, and only then published and passed to
#' EFFIS. So the current year, and the previous one until roughly May, are not
#' consolidated. This function compares what you asked for against what can be
#' consolidated today and warns with the years rather than a vague caveat.
#'
#' @section Two acquisition routes, and only one of them is verified:
#' `file` reads a CSV exported from the BDIFF search interface. This is the
#' route the package tests and the one to prefer.
#'
#' Without `file`, the function resolves the dataset on **data.gouv.fr** through
#' its public API and downloads a CSV resource. BDIFF publishes no API of its
#' own -- no WFS, no documented REST -- so this is the only programmatic route
#' that rests on a stable contract rather than on scraping a search form.
#'
#' **This remote route has not been exercised against the live service.** Every
#' endpoint in [fev_sources()] was verified by a real call on 2026-08-15; this
#' one was not, because the environment it was written in cannot reach
#' `data.gouv.fr`. It is marked `endpoint_verified = FALSE` in the source record
#' and warns once per session. Treat a result obtained through it as unverified
#' provenance until someone has run it and confirmed the resource it picked.
#'
#' @section Column names are a lookup, not a constant:
#' The CSV headers are a publication choice of the producer and they move. The
#' mapping from headers to the columns this function returns is
#' [fev_bdiff_columns()] — a default with documented candidates, entirely
#' overridable, like every other imported table in the package. When a required
#' column cannot be matched the error lists the headers actually present, so the
#' fix is one `columns` argument away rather than a reading of the source.
#'
#' @param aoi Optional area of interest to clip to: `sf`, `sfc`, `bbox`,
#'   `SpatVector` or `SpatRaster`. Requires `communes`, since without geometry
#'   there is nothing to clip.
#' @param period Two-element vector giving the first and last year, e.g.
#'   `c(2006, 2025)`. `NULL` keeps everything.
#' @param departements Character vector of department codes to keep, e.g.
#'   `c("21", "39", "2A")`. Compared as strings, so `"01"` and `"1"` both work.
#'   `NULL` keeps everything.
#' @param communes Optional `sf` of commune polygons carrying an INSEE code, to
#'   geolocate the records. Without it the result is a plain data frame.
#' @param communes_key Name of the INSEE code column in `communes`. `NULL`
#'   auto-detects among the usual names and says which it chose.
#' @param file Path to a CSV exported from the BDIFF interface. The verified
#'   route.
#' @param resource Title or URL of the data.gouv.fr resource to download,
#'   overriding the automatic choice. Ignored when `file` is given.
#' @param columns Header-to-column mapping; see [fev_bdiff_columns()].
#' @param area_units Units the area columns are published in: `"m2"` (the
#'   default, and what the BDIFF export declares) or `"ha"`. A plausibility
#'   check warns when the values do not look like the declared unit.
#' @param crs_work EPSG code for the returned geometry. Default `2154`. Ignored
#'   when `communes` is absent.
#' @param cache Use the on-disk cache.
#'
#' @return A [fev_source]. Its data is a data frame with one row per fire —
#'   `fire_id`, `fire_date`, `fire_year`, `insee`, `commune`, `dep`, `area_ha`,
#'   `area_forest_ha`, `area_other_wooded_ha`, `area_other_ha`, `cause` — or an
#'   `sf` of commune polygons when `communes` is supplied.
#'
#' @seealso [fev_fetch_burnt()] for perimeters, [fev_bdiff_columns()] for the
#'   header mapping, [fev_validate()] which scores a risk surface.
#'
#' @source
#' BDIFF, *Base de Donnees sur les Incendies de Forets en France*, hosted by
#' IGN for the ministries in charge of forests and the interior:
#' <https://bdiff.agriculture.gouv.fr/>. Coverage from 2006; Promethee (the
#' Mediterranean base) merged into it in early 2023. Consolidation, absence of
#' an area threshold and the exhaustivity caveat are stated on the base's own
#' help pages, read 2026-08-31.
#'
#' @examples
#' \dontrun{
#' # The verified route: export a CSV from the BDIFF interface first.
#' fires <- fev_fetch_bdiff(
#'   file = "bdiff_bfc_2006_2025.csv",
#'   period = c(2006, 2025),
#'   departements = c("21", "25", "39", "58", "70", "71", "89", "90")
#' )
#' fev_source_info(fires)$n_features
#'
#' # With commune polygons, the result is an sf ready for a density.
#' com <- sf::st_read("admin_express_communes.gpkg")
#' fires <- fev_fetch_bdiff(file = "bdiff_bfc.csv", communes = com)
#' }
#'
#' @export
fev_fetch_bdiff <- function(aoi = NULL,
                            period = NULL,
                            departements = NULL,
                            communes = NULL,
                            communes_key = NULL,
                            file = NULL,
                            resource = NULL,
                            columns = fev_bdiff_columns(),
                            area_units = c("m2", "ha"),
                            crs_work = 2154,
                            cache = TRUE) {
  area_units <- match.arg(area_units)

  if (!is.null(aoi) && is.null(communes)) {
    fev_abort(c(
      "{.arg aoi} needs {.arg communes}.",
      x = "BDIFF records carry a commune code, not a geometry.",
      i = "Pass commune polygons through {.arg communes} to geolocate them, \\
           or filter with {.arg departements} instead."
    ), class = "fev_bdiff_no_geometry")
  }

  got <- if (!is.null(file)) {
    fev_bdiff_from_file(file)
  } else {
    fev_bdiff_from_datagouv(resource, cache)
  }

  raw <- got$data
  mapping <- fev_bdiff_match_columns(raw, columns)
  fires <- fev_bdiff_prepare(raw, mapping, area_units)
  n_all <- nrow(fires)

  avail <- range(fires$fire_year, na.rm = TRUE)
  fires <- fev_bdiff_filter_period(fires, period, avail)
  fires <- fev_bdiff_filter_departements(fires, departements)

  if (!nrow(fires)) {
    fev_abort(c(
      "No fire record left after filtering.",
      i = "{n_all} record{?s} were read, covering {avail[1]}-{avail[2]}.",
      i = "Widen {.arg period}, or check {.arg departements}."
    ), class = "fev_empty_result")
  }

  geoloc <- "none (commune code only, no geometry attached)"
  if (!is.null(communes)) {
    joined <- fev_bdiff_attach_communes(fires, communes, communes_key, crs_work)
    fires <- joined$data
    geoloc <- joined$note
    if (!is.null(aoi)) {
      fires <- fev_bdiff_clip(fires, aoi, crs_work)
    }
  }

  returned <- range(fires$fire_year, na.rm = TRUE)
  fev_bdiff_warn_consolidation(returned)

  src <- got$source
  src$period_requested <- if (is.null(period)) NA_character_ else
    paste(fev_period_years(period), collapse = "-")
  src$period_returned <- paste(returned, collapse = "-")
  src$departements <- if (is.null(departements)) NA_character_ else
    paste(sort(unique(as.character(departements))), collapse = ",")
  src$n_features <- nrow(fires)
  src$area_units_declared <- area_units
  src$columns_matched <- vapply(mapping, function(m) m %||% NA_character_,
                                character(1))
  src$geolocation <- geoloc
  src$exhaustivity <- paste(
    "declarative entry; BDIFF states exhaustivity is not guaranteed.",
    "Under-reporting is probably spatially structured: a commune with no",
    "record is not a commune with no fire."
  )

  fev_once("bdiff_declarative", fev_warn(c(
    "BDIFF is filled by declaration, and its exhaustivity is not guaranteed.",
    x = "A commune with no recorded fire is not a commune with no fire.",
    i = "Under-reporting almost certainly varies between departments, so an \\
         occurrence map built on this carries a structured bias, not noise.",
    i = "Shown once per session; recorded in the provenance every time."
  ), class = "fev_declarative_source"))

  total <- round(sum(fires$area_ha, na.rm = TRUE))
  fev_inform("Got {nrow(fires)} fire record{?s}, {returned[1]}-{returned[2]}, \\
              {total} ha total.")
  structure(list(data = fires, source = src), class = "fev_source")
}


#' Which CSV header feeds which column
#'
#' The mapping [fev_fetch_bdiff()] uses to turn BDIFF's published headers into
#' the columns it returns. Each entry names one output column and the headers
#' that may carry it, in preference order.
#'
#' @section Why this is a lookup and not a constant:
#' The headers are a publication choice of the producer, not part of any
#' standard, and the export has been through more than one wording. Hard-coding
#' them would make the connector fail on the next revision with a message about
#' a missing column rather than about a renamed one. Override the entry that
#' moved and the connector keeps working.
#'
#' Headers are compared after normalisation: lower-cased, accents stripped,
#' every run of non-alphanumeric characters collapsed to a single underscore.
#' So `"Surface parcourue (m2)"` and `"surface_parcourue_m2"` are the same
#' candidate and you do not have to reproduce the punctuation.
#'
#' @section What is required and what is not:
#' `insee` is required, and so is at least one of `fire_date` and `fire_year`:
#' without a commune code there is nothing to geolocate, and without a date
#' there is no period to filter on. Everything else is optional and comes back
#' as `NA` when the export does not carry it.
#'
#' @section These candidates are expected, not verified:
#' They were written from BDIFF's documented export rather than read off a live
#' download, for the same reason the remote route is unverified — see
#' [fev_fetch_bdiff()]. The design consequence is deliberate: a wrong candidate
#' produces an error that lists the headers actually present, not a silently
#' empty column.
#'
#' @param ... Named overrides, e.g. `cause = "origine_du_feu"`. Each replaces
#'   the candidates for that column.
#'
#' @return A named list of character vectors, one per output column.
#'
#' @seealso [fev_fetch_bdiff()].
#'
#' @examples
#' names(fev_bdiff_columns())
#' fev_bdiff_columns()$area_total
#' # An export that renamed one field:
#' fev_bdiff_columns(cause = "origine")$cause
#'
#' @export
fev_bdiff_columns <- function(...) {
  base <- list(
    fire_id = c("numero", "numero_de_l_incendie", "id", "identifiant"),
    fire_date = c("date_de_premiere_alerte", "date_de_premiere_alerte_",
                  "date_d_alerte", "date_alerte", "date"),
    fire_year = c("annee", "annee_de_l_incendie"),
    insee = c("code_insee", "code_insee_commune", "insee", "insee_com",
              "code_commune"),
    commune = c("commune", "nom_de_la_commune", "nom_commune"),
    dep = c("departement", "code_departement", "dep", "code_du_departement"),
    area_total = c("surface_parcourue_m2", "surface_parcourue",
                   "surface_totale_m2", "surface_totale"),
    area_forest = c("surface_foret_m2", "surface_foret", "surface_boisee_m2",
                    "surface_boisee"),
    area_other_wooded = c("surface_autres_terres_boisees_m2",
                          "surface_autres_terres_boisees",
                          "surface_maquis_garrigues_m2",
                          "surface_maquis_garrigues"),
    area_other = c("surface_autres_terres_m2", "surface_autres_terres",
                   "surface_non_boisee_m2", "surface_non_boisee"),
    cause = c("nature", "cause", "cause_du_feu", "origine")
  )
  over <- list(...)
  if (length(over)) {
    unknown <- setdiff(names(over), names(base))
    if (length(unknown)) {
      fev_abort(c(
        "{.val {unknown}} {?is not a column/are not columns} of the BDIFF \\
         mapping.",
        i = "Available: {.val {names(base)}}."
      ))
    }
    base[names(over)] <- lapply(over, as.character)
  }
  base
}


# Acquisition -----------------------------------------------------------------

#' Read a CSV exported from the BDIFF interface
#'
#' Separator and encoding are both determined rather than assumed. The export is
#' semicolon-separated in the French convention, but a file that has been
#' through a spreadsheet comes back comma-separated often enough that guessing
#' from the header beats hard-coding either.
#'
#' @noRd
fev_bdiff_from_file <- function(file) {
  if (!file.exists(file)) {
    fev_abort(c(
      "{.file {file}} does not exist.",
      i = "Export a CSV from the BDIFF search interface at \\
           {.url https://bdiff.agriculture.gouv.fr/incendies}, then pass it \\
           here."
    ))
  }
  fev_inform("Reading BDIFF records from {.file {file}} ...")
  got <- fev_bdiff_read_csv(file)
  df <- got$data
  list(
    data = df,
    source = list(
      dataset            = "bdiff",
      provider           = "BDIFF / IGN for MASA and Interior (local export)",
      licence            = NA_character_,
      licence_from       = "non etablie : la licence n'a pas ete lue chez le producteur",
      endpoint           = normalizePath(file),
      endpoint_verified  = TRUE,
      query              = list(file = basename(file),
                                encoding = got$encoding, sep = got$sep),
      millesime          = NA,
      downloaded_at      = fev_now(),
      crs_native         = "none (commune code, no geometry)",
      n_features         = nrow(df),
      import             = "local file"
    )
  )
}

#' Resolve the dataset on data.gouv.fr and download a CSV resource
#'
#' BDIFF publishes no API. The search interface takes URL parameters and is
#' therefore scriptable, but scraping a form is not a contract: it breaks at the
#' first redesign and there would be no way to tell a changed layout from an
#' empty result. data.gouv.fr's `/api/1/datasets/{slug}/` is a contract, so that
#' is the route, and the resource actually chosen goes into the record.
#'
#' @noRd
fev_bdiff_from_datagouv <- function(resource, cache) {
  key <- fev_cache_key("bdiff", list(resource = resource %||% "auto"))
  if (isTRUE(cache) && fev_cache_hit(key, ext = "rds")) {
    hit <- fev_cache_read(key, ext = "rds")
    fev_inform("BDIFF records served from cache.")
    return(list(data = hit$data, source = hit$source))
  }

  fev_require("httr2", "download BDIFF from data.gouv.fr")
  fev_require("jsonlite", "read the data.gouv.fr catalogue")

  fev_once("bdiff_unverified_endpoint", fev_warn(c(
    "The data.gouv.fr route to BDIFF has not been exercised against the live \\
     service.",
    x = "Unlike every endpoint in {.fn fev_sources}, it was never confirmed by \\
         a real call.",
    i = "Prefer {.arg file} with an export from the BDIFF interface, which is \\
         the tested route.",
    i = "If you use this one, check the resource named in \\
         {.code fev_source_info(x)$resource} before citing the result."
  ), class = "fev_unverified_endpoint"))

  base <- .FEV_ENDPOINTS$data_gouv_api
  slug <- .FEV_BDIFF_DATAGOUV_SLUG
  url <- paste0(base, "datasets/", slug, "/")

  fev_inform("Resolving the BDIFF dataset on {.url {url}} ...")
  meta <- tryCatch({
    req <- httr2::request(url)
    req <- httr2::req_timeout(req, 120)
    httr2::resp_body_json(httr2::req_perform(req))
  }, error = function(e) {
    fev_abort(c(
      "Could not reach the data.gouv.fr catalogue.",
      x = "{conditionMessage(e)}",
      i = "Check network egress to {.url www.data.gouv.fr}, or pass an \\
           exported CSV through {.arg file}."
    ), class = "fev_fetch_failed")
  })

  chosen <- fev_bdiff_pick_resource(meta$resources, resource)

  fev_inform("Downloading {.val {chosen$title}} ...")
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  resp <- tryCatch({
    req <- httr2::request(chosen$url)
    req <- httr2::req_timeout(req, 600)
    httr2::req_perform(req, path = tmp)
  }, error = function(e) {
    fev_abort(c(
      "The BDIFF resource download failed.",
      x = "{conditionMessage(e)}"
    ), class = "fev_fetch_failed")
  })
  if (httr2::resp_status(resp) != 200L) {
    fev_abort("data.gouv.fr returned HTTP {httr2::resp_status(resp)}.")
  }

  got <- fev_bdiff_read_csv(tmp)
  df <- got$data
  src <- list(
    dataset           = "bdiff",
    provider          = "BDIFF / IGN for MASA and Interior, via data.gouv.fr",
    licence           = NA_character_,
    licence_from      = "non etablie : la licence n'a pas ete lue chez le producteur",
    endpoint          = url,
    endpoint_verified = FALSE,
    endpoint_note     = paste(
      "route never exercised against the live service;",
      "every other endpoint in fev_sources() was verified 2026-08-15"
    ),
    resource          = chosen$title,
    resource_url      = chosen$url,
    query             = list(slug = slug, resource = chosen$title,
                             encoding = got$encoding, sep = got$sep),
    millesime         = chosen$last_modified %||% NA,
    downloaded_at     = fev_now(),
    crs_native        = "none (commune code, no geometry)",
    n_features        = nrow(df),
    third_party       = TRUE
  )

  if (isTRUE(cache)) {
    fev_cache_write(key, df, src, ext = "rds")
  }
  list(data = df, source = src)
}

#' Choose one CSV resource out of the catalogue entry
#'
#' Refuses to guess when the choice is not obvious: an arbitrary pick among
#' several files is exactly the kind of decision that disappears into a result
#' and cannot be reconstructed later.
#'
#' @noRd
fev_bdiff_pick_resource <- function(resources, wanted) {
  if (!length(resources)) {
    fev_abort(c(
      "The data.gouv.fr entry lists no resource.",
      i = "Pass an exported CSV through {.arg file} instead."
    ), class = "fev_empty_result")
  }
  flat <- lapply(resources, function(r) {
    list(
      title = as.character(r$title %||% r$id %||% "untitled"),
      url = as.character(r$url %||% ""),
      format = tolower(as.character(r$format %||% "")),
      last_modified = as.character(r$last_modified %||% NA)
    )
  })
  flat <- Filter(function(r) nzchar(r$url), flat)

  if (!is.null(wanted)) {
    hit <- Filter(function(r) identical(r$url, wanted) ||
                    identical(r$title, wanted), flat)
    if (!length(hit)) {
      titles <- vapply(flat, function(r) r$title, character(1))
      fev_abort(c(
        "No resource matches {.val {wanted}}.",
        i = "Available: {.val {titles}}."
      ))
    }
    return(hit[[1]])
  }

  csv <- Filter(function(r) r$format == "csv" || grepl("\\.csv$", r$url), flat)
  if (!length(csv)) {
    formats <- unique(vapply(flat, function(r) r$format, character(1)))
    fev_abort(c(
      "The data.gouv.fr entry holds no CSV resource.",
      i = "Formats present: {.val {formats}}.",
      i = "Name one explicitly with {.arg resource}, or use {.arg file}."
    ), class = "fev_empty_result")
  }
  if (length(csv) > 1L) {
    titles <- vapply(csv, function(r) r$title, character(1))
    fev_abort(c(
      "{length(csv)} CSV resources are published, and picking one silently \\
       would put an unrecorded choice into your result.",
      i = "Available: {.val {titles}}.",
      i = "Name the one you want with {.arg resource}."
    ), class = "fev_ambiguous_resource")
  }
  csv[[1]]
}

#' Read a BDIFF CSV without guessing its dialect
#'
#' Everything is read as character. Coercion happens in one place afterwards,
#' where the French decimal comma and the leading zeros of an INSEE code can be
#' handled deliberately -- `read.csv()` would turn `"01004"` into `1004` and
#' silently break every join downstream.
#'
#' The encoding is determined from the bytes and converted explicitly, rather
#' than handed to `read.csv(fileEncoding=)`. That argument re-encodes into the
#' session's native encoding, and under a C locale it does not fail on an
#' accented byte -- it drops the rest of the connection and returns a table with
#' a header and **no rows**. A silent zero-row read of a file that has data in
#' it is the worst available outcome, so the bytes are converted here and the
#' encoding used goes into the record.
#'
#' @noRd
fev_bdiff_read_csv <- function(path) {
  raw <- readLines(path, warn = FALSE)
  if (!length(raw) || !any(nzchar(raw))) {
    fev_abort("{.file {basename(path)}} is empty.")
  }

  # A byte sequence that survives a UTF-8 round trip is UTF-8; one that does not
  # is, in practice, the latin1 a spreadsheet wrote.
  # The BOM is stripped on the BYTES, before any conversion. The tempting
  # sub("^\\ufeff", ...) is not a regex escape TRE understands: it matches
  # nothing and fails silently, so a BOM would ride into the first header and
  # that header would then match no candidate.
  raw[1] <- sub("^\xef\xbb\xbf", "", raw[1], useBytes = TRUE)

  encoding <- if (anyNA(iconv(raw, from = "UTF-8", to = "UTF-8")))
    "latin1" else "UTF-8"
  txt <- iconv(raw, from = encoding, to = "UTF-8")
  txt[is.na(txt)] <- raw[is.na(txt)]

  header <- txt[nzchar(txt)][1]
  n_semi <- lengths(regmatches(header, gregexpr(";", header)))
  n_comma <- lengths(regmatches(header, gregexpr(",", header)))
  sep <- if (n_semi >= n_comma) ";" else ","

  df <- tryCatch(
    utils::read.csv(text = txt, sep = sep, colClasses = "character",
                    check.names = FALSE, stringsAsFactors = FALSE,
                    encoding = "UTF-8", na.strings = c("", "NA")),
    error = function(e) {
      fev_abort(c("Could not read {.file {basename(path)}}.",
                  x = "{conditionMessage(e)}",
                  i = "Read as {.val {encoding}}, separator {.val {sep}}."))
    }
  )
  # read.csv() does not propagate the encoding to the names, and an undeclared
  # header prints as "Ann\\u00e9e" in every error message that lists it.
  names(df) <- `Encoding<-`(names(df), "UTF-8")
  if (!ncol(df) || !nrow(df)) {
    fev_abort(c(
      "{.file {basename(path)}} has a header but no rows.",
      i = "Read as {.val {encoding}}, separator {.val {sep}}, \\
           {ncol(df)} column{?s}.",
      i = "Check the filters used for the export."
    ), class = "fev_empty_result")
  }
  list(data = df, encoding = encoding, sep = sep)
}


# Column matching and typing --------------------------------------------------

#' Fold accented letters onto their ASCII base, without touching the locale
#'
#' Works on code points rather than on bytes or on `iconv()`, because both of
#' those are locale-dependent here and CI runs under C. See
#' `.FEV_ACCENT_FOLD` for what each route does wrong.
#'
#' @noRd
fev_bdiff_fold <- function(x) {
  vapply(as.character(x), function(s) {
    if (is.na(s) || !nzchar(s)) return(s)
    # The bytes are UTF-8 -- the reader converted them -- but read.csv() hands
    # back column names with their encoding "unknown", and utf8ToInt() on an
    # undeclared string reads bytes, not code points: "e" with a grave accent
    # comes back as 0xc3 0xa8 and folds to nothing. Declaring it is the whole
    # fix, and it is safe because we know what we converted.
    if (Encoding(s) == "unknown") Encoding(s) <- "UTF-8"
    cps <- tryCatch(utf8ToInt(s), error = function(e) NA_integer_)
    if (anyNA(cps)) return(s)
    chars <- intToUtf8(cps, multiple = TRUE)
    hit <- match(as.character(cps), names(.FEV_ACCENT_FOLD))
    chars[!is.na(hit)] <- unname(.FEV_ACCENT_FOLD)[hit[!is.na(hit)]]
    # Anything still outside ASCII cannot be folded and would survive into the
    # comparison as bytes; the caller collapses it like any other separator.
    chars[cps > 127L & is.na(hit)] <- "_"
    paste0(chars, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

#' Normalise a header for comparison
#'
#' Accents folded, lower-cased, every run of non-alphanumerics collapsed to one
#' underscore. So `"Surface parcourue (m2)"` and `"surface_parcourue_m2"` are
#' the same candidate, and a `columns` override does not have to reproduce the
#' producer's punctuation.
#'
#' @noRd
fev_bdiff_normalise <- function(x) {
  x <- fev_bdiff_fold(x)
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_+|_+$", "", x)
}

#' Match the mapping against the headers actually present
#'
#' Returns one header name (or NULL) per output column. Fails on the two
#' columns nothing downstream can do without, and lists what was seen -- the
#' message has to be enough to write the `columns` override from, without
#' opening the file.
#'
#' @noRd
fev_bdiff_match_columns <- function(df, columns) {
  if (!is.list(columns) || is.null(names(columns))) {
    fev_abort("{.arg columns} must be a named list; see {.fn fev_bdiff_columns}.")
  }
  present <- names(df)
  norm <- fev_bdiff_normalise(present)

  mapping <- lapply(columns, function(cands) {
    hit <- match(fev_bdiff_normalise(cands), norm)
    hit <- hit[!is.na(hit)]
    if (!length(hit)) NULL else present[hit[1]]
  })
  names(mapping) <- names(columns)

  if (is.null(mapping$insee)) {
    fev_abort(c(
      "No commune code column found in the BDIFF export.",
      i = "Tried: {.val {columns$insee}}.",
      i = "Headers present: {.val {present}}.",
      i = "Override with {.code fev_bdiff_columns(insee = \"<header>\")}."
    ), class = "fev_bdiff_missing_column")
  }
  if (is.null(mapping$fire_date) && is.null(mapping$fire_year)) {
    fev_abort(c(
      "No date and no year column found in the BDIFF export.",
      i = "Tried {.val {columns$fire_date}} and {.val {columns$fire_year}}.",
      i = "Headers present: {.val {present}}.",
      i = "One of the two is needed to filter on a period."
    ), class = "fev_bdiff_missing_column")
  }
  mapping
}

#' Coerce a French-formatted number
#'
#' Thousands separators are spaces (ordinary and non-breaking), the decimal mark
#' is a comma. A dot already present means the field is in the C convention and
#' the comma is then a thousands separator, so the two cases are told apart
#' rather than blindly substituted.
#'
#' @noRd
fev_bdiff_num <- function(x) {
  x <- as.character(x)
  # Everything that is not part of a number goes, rather than naming the
  # separators to strip. A character class holding a literal non-breaking space
  # is a class whose meaning depends on whether the locale makes the string
  # bytes or characters -- the same trap as the accent folding.
  x <- gsub("[^0-9,.eE+-]", "", x)
  has_dot <- grepl(".", x, fixed = TRUE)
  x[has_dot] <- gsub(",", "", x[has_dot], fixed = TRUE)
  x[!has_dot] <- gsub(",", ".", x[!has_dot], fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

#' Zero-pad a code to five characters
#'
#' `formatC(x, width = 5, flag = "0")` is the obvious call and it is wrong here:
#' on a CHARACTER input the zero flag is ignored and it pads with spaces, so
#' "1004" becomes " 1004". That matches nothing, and it matches nothing on both
#' sides of the commune join at once, which is how it survives a smoke test.
#'
#' @noRd
fev_bdiff_pad5 <- function(x) {
  x <- as.character(x)
  short <- !is.na(x) & nchar(x) > 0L & nchar(x) < 5L
  x[short] <- paste0(strrep("0", 5L - nchar(x[short])), x[short])
  x
}

#' Turn the raw character table into the columns the package returns
#' @noRd
fev_bdiff_prepare <- function(df, mapping, area_units) {
  pick <- function(name) {
    col <- mapping[[name]]
    if (is.null(col)) rep(NA_character_, nrow(df)) else as.character(df[[col]])
  }

  insee <- trimws(pick("insee"))
  # INSEE codes are five characters and the leading zero is significant: "01004"
  # is Ain, "1004" is nothing. A spreadsheet round trip drops it, so it is put
  # back rather than left to break the join silently.
  short <- !is.na(insee) & nchar(insee) > 0L & nchar(insee) < 5L
  if (any(short)) {
    n_short <- sum(short)
    insee <- fev_bdiff_pad5(insee)
    fev_inform("Repadded {n_short} commune code{?s} to five characters \\
                (a leading zero had been lost).")
  }

  dates <- fev_bdiff_dates(pick("fire_date"))
  years <- suppressWarnings(as.integer(substr(pick("fire_year"), 1, 4)))
  fire_year <- if (all(is.na(dates))) years else {
    y <- as.integer(format(dates, "%Y"))
    y[is.na(y)] <- years[is.na(y)]
    y
  }
  if (all(is.na(fire_year))) {
    fev_abort(c(
      "No record carries a usable year.",
      i = "Neither the date nor the year column could be parsed.",
      i = "First dates seen: {.val {utils::head(pick('fire_date'), 3)}}."
    ), class = "fev_bdiff_no_dates")
  }

  scale <- if (area_units == "m2") 1e-4 else 1
  areas <- lapply(
    c(area_total = "area_total", area_forest = "area_forest",
      area_other_wooded = "area_other_wooded", area_other = "area_other"),
    function(nm) fev_bdiff_num(pick(nm)) * scale
  )
  fev_bdiff_check_area_units(fev_bdiff_num(pick("area_total")), area_units)

  dep <- trimws(pick("dep"))
  # A department read from a spreadsheet loses its leading zero the same way a
  # commune code does. Two-character codes only: "2A" and "2B" are already two,
  # and the overseas three-digit codes must not be padded.
  dep_short <- !is.na(dep) & nchar(dep) == 1L
  dep[dep_short] <- paste0("0", dep[dep_short])
  # Fall back to the commune code when the export has no department column at
  # all: the first two characters of an INSEE code are the department, except
  # in Corsica where they are "2A"/"2B" in the code itself.
  if (is.null(mapping$dep)) {
    dep <- substr(insee, 1, 2)
  }

  out <- data.frame(
    fire_id              = pick("fire_id"),
    fire_date            = dates,
    fire_year            = fire_year,
    insee                = insee,
    commune              = pick("commune"),
    dep                  = dep,
    area_ha              = areas$area_total,
    area_forest_ha       = areas$area_forest,
    area_other_wooded_ha = areas$area_other_wooded,
    area_other_ha        = areas$area_other,
    cause                = pick("cause"),
    stringsAsFactors     = FALSE
  )
  out[!is.na(out$fire_year), , drop = FALSE]
}

#' Parse the date column across the formats an export can carry
#'
#' An explicit format is required rather than optional: `as.Date()` without one
#' throws on unparseable input instead of returning NA, which would crash here
#' rather than reach the diagnostic the caller needs.
#'
#' @noRd
fev_bdiff_dates <- function(x) {
  raw <- trimws(as.character(x))
  raw[!is.na(raw)] <- substr(raw[!is.na(raw)], 1, 10)
  out <- rep(as.Date(NA), length(raw))
  for (fmt in .FEV_BDIFF_DATE_FORMATS) {
    todo <- is.na(out) & !is.na(raw)
    if (!any(todo)) break
    out[todo] <- as.Date(raw[todo], format = fmt)
  }
  out
}

#' Warn when the areas do not look like the declared unit
#'
#' A fire whose median size reads as 8 000 has been published in square metres
#' whatever the argument says, and getting this wrong scales every area by
#' 10 000 -- silently, and in the direction that makes a study area look
#' catastrophic or trivial.
#'
#' @noRd
fev_bdiff_check_area_units <- function(raw, declared) {
  pos <- raw[is.finite(raw) & raw > 0]
  if (!length(pos)) return(invisible(FALSE))
  med <- stats::median(pos)
  lo <- .FEV_BDIFF_AREA_SANITY$m2_min
  hi <- .FEV_BDIFF_AREA_SANITY$ha_max
  if (declared == "m2" && med < lo) {
    fev_warn(c(
      "Areas are declared in {.val m2} but their median is {round(med, 2)}.",
      x = "That is {round(med / 1e4, 6)} ha per fire, which is not plausible.",
      i = "The export is probably already in hectares: pass \\
           {.code area_units = \"ha\"}."
    ), class = "fev_bdiff_area_units")
    return(invisible(TRUE))
  }
  if (declared == "ha" && med > hi) {
    fev_warn(c(
      "Areas are declared in {.val ha} but their median is {round(med)}.",
      x = "A median fire of {round(med)} ha is not plausible.",
      i = "The export is probably in square metres: pass \\
           {.code area_units = \"m2\"}."
    ), class = "fev_bdiff_area_units")
    return(invisible(TRUE))
  }
  invisible(FALSE)
}


# Filtering, joining, clipping ------------------------------------------------

#' @noRd
fev_bdiff_filter_period <- function(fires, period, avail) {
  if (is.null(period)) return(fires)
  want <- fev_period_years(period)
  if (want[1] < avail[1]) {
    min_year <- .FEV_BDIFF_MIN_YEAR
    gap_end <- min(avail[1] - 1L, want[2])
    fev_warn(c(
      "Requested period starts in {want[1]}, but the earliest record here is \\
       {avail[1]}.",
      x = "{want[1]}-{gap_end} is missing from this extract.",
      i = "BDIFF centralises the whole country from {min_year} onward. \\
           Mediterranean departments reach further back through the Promethee \\
           records merged into it in 2023.",
      i = "Widen the export rather than the argument: the gap is in the file, \\
           not in the filter."
    ), class = "fev_period_truncated")
  }
  keep <- !is.na(fires$fire_year) &
    fires$fire_year >= want[1] & fires$fire_year <= want[2]
  fires[keep, , drop = FALSE]
}

#' @noRd
fev_bdiff_filter_departements <- function(fires, departements) {
  if (is.null(departements)) return(fires)
  want <- toupper(trimws(as.character(departements)))
  short <- nchar(want) == 1L
  want[short] <- paste0("0", want[short])
  missing <- setdiff(want, toupper(unique(fires$dep)))
  if (length(missing)) {
    fev_warn(c(
      "No record for department{?s} {.val {missing}}.",
      i = "Present in this extract: {.val {sort(unique(fires$dep))}}."
    ), class = "fev_bdiff_absent_departement")
  }
  fires[toupper(fires$dep) %in% want, , drop = FALSE]
}

#' Attach commune polygons, and say how many records failed to match
#'
#' Communes merge and split. A fire recorded in 2007 under a code that a 2024
#' commune layer no longer holds cannot be placed, and the honest answer is a
#' count rather than a quiet inner join: on an occurrence map, records dropped
#' in the join look exactly like communes that never burnt.
#'
#' @noRd
fev_bdiff_attach_communes <- function(fires, communes, key, crs_work) {
  if (!inherits(communes, "sf")) {
    fev_abort(c(
      "{.arg communes} must be an {.cls sf}, not {.cls {class(communes)[1]}}.",
      i = "Commune polygons carrying an INSEE code, e.g. from ADMIN EXPRESS."
    ))
  }
  if (!fev_crs_usable(communes)) {
    fev_abort(c(
      "{.arg communes} carries no usable CRS.",
      i = "Set it explicitly; the package will not guess one."
    ))
  }

  key <- fev_bdiff_commune_key(communes, key)
  communes <- sf::st_transform(communes, crs_work)
  codes <- fev_bdiff_pad5(trimws(as.character(communes[[key]])))

  dup <- sum(duplicated(codes))
  if (dup) {
    fev_warn(c(
      "{.arg communes} holds {dup} duplicate code{?s} in {.field {key}}.",
      i = "The first polygon for each code is used.",
      i = "A commune layer with repeated codes is usually a multi-part \\
           geometry that needs dissolving first."
    ), class = "fev_bdiff_duplicate_communes")
    communes <- communes[!duplicated(codes), , drop = FALSE]
    codes <- codes[!duplicated(codes)]
  }

  idx <- match(fires$insee, codes)
  n_missing <- sum(is.na(idx))
  if (n_missing) {
    lost <- sort(unique(fires$insee[is.na(idx)]))
    fev_warn(c(
      "{n_missing} of {nrow(fires)} record{?s} ({round(100 * n_missing / nrow(fires), 1)}%) \\
       match no commune and were dropped.",
      x = "On an occurrence map a dropped record is indistinguishable from a \\
           commune that never burnt.",
      i = "{length(lost)} unmatched code{?s}, e.g. {.val {utils::head(lost, 5)}}.",
      i = "Communes merge and split: a commune layer more recent than the \\
           fires will not carry every historic code."
    ), class = "fev_bdiff_unmatched_communes")
  }

  keep <- !is.na(idx)
  out <- sf::st_sf(
    fires[keep, , drop = FALSE],
    geometry = sf::st_geometry(communes)[idx[keep]]
  )
  note <- sprintf(
    "commune of departure (commune polygon, key %s); %d of %d records matched",
    key, sum(keep), nrow(fires)
  )
  list(data = out, note = note)
}

#' Find the INSEE code column of a commune layer
#' @noRd
fev_bdiff_commune_key <- function(communes, key) {
  if (!is.null(key)) {
    if (!key %in% names(communes)) {
      fev_abort(c(
        "{.arg communes} has no column {.field {key}}.",
        i = "Available: {.val {setdiff(names(communes), attr(communes, 'sf_column'))}}."
      ))
    }
    return(key)
  }
  cands <- .FEV_BDIFF_COMMUNE_KEYS
  norm <- fev_bdiff_normalise(names(communes))
  hit <- match(cands, norm)
  hit <- hit[!is.na(hit)]
  if (!length(hit)) {
    fev_abort(c(
      "Could not find an INSEE code column in {.arg communes}.",
      i = "Tried: {.val {cands}}.",
      i = "Columns present: {.val {setdiff(names(communes), attr(communes, 'sf_column'))}}.",
      i = "Name it with {.arg communes_key}."
    ), class = "fev_bdiff_no_commune_key")
  }
  chosen <- names(communes)[hit[1]]
  fev_inform("Using {.field {chosen}} as the commune code in {.arg communes}.")
  chosen
}

#' @noRd
fev_bdiff_clip <- function(fires, aoi, crs_work) {
  aoi <- fev_as_aoi(aoi, crs = crs_work)
  hit <- lengths(sf::st_intersects(fires, aoi)) > 0
  if (!any(hit)) {
    fev_abort(c(
      "No fire record intersects {.arg aoi}.",
      i = "{nrow(fires)} record{?s} were geolocated before clipping.",
      i = "Check that the AOI and the commune layer describe the same place."
    ), class = "fev_empty_result")
  }
  fires[hit, , drop = FALSE]
}

#' Warn when the requested years cannot be consolidated yet
#'
#' Campaign year Y is validated by the deconcentrated services between December
#' Y and April Y+1, and published after that. Asking for a year inside that
#' window is legitimate, but reading its totals as final is not.
#'
#' @noRd
fev_bdiff_warn_consolidation <- function(returned) {
  today <- Sys.Date()
  month <- as.integer(format(today, "%m"))
  year <- as.integer(format(today, "%Y"))
  last_ok <- if (month >= .FEV_BDIFF_CONSOLIDATION_MONTH) year - 1L else year - 2L
  if (returned[2] <= last_ok) return(invisible(FALSE))

  provisional <- seq(max(returned[1], last_ok + 1L), returned[2])
  n <- length(provisional)
  fev_warn(c(
    # The quantity has to come before the {?}: cli cannot pluralise without one,
    # and fails at format time rather than at write time.
    "{n} campaign{?s} not consolidated yet: {.val {provisional}}.",
    i = "Fiches for year Y are validated between December Y and April Y+1, \\
         then published and passed to EFFIS. The latest consolidated campaign \\
         is {last_ok}.",
    i = "Counts and areas will change. Say so if you report them."
  ), class = "fev_bdiff_provisional")
  invisible(TRUE)
}
