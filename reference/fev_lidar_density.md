# Effective pulse and point density of a point cloud

Measures what the LiDAR HD specification is written in — pulses per
square metre — rather than the point count that is easier to compute.

## Usage

``` r
fev_lidar_density(las)
```

## Source

Density specification: IGN, *Nuages de points LiDAR HD*, at least 10
pulses per m² and 5 above 3200 m, verified 2026-08-17. Direction of the
bias with decreasing density: stated in the brief governing this
package, and consistent with the null-return path of
[`lidarforfuel::fCBDprofile_fuelmetrics()`](https://rdrr.io/pkg/lidarforfuel/man/fCBDprofile_fuelmetrics.html).

## Arguments

- las:

  A `LAS` object, or anything
  [`lidR::readLAS()`](https://rdrr.io/pkg/lidR/man/readLAS.html)
  accepts.

## Value

A list with `pulses_per_m2`, `points_per_m2`, `n_points`, `n_pulses` and
`area_m2`.

## Why pulses and not points

IGN specifies LiDAR HD at **at least 10 pulses/m²**, and 5 pulses/m²
above 3200 m of altitude. A pulse produces several returns in
vegetation, so point density overstates the figure the specification is
about, sometimes by a factor of two. Pulses are counted here as first
returns.

## Why it matters more here than elsewhere

Density does not degrade the result gracefully, it biases it in a known
direction. As pulses thin out, the understorey stratum is the first
thing to disappear from the profile — so fuel load is **underestimated**
— while crown base height and the gap between strata are
**overestimated**, because the lowest returns that would have defined
them are missing. A thin tile therefore reports a safer landscape than
it has.

## See also

[`fev_fuel_lidar()`](https://pobsteta.github.io/firexpovulnR/reference/fev_fuel_lidar.md),
which refuses to compute below a threshold.

## Examples

``` r
if (FALSE) { # \dontrun{
las <- lidR::readLAS("LHD_FXX_0968_6240_PTS_C_LAMB93_IGN69.copc.laz")
fev_lidar_density(las)
} # }
```
