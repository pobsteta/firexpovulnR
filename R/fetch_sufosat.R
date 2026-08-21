# SUFOSAT: forest clear-cuts in mainland France, from Sentinel-1 radar.
#
# What it brings the package is a DATE OF DISTURBANCE per pixel at 10 m, which
# is the one thing the fuel layer has never had. BD Foret v2 was built between
# 2007 and 2018 and knows nothing of what was cut afterwards; fev_validate()
# can only measure that lag, never correct it.
#
# The trap, and it is not a small one. SUFOSAT measures a change in radar
# backscatter -- vegetation gone -- and cannot say what removed it. Measured on
# the Maures study area: 2 626 ha detected for 2021, of which **97% fall inside
# the perimeter of the Cannet-des-Maures fire**, median detection day 246
# (3 September), fifteen days after containment. The map calls a severe fire a
# clear-cut, because to a radar it is one.
#
# So `fires` is not an optional refinement. Without it the fuel correction would
# record an incendie as an exploitation, and the difference matters: after a
# fire the stand is dead and standing, after a cut it is gone. This function
# therefore says so loudly rather than letting the caller find out.
#
# One genuinely useful thing falls out of the same property: the 599 ha detected
# INSIDE the 2021 perimeter during 2022 are real cuts -- post-fire salvage
# logging -- a fuel change nothing else in this package would ever see.

.FEV_SUFOSAT_RECORD <- "17253008"
.FEV_SUFOSAT_FILES <- c(
  dates = "forest-clearcuts_mainland-france_sufosat_dates_v3_set25.tif",
  prob  = "forest-clearcuts_mainland-france_sufosat_prob_v3_set25.tif"
)

#' Fetch SUFOSAT forest clear-cuts (10 m, mainland France)
#'
#' Reads the national clear-cut map for an area of interest and decodes it into
#' the year and day of each detected disturbance. Downloaded once from Zenodo
#' and cached; the national file is 254 MB and arrives in under a minute.
#'
#' @section It cannot tell a fire from a cut, and that is measured:
#' The method detects a drop in Sentinel-1 backscatter — vegetation removed —
#' and is blind to the cause. Over the Maures study area it reports 2 626 ha of
#' "clear-cut" for 2021, of which **97% lies inside the perimeter of the
#' Cannet-des-Maures fire**, with a median detection on day 246 (3 September),
#' fifteen days after the fire was contained.
#'
#' Passing `fires` removes those detections. Leaving it `NULL` does not fail —
#' the raw map is a legitimate thing to want — but it warns, because a fuel
#' correction built on it would record a fire as an exploitation. The two are
#' not the same fuel afterwards: a cut removes the stand, a severe fire leaves
#' it dead and standing, which is a different fire hazard entirely.
#'
#' @section What survives the exclusion is worth having:
#' On the Maures, 599 ha are detected **inside** the 2021 fire perimeter during
#' **2022** — post-fire salvage logging. That is a real fuel change, dated, that
#' nothing else in this package can see. Exclude the fire by perimeter and year,
#' not by perimeter alone, if you want to keep it: `fires` masks every year, so
#' pass only the years you mean to remove.
#'
#' @section Accuracy, as the producers report it:
#' Precision 99.4%, recall 80.9%, minimum mapping unit 0.1 ha. The recall is the
#' number to keep in mind: about one cut in five is missed, so an absence of
#' detection is not evidence of no cut.
#'
#' @param aoi Area of interest: `sf`, `sfc`, `bbox`, `SpatVector` or
#'   `SpatRaster`. Must carry a CRS.
#' @param fires Fire perimeters to exclude: a [fev_source] from
#'   [fev_fetch_burnt()], an `sf`, a `SpatVector`, or `NULL`. **Supply them**
#'   unless you want fires counted as cuts.
#' @param years Keep only these detection years, or `NULL` for all.
#' @param min_prob Keep only detections at or above this probability in percent,
#'   or `NULL` to skip it. Downloads a second 82 MB raster.
#' @param crs_work EPSG code to return the raster in. Default `2154`, which is
#'   the product's own projection, so the default does not reproject.
#' @param quiet Suppress the report.
#'
#' @return A [fev_source] holding a `SpatRaster` with `cut_year` and `cut_doy`,
#'   plus `prob` when `min_prob` was used. Cells with no detection are `NA`.
#'
#' @seealso [fev_fetch_burnt()] for the perimeters to exclude,
#'   [fev_fetch_severity()] for the optical counterpart on a single fire.
#'
#' @source
#' SUFOSAT v3.0.1, CESBIO and GlobEO, with ADEME support.
#' \doi{10.5281/zenodo.17253008}, CC-BY 4.0.
#'
#' Verified 2026-08-20 against the data, not the datasheet: 119 159 x 126 813
#' cells at 10 m in EPSG:2154, values `YYDDD` with years 17 to 25 and days 1 to
#' 366. The current Zenodo version is CC-BY 4.0; the superseded one was
#' CC-BY-NC, and the copy catalogued on the THEIA STAC sits on a bucket that
#' refuses anonymous reads — same file, three different answers about how you
#' may get it.
#'
#' @examples
#' \dontrun{
#' zone <- sf::st_read("massif_maures.gpkg", "study_area")
#' feux <- sf::st_read("massif_maures.gpkg", "burnt_areas")
#' coupes <- fev_fetch_sufosat(zone, fires = feux)
#' terra::plot(fev_data(coupes)[["cut_year"]])
#' }
#'
#' @export
fev_fetch_sufosat <- function(aoi,
                              fires = NULL,
                              years = NULL,
                              min_prob = NULL,
                              crs_work = 2154,
                              quiet = FALSE) {
  if (!is.null(min_prob) &&
      (!is.numeric(min_prob) || length(min_prob) != 1L || is.na(min_prob) ||
       min_prob < 0 || min_prob > 100)) {
    fev_abort("{.arg min_prob} must be a single percentage, or NULL.")
  }

  dates_file <- fev_sufosat_file("dates", quiet)
  r <- terra::rast(dates_file)
  v <- terra::vect(fev_as_aoi(aoi, crs = terra::crs(r)))
  r <- terra::crop(r, terra::ext(v))
  if (terra::ncell(r) == 0) {
    fev_abort(c(
      "The area of interest does not overlap the SUFOSAT map.",
      i = "It covers mainland France only."
    ), class = "fev_no_overlap")
  }

  out <- fev_sufosat_decode(r)

  n_raw <- fev_sufosat_count(out[["cut_year"]])

  if (!is.null(min_prob)) {
    p <- terra::crop(terra::rast(fev_sufosat_file("prob", quiet)),
                     terra::ext(v))
    p <- terra::resample(p, out[[1]], method = "near")
    names(p) <- "prob"
    out <- terra::mask(c(out, p), p >= min_prob, maskvalues = c(0, NA))
  }
  n_prob <- fev_sufosat_count(out[["cut_year"]])

  if (!is.null(years)) {
    keep <- out[["cut_year"]] %in% years
    out <- terra::mask(out, keep, maskvalues = c(0, NA))
  }

  n_fire <- 0
  if (!is.null(fires)) {
    fv <- fev_sufosat_fires(fires, terra::crs(out))
    burnt <- terra::rasterize(fv, out[[1]])
    before <- fev_sufosat_count(out[["cut_year"]])
    out <- terra::mask(out, burnt, inverse = TRUE)
    n_fire <- before - fev_sufosat_count(out[["cut_year"]])
  } else {
    fev_warn(c(
      "No fire perimeters given: burnt areas are counted as clear-cuts.",
      i = "The method sees vegetation gone and cannot say what removed it. On \\
           the Maures, 97% of the 2021 detections lie inside a fire perimeter.",
      i = "Pass {.arg fires} -- {.fn fev_fetch_burnt} returns them."
    ), class = "fev_sufosat_fires_included")
  }

  reprojected <- FALSE
  target <- paste0("EPSG:", crs_work)
  if (!terra::same.crs(out, target)) {
    out <- terra::project(out, target, method = "near")
    reprojected <- TRUE
  }

  n_final <- fev_sufosat_count(out[["cut_year"]])
  res_m <- terra::res(out)[1]
  if (!quiet) {
    fev_sufosat_report(out, n_raw, n_prob, n_fire, n_final, res_m,
                       min_prob, years, is.null(fires))
  }

  new_fev_source(
    out,
    dataset   = "sufosat_v3",
    provider  = "CESBIO and GlobEO, with ADEME support (Zenodo, CC-BY 4.0)",
    licence   = "CC-BY-4.0",
    licence_from = "metadonnees du depot Zenodo 10.5281/zenodo.17253008, lues 2026-08-20 ; la version supersedee etait CC-BY-NC-4.0 et la copie cataloguee sur le STAC THEIA refuse la lecture anonyme",
    endpoint  = paste0("https://zenodo.org/records/", .FEV_SUFOSAT_RECORD),
    query     = list(record = .FEV_SUFOSAT_RECORD, version = "v3.0.1",
                     res_m = 10, encoding = "YYDDD",
                     min_prob = min_prob %||% NA,
                     years = if (is.null(years)) NA else paste(years, collapse = ", "),
                     fires_excluded = !is.null(fires),
                     cells_detected = n_final),
    millesime = 2025L,
    version   = "SUFOSAT v3.0.1, 2018-01-01 to 2025-09-01",
    reprojected = reprojected,
    notes = paste0(
      "Radar backscatter change: cannot distinguish a severe fire from a ",
      "clear-cut. On the Maures 97% of 2021 detections fall inside a fire ",
      "perimeter. Precision 99.4%, recall 80.9% as reported by the producers, ",
      "so an absence of detection is not evidence of no cut.",
      if (is.null(fires)) " FIRE PERIMETERS WERE NOT EXCLUDED." else ""
    )
  )
}

#' The national file, downloaded once and kept
#'
#' Zenodo ignores Range requests -- a request for the first kilobyte comes back
#' as the whole file with a 200 -- so there is no windowed read to be had here
#' and the national raster is fetched entire. It is 254 MB and takes under a
#' minute; the alternative would be re-fetching it for every area of interest.
#'
#' @noRd
fev_sufosat_file <- function(which, quiet) {
  fname <- .FEV_SUFOSAT_FILES[[which]]
  dest <- file.path(fev_cache_dir(create = TRUE), fname)
  url <- sprintf("https://zenodo.org/records/%s/files/%s?download=1",
                 .FEV_SUFOSAT_RECORD, fname)

  expected <- fev_lidar_expected_size(url)
  if (file.exists(dest) && !is.na(expected) && file.size(dest) != expected) {
    # Same discipline as the LiDAR tiles: a truncated file that sits in the
    # cache fails identically on every rerun, and a size check is what stops it.
    unlink(dest)
  }
  if (file.exists(dest)) {
    return(dest)
  }

  if (!quiet) {
    fev_inform(c(
      "Downloading the SUFOSAT {which} raster \\
       ({if (is.na(expected)) '?' else round(expected / 1e6)} MB), once.",
      i = "Kept in {.path {fev_cache_dir()}}; later areas read from it."
    ), .envir = environment())
  }
  ok <- tryCatch({
    old <- options(timeout = max(1800, getOption("timeout")))
    on.exit(options(old), add = TRUE)
    utils::download.file(url, dest, quiet = TRUE, mode = "wb")
    file.exists(dest) && (is.na(expected) || file.size(dest) == expected)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) {
    got <- if (file.exists(dest)) file.size(dest) else 0
    unlink(dest)
    fev_abort(c(
      "The SUFOSAT {which} raster could not be downloaded.",
      x = if (is.na(expected)) "The server did not answer." else
        sprintf("Got %.0f of %.0f MB.", got / 1e6, expected / 1e6),
      i = "Check network egress to {.url https://zenodo.org}."
    ), class = "fev_sufosat_unreachable", .envir = environment())
  }
  dest
}

#' Decode the YYDDD encoding into a year and a day
#'
#' Values are `YYDDD`: two digits of year, three of day-of-year. `0` is nodata
#' and must not become year 2000 day 0 -- which is what an unguarded integer
#' division would produce, and it would look like a plausible detection.
#'
#' Verified against the data on 2026-08-20: years 17 to 25, days 1 to 366,
#' consistent with a product covering 2018-01-01 to 2025-09-01.
#'
#' @noRd
fev_sufosat_decode <- function(r) {
  code <- terra::classify(r, cbind(0, NA))
  cut_year <- 2000 + code %/% 1000
  cut_doy <- code %% 1000
  names(cut_year) <- "cut_year"
  names(cut_doy) <- "cut_doy"
  c(cut_year, cut_doy)
}

#' @noRd
fev_sufosat_count <- function(r) {
  as.numeric(terra::global(!is.na(r), "sum", na.rm = TRUE)[1, 1])
}

#' @noRd
fev_sufosat_fires <- function(fires, crs_target) {
  f <- if (inherits(fires, "fev_source")) fires$data else fires
  if (inherits(f, "SpatVector")) {
    f <- sf::st_as_sf(f)
  }
  if (!inherits(f, c("sf", "sfc"))) {
    fev_abort(c(
      "{.arg fires} must be a {.cls fev_source}, {.cls sf} or \\
       {.cls SpatVector}.",
      x = "Got {.cls {class(fires)[1]}}.",
      i = "{.fn fev_fetch_burnt} returns one."
    ), .envir = environment())
  }
  terra::vect(sf::st_transform(sf::st_geometry(f), sf::st_crs(crs_target)))
}

#' @noRd
fev_sufosat_report <- function(out, n_raw, n_prob, n_fire, n_final, res_m,
                               min_prob, years, no_fires) {
  ha <- function(n) signif(n * res_m^2 / 1e4, 4)
  cli::cli_h1("SUFOSAT v3.0.1")
  cli::cli_li("{ha(n_raw)} ha detected over the area")
  if (!is.null(min_prob)) {
    cli::cli_li("{ha(n_raw - n_prob)} ha below {min_prob}% probability, dropped")
  }
  if (n_fire > 0) {
    cli::cli_li("{ha(n_fire)} ha inside a fire perimeter, removed")
  }
  if (!is.null(years)) {
    cli::cli_li("Kept year{?s} {years}")
  }
  cli::cli_li("{ha(n_final)} ha kept")
  v <- stats::na.omit(terra::values(out[["cut_year"]])[, 1])
  if (length(v)) {
    tb <- table(v)
    cli::cli_li("By year: {paste(names(tb), round(ha(as.numeric(tb))), sep = ': ', collapse = ' ha, ')} ha")
  }
  if (no_fires) {
    cli::cli_alert_warning(
      "Fire perimeters not excluded: a severe fire reads as a clear-cut here."
    )
  }
  cli::cli_alert_info(
    "Recall 80.9%: about one cut in five is missed, so no detection is not \\
     evidence of no cut."
  )
}
