# https://humaniverse.github.io/geographr/
# https://bristol.libguides.com/maps/map-data
# https://osdatahub.os.uk/data/downloads/open

libs_name <- c(
  "sf",
  "terra",
  "here",
  "purrr",
  "ggplot2",
  "tidyr",
  "tibble",
  "readxl",
  "dplyr",
  "future",
  "patchwork",
  "readr",
  "stringr"
)

missing_pkgs <- libs_name[!sapply(libs_name, requireNamespace, quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  install.packages(setdiff(missing_pkgs, c(
    "INLA", "inlabru", "fmesher", "fingertipsR"
  )))
}

# load all libraries
invisible(lapply(libs_name, library, character.only = TRUE))


# process ons lsoa pop ----------------------------------------------------

pop_board_dir <- here("data", "lsoa_pop_est_board")
pop_sing_dir <- here("data", "lsoa_pop_est_sing")


# broad -------------------------------------------------------------------
if (FALSE) {
  # lsoa_pop_est_broad folder
  # sapelsoabroadage20222024.xlsx
  # sapelsoabroadage20112022.xlsx

  # check sheets names
  if (FALSE) {
    board_files <- list.files(
      pop_board_dir,
      pattern = "\\.xlsx$",
      full.names = TRUE,
      ignore.case = TRUE
    )

    setNames(
      lapply(board_files, readxl::excel_sheets),
      basename(board_files)
    )

    board_files <- board_files[basename(board_files) %in% c(
      "sapelsoabroadage20112022.xlsx",
      "sapelsoabroadage20222024.xlsx"
    )]
  }

  board_files <- list.files(
    pop_board_dir,
    pattern = "sapelsoabroadage(20112022|20222024)\\.xlsx$",
    full.names = TRUE,
    ignore.case = TRUE
  )

  board_data <- tibble(path = board_files) %>%
    mutate(
      file = basename(path),
      sheets = map(path, excel_sheets)
    ) %>%
    unnest(sheets) %>%
    filter(str_detect(sheets, "^Mid-[0-9]{4} LSOA 2021$")) %>%
    mutate(year = as.integer(str_extract(sheets, "[0-9]{4}"))) %>%
    filter(
      (file == "sapelsoabroadage20112022.xlsx" & year <= 2021) |
        (file == "sapelsoabroadage20222024.xlsx" & year >= 2022)
    ) %>%
    mutate(data = map2(path, sheets, ~ read_excel(.x, sheet = .y, skip = 3)))

  # board_combined <- board_data %>%
  #   mutate(
  #     data = map2(data, year, ~ mutate(.x, year = .y)),
  #     data = map2(data, file, ~ mutate(.x, source_file = .y))
  #   ) %>%
  #   select(file, sheets, year, data) %>%
  #   unnest(data)


  board_combined <- board_data %>%
    select(file, sheets, year, data) %>%
    unnest(data)


  board_combined <- board_combined %>%
    rename(
      lad_2021_code = `LAD 2021 Code`,
      lad_2021_name = `LAD 2021 Name`,
      lad_2023_code = `LAD 2023 Code`,
      lad_2023_name = `LAD 2023 Name`,
      lsoa_2021_code = `LSOA 2021 Code`,
      lsoa_2021_name = `LSOA 2021 Name`,
      total = Total,
      f_0_15 = `F0 to 15`,
      f_16_29 = `F16 to 29`,
      f_30_44 = `F30 to 44`,
      f_45_64 = `F45 to 64`,
      f_65_plus = `F65 and over`,
      m_0_15 = `M0 to 15`,
      m_16_29 = `M16 to 29`,
      m_30_44 = `M30 to 44`,
      m_45_64 = `M45 to 64`,
      m_65_plus = `M65 and over`
    )


  glimpse(board_combined)
}
# single 2002 - 2010------------------------------------------------------------------
# lsoa_pop_est_sing folder
# SAPE8DT2a-LSOA-syoa-unformatted-males-mid2002-to-mid2006.xls
# SAPE8DT2b-LSOA-syoa-unformatted-males-mid2007-to-mid2010.xls
# SAPE8DT3a-LSOA-syoa-unformatted-females-mid2002-to-mid2006.xls
# SAPE8DT3b-LSOA-syoa-unformatted-females-mid2007-to-mid2010.xls
sing_files <- list.files(
  pop_sing_dir,
  pattern = "\\.xls$",
  full.names = TRUE,
  ignore.case = TRUE
)

sing_data <- tibble(path = sing_files) %>%
  mutate(file = basename(path)) %>%
  filter(str_detect(tolower(file), "males|females")) %>%
  mutate(
    sex = case_when(
      str_detect(tolower(file), "females") ~ "f",
      str_detect(tolower(file), "males") ~ "m"
    ),
    sheets = map(path, excel_sheets)
  ) %>%
  unnest(sheets) %>%
  filter(str_detect(sheets, "^Mid-[0-9]{4}$")) %>%
  mutate(
    year = as.integer(str_extract(sheets, "[0-9]{4}"))
  ) %>%
  filter(year != 2011) %>% # remove duplicated year 2011
  mutate(
    data = map2(path, sheets, read_excel)
  )


sing_combined <- sing_data %>%
  select(file, sex, sheets, year, data) %>%
  unnest(data)

sing_regrouped <- sing_combined %>%
  mutate(across(matches("^[mf][0-9]+$|^[mf]90plus$"), as.numeric)) %>%
  transmute(
    year,
    lsoa_2011_code = LSOA11CD,
    lad_2011_code = LAD11CD,
    lad_2011_name = LAD11NM,
    total = all_ages,
    f_25_49 = rowSums(across(any_of(paste0(
      "f", 25:49
    ))), na.rm = TRUE),
    f_50_74 = rowSums(across(any_of(paste0(
      "f", 50:74
    ))), na.rm = TRUE),
    f_75_plus = rowSums(across(any_of(
      c(paste0("f", 75:89), "f90plus")
    )), na.rm = TRUE),
    m_25_49 = rowSums(across(any_of(paste0(
      "m", 25:49
    ))), na.rm = TRUE),
    m_50_74 = rowSums(across(any_of(paste0(
      "m", 50:74
    ))), na.rm = TRUE),
    m_75_plus = rowSums(across(any_of(
      c(paste0("m", 75:89), "m90plus")
    )), na.rm = TRUE)
  ) %>%
  group_by(year, lsoa_2011_code, lad_2011_code, lad_2011_name) %>%
  summarise(
    total = sum(total, na.rm = TRUE),
    f_25_49 = sum(f_25_49, na.rm = TRUE),
    f_50_74 = sum(f_50_74, na.rm = TRUE),
    f_75_plus = sum(f_75_plus, na.rm = TRUE),
    m_25_49 = sum(m_25_49, na.rm = TRUE),
    m_50_74 = sum(m_50_74, na.rm = TRUE),
    m_75_plus = sum(m_75_plus, na.rm = TRUE),
    .groups = "drop"
  )


## project to LSOA 2021 ----------------------------------------------------

source("lsoa11221.R")

sing_regrouped_2021 <- merge(
  as.data.table(sing_regrouped),
  lookup_wgt_11_21,
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
] %>%
  setorder(year, LSOA21CD)

lsoa21_names <- poly_lsoa_21 %>%
  st_drop_geometry() %>%
  select(LSOA21CD, LSOA21NM) %>%
  distinct() %>%
  as.data.table()

sing_regrouped_2021 <- merge(
  sing_regrouped_2021,
  lsoa21_names,
  by = "LSOA21CD",
  all.x = TRUE
)

sing_regrouped_2021 <- sing_regrouped_2021 %>%
  as_tibble() %>%
  rename(
    lsoa_2021_code = LSOA21CD,
    lsoa_2021_name = LSOA21NM
  )


## add lsoa names 2021 -----------------------------------------------------

lad21_lookup <- lookup_11_21 %>%
  as_tibble() %>%
  select(LSOA21CD, LAD22CD, LAD22NM) %>%
  distinct() %>%
  rename(
    lsoa_2021_code = LSOA21CD,
    lad_code = LAD22CD,
    lad_name = LAD22NM
  )

sing_regrouped_2021 <- sing_regrouped_2021 %>%
  left_join(lad21_lookup, by = "lsoa_2021_code") %>%
  select(
    year,
    lsoa_2021_code,
    lsoa_2021_name,
    lad_code,
    lad_name,
    total,
    f_25_49,
    f_50_74,
    f_75_plus,
    m_25_49,
    m_50_74,
    m_75_plus
  )



# syoa from 2011 --------------------------------------------------------------------

pop_sing_dir <- here("data", "lsoa_pop_est_sing")

syoa_files <- list.files(
  pop_sing_dir,
  pattern = "^sapelsoasyoa.*\\.xlsx$",
  full.names = TRUE,
  ignore.case = TRUE
)

syoa_data <- tibble(path = syoa_files) %>%
  mutate(file = basename(path), sheets = map(path, excel_sheets)) %>%
  unnest(sheets) %>%
  filter(str_detect(sheets, "^Mid-[0-9]{4} LSOA 2021$")) %>%
  mutate(year = as.integer(str_extract(sheets, "[0-9]{4}"))) %>%
  mutate(data = map2(path, sheets, ~ read_excel(.x, sheet = .y, skip = 3)))

syoa_combined <- syoa_data %>%
  select(file, sheets, year, data) %>%
  unnest(data)

syoa_regrouped <- syoa_combined %>%
  mutate(
    across(
      matches("^[FM][0-9]{1,2}$"),
      ~ parse_number(as.character(.x))
    ),
    Total = parse_number(as.character(Total))
  ) %>%
  transmute(
    file,
    year,
    `LAD 2021 Code` = coalesce(`LAD 2021 Code`, `LAD 2023 Code`),
    `LAD 2021 Name` = coalesce(`LAD 2021 Name`, `LAD 2023 Name`),
    `LSOA 2021 Code`,
    `LSOA 2021 Name`,
    Total,
    f_25_49 = rowSums(across(all_of(paste0(
      "F", 25:49
    ))), na.rm = TRUE),
    f_50_74 = rowSums(across(all_of(paste0(
      "F", 50:74
    ))), na.rm = TRUE),
    f_75_plus = rowSums(across(all_of(paste0(
      "F", 75:90
    ))), na.rm = TRUE),
    m_25_49 = rowSums(across(all_of(paste0(
      "M", 25:49
    ))), na.rm = TRUE),
    m_50_74 = rowSums(across(all_of(paste0(
      "M", 50:74
    ))), na.rm = TRUE),
    m_75_plus = rowSums(across(all_of(paste0(
      "M", 75:90
    ))), na.rm = TRUE)
  )


syoa_regrouped <- syoa_regrouped %>%
  rename(
    lad_code = `LAD 2021 Code`,
    lad_name = `LAD 2021 Name`,
    lsoa_2021_code = `LSOA 2021 Code`,
    lsoa_2021_name = `LSOA 2021 Name`,
    total = Total
  ) %>%
  select(
    year,
    lsoa_2021_code,
    lsoa_2021_name,
    lad_code,
    lad_name,
    total,
    f_25_49,
    f_50_74,
    f_75_plus,
    m_25_49,
    m_50_74,
    m_75_plus
  )


# combine everything ------------------------------------------------------
pop_regrouped_2002_2024 <- bind_rows(
  sing_regrouped_2021,
  syoa_regrouped
) %>%
  arrange(lsoa_2021_code, year)
  
  readr::write_csv(
    pop_regrouped_2002_2024,
    here::here("data", "pop_regrouped_2002_2024.csv")
  )
  

  
  # > head(pop_regrouped_2002_2024, n = 20)
  # # A tibble: 20 × 12
  # year lsoa_2021_code lsoa_2021_name   lad_code lad_name total f_25_49 f_50_74
  # <int> <chr>          <chr>            <chr>    <chr>    <dbl>   <dbl>   <dbl>
  #   1  2002 E01000001      City of London … E090000… City of…  1571     329     265
  # 2  2003 E01000001      City of London … E090000… City of…  1578     343     257
  # 3  2004 E01000001      City of London … E090000… City of…  1559     344     244
  # 4  2005 E01000001      City of London … E090000… City of…  1461     297     257
  # 5  2006 E01000001      City of London … E090000… City of…  1474     318     246
  # 6  2007 E01000001      City of London … E090000… City of…  1538     340     250
  # 7  2008 E01000001      City of London … E090000… City of…  1504     322     244
  # 8  2009 E01000001      City of London … E090000… City of…  1515     314     247
  # 9  2010 E01000001      City of London … E090000… City of…  1450     309     236
  # 10  2011 E01000001      City of London … E090000… City of…  1472     279     241
  # 11  2011 E01000001      City of London … E090000… City of…  1472     279     241
  # 12  2012 E01000001      City of London … E090000… City of…  1498     285     236
  # 13  2013 E01000001      City of London … E090000… City of…  1624     297     248
  # 14  2014 E01000001      City of London … E090000… City of…  1592     316     248
  # 15  2015 E01000001      City of London … E090000… City of…  1642     370     251
  # 16  2016 E01000001      City of London … E090000… City of…  1613     349     254
  # 17  2017 E01000001      City of London … E090000… City of…  1554     322     243
  # 18  2018 E01000001      City of London … E090000… City of…  1589     288     239
  # 19  2019 E01000001      City of London … E090000… City of…  1677     322     242
  # 20  2020 E01000001      City of London … E090000… City of…  1563     316     236


# sth else ----------------------------------------------------------------

if (FALSE) {
  pop <- tibble(path = files, file = basename(files)) %>%
    mutate(
      file_lower = tolower(file),
      year = str_extract(file_lower, "20\\d{2}") |> as.integer(),
      format_status = case_when(
        str_detect(file_lower, "unformatted") ~ "unformatted",
        str_detect(file_lower, "formatted") ~ "formatted",
        TRUE ~ NA_character_
      ),
      data = map(path, read_excel)
    )
}
