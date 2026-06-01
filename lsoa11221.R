
# where to download the data ----------------------------------------------

# https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3
# https://geoportal.statistics.gov.uk/datasets/ons::lsoa-2001-to-lsoa-2011-to-lad-december-2011-best-fit-lookup-in-ew/about?appid=e2d91cb940234693bf2c78e5e2d7a504&edit=true

# LSOA 2001
# https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2001-boundaries-ew-bfe/about
# LSOA 2011
# https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-ew-bfc-v3/about
# https://data.london.gov.uk/dataset/2011-census-geography-boundary-files-29jwj/

# set the scene -----------------------------------------------------------
library(sf)
library(dplyr)
library(data.table)

lsoa_dir <- here("data", "lsoa")

lsoa_shp_files <- list.files(
  lsoa_dir,
  pattern = "LSOA.*(BFE|BFC).*\\.shp$",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)

lsoa_csv_files <- list.files(
  lsoa_dir,
  pattern = "\\.csv$",
  full.names = TRUE,
  recursive = TRUE,
  ignore.case = TRUE
)

lsoa_shp <- setNames(
  lapply(lsoa_shp_files, sf::st_read, quiet = TRUE),
  basename(lsoa_shp_files)
)

lsoa_csv <- setNames(
  lapply(lsoa_csv_files, data.table::fread),
  basename(lsoa_csv_files)
)


poly_lsoa_01 <- lsoa_shp[["LSOA_2001_EW_BFE_V2.shp"]] %>%
  filter(startsWith(LSOA01CD, "E")) %>%
  st_transform(27700)

poly_lsoa_11 <- lsoa_shp[["LSOA_2011_EW_BFC_V3.shp"]] %>%
  filter(startsWith(LSOA11CD, "E")) %>%
  st_transform(27700)

poly_lsoa_21 <- lsoa_shp[["LSOA_2021_EW_BFE_V10.shp"]] %>%
  filter(startsWith(LSOA21CD, "E")) %>%
  st_transform(27700)

lookup_01_11 <- lsoa_csv[["Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv"]] %>%
  .[grepl("^E", LSOA01CD)]

lookup_11_21 <- lsoa_csv[["LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3).csv"]] %>%
  .[grepl("^E", LSOA11CD)]



# Build 2011 → 2021 area weights ------------------------------------------

lsoa11_one2many <- lookup_11_21 %>%
  .[, .(LSOA11CD, LSOA21CD)] %>%
  unique() %>%
  .[, .N, by = LSOA11CD] %>%
  .[N > 1, LSOA11CD]

poly_lsoa_11_one2many <- poly_lsoa_11 %>%
  filter(LSOA11CD %in% lsoa11_one2many)

lookup_wgt_11_21_one2many <- poly_lsoa_11_one2many %>%
  select(LSOA11CD, geometry) %>%
  st_intersection(poly_lsoa_21 %>% select(LSOA21CD, geometry)) %>%
  mutate(
    intersect_area = st_area(geometry),
    LSOA11AREA = st_area(poly_lsoa_11_one2many)[match(LSOA11CD, poly_lsoa_11_one2many$LSOA11CD)],
    LSOA11WGT = as.numeric(intersect_area / LSOA11AREA)
  ) %>%
  st_drop_geometry() %>%
  select(LSOA11CD, LSOA21CD, LSOA11WGT) %>%
  as.data.table()

lookup_wgt_11_21_one2one <- lookup_11_21 %>%
  .[, .(LSOA11CD, LSOA21CD)] %>%
  unique() %>%
  .[!(LSOA11CD %in% lsoa11_one2many)] %>%
  .[, LSOA11WGT := 1]

lookup_wgt_11_21 <- rbindlist(
  list(lookup_wgt_11_21_one2many, lookup_wgt_11_21_one2one)
) %>%
  setorder(LSOA11CD, LSOA21CD)


## Normalise the 2011 → 2021 weights ---------------------------------------
lookup_wgt_11_21 <- copy(lookup_wgt_11_21)

lookup_wgt_11_21[
  , LSOA11WGT := LSOA11WGT / sum(LSOA11WGT),
  by = LSOA11CD
]

# Build 2001 → 2011 area weights ------------------------------------------

lsoa01_one2many <- lookup_01_11 %>%
  .[, .(LSOA01CD, LSOA11CD)] %>%
  unique() %>%
  .[, .N, by = LSOA01CD] %>%
  .[N > 1, LSOA01CD]

poly_lsoa_01_one2many <- poly_lsoa_01 %>%
  filter(LSOA01CD %in% lsoa01_one2many)

lookup_wgt_01_11_one2many <- poly_lsoa_01_one2many %>%
  select(LSOA01CD, geometry) %>%
  st_intersection(poly_lsoa_11 %>% select(LSOA11CD, geometry)) %>%
  mutate(
    intersect_area = st_area(geometry),
    LSOA01AREA = st_area(poly_lsoa_01_one2many)[match(LSOA01CD, poly_lsoa_01_one2many$LSOA01CD)],
    LSOA01WGT = as.numeric(intersect_area / LSOA01AREA)
  ) %>%
  st_drop_geometry() %>%
  select(LSOA01CD, LSOA11CD, LSOA01WGT) %>%
  as.data.table()

lookup_wgt_01_11_one2one <- lookup_01_11 %>%
  .[, .(LSOA01CD, LSOA11CD)] %>%
  unique() %>%
  .[!(LSOA01CD %in% lsoa01_one2many)] %>%
  .[, LSOA01WGT := 1]

lookup_wgt_01_11 <- rbindlist(
  list(lookup_wgt_01_11_one2many, lookup_wgt_01_11_one2one)
) %>%
  setorder(LSOA01CD, LSOA11CD)


## Normalise lookup_wgt_01_11 ----------------------------------------------
lookup_wgt_01_11 <- copy(lookup_wgt_01_11)

lookup_wgt_01_11[
  , LSOA01WGT := LSOA01WGT / sum(LSOA01WGT),
  by = LSOA01CD
]




# Build 2001 → 2021 weights via 2011 --------------------------------------

lookup_wgt_01_21 <- merge(
  lookup_wgt_01_11,
  lookup_wgt_11_21,
  by = "LSOA11CD",
  allow.cartesian = TRUE
)[
  , LSOA01WGT21 := LSOA01WGT * LSOA11WGT
][
  , .(LSOA01WGT21 = sum(LSOA01WGT21)),
  by = .(LSOA01CD, LSOA21CD)
] %>%
  setorder(LSOA01CD, LSOA21CD)

## Normalise the final 2001 → 2021 weights too ---------------------------
lookup_wgt_01_21 <- copy(lookup_wgt_01_21)

lookup_wgt_01_21[
  , LSOA01WGT21 := LSOA01WGT21 / sum(LSOA01WGT21),
  by = LSOA01CD
]

# Check weights sum to 1 within source LSOA -------------------------------

if(FALSE){

lookup_wgt_11_21[
  , .(sum_wgt = sum(LSOA11WGT)), by = LSOA11CD
][
  order(abs(sum_wgt - 1), decreasing = TRUE)
] %>%
  head()


# > check_11_21 <- lookup_wgt_11_21[
#   , .(sum_wgt = sum(LSOA11WGT)), by = LSOA11CD
# ]
# 
# check_11_21[abs(sum_wgt - 1) > 0.001, .N]
# check_11_21[abs(sum_wgt - 1) > 0.005, .N]
# check_11_21[abs(sum_wgt - 1) > 0.01, .N]
# [1] 2
# [1] 0                                                                                                                                   
# [1] 0

## 2001 → 2011 -----------------------------------------------------------

lookup_wgt_01_11[
  , .(sum_wgt = sum(LSOA01WGT)), by = LSOA01CD
][
  order(abs(sum_wgt - 1), decreasing = TRUE)
] %>%
  head()


## 2001 → 2021 -----------------------------------------------------------

lookup_wgt_01_21[
  , .(sum_wgt = sum(LSOA01WGT21)), by = LSOA01CD
][
  order(abs(sum_wgt - 1), decreasing = TRUE)
] %>%
  head()

  
}


# from connor -------------------------------------------------------------



if(FALSE){
  # Thanks Connor
  #### 0.3.2.1. polygon ----
poly.lsoa <- 
  file.path(dir.data.spa, 'ons21_LSOA') %>% 
  sf::st_read(dsn = ., layer = 'ons21_LSOA') %>% 
  dplyr::filter(startsWith(LSOA21CD, 'E'))

poly.lsoa.11 <- 
  file.path(dir.data.spa, 'ons21_LSOA') %>% 
  sf::st_read(dsn = ., layer = 'ons21_LSOA') %>% 
  dplyr::filter(startsWith(LSOA21CD, 'E')) %>% 
  sf::st_transform(
    x = .,
    crs = sf::st_crs(poly.lsoa))

#### 0.3.2.3. look up ----

lsoa.lookup <- 
  file.path(dir.data.spa, 'ons_lookup', 'LSOA11_LSOA21_LAD22_lookUp.csv') %>% 
  data.table::fread(file = .) %>% 
  .[grepl(pattern = '^E', x = LSOA11CD)]

lsoa.lookup.one2many <-
  lsoa.lookup %>% 
  .[, .(LSOA11CD, LSOA21CD)] %>% 
  unique() %>% 
  .[, .N, by = LSOA11CD] %>% 
  .[N > 1, LSOA11CD]

poly.lsoa.11.one2many <- 
  poly.lsoa.11 %>% 
  dplyr::filter(LSOA11CD %in% lsoa.lookup.one2many)

lsoa.lookup.wgt.one2many <-
  poly.lsoa.11.one2many %>% 
  dplyr::select(LSOA11CD, geometry) %>% 
  sf::st_intersection(
    x = .,
    y = poly.lsoa %>% dplyr::select(LSOA21CD, geometry)
  ) %>% 
  dplyr::mutate(
    intersect_area = geometry %>% sf::st_area(),
    LSOA11AREA = sf::st_geometry(poly.lsoa.11.one2many)[match(LSOA11CD, poly.lsoa.11.one2many$LSOA11CD)] %>% sf::st_area(),
    LSOA11WGT = as.numeric(intersect_area / LSOA11AREA)
  ) %>%
  sf::st_drop_geometry() %>%
  dplyr::select(LSOA11CD, LSOA21CD, LSOA11WGT) %>% 
  data.table::data.table()

lsoa.lookup.wgt.one2one <- 
  lsoa.lookup %>% 
  .[, .(LSOA11CD, LSOA21CD)] %>% 
  unique() %>% 
  .[!(LSOA11CD %in% lsoa.lookup.one2many)] %>% 
  .[, LSOA11WGT := 1]

lsoa.lookup.wgt <-
  data.table::rbindlist(
    list(lsoa.lookup.wgt.one2many, lsoa.lookup.wgt.one2one)
  ) %>% 
  data.table::setorder(LSOA11CD, LSOA21CD)

}