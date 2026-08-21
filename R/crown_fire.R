# Crown fire thresholds, which is where the LiDAR campaign finally pays off.
#
# Phase 12 step 3, and only the part that can be done from a desk. The damage
# function itself needs field plots and is not attempted here.
#
# What this file does is bridge a gap the package has carried since phase 6:
# fev_risk() outputs a number between 0 and 1, and no published damage curve
# takes a dimensionless index. Curves take an INTENSITY, in kW/m. Byram gives
# one from a fuel load and a spread rate -- and fev_fuel_lidar() has measured
# the load in kg/m2 across 32 windows of the Maures.
#
# Van Wagner's two criteria then consume exactly what the same campaign
# measures: crown base height decides whether a surface fire climbs, canopy bulk
# density decides whether it keeps going once up. The 0.05 to 0.32 kg/m3 range
# of CBD_max measured on the Maures is not decoration; it is the input.
#
# Everything here was verified in Scott and Reinhardt (2001), RMRS-RP-29, read
# as a PDF rather than summarised -- including the worked examples, which are
# the real check:
#
#   eq. 1   I = H Wf R / 60, H = 18 000 kJ/kg for canopy fuels
#   eq. 11  I'initiation = [CBH (460 + 25.9 FMC) / 100]^1.5
#           worked: CBH 3 m, FMC 100% -> 875 kW/m
#   eq. 14  R'active = 3.0 / CBD
#           worked: CBD 0.2 kg/m3 -> 15.0 m/min
#
# Two renderings of eq. 11 circulate, differing in where the 1.5 exponent sits.
# The worked example settles it: only the bracketed form returns 875.

#' Byram's fireline intensity
#'
#' Turns a fuel load and a rate of spread into an intensity in kW/m — the unit
#' every published damage and mortality curve expects, and the one this package
#' has never produced.
#'
#' @section Why the package needed this:
#' [fev_risk()] returns a number in `[0, 1]`. No fragility curve takes such a
#' thing: they take kW/m, or a flame length derived from it. So nothing could be
#' branched onto the risk layer, and the vulnerability half stayed a normalised
#' asset density. Byram is the bridge, and the LiDAR campaign supplies its
#' hardest term — `fev_fuel_lidar()` measures crown fuel load in kg/m².
#'
#' @section What it does not know:
#' The **rate of spread** is not measured by anything in this package. It comes
#' from a spread model — Rothermel, or the Canadian FBP system — fed by wind,
#' slope and surface fuel. Passing a plausible number here produces a plausible
#' intensity, and there is no way for the function to tell the difference. It is
#' recorded, not validated.
#'
#' And `fuel_load` must be the fuel consumed **in the flaming front**, not the
#' total load. Scott and Reinhardt are explicit that Byram's "available fuel"
#' excludes what burns in smouldering combustion. Handing it a total load
#' overstates the intensity.
#'
#' @param fuel_load Fuel consumed in the flaming front, kg/m². A `SpatRaster`,
#'   `fev_layer` or number.
#' @param spread_rate Forward rate of spread, m/min.
#' @param heat_yield Heat yield of the fuel, kJ/kg. Default 18000, the value
#'   Scott and Reinhardt assume for canopy fuels after Finney.
#'
#' @return Fireline intensity in kW/m, in the shape of `fuel_load`.
#'
#' @seealso [fev_crown_fire()] for the thresholds it feeds.
#'
#' @source
#' Scott, J. H. and Reinhardt, E. D. (2001). *Assessing crown fire potential by
#' linking models of surface and crown fire behavior*. USDA Forest Service
#' Research Paper RMRS-RP-29, equation 1, after Byram (1959).
#'
#' Read from the paper on 2026-08-21, not from a summary.
#'
#' @examples
#' # A crown fuel load of 1 kg/m2 spreading at 15 m/min.
#' fev_byram_intensity(1, 15)
#'
#' @export
fev_byram_intensity <- function(fuel_load, spread_rate, heat_yield = 18000) {
  if (!is.numeric(spread_rate) || length(spread_rate) != 1L ||
      is.na(spread_rate) || spread_rate < 0) {
    fev_abort("{.arg spread_rate} must be a single non-negative number, in \\
               m/min.")
  }
  if (!is.numeric(heat_yield) || length(heat_yield) != 1L ||
      is.na(heat_yield) || heat_yield <= 0) {
    fev_abort("{.arg heat_yield} must be a single positive number, in kJ/kg.")
  }
  w <- fev_crown_numeric(fuel_load, "fuel_load")
  # The 60 converts m/min to m/s so the result reduces to kW/m.
  heat_yield * w * spread_rate / 60
}

#' Van Wagner's crown fire thresholds
#'
#' Two questions, two criteria, and the package now measures the input to both:
#' does a surface fire climb into the canopy, and once up does it keep going.
#'
#' @section Initiation, decided by crown base height:
#' A surface fire crowns when its intensity exceeds
#' `[CBH (460 + 25.9 FMC) / 100]^1.5`. Low crowns crown easily: at 100% foliar
#' moisture, 1 m of clearance needs 168 kW/m and 6 m needs 2 476 — a factor of
#' fifteen for a factor of six in height.
#'
#' This is why the FSG and CBH the LiDAR campaign measures matter more than the
#' species. Of 32 windows on the Maures, 14 had FSG below 0.5 m: the understorey
#' reaches the crowns, and the clearance that would stop a surface fire is not
#' there.
#'
#' @section Propagation, decided by canopy bulk density:
#' Once in the canopy, active spread needs a mass flow of fuel into the flaming
#' zone, so the fire must move at least `3.0 / CBD` m/min. A dense canopy
#' sustains crowning at a slower spread rate; a sparse one needs the fire to run.
#'
#' The Maures measurements put CBD_max between 0.05 and 0.32 kg/m³, which is a
#' critical spread rate between 60 and 9 m/min — a range wide enough that the
#' answer genuinely depends on the stand.
#'
#' @section What this is not:
#' A threshold, not a damage function. It says whether a crown fire is possible,
#' not what it destroys. And both criteria are Van Wagner's, developed on
#' Canadian conifers: nothing here has been calibrated on cork oak or maquis,
#' any more than the exposure radii were.
#'
#' @param cbh Crown base height, m. A `SpatRaster`, `fev_layer` or number —
#'   `fev_fuel_lidar()` produces `CBH`.
#' @param cbd Canopy bulk density, kg/m³, as `fev_fuel_lidar()` produces
#'   `CBD_max`. Optional; without it only the initiation threshold is returned.
#' @param fmc Foliar moisture content, percent. Default 100, the value Scott and
#'   Reinhardt use in their worked example. It is a season and a species, not a
#'   constant, and it is recorded.
#' @param intensity Surface fireline intensity, kW/m, from
#'   [fev_byram_intensity()]. Optional; with it the result says whether the
#'   threshold is passed rather than only where it sits.
#' @param spread_rate Forward rate of spread, m/min. Optional; with `cbd` it
#'   says whether active crowning can be sustained.
#' @param quiet Suppress the standing caveat.
#'
#' @return A `SpatRaster` or numeric vector with `i_initiation` (kW/m) and, when
#'   `cbd` is given, `r_active` (m/min). With `intensity` or `spread_rate`, the
#'   logical layers `crowns` and `active` are added.
#'
#' @seealso [fev_fuel_lidar()] for the measurements this consumes,
#'   [fev_byram_intensity()] for the intensity.
#'
#' @source
#' Van Wagner, C. E. (1977), as formulated by Scott and Reinhardt (2001), USDA
#' Forest Service Research Paper RMRS-RP-29, equations 11 and 14.
#'
#' Verified on 2026-08-21 against the paper's own worked examples, which is a
#' stronger check than reading the equations: CBH 3 m at 100% FMC gives
#' **875 kW/m**, and CBD 0.2 kg/m³ gives **15.0 m/min**. Both reproduce exactly.
#'
#' The paper's figure 5 caption states the critical mass flow rate as
#' 0.05 kg m-2 **min**-1 where its text says 0.05 kg m-2 **sec**-1. The text is
#' right — 0.05 kg/m²/s times 60 gives the 3.0 of equation 14 — and the caption
#' is a slip in the source.
#'
#' @examples
#' # The paper's own examples.
#' fev_crown_fire(cbh = 3, fmc = 100, quiet = TRUE)[["i_initiation"]]
#' fev_crown_fire(cbh = 3, cbd = 0.2, quiet = TRUE)[["r_active"]]
#'
#' @export
fev_crown_fire <- function(cbh,
                           cbd = NULL,
                           fmc = 100,
                           intensity = NULL,
                           spread_rate = NULL,
                           quiet = FALSE) {
  if (!is.numeric(fmc) || length(fmc) != 1L || is.na(fmc) || fmc <= 0) {
    fev_abort("{.arg fmc} must be a single positive percentage.")
  }
  h <- fev_crown_numeric(cbh, "cbh")

  # Equation 11. The whole bracket is raised to 1.5 -- the paper's worked
  # example, 875 kW/m for CBH 3 m at 100% FMC, is what settles the two
  # renderings that circulate.
  i_init <- (h * (460 + 25.9 * fmc) / 100)^1.5
  out <- fev_crown_name(i_init, "i_initiation")

  if (!is.null(cbd)) {
    d <- fev_crown_numeric(cbd, "cbd")
    # Equation 14, from a critical mass flow of 0.05 kg/m2/s times 60.
    r_act <- 3.0 / d
    out <- fev_crown_bind(out, fev_crown_name(r_act, "r_active"))
  }

  if (!is.null(intensity)) {
    i <- fev_crown_numeric(intensity, "intensity")
    out <- fev_crown_bind(out, fev_crown_name(i > i_init, "crowns"))
  }
  if (!is.null(spread_rate) && !is.null(cbd)) {
    s <- fev_crown_numeric(spread_rate, "spread_rate")
    out <- fev_crown_bind(out, fev_crown_name(s >= 3.0 / d, "active"))
  }

  if (!quiet) {
    fev_once("crown_fire_calibration", fev_inform(c(
      "Van Wagner's criteria were developed on Canadian conifers.",
      i = "Nothing here is calibrated on cork oak or maquis, any more than the \\
           exposure radii were. {.arg fmc} = {.val {fmc}}% is a season and a \\
           species, not a constant.",
      i = "A threshold is not a damage function: it says whether a crown fire \\
           is possible, not what it destroys.",
      i = "Shown once per session."
    ), .envir = environment()))
  }
  out
}

#' @noRd
fev_crown_numeric <- function(x, arg) {
  if (inherits(x, c("fev_layer", "fev_source"))) {
    return(fev_data(x))
  }
  if (inherits(x, "SpatRaster") || is.numeric(x)) {
    return(x)
  }
  fev_abort("{.arg {arg}} must be a number, a {.cls SpatRaster} or a \\
             {.cls fev_layer}.", .envir = environment())
}

#' Name a result, keeping its type
#'
#' A list rather than a named vector for the non-raster case, because
#' `c(numeric, logical)` coerces and `crowns` would come back as 0 and 1. The
#' distinction matters: a threshold crossed is a fact, not a quantity.
#'
#' @noRd
fev_crown_name <- function(x, nm) {
  if (inherits(x, "SpatRaster")) {
    names(x) <- nm
    x
  } else {
    stats::setNames(list(x), nm)
  }
}

#' @noRd
fev_crown_bind <- function(a, b) {
  c(a, b)
}
