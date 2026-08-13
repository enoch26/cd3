###############################################################################
# Aggregate LSOA attributes to MSOA geography
#
# Expected inputs:
# - lsoa_sf: an sf object containing one row per LSOA with attributes to
#   aggregate (population, cancer counts, NDVI, IMD, etc.)
# - msoa_sf: an sf object containing MSOA boundaries
#
# This function:
# 1. Ensures both layers use the same CRS
# 2. Intersects LSOAs and MSOAs
# 3. Computes overlap areas
# 4. Sums count variables (e.g. population, cases, deaths)
# 5. Computes area-weighted means for continuous variables
#    (e.g. NDVI, PM2.5, IMD score)
# 6. Computes area-weighted majority class for categorical variables
#    (e.g. urban/rural, deprivation quintile)
# 7. Returns an sf object with one row per MSOA
#
# Notes:
# - If LSOAs nest perfectly within MSOAs (which is usually true for ONS
#   geographies), a simple group_by(MSOA) aggregation may be sufficient.
# - This function is more general and will correctly handle partial overlaps.
#
# Returns:
# - sf object with MSOA geometry and aggregated attributes
#
# Example:
#
# ndvi_cols <- grep(
#     "^ltdr_avhrr_ndvi",
#     names(lsoa_sf),
#     value = TRUE
# )
#
# msoa_sf_out <- aggregate_lsoa_to_msoa(
#     lsoa_sf = lsoa_sf,
#     msoa_sf = msoa_sf,
#     msoa_id = "MSOA21CD",
#     sum_vars = c(
#         "population",
#         "cancer_cases",
#         "deaths"
#     ),
#     cont_vars = c(
#         "imd_score",
#         "pm25",
#         ndvi_cols
#     ),
#     cat_vars = c(
#         "urban_rural",
#         "ethnicity_group"
#     )
# )
#
# Example: aggregate all NDVI years to MSOA
#
# ndvi_cols <- grep(
#     "^ltdr_avhrr_ndvi",
#     names(lsoa_sf),
#     value = TRUE
# )
#
# msoa_ndvi <- aggregate_lsoa_to_msoa(
#     lsoa_sf = lsoa_sf,
#     msoa_sf = msoa_sf,
#     msoa_id = "MSOA21CD",
#     cont_vars = ndvi_cols
# )
###############################################################################

aggregate_lsoa_to_msoa <- function(
    lsoa_sf,
    msoa_sf,
    msoa_id = "MSOA21CD",
    sum_vars = NULL,
    cont_vars = NULL,
    cat_vars = NULL
) {
  
  library(sf)
  library(dplyr)
  
  if (st_crs(lsoa_sf) != st_crs(msoa_sf)) {
    msoa_sf <- st_transform(msoa_sf, st_crs(lsoa_sf))
  }
  
  inter <- st_intersection(
    lsoa_sf,
    msoa_sf[, msoa_id]
  )
  
  inter$int_area <- as.numeric(st_area(inter))
  
  result <- inter %>%
    st_drop_geometry() %>%
    group_by(.data[[msoa_id]]) %>%
    summarise(
      across(
        all_of(sum_vars),
        ~ sum(.x, na.rm = TRUE)
      ),
      .groups = "drop"
    )
  
  if (!is.null(cont_vars)) {
    
    cont_res <- inter %>%
      st_drop_geometry() %>%
      group_by(.data[[msoa_id]]) %>%
      summarise(
        across(
          all_of(cont_vars),
          ~ weighted.mean(
            .x,
            w = int_area,
            na.rm = TRUE
          )
        ),
        .groups = "drop"
      )
    
    result <- left_join(
      result,
      cont_res,
      by = msoa_id
    )
  }
  
  if (!is.null(cat_vars)) {
    
    dominant_class <- function(x, w) {
      
      tmp <- data.frame(x, w) %>%
        group_by(x) %>%
        summarise(
          w = sum(w, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        arrange(desc(w))
      
      tmp$x[1]
    }
    
    for (v in cat_vars) {
      
      cat_res <- inter %>%
        st_drop_geometry() %>%
        group_by(.data[[msoa_id]]) %>%
        summarise(
          value = dominant_class(
            .data[[v]],
            int_area
          ),
          .groups = "drop"
        )
      
      names(cat_res)[2] <- v
      
      result <- left_join(
        result,
        cat_res,
        by = msoa_id
      )
    }
  }
  
  left_join(
    msoa_sf,
    result,
    by = msoa_id
  )
}