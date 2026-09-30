# LSOA 2001–2021 area-weighted crosswalks -------------------------------------
#
# Purpose:
#   Build England-only LSOA correspondence weights for:
#     * LSOA 2001 -> LSOA 2011
#     * LSOA 2011 -> LSOA 2021
#     * LSOA 2001 -> LSOA 2021 (via 2011)
#
# Weights are area-based. They are suitable for transferring additive measures
# (for example, counts or totals) only where a uniform within-LSOA distribution
# is an acceptable assumption.
#
# Required packages:
#   install.packages(c("sf", "dplyr", "data.table", "here"))
#
# Expected project layout:
#   <project-root>/
#   └── data/
#       └── lsoa/
#           ├── LSOA_2001_EW_BFE_V2.shp (+ companion shapefile files)
#           ├── LSOA_2011_EW_BFC_V3.shp (+ companion shapefile files)
#           ├── LSOA_2021_EW_BFE_V10.shp (+ companion shapefile files)
#           ├── Lower_Layer_Super_Output_Area_(2001)_to_...
#           └── LSOA_(2011)_to_LSOA_(2021)_to_...
#
# Data downloads:
#   * 2001 -> 2011 lookup:
#     https://www.data.gov.uk/dataset/4048a518-3eaf-457a-905c-9e04f4fffca8/lower-layer-super-output-area-2001-to-lower-layer-super-output-area-2011-to-local-authority-district-2011-lookup-in-england-and-wales
#   * 2011 -> 2021 lookup:
#     https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3
#   * 2001 boundary:
#     https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2001-boundaries-ew-bfe/about
#   * 2011 boundary:
#     https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-ew-bfc-v3/about
#   * 2021 boundary: obtain the EW BFE release named below.

library(sf)
library(dplyr)
library(data.table)
library(here)

# Use British National Grid: coordinates are measured in metres, making it
# appropriate for polygon-area calculations.
area_crs <- 27700

# `here()` resolves paths relative to the root of an R project. If this is not
# an R project, replace this line with a full or relative directory path.
lsoa_dir <- here::here("data", "lsoa")
output_dir <- here::here("data", "derived")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Expected input names. Change these only if a downloaded release uses a
# different filename.
shapefile_names <- c(
  lsoa_01 = "LSOA_2001_EW_BFE_V2.shp",
  lsoa_11 = "LSOA_2011_EW_BFC_V3.shp",
  lsoa_21 = "LSOA_2021_EW_BFE_V10.shp"
)

lookup_names <- c(
  lookup_01_11 = paste0(
    "Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_",
    "(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv"
  ),
  lookup_11_21 = paste0(
    "LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_",
    "Exact_Fit_Lookup_for_EW_(V3).csv"
  )
)

# Find inputs recursively, allowing downloaded datasets to remain in folders.
shapefile_paths <- list.files(
  lsoa_dir,
  pattern = "LSOA.*(BFE|BFC).*\\.shp$",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)
csv_paths <- list.files(
  lsoa_dir,
  pattern = "\\.csv$",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)

shapefiles <- setNames(shapefile_paths, basename(shapefile_paths))
csv_files <- setNames(csv_paths, basename(csv_paths))

# Stop early with a useful error if files are absent or filenames differ.
missing_shapefiles <- setdiff(unname(shapefile_names), names(shapefiles))
missing_lookups <- setdiff(unname(lookup_names), names(csv_files))
if (length(missing_shapefiles) > 0 || length(missing_lookups) > 0) {
  stop(
    "Missing required input file(s):\n",
    paste(c(missing_shapefiles, missing_lookups), collapse = "\n"),
    "\n\nCheck filenames or amend `shapefile_names` / `lookup_names`."
  )
}

# Read, retain England only (codes beginning E), and project to British
# National Grid before calculating areas.
read_lsoa_boundary <- function(path, code_column) {
  boundary <- sf::st_read(path, quiet = TRUE)
  
  if (!code_column %in% names(boundary)) {
    stop("Column `", code_column, "` was not found in ", basename(path))
  }
  
  boundary |>
    filter(startsWith(.data[[code_column]], "E")) |>
    st_transform(area_crs)
}

poly_lsoa_01 <- read_lsoa_boundary(shapefiles[[shapefile_names[["lsoa_01"]]]], "LSOA01CD")
poly_lsoa_11 <- read_lsoa_boundary(shapefiles[[shapefile_names[["lsoa_11"]]]], "LSOA11CD")
poly_lsoa_21 <- read_lsoa_boundary(shapefiles[[shapefile_names[["lsoa_21"]]]], "LSOA21CD")

# Read lookup tables and retain their code-pair columns only. The published
# relationships define eligible pairs; geometry provides weights for splits.
lookup_01_11 <- fread(csv_files[[lookup_names[["lookup_01_11"]]]])[
  startsWith(LSOA01CD, "E"),
  .(LSOA01CD, LSOA11CD)
] |> unique()

lookup_11_21 <- fread(csv_files[[lookup_names[["lookup_11_21"]]]])[
  startsWith(LSOA11CD, "E"),
  .(LSOA11CD, LSOA21CD)
] |> unique()

# Build source-to-target area weights for a published lookup.
#
# Sources with a single target receive weight 1. For one-to-many sources, the
# source polygon is intersected with target polygons; each intersection area is
# divided by the total source area. Final normalisation handles tiny geometric
# precision differences.
build_area_weights <- function(source_polygons, target_polygons, lookup,
                               source_code, target_code, weight_column) {
  lookup <- copy(as.data.table(lookup))
  setnames(lookup, c(source_code, target_code), c("source_code", "target_code"))
  
  one_to_many_sources <- lookup[, .N, by = source_code][N > 1, source_code]
  one_to_one <- lookup[!source_code %in% one_to_many_sources]
  one_to_one[, weight := 1]
  
  source_splits <- source_polygons |>
    filter(.data[[source_code]] %in% one_to_many_sources) |>
    select(source_code = all_of(source_code), geometry)
  
  target_geometry <- target_polygons |>
    select(target_code = all_of(target_code), geometry)
  
  # Retain only intersections that are official lookup relationships.
  split_weights <- source_splits |>
    st_intersection(target_geometry) |>
    mutate(
      intersection_area = st_area(geometry),
      source_area = st_area(source_splits)[match(source_code, source_splits$source_code)],
      weight = as.numeric(intersection_area / source_area)
    ) |>
    st_drop_geometry() |>
    as.data.table() |>
    merge(lookup, by = c("source_code", "target_code"), nomatch = 0L) |>
    .[, .(weight = sum(weight)), by = .(source_code, target_code)]
  
  weights <- rbindlist(
    list(
      split_weights,
      one_to_one[, .(source_code, target_code, weight)]
    ),
    use.names = TRUE
  )
  
  # A source should have at least one relationship and a positive total weight.
  weights[, weight := weight / sum(weight), by = source_code]
  setnames(weights, c("source_code", "target_code", "weight"),
           c(source_code, target_code, weight_column))
  setorderv(weights, c(source_code, target_code))
  weights[]
}

# 2011 -> 2021 ---------------------------------------------------------------
lookup_wgt_11_21 <- build_area_weights(
  source_polygons = poly_lsoa_11,
  target_polygons = poly_lsoa_21,
  lookup = lookup_11_21,
  source_code = "LSOA11CD",
  target_code = "LSOA21CD",
  weight_column = "LSOA11WGT"
)

# 2001 -> 2011 ---------------------------------------------------------------
lookup_wgt_01_11 <- build_area_weights(
  source_polygons = poly_lsoa_01,
  target_polygons = poly_lsoa_11,
  lookup = lookup_01_11,
  source_code = "LSOA01CD",
  target_code = "LSOA11CD",
  weight_column = "LSOA01WGT"
)

# 2001 -> 2021, chained through 2011 ----------------------------------------
# Multiply weights along each 2001 -> 2011 -> 2021 path, then sum any paths
# that end at the same 2021 LSOA.
lookup_wgt_01_21 <- merge(
  lookup_wgt_01_11,
  lookup_wgt_11_21,
  by = "LSOA11CD",
  allow.cartesian = TRUE
)[
  , .(LSOA01WGT21 = sum(LSOA01WGT * LSOA11WGT)),
  by = .(LSOA01CD, LSOA21CD)
][
  , LSOA01WGT21 := LSOA01WGT21 / sum(LSOA01WGT21),
  by = LSOA01CD
]
setorder(lookup_wgt_01_21, LSOA01CD, LSOA21CD)

# Quality assurance ----------------------------------------------------------
# Report source areas whose weights do not sum to one within `tolerance`.
check_weight_sums <- function(weights, source_code, weight_column,
                              tolerance = 1e-8) {
  checks <- weights[
    , .(sum_weight = sum(get(weight_column))),
    by = source_code
  ][
    , difference := abs(sum_weight - 1)
  ][
    order(-difference)
  ]
  
  failures <- checks[difference > tolerance]
  if (nrow(failures) > 0) {
    warning(
      nrow(failures), " source LSOA(s) have weight sums outside tolerance."
    )
  }
  checks
}

check_11_21 <- check_weight_sums(lookup_wgt_11_21, "LSOA11CD", "LSOA11WGT")
check_01_11 <- check_weight_sums(lookup_wgt_01_11, "LSOA01CD", "LSOA01WGT")
check_01_21 <- check_weight_sums(lookup_wgt_01_21, "LSOA01CD", "LSOA01WGT21")

# Save outputs ---------------------------------------------------------------
fwrite(lookup_wgt_11_21, file.path(output_dir, "lsoa_2011_to_2021_area_weights.csv"))
fwrite(lookup_wgt_01_11, file.path(output_dir, "lsoa_2001_to_2011_area_weights.csv"))
fwrite(lookup_wgt_01_21, file.path(output_dir, "lsoa_2001_to_2021_area_weights.csv"))
