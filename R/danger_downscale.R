# Giving the danger term a spatial structure it did not have.
#
# Measured on the Maures, 597 840 cells: the composite risk correlates 0.995
# with its vulnerability layer and 0.542 with its danger layer, and the aligned
# FWI percentile carries EIGHT distinct values over the whole massif. ERA5 is 9
# to 31 km and the massif fits in a handful of its cells, so fev_align() copies
# one reanalysis value across about 141 000 fine cells -- resolution without
# information, which the function already says out loud.
#
# The correction has to happen on the INPUTS, before cffdrs runs. FFMC, DMC and
# DC are cumulative and nonlinear: yesterday's moisture sets today's, so
# adjusting an FWI value after the fact adjusts a number that was never computed
# from the corrected weather. That single constraint decides the whole design.
#
# What is downscaled, and what deliberately is not:
#
#   temperature  yes -- environmental lapse rate, the one correction with a
#                       textbook constant behind it
#   humidity     yes -- follows from temperature at constant dewpoint, which is
#                       physics rather than a fitted relation
#   wind         NO  -- topographic exposure is real and has no calibration this
#                       package can defend. ISI keeps the coarse signal.
#   rain         NO  -- orographic enhancement is real and needs a local
#                       gradient nobody here has. DMC and DC keep the coarse
#                       signal.
#
# So this improves the fine-fuel path and leaves the drought path coarse. That
# is a partial result and it is stated as one.

#' Topographic zones for downscaling
#'
#' Cuts a digital elevation model into elevation bands, optionally crossed with
#' aspect classes, so that weather can be corrected once per zone rather than
#' once per cell.
#'
#' @section Why zones and not cells:
#' The FWI codes are cumulative, so a per-cell downscaling means running the
#' whole seasonal integration in every cell — 678 000 integrations over the
#' Maures where the input carries eight distinct values. Zones put the cost
#' where the information is: a handful of integrations, mapped back onto the
#' grid. Raising `n_elev` past the point where bands differ by less than the
#' lapse rate can resolve buys nothing but time.
#'
#' @section Bands are quantiles, not equal intervals:
#' Equal elevation intervals on a massif put nearly every cell in the lowest
#' band and leave the top ones almost empty, which spends the integrations
#' where there is no ground. Quantiles give bands of comparable area. The
#' consequence is that band edges are not round numbers and change with the
#' area of interest, so zone ids are not comparable between two runs on
#' different extents — the table returned says where the edges fell.
#'
#' @param dem Elevation: a [fev_source] from [fev_fetch_dem()], a `fev_layer`
#'   or a `SpatRaster`.
#' @param n_elev Number of elevation bands. Default 8.
#' @param n_aspect Number of aspect classes, or `1` for none. Aspect is a proxy
#'   for insolation, which this package cannot use yet: ERA5 supplies no
#'   radiation to the FWI, so crossing by aspect multiplies the zones without
#'   changing any input. Left at 1 unless you intend to use the zones for
#'   something else.
#' @param stations The weather points the downscaling will draw from: a table
#'   with `id`, `lat` and `long`, or `NULL`. **Supply them.** Without them the
#'   zones are elevation bands alone, and a band pools cells scattered across
#'   the whole area under one series — which replaces the reanalysis's
#'   horizontal variation by the vertical one instead of adding to it. Measured
#'   on the Maures: bands alone gave 8 distinct FWI values where the coarse
#'   chain gave 17, so the downscaling made the field *flatter*. Crossing the
#'   bands with each point's own territory keeps both.
#' @param quiet Suppress the report.
#'
#' @return A `fev_layer` of role `"topo_zone"` holding integer zone ids, with a
#'   `zones` attribute: one row per zone with `zone`, `n_cells`, `elev_mean`,
#'   `elev_min`, `elev_max`, and the representative latitude cffdrs needs.
#'
#' @seealso [fev_downscale_weather()] for the correction itself.
#'
#' @examples
#' g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 2000,
#'                  ymin = 0, ymax = 2000, crs = "EPSG:2154")
#' dem <- terra::init(g, "y") / 4
#' z <- fev_topo_zones(dem, n_elev = 4, quiet = TRUE)
#' attr(z, "zones")[, c("zone", "n_cells", "elev_mean")]
#'
#' @export
fev_topo_zones <- function(dem, n_elev = 8L, n_aspect = 1L, stations = NULL,
                           quiet = FALSE) {
  n_elev <- as.integer(n_elev)
  n_aspect <- as.integer(n_aspect)
  if (is.na(n_elev) || n_elev < 1L) {
    fev_abort("{.arg n_elev} must be at least 1.")
  }
  if (is.na(n_aspect) || n_aspect < 1L) {
    fev_abort("{.arg n_aspect} must be at least 1.")
  }

  prov <- fev_layer_prov(dem) %||% attr(dem, "provenance") %||%
    fev_prov_new(crs_work = NA)
  z <- fev_as_raster(dem, "dem")[[1]]
  vals <- terra::values(z)[, 1]
  if (all(is.na(vals))) {
    fev_abort("The elevation model is entirely {.val NA}.", class = "fev_all_na")
  }

  brk <- unique(stats::quantile(vals, probs = seq(0, 1, length.out = n_elev + 1L),
                                na.rm = TRUE, names = FALSE))
  if (length(brk) < 2L) {
    # Flat ground: one band, and saying so beats returning a single zone that
    # looks like a choice.
    brk <- c(brk[1] - 1, brk[1] + 1)
  }
  band <- cut(vals, breaks = brk, include.lowest = TRUE, labels = FALSE)

  if (n_aspect > 1L) {
    asp <- terra::values(terra::terrain(z, v = "aspect", unit = "degrees",
                                        neighbors = 8))[, 1]
    # Classes centred on their nominal bearing, as the exposure sectors are, so
    # north falls inside a class rather than on the seam between two.
    width <- 360 / n_aspect
    acl <- (floor(((asp + width / 2) %% 360) / width) + 1L)
    acl[is.na(acl)] <- 1L
    id <- (band - 1L) * n_aspect + acl
  } else {
    id <- band
  }
  n_sub <- n_elev * n_aspect

  # The crossing that makes this a downscaling rather than a re-slicing: each
  # cell keeps the reanalysis point whose territory it falls in, and gains the
  # elevation band it sits in. Zones = points x bands.
  st_idx <- NULL
  if (!is.null(stations)) {
    st <- fev_zone_stations(stations)
    st_idx <- fev_nearest_station_cell(z, st)
    id <- (st_idx - 1L) * n_sub + id
  }

  out <- terra::setValues(z, as.integer(id))
  names(out) <- "topo_zone"

  xy <- terra::xyFromCell(z, seq_len(terra::ncell(z)))
  ll <- fev_zone_latitudes(z, xy)
  tab <- fev_zone_table(id, vals, ll)
  if (!is.null(st_idx)) {
    # Which point each zone draws from, decided here where the geometry is,
    # rather than re-derived from a centroid later: a zone is a band inside one
    # point's territory and can be far from its own centroid.
    tab$station <- fev_zone_station_id(id, st_idx, fev_zone_stations(stations),
                                       tab$zone)
  }

  if (!quiet) {
    cli::cli_h1("fev_topo_zones")
    cli::cli_li("{nrow(tab)} zone{?s} over \\
                {sum(!is.na(vals))} cell{?s} with elevation")
    cli::cli_li("Bands at {paste(round(brk), collapse = ', ')} m")
    if (n_aspect > 1L) {
      cli::cli_alert_info(
        "Aspect classes multiply the zones but change no FWI input: the \\
         reanalysis supplies no radiation."
      )
    }
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_topo_zones",
    params = list(n_elev = n_elev, n_aspect = n_aspect,
                  n_zones = nrow(tab),
                  crossed_with_stations = !is.null(st_idx),
                  breaks_m = paste(round(brk), collapse = ", ")),
    notes = if (is.null(st_idx)) {
      paste0("elevation bands only: a band pools cells across the whole area, ",
             "so this REPLACES the horizontal variation instead of adding to it")
    } else {
      "quantile elevation bands crossed with each weather point's territory"
    }
  )

  structure(
    new_fev_layer(out, role = "topo_zone", provenance = prov,
                  units = "zone id"),
    zones = tab
  )
}

#' The weather points, reduced to what the crossing needs
#' @noRd
fev_zone_stations <- function(stations) {
  st <- if (inherits(stations, "fev_source")) stations$data else stations
  if (inherits(st, "sf")) {
    xy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(st), 4326))
    st <- data.frame(id = as.character(seq_len(nrow(xy))),
                     lat = xy[, 2], long = xy[, 1])
  }
  need <- c("id", "lat", "long")
  if (!is.data.frame(st) || length(setdiff(need, names(st)))) {
    fev_abort(c(
      "{.arg stations} needs {.field id}, {.field lat} and {.field long}.",
      i = "The weather table {.fn fev_fetch_weather} returns has them."
    ))
  }
  unique(st[, need])
}

#' Which point's territory each cell falls in
#'
#' Nearest point, which is a Voronoi tessellation computed the direct way. With
#' a score of reanalysis cell centres against a few hundred thousand cells that
#' is a small matrix and not worth a spatial index.
#'
#' @noRd
fev_nearest_station_cell <- function(z, st) {
  xy <- terra::xyFromCell(z, seq_len(terra::ncell(z)))
  pts <- sf::st_as_sf(st, coords = c("long", "lat"), crs = 4326)
  pts <- sf::st_coordinates(sf::st_transform(pts, sf::st_crs(terra::crs(z))))
  d2 <- vapply(seq_len(nrow(pts)), function(k) {
    (xy[, 1] - pts[k, 1])^2 + (xy[, 2] - pts[k, 2])^2
  }, numeric(nrow(xy)))
  max.col(-d2, ties.method = "first")
}

#' @noRd
fev_zone_station_id <- function(id, st_idx, st, zones) {
  # One station per zone by construction, so the first cell of each zone
  # settles it; taking a mode would hide a crossing that had gone wrong.
  first <- match(zones, id)
  st$id[st_idx[first]]
}

#' @noRd
fev_zone_latitudes <- function(z, xy) {
  # cffdrs needs a latitude for its day-length adjustment, so each zone needs a
  # representative one in degrees whatever the working CRS is.
  pts <- sf::st_as_sf(as.data.frame(xy), coords = c("x", "y"),
                      crs = sf::st_crs(terra::crs(z)))
  sf::st_coordinates(sf::st_transform(pts, 4326))[, 2]
}

#' @noRd
fev_zone_table <- function(id, vals, lat) {
  ok <- !is.na(id) & !is.na(vals)
  sp <- split(seq_along(id)[ok], id[ok])
  do.call(rbind, lapply(names(sp), function(k) {
    i <- sp[[k]]
    data.frame(zone = as.integer(k), n_cells = length(i),
               elev_mean = mean(vals[i]), elev_min = min(vals[i]),
               elev_max = max(vals[i]), lat = stats::median(lat[i]),
               stringsAsFactors = FALSE)
  }))
}

#' Correct weather to the elevation of each topographic zone
#'
#' Produces one weather series per zone, with temperature moved by the
#' environmental lapse rate and relative humidity following from it at constant
#' dewpoint. The result is the exact shape [fev_fwi_calc()] expects, so the FWI
#' accumulates per zone from corrected inputs rather than being adjusted after
#' the fact.
#'
#' @section What is corrected and what is not:
#' **Temperature** moves with the lapse rate. **Humidity** follows, because
#' cooling air at constant water content raises its relative humidity — that is
#' thermodynamics, not a fitted relation.
#'
#' **Wind and rain are passed through unchanged.** Topographic exposure and
#' orographic enhancement are both real and neither has a calibration this
#' package can defend on a Mediterranean massif. Inventing a multiplier for
#' either would put a number in the provenance that nobody could justify. The
#' consequence is precise and must be read: ISI keeps the coarse wind signal,
#' DMC and DC keep the coarse rain signal, and it is the fine-fuel path — FFMC,
#' and FWI through it — that gains structure.
#'
#' @section It helps a raw-FWI chain and hurts a percentile one:
#' Measured on the Maures for 16 August 2021 over 597 840 cells, decomposing the
#' composite risk into its two terms:
#'
#' | chain | sd(danger) | cor(risk, danger) | cor(risk, vulnerability) |
#' |---|---|---|---|
#' | coarse, percentile | 0.308 | **0.879** | 0.833 |
#' | coarse, raw FWI + minmax | 0.237 | 0.699 | 0.769 |
#' | downscaled, raw FWI + minmax | 0.249 | **0.801** | 0.827 |
#' | downscaled, percentile | 0.003 | 0.479 | 1.000 |
#'
#' Downscaling lifts a raw-FWI chain — 0.699 to 0.801 — and **wrecks a
#' percentile one**, and the reason is structural rather than incidental.
#'
#' A lapse rate is a **monotone** transform of a zone's whole series. Shifting a
#' series by a near-constant offset barely changes where any one day ranks
#' inside it. Every zone inherits a history that is a deterministic transform of
#' its parent reanalysis cell's, so every zone ranks 16 August at nearly the
#' same percentile and the spatial contrast collapses: the standard deviation
#' falls to 0.003.
#'
#' What the coarse percentile chain has, and this destroys, is genuine: distinct
#' reanalysis cells carry distinct climatologies, and ranking today against each
#' one says where today is most exceptional. That is information about local
#' climate, not an artefact of cell boundaries.
#'
#' So the two answer different questions and want different inputs. *Where is it
#' worst today* wants a downscaled raw FWI with `normalise = "minmax"`. *Where is
#' today most unusual* wants the percentile, and has no use for a monotone
#' correction.
#'
#' @section The lapse rate is a constant and the atmosphere is not:
#' 6.5 K/km is the ICAO standard mean. The real rate runs from about 9.8 K/km in
#' dry unstable air to near zero, and **inverts** during Mediterranean summer
#' nights, when cold air pools in the valleys and the slope above is warmer than
#' the floor. The FWI takes noon conditions, when inversions have usually broken,
#' which is the argument for using a mean rate here — not that it is always
#' right, but that it is right at the hour the index reads.
#'
#' Pass your own `lapse_rate` if you have one for your season and site. It is
#' recorded either way.
#'
#' @param weather A weather table as [fev_fetch_weather()] returns, or a
#'   [fev_source] holding one. Needs `elev_m`, the elevation the reanalysis
#'   thinks each point sits at, without which there is nothing to correct
#'   *from*.
#' @param zones A `fev_layer` from [fev_topo_zones()].
#' @param lapse_rate Kelvin per kilometre, positive for cooling with height.
#'   Default 6.5.
#' @param wind `"none"` (default) or `"curvature"`. The second applies the
#'   MicroMet terrain weighting through [fev_curvature()], which needs
#'   `curvature`. **Only the curvature half of the published scheme**: its slope
#'   term needs a wind direction and this package fetches none.
#' @param curvature A `fev_layer` from [fev_curvature()], on the zone grid.
#'   Required when `wind = "curvature"`.
#' @param curve_weight Weight on the curvature term, `gamma_c` in Liston and
#'   Elder. Default 0.5, their default. A ridge then carries 1.25 times the
#'   reanalysis wind and a hollow 0.75 times.
#' @param rain `"none"` (default) or `"fitted"`. The second asks
#'   [fev_rain_gradient()] whether these points show an orographic gradient and
#'   **applies nothing if they do not** — saying so rather than fitting noise.
#' @param quiet Suppress the report.
#'
#' @return A data frame in [fev_fwi_calc()]'s input shape, one `id` per zone,
#'   with `elev_m` set to the zone's mean elevation and a `zone` column.
#'
#' @seealso [fev_topo_zones()], [fev_fwi_zonal()] to run the FWI on the result.
#'
#' @examples
#' \dontrun{
#' dem <- fev_fetch_dem(zone)
#' z <- fev_topo_zones(fev_data(dem))
#' w <- fev_downscale_weather(meteo, z)
#' danger <- fev_fwi_zonal(w, z, dates = as.Date("2021-08-16"))
#' }
#'
#' @export
fev_downscale_weather <- function(weather, zones, lapse_rate = 6.5,
                                  wind = c("none", "curvature"),
                                  curvature = NULL, curve_weight = 0.5,
                                  rain = c("none", "fitted"),
                                  quiet = FALSE) {
  wind <- match.arg(wind)
  rain <- match.arg(rain)
  tab <- if (inherits(weather, "fev_source")) weather$data else weather
  if (!is.data.frame(tab)) {
    fev_abort("{.arg weather} must be a {.cls data.frame} or {.cls fev_source}.")
  }
  needed <- c("id", "lat", "long", "yr", "mon", "day", "temp", "rh", "ws",
              "prec")
  missing <- setdiff(needed, names(tab))
  if (length(missing)) {
    fev_abort(c(
      "{.arg weather} is missing column{?s} {.field {missing}}.",
      i = "{.fn fev_fetch_weather} returns exactly this shape."
    ), class = "fev_bad_weather", .envir = environment())
  }
  if (!"elev_m" %in% names(tab)) {
    fev_abort(c(
      "{.arg weather} has no {.field elev_m} column.",
      i = "There is nothing to correct FROM: the lapse rate needs the \\
           elevation the reanalysis believes each point sits at, which is not \\
           the ground elevation there.",
      i = "{.fn fev_fetch_weather} records it."
    ), class = "fev_no_reference_elevation")
  }
  if (!is.numeric(lapse_rate) || length(lapse_rate) != 1L || is.na(lapse_rate)) {
    fev_abort("{.arg lapse_rate} must be a single number, in K/km.")
  }

  zt <- attr(zones, "zones")
  if (is.null(zt)) {
    fev_abort(c(
      "{.arg zones} carries no zone table.",
      i = "{.fn fev_topo_zones} returns one; a bare raster is not enough."
    ))
  }

  zr <- fev_as_raster(zones, "zones")[[1]]
  stations <- unique(tab[, c("id", "lat", "long", "elev_m")])

  if ("station" %in% names(zt)) {
    # The crossing already decided, cell by cell, whose territory each zone
    # sits in. Re-deriving it from the zone centroid here would be worse than
    # redundant: a band inside a point's territory need not contain its own
    # centroid, so the two answers can differ.
    src_id <- zt$station
  } else {
    fev_warn(c(
      "These zones were built without stations, so each one pools cells from \
       across the whole area.",
      i = "The downscaling then REPLACES the reanalysis's horizontal \
           variation by the vertical one instead of adding to it.",
      i = "Pass {.arg stations} to {.fn fev_topo_zones}."
    ), class = "fev_zones_without_stations")
    zxy <- fev_zone_centroids(zr, zt$zone)
    src_id <- stations$id[fev_nearest_station(zxy, stations, terra::crs(zr))]
  }

  wind_wt <- fev_zone_wind_weight(wind, curvature, zr, zt, curve_weight)
  grad <- fev_zone_rain_gradient(rain, tab, quiet)

  out <- do.call(rbind, lapply(seq_len(nrow(zt)), function(i) {
    src <- tab[tab$id == src_id[i], , drop = FALSE]
    dz_m <- zt$elev_mean[i] - src$elev_m
    dz <- dz_m / 1000
    t_new <- src$temp - lapse_rate * dz
    rh_new <- fev_rh_at_temperature(src$temp, src$rh, t_new)
    # Never below zero: a gradient extrapolated down a valley can otherwise
    # subtract more rain than fell, and a negative precipitation is not a dry
    # day, it is a broken input cffdrs will happily accept.
    p_new <- if (is.null(grad$slope)) src$prec else
      pmax(src$prec + grad$slope * dz_m, 0)
    data.frame(
      id = paste0("zone", zt$zone[i]), zone = zt$zone[i],
      lat = zt$lat[i], long = src$long,
      yr = src$yr, mon = src$mon, day = src$day,
      temp = t_new, rh = rh_new, ws = src$ws * wind_wt[i], prec = p_new,
      elev_m = zt$elev_mean[i], from_id = src$id,
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL

  if (!quiet) {
    span <- range(zt$elev_mean)
    dt <- lapse_rate * diff(span) / 1000
    cli::cli_h1("fev_downscale_weather")
    cli::cli_li("{nrow(zt)} zone{?s}, {round(span[1])} to {round(span[2])} m")
    cli::cli_li("Lapse rate {lapse_rate} K/km: \\
                {signif(dt, 3)} K between lowest and highest zone")
    if (identical(wind, "none") && is.null(grad$slope)) {
      cli::cli_alert_warning(
        "Wind and rain pass through unchanged. ISI keeps the coarse wind \\
         signal, DMC and DC the coarse rain signal: this corrects the \\
         fine-fuel path only."
      )
    } else {
      if (!identical(wind, "none")) {
        cli::cli_li("Wind by curvature: multiplier \\
                    {signif(min(wind_wt), 3)} to {signif(max(wind_wt), 3)}")
      }
      if (!is.null(grad$slope)) {
        cli::cli_li("Rain by fitted gradient: \\
                    {signif(100 * grad$relative, 3)}% per 1000 m \\
                    (R2 {signif(grad$r_squared, 2)}, \\
                    n {grad$n_points})")
      }
    }
    fev_once("downscale_percentile", cli::cli_alert_warning(
      "This helps a raw-FWI chain and hurts a percentile one: a lapse rate is \\
       a monotone transform, so it barely moves a day's rank inside its own \\
       series. Pair it with {.code normalise = \"minmax\"}. Shown once per \\
       session."
    ))
  }

  attr(out, "provenance") <- fev_prov_add_step(
    fev_layer_prov(zones) %||% fev_prov_new(crs_work = NA),
    fun = "fev_downscale_weather",
    params = list(n_zones = nrow(zt), lapse_rate = lapse_rate,
                  elev_range_m = paste(round(range(zt$elev_mean)), collapse = "-"),
                  corrected = paste(c("temp", "rh",
                                      if (!identical(wind, "none")) "ws",
                                      if (!is.null(grad$slope)) "prec"),
                                    collapse = ", "),
                  passed_through = paste(c(
                    if (identical(wind, "none")) "ws",
                    if (is.null(grad$slope)) "prec"), collapse = ", "),
                  wind = wind, curve_weight = curve_weight,
                  rain = rain,
                  rain_slope_mm_per_m = grad$slope %||% NA,
                  rain_fit_r2 = grad$r_squared %||% NA,
                  station_choice = if ("station" %in% names(zt))
                    "zone crossing" else "nearest to centroid"),
    notes = paste0(
      "temperature by lapse rate, humidity at constant dewpoint",
      if (!identical(wind, "none"))
        "; wind by MicroMet curvature only, its slope term needs a direction \
this package does not fetch" else "; wind uncorrected, ISI keeps the \
reanalysis structure",
      if (!is.null(grad$slope))
        "; rain by a gradient fitted on these points themselves" else
        "; rain uncorrected, DMC and DC keep the reanalysis structure"
    )
  )
  out
}

#' Relative humidity after a temperature change at constant dewpoint
#'
#' Magnus-Tetens. Cooling air without removing water raises its relative
#' humidity; the dewpoint is what stays put, so it is computed once from the
#' original pair and reused.
#'
#' @noRd
fev_rh_at_temperature <- function(t_old, rh_old, t_new) {
  a <- 17.67
  b <- 243.5
  rh <- pmin(pmax(rh_old, 1e-3), 100)
  gamma <- log(rh / 100) + a * t_old / (b + t_old)
  td <- b * gamma / (a - gamma)
  es <- function(x) 6.112 * exp(a * x / (b + x))
  # Clamped at 100: saturation is a ceiling, and a lapse-rate extrapolation far
  # enough up a mountain will cross it. Clamped at 1 because the FWI equations
  # divide by humidity terms and a zero is not a physical reading anyway.
  pmin(pmax(100 * es(td) / es(t_new), 1), 100)
}

#' @noRd
fev_zone_centroids <- function(zr, zones) {
  v <- terra::values(zr)[, 1]
  xy <- terra::xyFromCell(zr, seq_len(terra::ncell(zr)))
  do.call(rbind, lapply(zones, function(k) {
    i <- which(v == k)
    data.frame(zone = k, x = mean(xy[i, 1]), y = mean(xy[i, 2]))
  }))
}

#' @noRd
fev_nearest_station <- function(zxy, stations, crs_zones) {
  pts <- sf::st_as_sf(stations, coords = c("long", "lat"), crs = 4326)
  pts <- sf::st_transform(pts, sf::st_crs(crs_zones))
  zpt <- sf::st_as_sf(zxy, coords = c("x", "y"), crs = sf::st_crs(crs_zones))
  apply(sf::st_distance(zpt, pts), 1, which.min)
}

#' Run the FWI per zone and map it back onto the grid
#'
#' Accumulates the FWI codes independently in each zone — which is what makes
#' the downscaling mean anything, since the codes carry memory — then paints the
#' result onto the zone raster.
#'
#' @section Why this does not go through `fev_fwi_from_weather()`:
#' That function places each weather point on a regular longitude/latitude
#' lattice, because its points are reanalysis cell centres and they form one.
#' Zone representative points do not, and feeding them to it would produce a
#' sparse grid of mostly empty cells. Same engine, different assembly.
#'
#' @param weather A per-zone table from [fev_downscale_weather()].
#' @param zones The `fev_layer` from [fev_topo_zones()] the weather was
#'   downscaled onto.
#' @param index Which index to map, default `"FWI"`.
#' @param dates Dates to materialise, as `Date`. `NULL` gives every day in the
#'   table, which on a fine grid over a season is a large object — the function
#'   says how large before building it.
#' @param init,reset,reset_month As [fev_fwi_from_weather()].
#' @param quiet Suppress the report.
#'
#' @return A `fev_danger_layer` on the zone grid, one layer per date.
#'
#' @seealso [fev_downscale_weather()], [fev_fwi_percentile()] for what usually
#'   comes next.
#'
#' @export
fev_fwi_zonal <- function(weather, zones, index = "FWI", dates = NULL,
                          init = c(ffmc = 85, dmc = 6, dc = 15),
                          reset = c("none", "annual"), reset_month = 1L,
                          quiet = FALSE) {
  reset <- match.arg(reset)
  if (!is.data.frame(weather) || !"zone" %in% names(weather)) {
    fev_abort(c(
      "{.arg weather} must come from {.fn fev_downscale_weather}.",
      i = "It needs a {.field zone} column tying each series to a zone."
    ))
  }
  zr <- fev_as_raster(zones, "zones")[[1]]

  tab <- weather[order(weather$id, weather$yr, weather$mon, weather$day), ]
  fwi <- if (identical(reset, "annual")) {
    season <- tab$yr - (tab$mon < reset_month)
    do.call(rbind, lapply(split(tab, season), function(chunk) {
      fev_fwi_calc(chunk[order(chunk$id, chunk$yr, chunk$mon, chunk$day), ],
                   init = init)
    }))
  } else {
    fev_fwi_calc(tab, init = init)
  }
  if (!index %in% names(fwi)) {
    fev_abort(c(
      "No index {.val {index}} in the result.",
      i = "Available: {.val {setdiff(names(fwi), c('ID','LAT','LONG','YR','MON','DAY'))}}."
    ), .envir = environment())
  }

  fwi$date <- as.Date(sprintf("%d-%02d-%02d", fwi$YR, fwi$MON, fwi$DAY))
  fwi$zone <- as.integer(sub("^zone", "", fwi$ID))
  want <- if (is.null(dates)) sort(unique(fwi$date)) else as.Date(dates)
  unknown <- setdiff(as.character(want), as.character(unique(fwi$date)))
  if (length(unknown)) {
    fev_abort(c(
      "{length(unknown)} requested date{?s} not in the weather: \\
       {.val {utils::head(unknown, 3)}}.",
      i = "Range available: {.val {as.character(range(fwi$date))}}."
    ), .envir = environment())
  }

  cost <- terra::ncell(zr) * length(want)
  if (!quiet && cost > 5e7) {
    fev_inform(c(
      "{length(want)} day{?s} on {terra::ncell(zr)} cells is \\
       {signif(cost / 1e6, 3)} million values.",
      i = "Pass {.arg dates} to materialise only the days you need."
    ), .envir = environment())
  }

  layers <- lapply(want, function(d) {
    sub <- fwi[fwi$date == d, ]
    terra::classify(zr, cbind(sub$zone, sub[[index]]), others = NA)
  })
  out <- terra::rast(layers)
  terra::time(out) <- want
  names(out) <- format(want, "d%Y%m%d")

  if (!quiet) {
    rng <- as.numeric(terra::global(out[[1]], range, na.rm = TRUE)[1, ])
    cli::cli_h1("fev_fwi_zonal: {index}")
    cli::cli_li("{length(want)} day{?s} over \\
                {length(unique(fwi$zone))} zone{?s}")
    cli::cli_li("First day spans {signif(rng[1], 4)} to {signif(rng[2], 4)}")
  }

  prov <- attr(weather, "provenance") %||% fev_prov_new(crs_work = NA)
  prov <- fev_prov_add_step(
    prov, fun = "fev_fwi_zonal",
    params = list(index = index, n_zones = length(unique(fwi$zone)),
                  n_days = length(want), init = as.list(init),
                  reset = reset,
                  engine = "cffdrs::fwi (batch, per-zone accumulation)"),
    notes = paste0(
      "codes accumulated per topographic zone from downscaled inputs, not ",
      "adjusted after the fact: FFMC, DMC and DC carry memory and could not ",
      "be corrected retrospectively"
    )
  )

  new_fev_layer(out, role = "fwi", provenance = prov,
                units = "FWI system, dimensionless",
                class = "fev_danger_layer")
}
