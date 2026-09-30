# Annual population estimates on 2021 English LSOAs --------------------------
#
# Purpose:
#   Build a consistent 2002–2024 annual population dataset on 2021 English
#   Lower-layer Super Output Area (LSOA) boundaries. The output contains total
#   population and sex-by-age-group counts.
#
# Data sources:
#   * ONS small-area population estimates (SAPE) by single year of age:
#     https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/smallareapopulationestimatesinenglandandwales
#   * Geography, maps, and supporting data:
#     https://humaniverse.github.io/geographr/
#     https://bristol.libguides.com/maps/map-data
#     https://osdatahub.os.uk/data/downloads/open
#
# Required project layout:
#   <project root>/
#   ├── lsoa11221.R
#   └── data/
#       ├── lsoa_pop_est_sing/
#       │   ├── SAPE8DT2a-LSOA-syoa-unformatted-males-mid2002-to-mid2006.xls
#       │   ├── SAPE8DT2b-LSOA-syoa-unformatted-males-mid2007-to-mid2010.xls
#       │   ├── SAPE8DT3a-LSOA-syoa-unformatted-females-mid2002-to-mid2006.xls
#       │   ├── SAPE8DT3b-LSOA-syoa-unformatted-females-mid2007-to-mid2010.xls
#       │   └── sapelsoasyoa*.xlsx          # 2011 onward releases
#       └── pop_regrouped_2002_2024.csv     # created by this script
#
# `lsoa11221.R` must create:
#   * `poly_lsoa_21`: 2021 LSOA sf boundaries, including LSOA21CD and LSOA21NM
#   * `lookup_wgt_11_21`: an area-weighted 2011-to-2021 crosswalk with
#     LSOA11CD, LSOA21CD, and LSOA11WGT.
#
# Important:
#   The 2002–2010 values are allocated from 2011 to 2021 LSOAs using geographic
#   area weights. This is suitable for additive counts, subject to the usual
#   assumption of a uniform population distribution within each source LSOA.

# Packages -----------------------------------------------------------------
required_packages <- c("sf", "here", "readxl", "dplyr", "purrr", "tidyr",
                       "tibble", "readr", "stringr", "data.table")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]

if (length(missing_packages) > 0L) {
  install.packages(missing_packages)
}

invisible(lapply(required_packages, library, character.only = TRUE))

# Paths and geography/crosswalk setup --------------------------------------
population_dir <- here::here("data", "lsoa_pop_est_sing")
output_file <- here::here("data", "pop_regrouped_2002_2024.csv")
crosswalk_script <- here::here("lsoa11221.R")

if (!dir.exists(population_dir)) {
  stop("Population-data directory not found: ", population_dir, call. = FALSE)
}
if (!file.exists(crosswalk_script)) {
  stop("Crosswalk/geography script not found: ", crosswalk_script, call. = FALSE)
}

source(crosswalk_script)

required_objects <- c("poly_lsoa_21", "lookup_wgt_11_21")
missing_objects <- required_objects[!vapply(required_objects, exists, logical(1), inherits = TRUE)]
if (length(missing_objects) > 0L) {
  stop(
    "`lsoa11221.R` must create: ", paste(missing_objects, collapse = ", "),
    call. = FALSE
  )
}

required_crosswalk_columns <- c("LSOA11CD", "LSOA21CD", "LSOA11WGT")
if (!all(required_crosswalk_columns %in% names(lookup_wgt_11_21))) {
  stop("`lookup_wgt_11_21` does not contain the expected columns.", call. = FALSE)
}
if (!all(c("LSOA21CD", "LSOA21NM") %in% names(poly_lsoa_21))) {
  stop("`poly_lsoa_21` must contain `LSOA21CD` and `LSOA21NM`.", call. = FALSE)
}

# Reusable helpers ---------------------------------------------------------
# Convert requested columns to numeric safely, allowing Excel cells that were
# imported as text (including values with commas or other display formatting).
as_numeric_columns <- function(data, columns) {
  data |>
    mutate(across(any_of(columns), ~ readr::parse_number(as.character(.x))))
}

# Sum a supplied set of age columns for every row. `any_of()` means a release
# may omit a requested column without causing an error; absent columns add zero.
sum_age_columns <- function(data, columns) {
  data |>
    transmute(value = rowSums(pick(any_of(columns)), na.rm = TRUE)) |>
    pull(value)
}

# Build standard population fields from lower-case single-year-age columns.
# The old 2002–2010 spreadsheets contain male and female records separately;
# grouping afterwards adds them to LSOA-year totals.
regroup_old_syoa <- function(data, year, sex, source_file) {
  age_columns <- names(data)[stringr::str_detect(names(data), "^[fm](?:[0-9]+|90plus)$")]
  
  data |>
    as_numeric_columns(c("all_ages", age_columns)) |>
    transmute(
      year = year,
      source_file = source_file,
      sex = sex,
      lsoa_2011_code = LSOA11CD,
      lad_2011_code = LAD11CD,
      lad_2011_name = LAD11NM,
      total = all_ages,
      f_25_49 = sum_age_columns(pick(everything()), paste0("f", 25:49)),
      f_50_74 = sum_age_columns(pick(everything()), paste0("f", 50:74)),
      f_75_plus = sum_age_columns(pick(everything()), c(paste0("f", 75:89), "f90plus")),
      m_25_49 = sum_age_columns(pick(everything()), paste0("m", 25:49)),
      m_50_74 = sum_age_columns(pick(everything()), paste0("m", 50:74)),
      m_75_plus = sum_age_columns(pick(everything()), c(paste0("m", 75:89), "m90plus"))
    ) |>
    group_by(year, lsoa_2011_code, lad_2011_code, lad_2011_name) |>
    summarise(
      across(c(total, f_25_49, f_50_74, f_75_plus, m_25_49, m_50_74, m_75_plus),
             ~ sum(.x, na.rm = TRUE)),
      .groups = "drop"
    )
}

# Read and regroup 2002–2010 source files ----------------------------------
old_files <- list.files(
  population_dir,
  pattern = "\\.xls$",
  full.names = TRUE,
  ignore.case = TRUE
)

old_sheet_index <- tibble(path = old_files, file = basename(old_files)) |>
  filter(stringr::str_detect(stringr::str_to_lower(file), "males|females")) |>
  mutate(
    sex = case_when(
      stringr::str_detect(stringr::str_to_lower(file), "females") ~ "f",
      stringr::str_detect(stringr::str_to_lower(file), "males") ~ "m"
    ),
    sheet = purrr::map(path, readxl::excel_sheets)
  ) |>
  tidyr::unnest(sheet) |>
  filter(stringr::str_detect(sheet, "^Mid-[0-9]{4}$")) |>
  mutate(year = as.integer(stringr::str_extract(sheet, "[0-9]{4}"))) |>
  # Restrict this legacy source explicitly to avoid a duplicate 2011 estimate.
  filter(year >= 2002L, year <= 2010L) |>
  mutate(data = purrr::map2(path, sheet, readxl::read_excel))

if (nrow(old_sheet_index) == 0L) {
  stop("No eligible 2002–2010 male/female SAPE worksheets were found.", call. = FALSE)
}

old_population_2011 <- old_sheet_index |>
  mutate(
    data = purrr::map(data, ~ dplyr::rename_with(.x, tolower)),
    grouped = purrr::pmap(
      list(data, year, sex, file),
      regroup_old_syoa
    )
  ) |>
  select(grouped) |>
  tidyr::unnest(grouped)

# Allocate 2002–2010 counts from 2011 LSOAs to 2021 LSOAs -----------------
# Counts are additive, so each source value is multiplied by its crosswalk
# weight and then summed within the target LSOA and year.
old_population_2021 <- merge(
  data.table::as.data.table(old_population_2011),
  data.table::as.data.table(lookup_wgt_11_21),
  by.x = "lsoa_2011_code",
  by.y = "LSOA11CD",
  allow.cartesian = TRUE
)[
  , .(
    total = sum(total * LSOA11WGT, na.rm = TRUE),
    f_25_49 = sum(f_25_49 * LSOA11WGT, na.rm = TRUE),
    f_50_74 = sum(f_50_74 * LSOA11WGT, na.rm = TRUE),
    f_75_plus = sum(f_75_plus * LSOA11WGT, na.rm = TRUE),
    m_25_49 = sum(m_25_49 * LSOA11WGT, na.rm = TRUE),
    m_50_74 = sum(m_50_74 * LSOA11WGT, na.rm = TRUE),
    m_75_plus = sum(m_75_plus * LSOA11WGT, na.rm = TRUE)
  ),
  by = .(year, LSOA21CD)
] |>
  as_tibble()

lsoa21_attributes <- poly_lsoa_21 |>
  sf::st_drop_geometry() |>
  select(LSOA21CD, LSOA21NM) |>
  distinct() |>
  as_tibble()

lad21_lookup <- data.table::as.data.table(lookup_wgt_11_21) |>
  merge(
    # The lookup metadata should be available from the crosswalk source script.
    # If its LAD fields are elsewhere, replace this object with that lookup.
    data.table::data.table(LSOA21CD = character(), LAD22CD = character(), LAD22NM = character()),
    by = "LSOA21CD",
    all.x = TRUE
  )

# Obtain LAD attributes from the 2011-to-2021 published lookup if the object
# is provided by `lsoa11221.R`; otherwise leave them missing rather than
# incorrectly assigning a LAD after a boundary change.
if (exists("lookup_11_21", inherits = TRUE) &&
    all(c("LSOA21CD", "LAD22CD", "LAD22NM") %in% names(lookup_11_21))) {
  lad21_lookup <- lookup_11_21 |>
    as_tibble() |>
    select(LSOA21CD, LAD22CD, LAD22NM) |>
    distinct() |>
    rename(lad_code = LAD22CD, lad_name = LAD22NM)
} else {
  lad21_lookup <- tibble(LSOA21CD = character(), lad_code = character(), lad_name = character())
}

old_population_2021 <- old_population_2021 |>
  left_join(lsoa21_attributes, by = "LSOA21CD") |>
  left_join(lad21_lookup, by = "LSOA21CD") |>
  transmute(
    year,
    lsoa_2021_code = LSOA21CD,
    lsoa_2021_name = LSOA21NM,
    lad_code,
    lad_name,
    total, f_25_49, f_50_74, f_75_plus, m_25_49, m_50_74, m_75_plus
  )

# Read and regroup 2011–2024 source files ----------------------------------
new_files <- list.files(
  population_dir,
  pattern = "^sapelsoasyoa.*\\.xlsx$",
  full.names = TRUE,
  ignore.case = TRUE
)

new_sheet_index <- tibble(path = new_files, file = basename(new_files)) |>
  mutate(sheet = purrr::map(path, readxl::excel_sheets)) |>
  tidyr::unnest(sheet) |>
  filter(stringr::str_detect(sheet, "^Mid-[0-9]{4} LSOA 2021$")) |>
  mutate(year = as.integer(stringr::str_extract(sheet, "[0-9]{4}"))) |>
  filter(year >= 2011L, year <= 2024L) |>
  mutate(data = purrr::map2(path, sheet, ~ readxl::read_excel(.x, sheet = .y, skip = 3)))

if (nrow(new_sheet_index) == 0L) {
  stop("No eligible 2011–2024 LSOA 2021 SAPE worksheets were found.", call. = FALSE)
}

new_population_2021 <- new_sheet_index |>
  select(file, year, data) |>
  tidyr::unnest(data) |>
  as_numeric_columns(c("Total", paste0("F", 0:90), paste0("M", 0:90))) |>
  transmute(
    year,
    lad_code = coalesce(`LAD 2021 Code`, `LAD 2023 Code`),
    lad_name = coalesce(`LAD 2021 Name`, `LAD 2023 Name`),
    lsoa_2021_code = `LSOA 2021 Code`,
    lsoa_2021_name = `LSOA 2021 Name`,
    total = Total,
    f_25_49 = sum_age_columns(pick(everything()), paste0("F", 25:49)),
    f_50_74 = sum_age_columns(pick(everything()), paste0("F", 50:74)),
    f_75_plus = sum_age_columns(pick(everything()), paste0("F", 75:90)),
    m_25_49 = sum_age_columns(pick(everything()), paste0("M", 25:49)),
    m_50_74 = sum_age_columns(pick(everything()), paste0("M", 50:74)),
    m_75_plus = sum_age_columns(pick(everything()), paste0("M", 75:90))
  )

# Combine, validate, and export --------------------------------------------
population_2002_2024 <- bind_rows(old_population_2021, new_population_2021) |>
  filter(stringr::str_starts(lsoa_2021_code, "E")) |>
  arrange(lsoa_2021_code, year)

# Every LSOA-year must occur once. A duplicate generally means overlapping
# workbook releases or a year that was included in both source streams.
duplicate_lsoa_years <- population_2002_2024 |>
  count(lsoa_2021_code, year, name = "n") |>
  filter(n > 1L)

if (nrow(duplicate_lsoa_years) > 0L) {
  print(duplicate_lsoa_years, n = 20L)
  stop("Duplicate LSOA-year records found; review the selected source worksheets.", call. = FALSE)
}

missing_years <- setdiff(2002:2024, sort(unique(population_2002_2024$year)))
if (length(missing_years) > 0L) {
  warning("No records were produced for year(s): ", paste(missing_years, collapse = ", "))
}

readr::write_csv(population_2002_2024, output_file)
message("Wrote ", format(nrow(population_2002_2024), big.mark = ","), " rows to: ", output_file)
