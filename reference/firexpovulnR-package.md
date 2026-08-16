# firexpovulnR: Fire Danger, Exposure and Vulnerability Assessment for European Forests

Reproducible processing chain combining fire weather danger (Fire
Weather Index calibrated on regional percentiles), fuel-based fire
exposure metrics, and vulnerability of exposed assets into a composite
risk index, for European forest study areas with metropolitan France as
the primary field. Every imported threshold is an explicit, documented
and overridable parameter, and every analysis carries a full provenance
record. Intended for internal research use, not for CRAN submission.

## Design principles

Four rules govern the whole package, and every function is expected to
honour them:

- No hard-coded thresholds:

  Every radius, class break and lookup table imported from a publication
  or an external service is an argument with a sourced default, fully
  overridable.

- One reprojection:

  The working CRS (`crs_work`, default `2154`) is that of the primary
  fuel source. Auxiliary layers are reprojected as late as possible; the
  primary source never is.

- Provenance everywhere:

  Every
  [`fev_stack()`](https://pobsteta.github.io/firexpovulnR/reference/fev_stack.md)
  carries its sources, vintages, calibration period and the full set of
  parameters used.
  [`fev_provenance()`](https://pobsteta.github.io/firexpovulnR/reference/fev_provenance.md)
  exports the record as YAML.

- Explicit scale changes:

  Resampling between kilometric danger and decametric exposure goes
  through
  [`fev_align()`](https://pobsteta.github.io/firexpovulnR/reference/fev_align.md),
  which warns and logs. There is no implicit alignment anywhere else.

## Imported parameters that are not validated for Europe

The package draws defaults from work calibrated outside temperate and
Mediterranean Europe. They are usable, but their transposition is not
established: exposure radii come from boreal and coniferous Canadian
fuels, and FWI danger classes are operational service thresholds rather
than physical constants. Neither CORINE nor BD Forêt v2 describes the
understorey or the fuel load, although surface spread depends on it
directly.

## See also

Useful links:

- <https://github.com/pobsteta/firexpovulnR>

- Report bugs at <https://github.com/pobsteta/firexpovulnR/issues>

## Author

**Maintainer**: Pascal Obstétar <pascal.obstetar@gmail.com>

Authors:

- Pascal Obstétar <pascal.obstetar@gmail.com>
