# LSOA 2001, 2011 and 2021 area-weight lookup functions ---------------------
#
# Purpose
# -------
# Build area-based correspondence weights between England LSOA vintages:
#   * LSOA 2001 -> LSOA 2011
#   * LSOA 2011 -> LSOA 2021
#   * LSOA 2001 -> LSOA 2021 (chained via LSOA 2011)
#
# A weight represents the share of a source LSOA's polygon area allocated to
# a target LSOA. These are AREA weights, not population-weighted estimates.
# They are appropriate for allocating quantities only where an area-weighted
# allocation is substantively defensible.
#
# Data download locations
# -----------------------
# 1. LSOA 2001 -> LSOA 2011 -> LAD 2011 lookup:
# https://www.data.gov.uk/dataset/4048a518-3eaf-457a-905c-9e04f4fffca8/lower-layer-super-output-area-2001-to-lower-layer-super-output-area-2011-to-local-authority-district-2011-lookup-in-england-and-wales
#
# 2. LSOA 2011 -> LSOA 2021 -> LAD 2022 Exact Fit Lookup (EW, V3):
# https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3
# https://geoportal.statistics.gov.uk/datasets/ons::lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3/about
#
# 3. LSOA boundaries:
# LSOA 2001: https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2001-boundaries-ew-bfe/about
# LSOA 2011: https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-ew-bfc-v3/about
# LSOA 2021: download the England and Wales full-extent boundary file from
# the ONS Open Geography Portal.  Use a BFE/BFC file, not a generalised one.
#
# Required packages
# -----------------
# install.packages(c("sf", "data.table"))
#
# Example
# -------
# library(sf)
# library(data.table)
# source("lsoa_area_weight_functions.R")
#
# paths <- list(
#   lsoa01_shp = "data/lsoa/LSOA_2001_EW_BFE_V2.shp",
#   lsoa11_shp = "data/lsoa/LSOA_2011_EW_BFC_V3.shp",
#   lsoa21_shp = "data/lsoa/LSOA_2021_EW_BFE_V10.shp",
#   lookup01_11 = "data/lsoa/Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv",
#   lookup11_21 = "data/lsoa/LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3).csv"
# )
#
# weights <- build_lsoa_area_weights(
#   lsoa01_shp = paths$lsoa01_shp,
#   lsoa11_shp = paths$lsoa11_shp,
#   lsoa21_shp = paths$lsoa21_shp,
#   lookup01_11_csv = paths$lookup01_11,
#   lookup11_21_csv = paths$lookup11_21
# )
#
# data.table::fwrite(weights$wgt_01_11, "data/lsoa/lsoa_area_weights_2001_2011.csv")
# data.table::fwrite(weights$wgt_11_21, "data/lsoa/lsoa_area_weights_2011_2021.csv")
# data.table::fwrite(weights$wgt_01_21, "data/lsoa/lsoa_area_weights_2001_2021.csv")
#
# To transfer a source-LSOA 2001 count `value_2001` to LSOA 2021, join it to
# `weights$wgt_01_21` by LSOA01CD, then calculate:
# `allocated_value = value_2001 * LSOA01WGT21`.

.require_lsoa_area_packages <- function() {
  packages <- c("sf", "data.table")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Install required package(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

.assert_columns <- function(x, required, object_name) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(object_name, " is missing required column(s): ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
}

#' Read one England LSOA boundary shapefile and set a projected CRS.
#'
#' @param path Path to a .shp file.
#' @param code_column LSOA code field, e.g. "LSOA11CD".
#' @param crs Target projected coordinate reference system. EPSG:27700 is
#'   British National Grid and is suitable for area calculations.
#' @return An sf object containing the LSOA code and geometry.
read_england_lsoa_boundaries <- function(path, code_column, crs = 27700) {
  .require_lsoa_area_packages()
  if (!file.exists(path)) stop("Boundary file not found: ", path, call. = FALSE)
  
  polygons <- sf::st_read(path, quiet = TRUE)
  .assert_columns(polygons, code_column, basename(path))
  
  polygons <- polygons[startsWith(as.character(polygons[[code_column]]), "E"),
                       c(code_column, attr(polygons, "sf_column")), drop = FALSE]
  names(polygons)[names(polygons) == code_column] <- "source_code"
  
  if (is.na(sf::st_crs(polygons))) {
    stop("Boundary file has no CRS: ", path, call. = FALSE)
  }
  sf::st_make_valid(sf::st_transform(polygons, crs))
}

#' Read an England-only LSOA correspondence lookup.
#'
#' @param path Path to the ONS lookup CSV.
#' @param source_column Source LSOA code column.
#' @param target_column Target LSOA code column.
#' @return A data.table with source_code and target_code.
read_england_lsoa_lookup <- function(path, source_column, target_column) {
  .require_lsoa_area_packages()
  if (!file.exists(path)) stop("Lookup CSV not found: ", path, call. = FALSE)
  
  lookup <- data.table::fread(path)
  .assert_columns(lookup, c(source_column, target_column), basename(path))
  
  result <- unique(lookup[, .(
    source_code = as.character(get(source_column)),
    target_code = as.character(get(target_column))
  )])
  result[startsWith(source_code, "E") & startsWith(target_code, "E")]
}

#' Build normalised area weights for one LSOA correspondence.
#'
#' One-to-one source areas are assigned a weight of 1. For one-to-many source
#' areas, weights are calculated from geometric intersections and then
#' normalised within each source code to protect against small topology or
#' rounding differences.
#'
#' @param source_polygons sf object from read_england_lsoa_boundaries().
#' @param target_polygons sf object from read_england_lsoa_boundaries().
#' @param lookup Correspondence table with source_code and target_code.
#' @param source_name Name of source output column, e.g. "LSOA11CD".
#' @param target_name Name of target output column, e.g. "LSOA21CD".
#' @param weight_name Name of output weight column.
#' @return A data.table containing source code, target code and area weight.
build_area_weight_lookup <- function(
    source_polygons, target_polygons, lookup,
    source_name, target_name, weight_name) {
  
  .require_lsoa_area_packages()
  .assert_columns(source_polygons, "source_code", "source_polygons")
  .assert_columns(target_polygons, "source_code", "target_polygons")
  .assert_columns(lookup, c("source_code", "target_code"), "lookup")
  
  data.table::setDT(lookup)
  lookup <- unique(data.table::copy(lookup))
  source_counts <- lookup[, .N, by = source_code]
  one_to_many <- source_counts[N > 1L, source_code]
  
  one_to_one <- lookup[!source_code %in% one_to_many]
  one_to_one[, weight := 1]
  
  if (length(one_to_many)) {
    source_many <- source_polygons[source_polygons$source_code %in% one_to_many, ]
    target_for_intersection <- target_polygons[
      target_polygons$source_code %in% lookup[source_code %in% one_to_many, target_code],
    ]
    names(target_for_intersection)[names(target_for_intersection) == "source_code"] <- "target_code"
    
    source_areas <- data.table::data.table(
      source_code = source_many$source_code,
      source_area = as.numeric(sf::st_area(source_many))
    )
    
    intersections <- suppressWarnings(sf::st_intersection(
      source_many[, "source_code", drop = FALSE],
      target_for_intersection[, "target_code", drop = FALSE]
    ))
    intersections <- intersections[!sf::st_is_empty(intersections), ]
    
    one_to_many_weights <- data.table::as.data.table(sf::st_drop_geometry(intersections))
    one_to_many_weights[, overlap_area := as.numeric(sf::st_area(intersections))]
    one_to_many_weights <- merge(one_to_many_weights, source_areas,
                                 by = "source_code", all.x = TRUE)
    one_to_many_weights[, weight := overlap_area / source_area]
    one_to_many_weights <- one_to_many_weights[, .(weight = sum(weight)),
                                               by = .(source_code, target_code)]
  } else {
    one_to_many_weights <- data.table::data.table(
      source_code = character(), target_code = character(), weight = numeric()
    )
  }
  
  result <- data.table::rbindlist(list(
    one_to_one[, .(source_code, target_code, weight)],
    one_to_many_weights[, .(source_code, target_code, weight)]
  ))
  
  # Retain only pairs stated in the official lookup, then normalise.
  result <- merge(result, lookup, by = c("source_code", "target_code"))
  result[, weight := weight / sum(weight), by = source_code]
  data.table::setnames(result, c("source_code", "target_code", "weight"),
                       c(source_name, target_name, weight_name))
  data.table::setorderv(result, c(source_name, target_name))
  result[]
}

#' Validate that correspondence weights sum to one per source LSOA.
#'
#' @param weights A correspondence data.table.
#' @param source_column Source LSOA code column.
#' @param weight_column Weight column.
#' @param tolerance Allowed absolute difference from 1.
#' @return A data.table of failing source areas; zero rows means success.
check_lsoa_weight_sums <- function(weights, source_column, weight_column,
                                   tolerance = 1e-8) {
  .require_lsoa_area_packages()
  data.table::setDT(weights)
  check <- weights[, .(sum_weight = sum(get(weight_column), na.rm = TRUE)),
                   by = source_column]
  check[abs(sum_weight - 1) > tolerance][order(-abs(sum_weight - 1))]
}

#' Build LSOA 2001->2011, 2011->2021 and chained 2001->2021 area weights.
#'
#' @return A named list with wgt_01_11, wgt_11_21, wgt_01_21 and checks.
build_lsoa_area_weights <- function(
    lsoa01_shp, lsoa11_shp, lsoa21_shp,
    lookup01_11_csv, lookup11_21_csv,
    crs = 27700) {
  
  .require_lsoa_area_packages()
  
  poly01 <- read_england_lsoa_boundaries(lsoa01_shp, "LSOA01CD", crs)
  poly11 <- read_england_lsoa_boundaries(lsoa11_shp, "LSOA11CD", crs)
  poly21 <- read_england_lsoa_boundaries(lsoa21_shp, "LSOA21CD", crs)
  
  lookup01_11 <- read_england_lsoa_lookup(
    lookup01_11_csv, "LSOA01CD", "LSOA11CD"
  )
  lookup11_21 <- read_england_lsoa_lookup(
    lookup11_21_csv, "LSOA11CD", "LSOA21CD"
  )
  
  wgt_01_11 <- build_area_weight_lookup(
    poly01, poly11, lookup01_11,
    source_name = "LSOA01CD", target_name = "LSOA11CD",
    weight_name = "LSOA01WGT"
  )
  wgt_11_21 <- build_area_weight_lookup(
    poly11, poly21, lookup11_21,
    source_name = "LSOA11CD", target_name = "LSOA21CD",
    weight_name = "LSOA11WGT"
  )
  
  wgt_01_21 <- merge(wgt_01_11, wgt_11_21, by = "LSOA11CD",
                     allow.cartesian = TRUE)
  wgt_01_21[, LSOA01WGT21 := LSOA01WGT * LSOA11WGT]
  wgt_01_21 <- wgt_01_21[, .(LSOA01WGT21 = sum(LSOA01WGT21)),
                         by = .(LSOA01CD, LSOA21CD)]
  wgt_01_21[, LSOA01WGT21 := LSOA01WGT21 / sum(LSOA01WGT21), by = LSOA01CD]
  data.table::setorderv(wgt_01_21, c("LSOA01CD", "LSOA21CD"))
  
  checks <- list(
    wgt_01_11 = check_lsoa_weight_sums(wgt_01_11, "LSOA01CD", "LSOA01WGT"),
    wgt_11_21 = check_lsoa_weight_sums(wgt_11_21, "LSOA11CD", "LSOA11WGT"),
    wgt_01_21 = check_lsoa_weight_sums(wgt_01_21, "LSOA01CD", "LSOA01WGT21")
  )
  if (any(vapply(checks, nrow, integer(1)) > 0L)) {
    warning("At least one correspondence has weights outside the requested tolerance. See $checks.")
  }
  
  list(
    wgt_01_11 = wgt_01_11,
    wgt_11_21 = wgt_11_21,
    wgt_01_21 = wgt_01_21,
    checks = checks
  )
}
