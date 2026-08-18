# LiDAR-derived fuel: the continuous register finally gets a producer.
#
# Everything in the fuel module was built so that this file would not require
# rewriting it. fev_fuel_source() has carried an empty continuous register since
# phase 4, tested through a synthetic path, precisely so that the day a
# continuous source arrived it would slot in rather than force a redesign.
#
# What LiDAR adds that nothing else in the package can: the understorey. Neither
# CORINE nor BD Forêt describes it, which the vignettes call the principal
# methodological weakness of the whole chain. A vertical bulk density profile
# does describe it, and the crown base height and fuel strata gap derived from
# it are the two numbers surface-to-crown transition actually depends on.
#
# The physics is lidarforfuel's (Olivier Martin's team, INRAE). Everything here
# is about naming its output correctly, refusing point clouds too thin to carry
# the answer, and recording what was assumed.

#' Effective pulse and point density of a point cloud
#'
#' Measures what the LiDAR HD specification is written in — pulses per square
#' metre — rather than the point count that is easier to compute.
#'
#' @section Why pulses and not points:
#' IGN specifies LiDAR HD at **at least 10 pulses/m²**, and 5 pulses/m² above
#' 3200 m of altitude. A pulse produces several returns in vegetation, so point
#' density overstates the figure the specification is about, sometimes by a
#' factor of two. Pulses are counted here as first returns.
#'
#' @section Why it matters more here than elsewhere:
#' Density does not degrade the result gracefully, it biases it in a known
#' direction. As pulses thin out, the understorey stratum is the first thing to
#' disappear from the profile — so fuel load is **underestimated** — while crown
#' base height and the gap between strata are **overestimated**, because the
#' lowest returns that would have defined them are missing. A thin tile
#' therefore reports a safer landscape than it has.
#'
#' @param las A `LAS` object, or anything [lidR::readLAS()] accepts.
#'
#' @return A list with `pulses_per_m2`, `points_per_m2`, `n_points`,
#'   `n_pulses` and `area_m2`.
#'
#' @seealso [fev_fuel_lidar()], which refuses to compute below a threshold.
#'
#' @source
#' Density specification: IGN, *Nuages de points LiDAR HD*, at least 10 pulses
#' per m² and 5 above 3200 m, verified 2026-08-17. Direction of the bias with
#' decreasing density: stated in the brief governing this package, and
#' consistent with the null-return path of
#' `lidarforfuel::fCBDprofile_fuelmetrics()`.
#'
#' @examples
#' \dontrun{
#' las <- lidR::readLAS("LHD_FXX_0968_6240_PTS_C_LAMB93_IGN69.copc.laz")
#' fev_lidar_density(las)
#' }
#'
#' @export
fev_lidar_density <- function(las) {
  fev_require("lidR", "read and measure a LiDAR point cloud")
  las <- fev_as_las(las)

  n_points <- nrow(las@data)
  if (!n_points) {
    fev_abort("The point cloud is empty.", class = "fev_empty_result")
  }
  area <- as.numeric(sf::st_area(sf::st_as_sfc(sf::st_bbox(las))))

  # First returns are one per pulse. Absent a ReturnNumber column the two
  # densities collapse, and the record says so rather than pretending.
  n_pulses <- if ("ReturnNumber" %in% names(las@data)) {
    sum(las@data$ReturnNumber == 1L)
  } else {
    fev_warn(c(
      "No {.field ReturnNumber} in the point cloud.",
      i = "Pulse density cannot be distinguished from point density, so the \\
           figure below is points and will overstate the specification."
    ), class = "fev_no_return_number")
    n_points
  }

  list(
    pulses_per_m2 = round(n_pulses / area, 2),
    points_per_m2 = round(n_points / area, 2),
    n_points = n_points, n_pulses = n_pulses,
    area_m2 = round(area)
  )
}

#' @noRd
fev_as_las <- function(x) {
  if (inherits(x, "LAS")) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L) {
    return(lidR::readLAS(x))
  }
  fev_abort(c(
    "Expected a {.cls LAS} or a path readable by {.fn lidR::readLAS}.",
    x = "Got {.cls {class(x)[1]}}."
  ))
}

# --- fuel metrics ------------------------------------------------------------

# Units, derived from the code rather than assumed. CBD is a bulk density in
# kg/m3; the loads are computed as sum(CBD) * d with d in metres, so they are
# kg/m2. Heights are metres. Covers are fractions. FMA is left unlabelled: its
# meaning was not established at a source, and a wrong unit is worse than none.
.FEV_LIDAR_UNITS <- c(
  Profil_Type = "profile type code", Profil_Type_L = "profile type code (A-D)",
  threshold = "kg/m3", Height = "m", CBH = "m", FSG = "m", Top_Fuel = "m",
  H_Bush = "m", continuity = "0/1", VCI_PAD = "dimensionless",
  VCI_lidr = "dimensionless", entropy_lidr = "dimensionless",
  PAI_tot = "m2/m2", CBD_max = "kg/m3", CFL = "kg/m2", TFL = "kg/m2",
  MFL = "kg/m2", FL_1_3 = "kg/m2", GSFL = "kg/m2", FL_0_1 = "kg/m2",
  FMA = NA_character_, date = "gpstime", Cover = "fraction",
  Cover_4 = "fraction", Cover_6 = "fraction"
)

# The subset that describes fuel rather than the computation. Kept as the
# default output because the other nineteen bands are diagnostics, and a
# continuous register with 175 layers is unusable.
.FEV_LIDAR_FUEL_METRICS <- c("Height", "CBH", "FSG", "H_Bush", "CBD_max",
                             "CFL", "TFL", "MFL", "FL_0_1", "FL_1_3", "GSFL",
                             "Cover", "PAI_tot")

#' Fuel metrics from a LiDAR point cloud
#'
#' Inverts a point cloud into a vertical bulk density profile and derives the
#' fuel metrics that describe what nothing else in this package can see: the
#' understorey.
#'
#' @section What comes out:
#' A `fev_fuel_source` whose **continuous** register holds one layer per metric.
#' By default the fuel-relevant subset — canopy and understorey loads, crown
#' base height, fuel strata gap, bulk density, cover, plant area index. The full
#' 25 diagnostics and the 150-layer bulk density profile are available on
#' request; a register of 175 layers is rarely what anyone wants.
#'
#' @section On the band names, which the upstream README gets wrong:
#' `lidarforfuel` returns 175 bands: 25 named metrics then `CBD_1` to `CBD_150`.
#' Its README says 173 with 23 metrics. Reading the profile from band 24 on that
#' basis takes `Cover_4` and `Cover_6` for bulk density and shifts everything by
#' two. This function never indexes positionally — it checks the names it got
#' against the names it expects and refuses if they differ, so a change upstream
#' surfaces as an error rather than as plausible wrong numbers.
#'
#' @section The null value is -1, not NA:
#' Every metric comes back as `-1` when the computation does not complete —
#' typically too few points in the pixel. Left alone that gives negative crown
#' base heights and negative fuel loads, which pass any naive plausibility
#' check. They are converted to `NA` here.
#'
#' @section Density control, which is not optional:
#' Pulse density is measured and recorded for every cloud, and the function
#' warns with the number below `min_pulse_density`. The reason is in
#' [fev_lidar_density()]: thinning does not blur the answer, it biases it
#' towards a safer landscape than the real one.
#'
#' @section Parameters imported from lidarforfuel:
#' `lma` (leaf mass per area, 140 g/m²) and `wd` (wood density, 591 kg/m³) are
#' that package's defaults. They are **species values**, they were not traced to
#' a primary source, and they scale the fuel loads directly — a stand whose
#' actual LMA is half of 140 has its load overestimated by a factor of two.
#' Override them for your species, and they go into the provenance either way.
#'
#' @param las A `LAS`, a path, or a URL to a COPC tile. COPC is readable over
#'   HTTP, so a small extent needs no download.
#' @param res Output cell size in metres. 25 m matches the rest of the chain;
#'   below about 10 m most cells fall under `lidarforfuel`'s own minimum point
#'   count and come back empty.
#' @param min_pulse_density Warn below this, in pulses/m². Defaults to 10, the
#'   LiDAR HD specification. Legitimately 5 above 3200 m of altitude.
#' @param metrics Which metrics to keep. `NULL` gives the fuel subset,
#'   `"all"` gives all 25.
#' @param profile Keep the 150-layer bulk density profile as well.
#' @param lma,wd Leaf mass per area (g/m²) and wood density (kg/m³).
#' @param threshold Bulk density above which a layer counts as fuel, kg/m³.
#' @param millesime Acquisition vintage, for the provenance record.
#' @param ... Passed to `lidarforfuel::fCBDprofile_fuelmetrics()`.
#'
#' @return A `fev_fuel_source` of type `"lidarhd"` with its continuous register
#'   populated.
#'
#' @seealso [fev_fuel_attach()] to graft this onto a categorical fuel source,
#'   [fev_lidar_density()], [fev_fetch_lidarhd()].
#'
#' @source
#' `lidarforfuel` 1.0.0.9001, Olivier Martin's team at INRAE,
#' <https://github.com/oliviermartin7/LidarForFuel>. Note the package is
#' installed as `lidarforfuel`, lowercase, not as its repository name. Method
#' published as *Unlocking the potential of Airborne LiDAR for direct assessment
#' of fuel bulk density and load distributions for wildfire hazard mapping*.
#' Signatures, band order, band count and the `-1` null value verified on
#' 2026-08-17 by reading the installed source and by running it; see
#' `specs/phase8-rapport-lidar.md`.
#'
#' Evaluated by its authors against field plots in France, Spain and Portugal —
#' which is what makes it preferable here to a North American equivalent.
#'
#' @examples
#' \dontrun{
#' idx <- fev_lidarhd_available(aoi)
#' tiles <- fev_fetch_lidarhd(idx, max_tiles = 1)
#' fuel_lidar <- fev_fuel_lidar(fev_data(tiles)$path[1], res = 25)
#' fev_fuel_registers(fuel_lidar)
#' names(fev_fuel_continuous(fuel_lidar))
#' }
#'
#' @export
fev_fuel_lidar <- function(las,
                           res = 25,
                           min_pulse_density = 10,
                           metrics = NULL,
                           profile = FALSE,
                           lma = 140,
                           wd = 591,
                           threshold = 0.02,
                           millesime = NA,
                           ...) {
  fev_require("lidR", "process a LiDAR point cloud")
  # Lowercase. The repository is LidarForFuel, the package is not, and
  # requireNamespace("LidarForFuel") returns FALSE on a working install.
  fev_require("lidarforfuel", "derive fuel metrics from a point cloud")

  if (!is.numeric(res) || length(res) != 1L || res <= 0) {
    fev_abort("{.arg res} must be a single positive number, in metres.")
  }
  if (res < 10) {
    fev_inform(c(
      "{.arg res} = {.val {res}} m is finer than the point cloud supports.",
      i = "{.pkg lidarforfuel} returns nothing for a pixel below its own \\
           minimum point count, so most cells will be empty."
    ), class = "fev_res_too_fine", .envir = environment())
  }

  cloud <- fev_as_las(las)
  density <- fev_lidar_density(cloud)
  fev_check_pulse_density(density, min_pulse_density)

  pre <- fev_lidar_pretreat(cloud, lma, wd)
  raw <- fev_lidar_pixel_metrics(pre$las, res, threshold, ...)

  wanted <- fev_lidar_select(metrics, profile)
  out <- fev_lidar_clean(raw, wanted)

  prov <- fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_source(
    prov, dataset = "lidarhd", provider = "IGN",
    millesime = millesime, version = "LiDAR HD point cloud",
    crs_native = fev_crs_label(out),
    pulses_per_m2 = density$pulses_per_m2,
    points_per_m2 = density$points_per_m2
  )
  prov <- fev_prov_add_step(
    prov, fun = "fev_fuel_lidar",
    params = list(
      res = res, threshold = threshold, lma = lma, wd = wd,
      lma_wd_sourced = FALSE,
      min_pulse_density = min_pulse_density,
      pulses_per_m2 = density$pulses_per_m2,
      points_per_m2 = density$points_per_m2,
      n_points = density$n_points,
      metrics = names(out), profile = profile,
      engine = "lidarforfuel::fCBDprofile_fuelmetrics",
      engine_version = as.character(utils::packageVersion("lidarforfuel")),
      trajectory = pre$trajectory
    ),
    notes = pre$notes
  )

  units <- c(.FEV_LIDAR_UNITS, stats::setNames(
    rep("kg/m3", .FEV_LIDAR_CBD_LAYERS),
    paste0("CBD_", seq_len(.FEV_LIDAR_CBD_LAYERS))
  ))

  new_fev_fuel_source(
    categorical = NULL,
    continuous  = out,
    units       = units[names(out)],
    lookup      = NULL,
    type        = "lidarhd",
    millesime   = millesime,
    provenance  = prov
  )
}

#' Refuse quietly is not an option here
#' @noRd
fev_check_pulse_density <- function(density, min_pulse_density) {
  d <- density$pulses_per_m2
  if (is.na(d) || d >= min_pulse_density) {
    return(invisible(TRUE))
  }
  fev_warn(c(
    "Pulse density is {.val {d}} per m2, below the {.val {min_pulse_density}} \\
     asked for.",
    i = "Point density is {.val {density$points_per_m2}} per m2 over \\
         {.val {density$area_m2}} m2 -- points are not pulses, and the \\
         specification is written in pulses.",
    i = "The bias has a direction: the understorey stratum thins out first, so \\
         fuel load comes out too low while crown base height and the strata \\
         gap come out too high. This tile will describe a safer landscape than \\
         it is.",
    i = "LiDAR HD specifies at least 10 pulses/m2, and 5 above 3200 m of \\
         altitude -- so a high mountain tile may legitimately sit at 5."
  ), class = "fev_low_pulse_density", .envir = environment())
  invisible(FALSE)
}

#' Pre-treatment, and surfacing the trajectory fallback
#'
#' `fPCpretreatment()` needs the sensor position to correct for scanning angle.
#' When it cannot reconstruct a trajectory it falls back to a nominal flight
#' height of 1400 m above the ground and says so in a warning that is easy to
#' lose in a loop over a thousand tiles. That fallback changes the result, so it
#' is caught here and recorded.
#'
#' The upstream also advises computing the trajectory on a buffered catalogue
#' rather than tile by tile, to avoid border effects. Honouring that properly is
#' a `catalog_apply()` concern; a single-tile call cannot, and says so.
#'
#' @noRd
fev_lidar_pretreat <- function(cloud, lma, wd) {
  warns <- character()
  las <- withCallingHandlers(
    lidarforfuel::fPCpretreatment(cloud, LMA = lma, WD = wd,
                                  LMA_bush = lma, WD_bush = wd),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  fallback <- any(grepl("default trajectory", warns, fixed = TRUE))
  if (fallback) {
    fev_warn(c(
      "The sensor trajectory could not be reconstructed from this cloud.",
      i = "{.pkg lidarforfuel} fell back to a nominal flight height of 1400 m \\
           above the ground, which changes the scanning-angle correction and \\
           therefore the bulk density profile.",
      i = "Recorded in the provenance as a fallback rather than a measurement. \\
           Supply a trajectory, or compute one on a buffered catalogue."
    ), class = "fev_trajectory_fallback")
  }
  if (any(grepl("buffer", warns, fixed = TRUE))) {
    fev_inform(c(
      "The trajectory was computed from this tile alone.",
      i = "The upstream advises a buffered catalogue (about 500 m) to avoid \\
           border effects. A single-tile call cannot do that."
    ), class = "fev_trajectory_unbuffered")
  }

  list(las = las,
       trajectory = if (fallback) "fallback: nominal 1400 m" else "reconstructed",
       notes = if (length(warns)) paste(unique(warns), collapse = " | ") else NULL)
}

#' Run the metrics, then check the names rather than trust them
#' @noRd
fev_lidar_pixel_metrics <- function(las, res, threshold, ...) {
  # The scalar parameters are inlined into the expression rather than referenced.
  # lidR evaluates the formula inside data.table's `j`, and neither the caller's
  # `...` (which fails with "'...' used in an incorrect context") nor a local
  # variable (which fails with "object not found") survives that. Only the
  # point-attribute names stay as symbols, because those are the columns.
  metrics_fun <- rlang::new_formula(NULL, rlang::expr(
    lidarforfuel::fCBDprofile_fuelmetrics(
      datatype = "Pixel", X = X, Y = Y, Z = Z, Zref = Zref,
      ReturnNumber = ReturnNumber, Easting = Easting, Northing = Northing,
      Elevation = Elevation, LMA = LMA, WD = WD, gpstime = gpstime,
      threshold = !!threshold, !!!list(...)
    )
  ))
  r <- suppressWarnings(lidR::pixel_metrics(las, metrics_fun, res = res))

  expected <- c(.FEV_LIDAR_METRICS,
                paste0("CBD_", seq_len(.FEV_LIDAR_CBD_LAYERS)))
  got <- names(r)
  if (!identical(got, expected)) {
    extra <- setdiff(got, expected)
    missing <- setdiff(expected, got)
    fev_abort(c(
      "{.pkg lidarforfuel} returned bands this package does not recognise.",
      x = "Expected {length(expected)} bands, got {length(got)}.",
      if (length(missing)) c(x = "Missing: {.val {utils::head(missing, 5)}}"),
      if (length(extra)) c(x = "Unexpected: {.val {utils::head(extra, 5)}}"),
      i = "The band list is pinned deliberately: its README documents 173 \\
           bands where the code produces 175, so nothing here indexes by \\
           position. A mismatch means the upstream changed and the mapping \\
           must be re-verified, not worked around.",
      i = "See {.file specs/phase8-rapport-lidar.md}."
    ), class = "fev_lidar_band_mismatch", .envir = environment())
  }
  r
}

#' @noRd
fev_lidar_select <- function(metrics, profile) {
  base <- if (is.null(metrics)) {
    .FEV_LIDAR_FUEL_METRICS
  } else if (identical(metrics, "all")) {
    .FEV_LIDAR_METRICS
  } else {
    unknown <- setdiff(metrics, .FEV_LIDAR_METRICS)
    if (length(unknown)) {
      # Dot-free local: cli reads a leading dot inside {} as a style, not an
      # expression. Same trap as in fev_fetch_bdforet() and fev_fwi_calc().
      available <- .FEV_LIDAR_METRICS
      fev_abort(c(
        "Unknown metric{?s} {.val {unknown}}.",
        i = "Available: {.val {available}}.",
        i = "Or {.val all} for every one, or {.code NULL} for the fuel subset."
      ), .envir = environment())
    }
    metrics
  }
  if (isTRUE(profile)) {
    base <- c(base, paste0("CBD_", seq_len(.FEV_LIDAR_CBD_LAYERS)))
  }
  base
}

#' Subset, and turn the -1 sentinel into NA
#' @noRd
fev_lidar_clean <- function(raw, wanted) {
  out <- raw[[wanted]]
  # terra::subst() rather than arithmetic: -1 is a sentinel across every band,
  # including the integer-coded profile types where a computed replacement
  # would be meaningless.
  out <- terra::subst(out, .FEV_LIDAR_NULL_VALUE, NA)
  names(out) <- wanted
  out
}

# --- attaching to a categorical source ---------------------------------------

#' Attach continuous fuel metrics to a categorical fuel source
#'
#' Carries a second description of the same ground alongside the first, instead
#' of making the two compete for the pixel. What the attached source holds
#' decides where it lands: **continuous** metrics populate the continuous
#' register, a **class** layer becomes a named extra layer of the categorical
#' one.
#'
#' @section Why this is not fev_fuel_merge():
#' [fev_fuel_merge()] arbitrates. Two sources propose a class for the same
#' pixel, one has to win, and the per-pixel `source` layer records which. The
#' loser's information is gone.
#'
#' Attaching arbitrates nothing. LiDAR competes for nothing to begin with — bulk
#' density and crown base height are quantities no categorical source has. And a
#' second classification need not compete either, if you want it for the
#' attributes the deciding one lacks rather than for the class itself.
#'
#' @section Keeping the species when a 10 m raster decides the class:
#' This is the case the categorical branch exists for. With
#' `fev_fuel_merge(hierarchy = "auto")`, ESA WorldCover outranks BD Forêt and,
#' having complete coverage, takes **every** pixel — BD Forêt contributes
#' nothing, and its species and crown cover go with it.
#'
#' Attaching it afterwards keeps both: the 10 m class from WorldCover, and the
#' botany from BD Forêt riding alongside in its own layer.
#'
#' ```r
#' fuel <- fev_fuel_merge(bdforet, worldcover)   # WorldCover decides `class`
#' fuel <- fev_fuel_attach(fuel, bdforet)        # species survives beside it
#' ```
#'
#' The attached layer decides no pixel. `fev_fuel_binary()`,
#' `fev_fuel_type()` and the exposure chain all read `class` and ignore it, and
#' `fev_fuel_fill_gaps()` leaves it alone — its `NA` mean "not forest here",
#' which is information, and filling them from a modal neighbour would invent
#' species.
#'
#' @section What it costs, measured:
#' Slow, and slow enough to plan around. Attempted on the development machine
#' 2026-08-18, on real LiDAR HD tiles over the Maures at 25 m — every figure is
#' a **lower bound**, because none of the three runs completed:
#'
#' | Extent | Points | Wall clock |
#' |---|---|---|
#' | 250 m square | 3.0 M | > 25 min, unfinished |
#' | 500 m square | 11.1 M | > 40 min, unfinished |
#' | 1 km tile | full | > 90 min, unfinished |
#'
#' Downloading is not the bottleneck: a 248 MB tile arrived in 42 s. The
#' inversion is.
#'
#' Two consequences worth stating. A departmental run is a batch job with a
#' resume path, not something to start interactively — which is why the phase 8
#' brief asked for one. And **do not buy speed by thinning the cloud**: the
#' understorey stratum is the first thing to disappear as pulse density falls,
#' so thinning biases exactly the quantity this function exists to measure. See
#' [fev_lidar_density()].
#'
#' @section Coverage is a per-metric mask, not a source layer:
#' LiDAR HD is still being flown, so the continuous register is full of holes
#' where the categorical one is complete. The function reports the share of
#' categorical cells that get continuous values, because a fuel object whose two
#' registers describe different subsets of the map is easy to misread.
#'
#' @param primary A `fev_fuel_source` with a categorical register. It keeps
#'   deciding `class`.
#' @param extra A `fev_fuel_source` to carry alongside. With a continuous
#'   register — from [fev_fuel_lidar()] — it populates the continuous one. With
#'   only a categorical register, its classes become an extra layer.
#' @param name Name for the attached categorical layer. `NULL` uses the source's
#'   own label. Ignored for a continuous attachment.
#'
#' @return `primary`, with the extra description carried alongside.
#'
#' @seealso [fev_fuel_lidar()], [fev_fuel_merge()], [fev_fuel_registers()].
#'
#' @examples
#' # Categorical from BD Forêt, continuous standing in for LiDAR.
#' cat_r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 200,
#'                      ymin = 0, ymax = 200, crs = "EPSG:2154")
#' terra::values(cat_r) <- rep_len(1:2, 64)
#' levels(cat_r) <- data.frame(id = 1:2, class = c("FF2-57-57", "LA4"))
#' names(cat_r) <- "class"
#' fuel <- fev_fuel_source(cat_r, type = "bdforet_v2", millesime = 2014)
#'
#' cbd <- terra::rast(cat_r)
#' terra::values(cbd) <- runif(64, 0, 0.4)
#' names(cbd) <- "CBD_max"
#' lidar <- fev_fuel_source(cbd, type = "custom", register = "continuous",
#'                          units = c(CBD_max = "kg/m3"))
#'
#' both <- fev_fuel_attach(fuel, lidar)
#' fev_fuel_registers(both)
#'
#' # And the categorical branch: a second classification kept alongside rather
#' # than made to compete.
#' other <- terra::rast(cat_r)
#' terra::values(other) <- rep_len(1:2, 64)
#' levels(other) <- data.frame(id = 1:2, class = c("10", "20"))
#' names(other) <- "class"
#' wc <- fev_fuel_source(other, type = "worldcover_2021", register = "categorical")
#'
#' names(fev_fuel_categorical(fev_fuel_attach(wc, fuel)))
#'
#' @export
fev_fuel_attach <- function(primary, extra, name = NULL) {
  fev_check_fuel_source(primary, "primary")
  fev_check_fuel_source(extra, "extra")
  fev_fuel_require_register(primary, "categorical", "fev_fuel_attach")

  # One meaning, two registers. What the attached source CARRIES decides where
  # it lands: continuous metrics go to the continuous register, a class layer
  # becomes a named extra layer of the categorical one. Neither competes for the
  # pixel, which is the whole difference from fev_fuel_merge().
  has_cont <- "continuous" %in% fev_fuel_registers(extra)
  if (!has_cont) {
    return(fev_fuel_attach_categorical(primary, extra, name))
  }

  cat_layer <- primary$categorical[["class"]]
  cont <- extra$continuous

  if (!fev_crs_equal(cont, cat_layer)) {
    fev_warn(c(
      "Reprojecting the continuous metrics from \\
       {.val {fev_crs_label(cont)}} to {.val {fev_crs_label(cat_layer)}}.",
      i = "These are continuous quantities, so bilinear is used -- unlike the \\
           categorical path, where only nearest neighbour is defensible."
    ), class = "fev_continuous_reprojected")
    cont <- terra::project(cont, cat_layer, method = "bilinear")
  } else if (!isTRUE(terra::compareGeom(cont, cat_layer, stopOnError = FALSE))) {
    fev_warn(c(
      "Resampling the continuous metrics onto the categorical grid.",
      i = "Continuous cell size {.val {signif(terra::res(cont)[1], 6)}}, \\
           categorical {.val {signif(terra::res(cat_layer)[1], 6)}}."
    ), class = "fev_continuous_resampled", .envir = environment())
    cont <- terra::resample(cont, cat_layer, method = "bilinear")
  }

  n_cat <- terra::global(!is.na(cat_layer), "sum", na.rm = TRUE)[[1]]
  n_both <- terra::global(!is.na(cat_layer) & !is.na(cont[[1]]), "sum",
                          na.rm = TRUE)[[1]]
  pct <- if (n_cat > 0) round(100 * n_both / n_cat, 1) else NA_real_

  if (isTRUE(pct < 100)) {
    fev_warn(c(
      "Continuous metrics cover {.val {pct}}% of the mapped categorical cells.",
      i = "LiDAR HD is still being flown, so the two registers describe \\
           different subsets of the map. Report which one each result came \\
           from.",
      i = "{.fn fev_lidarhd_available} gives the tile coverage before you get \\
           this far."
    ), class = "fev_partial_continuous", .envir = environment())
  }

  prov <- fev_prov_merge(primary$provenance, extra$provenance)
  prov <- fev_prov_add_step(
    prov, fun = "fev_fuel_attach",
    params = list(metrics = names(cont), n_metrics = terra::nlyr(cont),
                  pct_categorical_covered = pct,
                  res = signif(terra::res(cat_layer)[1], 6)),
    notes = "continuous register grafted; no pixel arbitration, unlike fev_fuel_merge()"
  )

  fev_inform("Attached {terra::nlyr(cont)} continuous metric{?s} covering \\
              {pct}% of the categorical cells.", .envir = environment())

  new_fev_fuel_source(
    categorical = primary$categorical,
    continuous  = cont,
    units       = c(primary$units, extra$units)[names(cont)],
    lookup      = primary$lookup,
    type        = paste(unique(c(fev_fuel_components(primary), "lidarhd")),
                        collapse = "+"),
    millesime   = fev_merge_millesime(primary, extra),
    provenance  = prov
  )
}


#' Carry a second classification alongside, without arbitrating the pixel
#'
#' The categorical counterpart of the continuous graft. Where
#' [fev_fuel_merge()] makes two class layers compete and one of them lose, this
#' keeps both: the primary keeps deciding `class`, and the other source's codes
#' ride along in a layer of their own.
#'
#' The case it exists for: with `fev_fuel_merge(hierarchy = "auto")` putting a
#' 10 m raster on top, BD Forêt loses every pixel and its species and crown
#' cover go with it. Attaching it afterwards keeps the resolution AND the
#' botany.
#'
#' @noRd
fev_fuel_attach_categorical <- function(primary, extra, name = NULL) {
  fev_fuel_require_register(extra, "categorical", "fev_fuel_attach")

  cat_r <- primary$categorical
  layer <- extra$categorical[["class"]]

  name <- name %||% fev_fuel_label(extra)
  if (name %in% names(cat_r)) {
    fev_abort(c(
      "The categorical register already has a layer called {.val {name}}.",
      i = "Pass {.arg name} to give this one a different one."
    ), class = "fev_attach_name_taken", .envir = environment())
  }

  target <- cat_r[["class"]]
  if (!fev_crs_equal(layer, target)) {
    fev_warn(c(
      "Reprojecting {.val {name}} from {.val {fev_crs_label(layer)}} to \\
       {.val {fev_crs_label(target)}} with nearest neighbour.",
      i = "It is a class layer, so no other method is defensible; boundaries \\
           move by up to half a cell. Logged in the provenance."
    ), class = "fev_categorical_reprojected", .envir = environment())
    layer <- terra::project(layer, target, method = "near")
  }
  if (!terra::compareGeom(layer, target, stopOnError = FALSE)) {
    layer <- terra::resample(layer, target, method = "near")
  }
  layer <- fev_restore_cat_levels(layer, extra$categorical[["class"]])
  names(layer) <- name

  covered <- as.numeric(terra::global(!is.na(layer), "sum", na.rm = TRUE)[1, 1])
  mapped <- as.numeric(terra::global(!is.na(target), "sum", na.rm = TRUE)[1, 1])
  pct <- if (mapped > 0) round(100 * covered / mapped, 1) else NA_real_

  # Name what actually decides `class`. On a merged source that is the winning
  # dataset, read off the source layer -- not the combined type string, which
  # lists every component and reads as though all of them decided it.
  decider <- if ("source" %in% names(cat_r)) {
    lv <- fev_cat_levels(cat_r[["source"]])
    if (!is.null(lv) && nrow(lv)) lv[[2]][1] else fev_fuel_label(primary)
  } else {
    fev_fuel_label(primary)
  }
  fev_inform(c(
    "Attached {.val {name}} alongside {.field class}, covering {pct}% of the \\
     mapped cells.",
    i = "It decides no pixel: {.field class} still comes from \\
         {.val {decider}}. Use it for what the deciding source does not \\
         carry -- species, crown cover.",
    i = "{.fn fev_fuel_fill_gaps} leaves it alone: its {.val NA} mean \\
         {.q not forest here}, which is information."
  ), .envir = environment())

  prov <- fev_prov_add_step(
    primary$provenance,
    fun = "fev_fuel_attach",
    params = list(attached = name, register = "categorical",
                  pct_categorical_covered = pct),
    notes = "second classification carried alongside; no pixel arbitration"
  )

  new_fev_fuel_source(
    categorical = c(cat_r, layer),
    continuous  = primary$continuous,
    units       = primary$units,
    lookup      = fev_merge_lookups(primary$lookup, extra$lookup),
    type        = paste(unique(c(fev_fuel_components(primary),
                                 fev_fuel_components(extra))), collapse = "+"),
    millesime   = primary$millesime,
    provenance  = prov
  )
}
