# The wildland-urban interface, which everything in this package pointed at and
# nothing computed.
#
# The brief names it, the WorldCover lookup notes name it ("the wildland-urban
# interface is where exposure matters most"), and fev_risk() documents it as the
# CLIMAAX dimension expected in `...`. It was the one term in that sentence with
# no function behind it.

#' The wildland-urban interface
#'
#' Where people and burnable vegetation are close enough that one reaches the
#' other: cells holding assets with fuel within `distance`, and optionally the
#' converse — fuel with assets within `distance`.
#'
#' @section Which definition this is:
#' There is no single WUI. The literature splits broadly into a **housing
#' density** definition (the US federal register's interface and intermix,
#' thresholds on structures per unit area) and a **proximity** definition
#' (anything built within a set distance of wildland). This function implements
#' the second, because it is the one the package's inputs can actually support:
#' GHS-POP gives a modelled population surface, not a structure count, and
#' counting structures per hectare from it would be inventing a precision the
#' source does not carry.
#'
#' The consequence is worth stating plainly: this identifies *proximity*, not
#' *risk to a dwelling*. A single isolated house 80 m from maquis and a dense
#' hamlet 80 m from the same maquis both come out as interface, and the second
#' is a far larger problem.
#'
#' @section Distance is measured through the window, not around obstacles:
#' The neighbourhood is a disc of radius `distance`, so a river, a motorway or a
#' cliff between the assets and the fuel counts for nothing. Fire does cross
#' most of those; embers cross all of them. That is the argument for the simple
#' version, and it is also the reason not to read the output as a fire-break
#' analysis.
#'
#' @section Two sides, and why both are offered:
#' `side = "assets"` returns the exposed assets — what a mayor asks for. `"fuel"`
#' returns the fuel that threatens them — what a forester asks for, since that
#' is where clearing obligations apply. `"both"` returns their union. The three
#' answer different questions and the record says which was asked.
#'
#' @param assets A raster of exposed assets: a [fev_source] from
#'   [fev_fetch_ghsl()], a `fev_layer`, or a `SpatRaster`. Cells above
#'   `assets_min` count as present.
#' @param fuel A [fev_fuel_source], `fev_layer` or `SpatRaster`, reduced to a
#'   burnable mask exactly as [fev_exposure()] reduces it.
#' @param distance Interface distance, in CRS units. Default 100 m, the
#'   short-range ember scale of [fev_exposure_radii()] and the order of the
#'   French *obligation légale de débroussaillement*. It is a parameter, not a
#'   constant: pass what your context justifies.
#' @param assets_min Threshold above which an assets cell counts as present.
#'   Default `0`, i.e. any non-zero value. With a modelled population surface
#'   that is a low bar — GHS-POP spreads fractions of a person over cells with a
#'   trace of built-up — so raise it when the result looks implausibly wide.
#' @param side `"assets"`, `"fuel"` or `"both"`.
#' @param lookup Passed to the fuel reduction, as in [fev_exposure()].
#' @param quiet Suppress the report.
#'
#' @return A `fev_layer` of role `"wui"`, values 1 on the interface and 0
#'   elsewhere, ready to enter [fev_risk()] as a further dimension.
#'
#' @seealso [fev_fetch_ghsl()] for an assets source, [fev_exposure()] for the
#'   graded metric this complements, [fev_risk()] to combine them.
#'
#' @examples
#' g <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 200,
#'                  ymin = 0, ymax = 200, crs = "EPSG:2154")
#' # Fuel on the left half, one inhabited cell just across the divide.
#' fuel <- terra::setValues(g, rep(rep(c(1, 0), each = 10), 20))
#' pop <- terra::setValues(g, 0)
#' pop[10, 12] <- 50
#' wui <- fev_wui(pop, fuel, distance = 30, quiet = TRUE)
#' terra::global(fev_data(wui), "sum", na.rm = TRUE)
#'
#' @export
fev_wui <- function(assets,
                    fuel,
                    distance = 100,
                    assets_min = 0,
                    side = c("assets", "fuel", "both"),
                    lookup = NULL,
                    quiet = FALSE) {
  side <- match.arg(side)
  if (!is.numeric(distance) || length(distance) != 1L || is.na(distance) ||
      distance <= 0) {
    fev_abort("{.arg distance} must be a single positive number, in CRS units.")
  }

  resolved <- fev_exposure_input(fuel, lookup)
  burnable <- resolved$raster
  prov <- resolved$provenance %||% fev_prov_new(crs_work = NA)

  a <- fev_as_raster(assets, "assets")[[1]]
  if (!terra::compareGeom(a, burnable, stopOnError = FALSE)) {
    fev_abort(c(
      "The assets and fuel grids do not match.",
      i = "As everywhere outside {.fn fev_align}, mismatched grids are an \\
           error rather than a silent resample.",
      i = "{.fn fev_align} exists for exactly this, and records what it did."
    ), class = "fev_grid_mismatch")
  }

  res <- terra::res(burnable)[1]
  if (distance < res) {
    fev_abort(c(
      "{.arg distance} = {.val {distance}} is below the cell size \\
       ({.val {signif(res, 6)}}).",
      i = "The neighbourhood would be the cell itself, and every asset cell \\
           holding fuel would be its own interface."
    ), .envir = environment())
  }

  # A burnable mask is 1 and NA, not 1 and 0: a source covering only wooded
  # formations has no zeroes at all. Treat absence as not-burnable HERE, which
  # is right for a maximum over the window and would be wrong for the
  # proportion fev_exposure() computes -- hence doing it here and not there.
  b01 <- terra::classify(burnable, cbind(NA, 0))
  a01 <- terra::classify(a, cbind(NA, 0)) > assets_min

  w <- fev_disc_window(res, distance)
  fuel_near <- terra::focal(b01, w = w, fun = "max", na.rm = TRUE) > 0
  assets_near <- terra::focal(terra::as.int(a01), w = w, fun = "max",
                              na.rm = TRUE) > 0

  out <- switch(
    side,
    assets = a01 & fuel_near,
    fuel   = (b01 > 0) & assets_near,
    both   = (a01 & fuel_near) | ((b01 > 0) & assets_near)
  )
  out <- terra::as.int(out)
  names(out) <- "wui"

  n_wui <- as.numeric(terra::global(out, "sum", na.rm = TRUE)[1, 1])
  area_ha <- n_wui * res^2 / 1e4

  if (!quiet) {
    cli::cli_h1("fev_wui: {side}")
    cli::cli_li("Interface distance: {distance} {if (res > 1) 'm' else 'units'}")
    cli::cli_li("{round(n_wui)} cell{?s}, {signif(area_ha, 4)} ha")
    cli::cli_alert_info(
      "Proximity, not housing density: an isolated house and a dense hamlet \\
       at the same distance from the same fuel score identically."
    )
  }

  prov <- fev_prov_add_step(
    prov, fun = "fev_wui",
    params = list(distance = distance, side = side, assets_min = assets_min,
                  res = signif(res, 6), window_cells = sum(!is.na(w)),
                  cells = round(n_wui), area_ha = signif(area_ha, 6)),
    notes = paste0(
      "proximity definition, not housing density; distance measured through ",
      "a disc window, so rivers, roads and cliffs between assets and fuel ",
      "count for nothing"
    )
  )

  new_fev_layer(out, role = "wui", provenance = prov, units = "1 = interface")
}

#' A filled disc window, unlike the annulus exposure uses
#'
#' The centre cell is INCLUDED here, and that is the difference from
#' `fev_annulus_window()`. Exposure asks what can reach a place, so it excludes
#' where it already stands; the interface asks whether fuel and people are
#' close, and a house standing in the maquis is the interface case par
#' excellence.
#'
#' @noRd
fev_disc_window <- function(res, distance) {
  n <- floor((distance / res) * 2 + 1)
  if (n %% 2 == 0) {
    n <- n + 1
  }
  offsets <- (seq_len(n) - (n + 1) / 2) * res
  x <- matrix(offsets, nrow = n, ncol = n, byrow = TRUE)
  y <- matrix(offsets, nrow = n, ncol = n, byrow = FALSE)
  w <- matrix(NA_real_, nrow = n, ncol = n)
  w[sqrt(x^2 + y^2) <= distance] <- 1
  w
}
