# LSOA population estimates harmonised to LSOA 2021 --------------------------
#
# Purpose
# -------
# Create a consistent England LSOA 2021 population time series from ONS
# small-area population estimates.  Historical LSOA 2011 estimates (2002–10)
# are allocated to LSOA 2021 with the AREA weights created by
# lsoa_area_weight_functions.R.  Estimates already published on LSOA 2021
# geography are retained directly.
#
# Important: these are area-weighted allocations, not population-weighted
# re-estimates. Use with care for small LSOAs and age-specific counts.
#
# Inputs to download manually
# ---------------------------
# * ONS LSOA population-estimate workbooks, placed in:
#     data/lsoa_pop_est_sing/
#   Historical files expected include the SAPE8DT single-year-of-age male and
#   female .xls workbooks for 2002–2010.
#   Current files expected match sapelsoasyoa*.xlsx and contain sheets named
#   "Mid-YYYY LSOA 2021".
#
# * Boundary and correspondence inputs required by lsoa_area_weight_functions.R
#   (place them under data/lsoa/, or set paths explicitly):
#   LSOA 2001 boundaries:
#   https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2001-boundaries-ew-bfe/about
#   LSOA 2011 boundaries:
#   https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-ew-bfc-v3/about
#   LSOA 2011 -> LSOA 2021 -> LAD 2022 lookup:
#   https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3
#   LSOA 2001 -> LSOA 2011 lookup (needed only when creating all three
#   lookup vintages, but accepted by the area-weight builder):
#   https://www.data.gov.uk/dataset/4048a518-3eaf-457a-905c-9e04f4fffca8/lower-layer-super-output-area-2001-to-lower-layer-super-output-area-2011-to-local-authority-district-2011-lookup-in-england-and-wales
#
# Required packages
# -----------------
# install.packages(c("dplyr", "purrr", "readxl", "readr", "stringr",
#                    "tibble", "data.table", "sf"))
#
# Example
# -------
# source("lsoa_area_weight_functions.R")
# source("lsoa_population_functions.R")
#
# paths <- list(
#   lsoa01_shp = "data/lsoa/LSOA_2001_EW_BFE_V2.shp",
#   lsoa11_shp = "data/lsoa/LSOA_2011_EW_BFC_V3.shp",
#   lsoa21_shp = "data/lsoa/LSOA_2021_EW_BFE_V10.shp",
#   lookup01_11_csv = "data/lsoa/Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv",
#   lookup11_21_csv = "data/lsoa/LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3).csv"
# )
#
# population <- build_lsoa_population_2002_2024(
#   population_dir = "data/lsoa_pop_est_sing",
#   area_weight_args = paths,
#   weights_cache = "data/lsoa/lsoa_area_weights_2011_2021.csv",
#   output_csv = "data/pop_regrouped_2002_2024.csv"
# )

.require_lsoa_population_packages <- function() {
  packages <- c("dplyr", "purrr", "readxl", "readr", "stringr", "tibble", "data.table", "sf")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Install required package(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

#' Create broad sex-by-age population bands from one historical SAPE8DT table.
#'
#' @param data One worksheet read from a historical male or female workbook.
#' @param year Estimate year.
#' @return Tibble with LSOA 2011 code and population measures.
.regroup_historical_population <- function(data, year) {
  .require_lsoa_population_packages()
  age_columns <- grep("^[mf]([0-9]+|90plus)$", names(data), value = TRUE, ignore.case = TRUE)
  data <- dplyr::mutate(data, dplyr::across(dplyr::all_of(age_columns), ~ suppressWarnings(as.numeric(.x))))
  
  band_sum <- function(prefix, ages) {
    columns <- intersect(paste0(prefix, ages), names(data))
    if (!length(columns)) return(rep(0, nrow(data)))
    rowSums(as.data.frame(data[, columns, drop = FALSE]), na.rm = TRUE)
  }
  plus_sum <- function(prefix) {
    columns <- intersect(c(paste0(prefix, 75:89), paste0(prefix, "90plus")), names(data))
    if (!length(columns)) return(rep(0, nrow(data)))
    rowSums(as.data.frame(data[, columns, drop = FALSE]), na.rm = TRUE)
  }
  
  tibble::tibble(
    year = as.integer(year),
    lsoa_2011_code = as.character(data$LSOA11CD),
    total = suppressWarnings(as.numeric(data$all_ages)),
    f_25_49 = band_sum("f", 25:49),
    f_50_74 = band_sum("f", 50:74),
    f_75_plus = plus_sum("f"),
    m_25_49 = band_sum("m", 25:49),
    m_50_74 = band_sum("m", 50:74),
    m_75_plus = plus_sum("m")
  )
}

#' Read and combine historical LSOA 2011 single-year-of-age workbooks.
#'
#' @param population_dir Directory holding SAPE8DT .xls files.
#' @return England historical population data, grouped over male/female files.
read_historical_lsoa_population <- function(population_dir) {
  .require_lsoa_population_packages()
  files <- list.files(population_dir, pattern = "\\.xls$", full.names = TRUE, ignore.case = TRUE)
  files <- files[stringr::str_detect(tolower(basename(files)), "males|females")]
  if (!length(files)) stop("No historical male/female .xls files found in: ", population_dir, call. = FALSE)
  
  workbook_sheets <- purrr::map_dfr(files, function(path) {
    sheets <- readxl::excel_sheets(path)
    sheets <- sheets[stringr::str_detect(sheets, "^Mid-[0-9]{4}$")]
    tibble::tibble(path = path, sheet = sheets,
                   year = as.integer(stringr::str_extract(sheets, "[0-9]{4}")))
  }) |>
    dplyr::filter(.data$year < 2011L)
  
  if (!nrow(workbook_sheets)) stop("No historical sheets for 2002–2010 were found.", call. = FALSE)
  
  workbook_sheets |>
    dplyr::mutate(data = purrr::map2(.data$path, .data$sheet, readxl::read_excel)) |>
    dplyr::mutate(regrouped = purrr::map2(.data$data, .data$year, .regroup_historical_population)) |>
    dplyr::select(.data$regrouped) |>
    tidyr::unnest(.data$regrouped) |>
    dplyr::filter(startsWith(.data$lsoa_2011_code, "E")) |>
    dplyr::group_by(.data$year, .data$lsoa_2011_code) |>
    dplyr::summarise(dplyr::across(c("total", "f_25_49", "f_50_74", "f_75_plus", "m_25_49", "m_50_74", "m_75_plus"), sum, na.rm = TRUE), .groups = "drop")
}

#' Allocate LSOA 2011 counts to LSOA 2021 using supplied area weights.
#'
#' @param historical_data Output of read_historical_lsoa_population().
#' @param weights_11_21 Data frame with LSOA11CD, LSOA21CD, and LSOA11WGT.
#' @return LSOA 2021 population estimates.
allocate_lsoa11_population_to_lsoa21 <- function(historical_data, weights_11_21) {
  .require_lsoa_population_packages()
  required <- c("LSOA11CD", "LSOA21CD", "LSOA11WGT")
  absent <- setdiff(required, names(weights_11_21))
  if (length(absent)) stop("weights_11_21 is missing: ", paste(absent, collapse = ", "), call. = FALSE)
  
  measures <- c("total", "f_25_49", "f_50_74", "f_75_plus", "m_25_49", "m_50_74", "m_75_plus")
  historical_data |>
    dplyr::inner_join(dplyr::as_tibble(weights_11_21), by = c("lsoa_2011_code" = "LSOA11CD")) |>
    dplyr::group_by(.data$year, .data$LSOA21CD) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(measures), ~ sum(.x * .data$LSOA11WGT, na.rm = TRUE)), .groups = "drop") |>
    dplyr::rename(lsoa_2021_code = .data$LSOA21CD)
}

#' Read LSOA 2021 single-year-of-age population workbooks and create age bands.
#'
#' @param population_dir Directory holding sapelsoasyoa*.xlsx files.
#' @return England LSOA 2021 population estimates.
read_lsoa21_population <- function(population_dir) {
  .require_lsoa_population_packages()
  files <- list.files(population_dir, pattern = "^sapelsoasyoa.*\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) stop("No sapelsoasyoa .xlsx files found in: ", population_dir, call. = FALSE)
  
  sheets <- purrr::map_dfr(files, function(path) {
    names <- readxl::excel_sheets(path)
    names <- names[stringr::str_detect(names, "^Mid-[0-9]{4} LSOA 2021$")]
    tibble::tibble(path = path, sheet = names,
                   year = as.integer(stringr::str_extract(names, "[0-9]{4}")))
  })
  
  raw <- sheets |>
    dplyr::mutate(data = purrr::map2(.data$path, .data$sheet, ~ readxl::read_excel(.x, sheet = .y, skip = 3))) |>
    dplyr::select(.data$year, .data$data) |>
    tidyr::unnest(.data$data)
  
  age_columns <- grep("^[FM][0-9]{1,2}$", names(raw), value = TRUE)
  raw <- dplyr::mutate(raw, dplyr::across(dplyr::all_of(age_columns), ~ readr::parse_number(as.character(.x))))
  sum_band <- function(prefix, ages) rowSums(as.data.frame(raw[, intersect(paste0(prefix, ages), names(raw)), drop = FALSE]), na.rm = TRUE)
  
  raw |>
    dplyr::filter(startsWith(.data$`LSOA 2021 Code`, "E")) |>
    dplyr::transmute(
      year = .data$year,
      lsoa_2021_code = as.character(.data$`LSOA 2021 Code`),
      lsoa_2021_name = as.character(.data$`LSOA 2021 Name`),
      total = readr::parse_number(as.character(.data$Total)),
      f_25_49 = sum_band("F", 25:49), f_50_74 = sum_band("F", 50:74), f_75_plus = sum_band("F", 75:90),
      m_25_49 = sum_band("M", 25:49), m_50_74 = sum_band("M", 50:74), m_75_plus = sum_band("M", 75:90)
    )
}

#' Build a harmonised England LSOA 2021 population time series.
#'
#' @param population_dir Folder with all ONS population workbooks.
#' @param weights_11_21 Optional pre-built area weights.
#' @param area_weight_args Optional named list passed to build_lsoa_area_weights().
#' @param weights_cache Optional CSV cache for the 2011-to-2021 weights.
#' @param lsoa21_shp Optional LSOA 2021 shapefile, used to add LSOA names.
#' @param lookup11_21_csv Official lookup CSV, used to add LAD codes/names.
#' @param output_csv Optional output CSV location.
#' @return A tibble, one row per year and LSOA 2021.
build_lsoa_population_2002_2024 <- function(
    population_dir,
    weights_11_21 = NULL,
    area_weight_args = NULL,
    weights_cache = NULL,
    lsoa21_shp = NULL,
    lookup11_21_csv = NULL,
    output_csv = NULL) {
  
  .require_lsoa_population_packages()
  if (is.null(weights_11_21) && !is.null(weights_cache) && file.exists(weights_cache)) {
    weights_11_21 <- data.table::fread(weights_cache)
  }
  if (is.null(weights_11_21)) {
    if (!exists("build_lsoa_area_weights", mode = "function")) {
      stop("Source lsoa_area_weight_functions.R before building weights.", call. = FALSE)
    }
    if (is.null(area_weight_args)) stop("Supply weights_11_21 or area_weight_args.", call. = FALSE)
    weights <- do.call(build_lsoa_area_weights, area_weight_args)
    weights_11_21 <- weights$wgt_11_21
    if (!is.null(weights_cache)) {
      dir.create(dirname(weights_cache), recursive = TRUE, showWarnings = FALSE)
      data.table::fwrite(weights_11_21, weights_cache)
    }
  }
  
  historical <- read_historical_lsoa_population(population_dir)
  allocated <- allocate_lsoa11_population_to_lsoa21(historical, weights_11_21)
  current <- read_lsoa21_population(population_dir)
  
  result <- dplyr::bind_rows(allocated, current) |>
    dplyr::arrange(.data$lsoa_2021_code, .data$year)
  
  if (!is.null(lsoa21_shp)) {
    shapes <- sf::st_read(lsoa21_shp, quiet = TRUE) |>
      sf::st_drop_geometry()
    if (all(c("LSOA21CD", "LSOA21NM") %in% names(shapes))) {
      result <- result |>
        dplyr::select(-dplyr::any_of("lsoa_2021_name")) |>
        dplyr::left_join(dplyr::distinct(shapes[, c("LSOA21CD", "LSOA21NM")]), by = c("lsoa_2021_code" = "LSOA21CD")) |>
        dplyr::rename(lsoa_2021_name = .data$LSOA21NM)
    }
  }
  if (!is.null(lookup11_21_csv)) {
    lad <- data.table::fread(lookup11_21_csv) |>
      dplyr::as_tibble() |>
      dplyr::filter(startsWith(.data$LAD22CD, "E")) |>
      dplyr::select(dplyr::any_of(c("LSOA21CD", "LAD22CD", "LAD22NM"))) |>
      dplyr::distinct()
    result <- result |>
      dplyr::left_join(lad, by = c("lsoa_2021_code" = "LSOA21CD")) |>
      dplyr::rename(lad_code = .data$LAD22CD, lad_name = .data$LAD22NM)
  }
  if (!is.null(output_csv)) {
    dir.create(dirname(output_csv), recursive = TRUE, showWarnings = FALSE)
    readr::write_csv(result, output_csv)
  }
  result
}
