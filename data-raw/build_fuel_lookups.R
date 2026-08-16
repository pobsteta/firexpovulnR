# Build the fuel correspondence tables shipped in inst/extdata/.
#
# Run with:  Rscript data-raw/build_fuel_lookups.R
#
# The brief requires every correspondence table to live here, to be justified
# line by line, and to be fully overridable by the user. This script is the
# authority: the CSVs in inst/extdata/ are build products and must never be
# edited by hand. Edit a row here, re-run, commit both.
#
# ---------------------------------------------------------------------------
# What is sourced and what is not -- read this before trusting the tables
# ---------------------------------------------------------------------------
#
# `code` and `label` are the producers' own values, verified at their source
# (see specs/phase2-rapport-faisabilite.md, sections 3 and 7). They are copied,
# not reconstructed.
#
# `crown_cover` is read off the BD Forêt v2 nomenclature itself: "forêt fermée"
# is tree cover above 40%, "forêt ouverte" between 10 and 40%. That is the
# producer's definition, not an interpretation.
#
# `fuel_type` and `burnable` are NOT sourced. They are this package's reading of
# what each nomenclature class means for fire, and they are the two columns a
# user is most likely to disagree with -- which is why every row carries a
# `confidence` flag and a `notes` sentence saying what the doubt is. Nothing
# here is imported from a published fuel model: mapping these classes onto
# Anderson 13, Scott & Burgan 40 or the Prometheus models is a separate step
# this package does not ship, because no such correspondence was verified at a
# source during phase 2.
#
# The vocabulary of `fuel_type` is shared by both tables so that a merged layer
# stays interpretable across vocabularies. It is structural, because structure
# is all these two databases actually record.

# --------------------------------------------------------------------------
# Row helpers
# --------------------------------------------------------------------------
# One row per call, columns in a fixed order, so that a reviewer reads the
# table as a table and a typo shifts nothing silently.

r <- function(code, label, crown_cover, fuel_type, burnable, confidence, notes) {
  data.frame(
    code        = code,
    label       = label,
    crown_cover = crown_cover,
    fuel_type   = fuel_type,
    burnable    = burnable,
    confidence  = confidence,
    notes       = notes,
    stringsAsFactors = FALSE
  )
}

tibble_rows <- function(...) do.call(rbind, list(...))

# The closed vocabulary of fuel types. Anything outside it is a typo, and the
# validation below refuses to write a table that uses one.
FUEL_TYPES <- c(
  "sclerophyll_closed",   # evergreen sclerophyllous forest (holm, cork oak)
  "broadleaf_closed",     # closed broadleaf, predominantly deciduous
  "conifer_closed",       # closed conifer
  "mixed_closed",         # closed broadleaf/conifer mixture
  "broadleaf_open",       # 10-40% tree cover, broadleaf
  "conifer_open",         # 10-40% tree cover, conifer
  "mixed_open",           # 10-40% tree cover, mixed
  "poplar_plantation",    # alluvial poplar, managed floor
  "unstocked",            # forest land with no current tree cover
  "shrubland",            # heath, maquis, garrigue, moor
  "transitional_shrub",   # regeneration and encroachment, transient
  "grassland",            # herbaceous formation
  "agroforestry",         # scattered trees over grazed grass (dehesa)
  "mosaic_agri_natural",  # agriculture with significant natural vegetation
  "sparse_vegetation",    # under 50% cover
  "burnt_regrowth",       # burnt at the source vintage
  "urban_vegetation",     # parks, campsites, leisure grounds
  "cropland",             # worked agricultural land
  "non_fuel"              # sealed, mineral, water, ice
)

# --------------------------------------------------------------------------
# BD Forêt v2 -- TFV nomenclature, 32 classes
# --------------------------------------------------------------------------
#
# Codes and French labels: the 32 posts announced by cartes.gouv.fr, taken from
# nemeton/inst/extdata/bdforet_v2_mapping.csv where they were already verified,
# and cross-checked against the attributes the IGN WFS actually serves
# (`code_tfv`, `tfv`, `tfv_g11`) on a Var/Maures extraction, 2026-08-15.
#
# The other columns of that file (`species_class`, `context_key`) are NOT
# reused: they encode silvicultural semantics -- stand structure, sampling
# design -- which have nothing to do with flammability. They are rebuilt from
# zero here.

bdforet <- tibble_rows(
  # code          label                                                              crown    fuel_type            burnable confidence  notes
  r("FF0",        "Forêt fermée sans couvert arboré",                 "none",  "unstocked",         TRUE,    "ambiguous", "Clearcut or disturbance inside closed forest. Burnable is a judgement call: fresh logging slash is among the most flammable states a stand ever reaches, while a scraped or replanted cut carries almost nothing. The database does not say which, and gives no date. Flagged TRUE because slash is the more dangerous error."),
  r("FF1-00",     "Forêt fermée de feuillus purs en îlots",            "closed","broadleaf_closed",  TRUE,    "ambiguous", "Broadleaf islets. The dominant species is not stated, so evergreen sclerophyll stands (holm oak, cork oak) cannot be separated from deciduous ones -- a distinction that matters for flammability. Defaults to the deciduous reading, which is the more common case nationally."),
  r("FF1G01-01",  "Forêt fermée de chênes décidus purs",          "closed","broadleaf_closed",  TRUE,    "clear",     "Deciduous oak. Burnable, but leaf-off for part of the year and with a moister litter regime than the evergreen oaks -- do not treat it as equivalent to FF1G06-06."),
  r("FF1G06-06",  "Forêt fermée de chênes sempervirents purs",         "closed","sclerophyll_closed",TRUE,    "clear",     "Holm and cork oak. Given its own fuel type rather than folded into broadleaf: evergreen sclerophyllous foliage, year-round crown fuel, and typically a dense shrub understorey. This is the single most important Mediterranean fuel type the BD Forêt can resolve and CORINE cannot -- CLC 311 lumps it with beech."),
  r("FF1-09-09",  "Forêt fermée de hêtre pur",                         "closed","broadleaf_closed",  TRUE,    "clear",     "Beech. Burnable but at the low end: dense shade, sparse understorey, moist litter. Kept TRUE because a burnable mask is not a flammability ranking; use fev_fuel_availability() to weight it down."),
  r("FF1-10-10",  "Forêt fermée de châtaignier pur",                   "closed","broadleaf_closed",  TRUE,    "clear",     "Chestnut, usually coppiced. Coppice means a dense low stratum, so the understorey assumption embedded in 'broadleaf_closed' understates it."),
  r("FF1-14-14",  "Forêt fermée de robinier pur",                           "closed","broadleaf_closed",  TRUE,    "clear",     "Black locust, usually coppiced, frequently on disturbed ground with a grassy or brambly understorey."),
  r("FF1-49-49",  "Forêt fermée d'un autre feuillu pur",                    "closed","broadleaf_closed",  TRUE,    "ambiguous", "Catch-all for pure broadleaf stands of any other species. The species is unknown by construction, so the fuel type is a default, not a determination. Override this row if your study area has a known dominant."),
  r("FF1-00-00",  "Forêt fermée à mélange de feuillus",           "closed","broadleaf_closed",  TRUE,    "clear",     "Mixed broadleaf."),
  r("FF2-00",     "Forêt fermée de conifères purs en îlots",       "closed","conifer_closed",    TRUE,    "clear",     "Conifer islets, generally plantation."),
  r("FF2-51-51",  "Forêt fermée de pin maritime pur",                       "closed","conifer_closed",    TRUE,    "clear",     "Maritime pine. Landes plantations: high crown fuel, and a heath or gorse understorey the database does not record."),
  r("FF2-52-52",  "Forêt fermée de pin sylvestre pur",                      "closed","conifer_closed",    TRUE,    "clear",     "Scots pine."),
  r("FF2G53-53",  "Forêt fermée de pin laricio ou pin noir pur",            "closed","conifer_closed",    TRUE,    "clear",     "Laricio and black pine, largely planted, often even-aged and dense."),
  r("FF2-57-57",  "Forêt fermée de pin d'Alep pur",                         "closed","conifer_closed",    TRUE,    "clear",     "Aleppo pine. The emblematic Mediterranean fire fuel: resinous, low crown base, serotinous regeneration, and near-systematically over a maquis or garrigue understorey that the BD Forêt cannot see."),
  r("FF2G58-58",  "Forêt fermée de pin à crochets ou pin cembro pur",   "closed","conifer_closed",    TRUE,    "clear",     "Mountain and Swiss stone pine, subalpine. Burnable, but in a fire regime with little in common with the lowland Mediterranean one."),
  r("FF2-81-81",  "Forêt fermée d'un autre pin pur",                        "closed","conifer_closed",    TRUE,    "clear",     "Generic pure pine."),
  r("FF2-80-80",  "Forêt fermée à mélange de pins purs",          "closed","conifer_closed",    TRUE,    "clear",     "Pine mixture."),
  r("FF2G61-61",  "Forêt fermée de sapin ou épicéa",              "closed","conifer_closed",    TRUE,    "clear",     "Fir and spruce, mostly montane."),
  r("FF2-63-63",  "Forêt fermée de mélèze pur",                    "closed","conifer_closed",    TRUE,    "clear",     "Larch: a deciduous conifer, so leaf-off in winter and with a grassy understorey. Treated as conifer_closed for structure, which overstates its crown fuel outside the growing season."),
  r("FF2-64-64",  "Forêt fermée de douglas pur",                            "closed","conifer_closed",    TRUE,    "clear",     "Douglas fir plantation."),
  r("FF2-91-91",  "Forêt fermée d'un autre conifère pur autre que pin", "closed","conifer_closed",    TRUE,    "clear",     "Generic pure conifer other than pine."),
  r("FF2-90-90",  "Forêt fermée à mélange d'autres conifères","closed","conifer_closed",   TRUE,    "clear",     "Mixture of conifers other than pine."),
  r("FF2-00-00",  "Forêt fermée à mélange de conifères",     "closed","conifer_closed",    TRUE,    "clear",     "Conifer mixture."),
  r("FF31",       "Forêt fermée à mélange de feuillus prépondérants et conifères", "closed","mixed_closed", TRUE, "clear", "Broadleaf-dominant mixture. Vertical mixtures raise crown continuity, which matters for torching, and neither database records it."),
  r("FF32",       "Forêt fermée à mélange de conifères prépondérants et feuillus","closed","mixed_closed", TRUE, "clear", "Conifer-dominant mixture."),
  r("FO0",        "Forêt ouverte sans couvert arboré",                      "none",  "unstocked",         TRUE,    "ambiguous", "Open forest with no tree cover left. Same reasoning as FF0."),
  r("FO1",        "Forêt ouverte de feuillus purs",                              "open",  "broadleaf_open",    TRUE,    "clear",     "Tree cover 10-40%, so a continuous herb or shrub stratum under the trees. This is the closest the BD Forêt gets to describing an understorey, and it is still far short of what surface spread would need."),
  r("FO2",        "Forêt ouverte de conifères purs",                        "open",  "conifer_open",      TRUE,    "clear",     "Open conifer. Discontinuous crowns over a continuous surface fuel bed -- often more dangerous for surface spread than the closed equivalent, not less."),
  r("FO3",        "Forêt ouverte à mélange de feuillus et conifères","open","mixed_open",       TRUE,    "clear",     "Open mixed forest."),
  r("FP",         "Peupleraie",                                                       "closed","poplar_plantation", TRUE,    "clear",     "Poplar plantation. Given its own type: alluvial, often damp, with a grassy managed floor and no shrub layer, so it behaves nothing like the other closed broadleaf stands."),
  r("LA4",        "Lande",                                                            "none",  "shrubland",         TRUE,    "clear",     "Heath, maquis and garrigue. Non-forest but among the most flammable fuels in the Mediterranean, which is exactly why the fuel abstraction must not be restricted to forest classes."),
  r("LA6",        "Formation herbacée",                                          "none",  "grassland",         TRUE,    "clear",     "Herbaceous formation. Fast-drying fine fuel, rapid spread, low intensity, strongly seasonal.")
)

# --------------------------------------------------------------------------
# CORINE Land Cover -- level 3, 44 classes
# --------------------------------------------------------------------------
#
# Codes and English labels verified 2026-08-16 against two independent
# publications of the nomenclature, which agree exactly on all 44 rows:
#   - Copernicus Land Monitoring Service, CLC nomenclature guidelines,
#     https://land.copernicus.eu/content/corine-land-cover-nomenclature-guidelines/html/
#   - CLC illustrated nomenclature guidelines (2019 edition), Table 2.
#
# CORINE is the AUXILIARY source. It fills what BD Forêt leaves unmapped:
# non-forest burnable vegetation (321, 322, 323, 324) and the unambiguously
# non-burnable classes (urban, water, bare rock). Its forest classes are kept
# burnable so that a study outside France can run on CORINE alone, but inside
# France they should lose every pixel to BD Forêt in fev_fuel_merge().
#
# ON AGRICULTURE, the one decision in this table worth arguing about:
# arable land, vineyards and orchards default to burnable = FALSE. The reason
# is what the mask is for -- fev_exposure() measures the wildland fuel that can
# carry fire or throw embers at an asset, and a ploughed field or a worked vine
# row does neither for most of the year. But stubble fires are a real ignition
# source, abandoned terraces revert to fuel, and EFFIS records burnt
# agricultural area as a distinct class precisely because it burns. Every one
# of these rows is flagged `ambiguous`, and a user working on a
# crop-forest interface should override them.

clc <- tibble_rows(
  # code    label                                                        crown  fuel_type              burnable confidence   notes
  r("111",  "Continuous urban fabric",                                   NA,    "non_fuel",            FALSE,   "clear",     "Sealed surface, vegetation below the mapping unit."),
  r("112",  "Discontinuous urban fabric",                                NA,    "non_fuel",            FALSE,   "ambiguous", "The wildland-urban interface itself. Gardens, hedges and unmanaged plots inside it do carry fire, and this is where exposure assessment matters most -- but the class records buildings, not fuel. Treated as non-fuel here and as an ASSET in fev_vuln_layer(), which is the honest split."),
  r("121",  "Industrial or commercial units",                            NA,    "non_fuel",            FALSE,   "clear",     "Sealed or bare surface."),
  r("122",  "Road and rail networks and associated land",                NA,    "non_fuel",            FALSE,   "clear",     "Linear infrastructure. Acts as a fuel break at this resolution, and as an ignition corridor in reality -- the mask records the first, not the second."),
  r("123",  "Port areas",                                                NA,    "non_fuel",            FALSE,   "clear",     "Sealed surface."),
  r("124",  "Airports",                                                  NA,    "non_fuel",            FALSE,   "ambiguous", "Runways are non-fuel but airport grassland can be extensive. Below the mapping unit, so not separable."),
  r("131",  "Mineral extraction sites",                                  NA,    "non_fuel",            FALSE,   "clear",     "Bare mineral surface."),
  r("132",  "Dump sites",                                                NA,    "non_fuel",            FALSE,   "clear",     "Not vegetation fuel."),
  r("133",  "Construction sites",                                        NA,    "non_fuel",            FALSE,   "clear",     "Bare ground."),
  r("141",  "Green urban areas",                                         NA,    "urban_vegetation",    TRUE,    "ambiguous", "Parks and cemeteries: real vegetation, but irrigated, fragmented and managed. Burnable TRUE, with a low availability weight, rather than excluded outright."),
  r("142",  "Sport and leisure facilities",                              NA,    "urban_vegetation",    TRUE,    "ambiguous", "Golf courses, campsites, leisure parks. Campsites embedded in maquis are a recurring casualty in Mediterranean fires, which is the reason this row is not FALSE."),
  r("211",  "Non-irrigated arable land",                                 NA,    "cropland",            FALSE,   "ambiguous", "See the note on agriculture above. Stubble carries fire for a few weeks a year; the mask has no season."),
  r("212",  "Permanently irrigated land",                                NA,    "cropland",            FALSE,   "clear",     "Irrigated, kept green."),
  r("213",  "Rice fields",                                               NA,    "cropland",            FALSE,   "clear",     "Flooded for most of the cycle."),
  r("221",  "Vineyards",                                                 NA,    "cropland",            FALSE,   "ambiguous", "Worked vine rows are near-inert and are used as fire breaks; abandoned ones are not."),
  r("222",  "Fruit trees and berry plantations",                         NA,    "cropland",            FALSE,   "ambiguous", "Same reasoning as vineyards."),
  r("223",  "Olive groves",                                              NA,    "cropland",            FALSE,   "ambiguous", "The weakest FALSE in this table. Abandoned Mediterranean olive groves with a grass or shrub floor burn readily, and abandonment is widespread. Override this row for a Mediterranean study area where groves are not actively worked."),
  r("231",  "Pastures",                                                  NA,    "cropland",            FALSE,   "ambiguous", "Grazed grassland: fine fuel, but kept short by stock. A pasture left ungrazed is functionally class 321."),
  r("241",  "Annual crops associated with permanent crops",              NA,    "cropland",            FALSE,   "ambiguous", "See the note on agriculture."),
  r("242",  "Complex cultivation patterns",                              NA,    "cropland",            FALSE,   "ambiguous", "Small-holding mosaic. Contains hedges, field margins and fallow below the 25 ha unit, none of which are separable."),
  r("243",  "Land principally occupied by agriculture, with significant areas of natural vegetation", NA, "mosaic_agri_natural", TRUE, "ambiguous", "The class is defined by containing significant natural vegetation, so the burnable fraction is real but unquantified -- somewhere between a quarter and a half of the polygon by the nomenclature's own definition. Burnable TRUE with a fractional availability weight is the least wrong option."),
  r("244",  "Agro-forestry areas",                                       NA,    "agroforestry",        TRUE,    "clear",     "Dehesa and montado: scattered oaks over grazed grass. Structurally an open forest, and it burns as one."),
  r("311",  "Broad-leaved forest",                                       NA,    "broadleaf_closed",    TRUE,    "clear",     "Broadleaf forest. Cannot separate evergreen sclerophyll from deciduous -- holm oak and beech land in the same class. This single limitation is the strongest argument for keeping BD Forêt primary in France."),
  r("312",  "Coniferous forest",                                         NA,    "conifer_closed",      TRUE,    "clear",     "Coniferous forest, species unresolved."),
  r("313",  "Mixed forest",                                              NA,    "mixed_closed",        TRUE,    "clear",     "Mixed forest."),
  r("321",  "Natural grassland",                                         NA,    "grassland",           TRUE,    "clear",     "Ungrazed or lightly grazed grassland. One of the three classes CORINE is kept for."),
  r("322",  "Moors and heathland",                                       NA,    "shrubland",           TRUE,    "clear",     "Moor and heath. One of the three classes CORINE is kept for."),
  r("323",  "Sclerophyllous vegetation",                                 NA,    "shrubland",           TRUE,    "clear",     "Maquis and garrigue. The most important class CORINE contributes: highly flammable, extensive around the Mediterranean, and outside the BD Forêt's forest scope in places."),
  r("324",  "Transitional woodland-shrub",                               NA,    "transitional_shrub",  TRUE,    "clear",     "Regeneration, encroachment and post-disturbance shrub. Given its own type because it is a transient state -- what it was at the CLC vintage is not what it is now, and the gap grows with the age of the vintage."),
  r("331",  "Beaches, dunes, sands",                                     NA,    "non_fuel",            FALSE,   "ambiguous", "Mostly bare, but back-dune vegetation exists below the mapping unit."),
  r("332",  "Bare rocks",                                                NA,    "non_fuel",            FALSE,   "clear",     "Rock. A genuine fuel break."),
  r("333",  "Sparsely vegetated areas",                                  NA,    "sparse_vegetation",   TRUE,    "ambiguous", "Under 50% vegetation cover by definition, so fuel is present but discontinuous. Burnable TRUE with a low weight; spread across it is unreliable in either direction."),
  r("334",  "Burnt areas",                                               NA,    "burnt_regrowth",      TRUE,    "ambiguous", "Burnt at the CLC vintage. Whether it is fuel today depends entirely on how long ago that was: bare in year one, and in Mediterranean shrubland among the most flammable states there is by year five to ten. Compare the CLC vintage to your analysis date before trusting this row."),
  r("335",  "Glaciers and perpetual snow",                               NA,    "non_fuel",            FALSE,   "clear",     "Ice and snow."),
  r("411",  "Inland marshes",                                            NA,    "non_fuel",            FALSE,   "ambiguous", "Waterlogged, but reedbeds burn fast and hot when dry -- Camargue-type situations are not covered by this FALSE."),
  r("412",  "Peat bogs",                                                 NA,    "non_fuel",            FALSE,   "ambiguous", "Peat burns by smouldering, which is a different process from the flaming spread this package models. FALSE is a scope decision, not a claim that peat does not burn."),
  r("421",  "Salt marshes",                                              NA,    "non_fuel",            FALSE,   "clear",     "Halophytic, waterlogged."),
  r("422",  "Salines",                                                   NA,    "non_fuel",            FALSE,   "clear",     "Salt pans."),
  r("423",  "Intertidal flats",                                          NA,    "non_fuel",            FALSE,   "clear",     "Tidal, unvegetated."),
  r("511",  "Water courses",                                             NA,    "non_fuel",            FALSE,   "clear",     "Water."),
  r("512",  "Water bodies",                                              NA,    "non_fuel",            FALSE,   "clear",     "Water."),
  r("521",  "Coastal lagoons",                                           NA,    "non_fuel",            FALSE,   "clear",     "Water."),
  r("522",  "Estuaries",                                                 NA,    "non_fuel",            FALSE,   "clear",     "Water."),
  r("523",  "Sea and ocean",                                             NA,    "non_fuel",            FALSE,   "clear",     "Water.")
)

# --------------------------------------------------------------------------
# Validation, then write
# --------------------------------------------------------------------------
# These checks are the reason this script exists rather than two hand-edited
# CSVs. A duplicated code or a mistyped fuel type would otherwise surface much
# later as a silently unmatched pixel.

validate <- function(x, nomenclature, expected_n) {
  stopifnot(
    "row count does not match the published class count" =
      nrow(x) == expected_n,
    "duplicated code" = !anyDuplicated(x$code),
    "unknown fuel type" = all(x$fuel_type %in% FUEL_TYPES),
    "burnable must be TRUE or FALSE, never NA" =
      is.logical(x$burnable) && !anyNA(x$burnable),
    "confidence must be clear or ambiguous" =
      all(x$confidence %in% c("clear", "ambiguous")),
    "every row needs a justification" =
      all(nzchar(x$notes)) && !anyNA(x$notes),
    "crown_cover must be closed, open, none or NA" =
      all(is.na(x$crown_cover) | x$crown_cover %in% c("closed", "open", "none"))
  )
  cbind(nomenclature = nomenclature, x, stringsAsFactors = FALSE)
}

# 32 posts: announced by cartes.gouv.fr for BD Forêt v2.
# 44 classes: the CLC level 3 count, in both nomenclature publications.
bdforet <- validate(bdforet, "bdforet_v2", 32L)
clc     <- validate(clc, "clc", 44L)

out_dir <- file.path("inst", "extdata")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# UTF-8 and quoted throughout: the French labels carry accents, and the notes
# carry commas.
write_lookup <- function(x, file) {
  utils::write.csv(x, file, row.names = FALSE, fileEncoding = "UTF-8")
  message(sprintf("wrote %s (%d rows, %d ambiguous)",
                  file, nrow(x), sum(x$confidence == "ambiguous")))
}

write_lookup(bdforet, file.path(out_dir, "fuel_lookup_bdforet_v2.csv"))
write_lookup(clc, file.path(out_dir, "fuel_lookup_clc.csv"))

# A summary worth reading after every rebuild: it says how much of each
# nomenclature the package is guessing at.
print(table(bdforet$fuel_type, bdforet$confidence))
print(table(clc$fuel_type, clc$confidence))
