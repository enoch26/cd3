# LSOA 2021 smoking-prevalence exposure dataset --------------------------------
#
# Purpose:
#   Download Adult Smoking Prevalence Survey (APS) estimates from the OHID
#   Fingertips API at Local Authority District (LAD) level, then attach each
#   LAD estimate to its constituent 2021 English LSOAs.
#
# IMPORTANT LIMITATION:
#   APS smoking prevalence is not available at LSOA level in this workflow.
#   Every LSOA in a LAD receives the same LAD-level percentage. The outputs
#   are therefore contextual/exposure variables, not observed or modelled
#   small-area smoking-prevalence estimates.
#
# Sources:
#   * OHID Fingertips / Smoking Profile: https://fingertips.phe.org.uk/
#   * LSOA 2011 -> LSOA 2021 -> LAD 2022 exact-fit lookup (EW), v3:
#     https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/
#     lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3
#
# Expected project layout:
#   <project root>/
#   ├── build_lsoa_smoking_aps_exposure.R
#   └── data/
#       └── lsoa/
#           └── LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_
#               Exact_Fit_Lookup_for_EW_(V3).csv
#
# Outputs:
#   data/derived/lsoa2021_smoking_aps_long.csv
#   data/derived/lsoa2021_smoking_aps_wide.csv
#
# The long file retains all periods returned by Fingertips, including multi-year
# periods. The wide file contains one column per single-year period only, named
# smokeYYYY (for example, smoke2021).

# Packages -----------------------------------------------------------------
required_packages <- c("dplyr", "fingertipsR", "here", "readr", "tidyr")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]

if (length(missing_packages) > 0L) {
  install.packages(missing_packages)
}

invisible(lapply(required_packages, library, character.only = TRUE))

# Configuration ------------------------------------------------------------
# Indicator 92443: Smoking Prevalence in adults (aged 18 and over) - current
# smokers (APS). Recheck the Fingertips metadata before reproducing analyses:
# indicator definitions and available periods can change between releases.
smoking_indicator_id <- 92443L

lookup_file <- here::here(
  "data", "lsoa",
  paste0(
    "LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_",
    "Exact_Fit_Lookup_for_EW_(V3).csv"
  )
)
output_dir <- here::here("data", "derived")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

long_output <- file.path(output_dir, "lsoa2021_smoking_aps_long.csv")
wide_output <- file.path(output_dir, "lsoa2021_smoking_aps_wide.csv")

if (!file.exists(lookup_file)) {
  stop(
    "LSOA-to-LAD lookup not found: ", lookup_file,
    "\nDownload it from the data.gov.uk source in this script header.",
    call. = FALSE
  )
}

# Optional metadata exploration -------------------------------------------
# Set to TRUE to list Smoking Profile indicators before selecting an ID.
# This block is not required to produce the two output datasets.
inspect_smoking_metadata <- FALSE

if (inspect_smoking_metadata) {
  smoking_profiles <- fingertipsR::profiles() |>
    dplyr::filter(grepl("smok", ProfileName, ignore.case = TRUE))
  print(smoking_profiles)
  
  smoking_indicators <- fingertipsR::indicators(ProfileID = 18L)
  print(smoking_indicators)
  
  readr::write_tsv(
    smoking_indicators,
    file.path(output_dir, "fingertips_smoking_profile_indicators.tsv")
  )
}

# Read the England-only LSOA-to-LAD lookup --------------------------------
# LAD codes beginning E identify English authorities. The exact-fit lookup
# contains a 2021 LSOA code and a LAD 2022 code for each relationship.
lsoa_lad_lookup <- readr::read_csv(lookup_file, show_col_types = FALSE) |>
  dplyr::filter(startsWith(LAD22CD, "E")) |>
  dplyr::transmute(LSOA21CD, LAD22CD) |>
  dplyr::distinct()

if (nrow(lsoa_lad_lookup) == 0L) {
  stop("No English LSOA 2021-to-LAD 2022 records were found in the lookup.", call. = FALSE)
}
if (anyDuplicated(lsoa_lad_lookup$LSOA21CD)) {
  stop(
    "At least one LSOA21CD has multiple LAD22CD assignments. ",
    "Inspect the lookup before continuing.",
    call. = FALSE
  )
}

# Download and select APS smoking estimates --------------------------------
# AreaTypeID = "All" retrieves every geographic resolution available for this
# indicator. The filters retain LAD, Persons, age 18+ records only.
smoking_raw <- fingertipsR::fingertips_data(
  IndicatorID = smoking_indicator_id,
  AreaTypeID = "All"
)

required_api_columns <- c("IndicatorID", "Sex", "Age", "AreaType", "AreaCode", "Timeperiod", "Value")
missing_api_columns <- setdiff(required_api_columns, names(smoking_raw))
if (length(missing_api_columns) > 0L) {
  stop(
    "The Fingertips response is missing expected column(s): ",
    paste(missing_api_columns, collapse = ", "),
    call. = FALSE
  )
}

smoking_lad <- smoking_raw |>
  dplyr::filter(
    IndicatorID == smoking_indicator_id,
    Sex == "Persons",
    Age == "18+ yrs",
    grepl("Districts", AreaType)
  ) |>
  dplyr::transmute(
    Timeperiod = as.character(Timeperiod),
    LAD22CD = AreaCode,
    smoking_prev = suppressWarnings(as.numeric(Value))
  ) |>
  dplyr::distinct()

if (nrow(smoking_lad) == 0L) {
  stop(
    "No LAD-level Persons, age-18+ APS smoking records remained after filtering. ",
    "Inspect current Fingertips metadata and revise the filters if needed.",
    call. = FALSE
  )
}
if (anyDuplicated(smoking_lad[c("Timeperiod", "LAD22CD")])) {
  stop("More than one smoking value exists for at least one LAD-period combination.", call. = FALSE)
}

# Handle LAD boundary changes ----------------------------------------------
# North and West Northamptonshire replaced seven predecessor districts in
# April 2021. If an estimate for the successor LAD is unavailable, fill it
# with the UNWEIGHTED mean of available predecessor-LAD percentages in the
# same time period. This is a pragmatic continuity rule, not an official
# reconstruction; retain and report this limitation in downstream work.
make_predecessor_mean <- function(data, predecessor_codes, output_name) {
  data |>
    dplyr::filter(LAD22CD %in% predecessor_codes) |>
    dplyr::group_by(Timeperiod) |>
    dplyr::summarise(
      "{output_name}" := mean(smoking_prev, na.rm = TRUE),
      .groups = "drop"
    )
}

north_fill <- make_predecessor_mean(
  smoking_lad,
  c("E07000150", "E07000152", "E07000153", "E07000156"),
  "north_value"
)
west_fill <- make_predecessor_mean(
  smoking_lad,
  c("E07000151", "E07000154", "E07000155"),
  "west_value"
)

smoking_lad <- smoking_lad |>
  dplyr::left_join(north_fill, by = "Timeperiod") |>
  dplyr::left_join(west_fill, by = "Timeperiod") |>
  dplyr::mutate(
    smoking_prev = dplyr::case_when(
      LAD22CD == "E06000061" & is.na(smoking_prev) ~ north_value,
      LAD22CD == "E06000062" & is.na(smoking_prev) ~ west_value,
      TRUE ~ smoking_prev
    )
  ) |>
  dplyr::select(Timeperiod, LAD22CD, smoking_prev)

# City of London and Isles of Scilly can have unavailable or suppressed APS
# estimates. Where absent, use the unweighted England mean for that period.
# This is an explicit imputation, not a local estimate.
england_mean <- smoking_lad |>
  dplyr::group_by(Timeperiod) |>
  dplyr::summarise(
    england_mean = mean(smoking_prev, na.rm = TRUE),
    .groups = "drop"
  )

smoking_lad <- smoking_lad |>
  dplyr::left_join(england_mean, by = "Timeperiod") |>
  dplyr::mutate(
    smoking_prev = dplyr::case_when(
      LAD22CD %in% c("E09000001", "E06000053") & is.na(smoking_prev) ~ england_mean,
      TRUE ~ smoking_prev
    )
  ) |>
  dplyr::select(Timeperiod, LAD22CD, smoking_prev)

# Fill any remaining suppressed or unavailable values using the closest
# available observation within the same LAD. `downup` can carry a value across
# a multi-period gap, so inspect the long output before using it in analysis.
smoking_lad <- smoking_lad |>
  dplyr::arrange(LAD22CD, Timeperiod) |>
  dplyr::group_by(LAD22CD) |>
  tidyr::fill(smoking_prev, .direction = "downup") |>
  dplyr::ungroup()

# Construct long and annual-wide LSOA datasets -----------------------------
# The long output preserves all API periods, including multi-year periods.
lsoa_smoking_long <- lsoa_lad_lookup |>
  dplyr::left_join(smoking_lad, by = "LAD22CD") |>
  dplyr::arrange(LSOA21CD, Timeperiod)

# Wide output is intentionally restricted to simple annual labels such as
# 2019. Periods such as 2019-21 remain available in the long output.
smoking_annual_lad <- smoking_lad |>
  dplyr::filter(!grepl("-", Timeperiod)) |>
  dplyr::mutate(
    year = suppressWarnings(as.integer(Timeperiod)),
    variable = paste0("smoke", year)
  ) |>
  dplyr::filter(!is.na(year))

lsoa_smoking_wide <- lsoa_lad_lookup |>
  dplyr::left_join(
    smoking_annual_lad |>
      dplyr::select(LAD22CD, variable, smoking_prev) |>
      tidyr::pivot_wider(names_from = variable, values_from = smoking_prev),
    by = "LAD22CD"
  ) |>
  dplyr::arrange(LSOA21CD)

# Quality assurance ---------------------------------------------------------
expected_lsoa_count <- dplyr::n_distinct(lsoa_lad_lookup$LSOA21CD)
actual_long_count <- dplyr::n_distinct(lsoa_smoking_long$LSOA21CD)
actual_wide_count <- dplyr::n_distinct(lsoa_smoking_wide$LSOA21CD)

if (actual_long_count != expected_lsoa_count || actual_wide_count != expected_lsoa_count) {
  stop(
    "LSOA coverage changed during the join; inspect the lookup and API data.",
    call. = FALSE
  )
}

message("English LSOAs in output: ", expected_lsoa_count)
message("Missing smoking values in long output: ", sum(is.na(lsoa_smoking_long$smoking_prev)))
message("Available annual smoking columns: ", paste(grep("^smoke[0-9]{4}$", names(lsoa_smoking_wide), value = TRUE), collapse = ", "))

# Write outputs -------------------------------------------------------------
readr::write_csv(lsoa_smoking_long, long_output)
readr::write_csv(lsoa_smoking_wide, wide_output)

message("Wrote: ", long_output)
message("Wrote: ", wide_output)
