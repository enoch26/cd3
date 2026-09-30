# LSOA-to-MSOA spatial aggregation helper ------------------------------------
#
# This file contains a reusable helper for aggregating attributes attached to
# LSOA polygons to MSOA polygons. It is intended for use with `sf` objects.

#' Aggregate LSOA attributes to MSOA geography
#'
#' Intersects LSOA and MSOA polygons, then produces MSOA-level attributes using
#' a method appropriate to each variable type. Count variables are summed,
#' continuous variables are area-weighted means, categorical variables are the
#' dominant class by intersected area, and copied variables are retained only
#' where their non-missing value is consistent within an MSOA.
#'
#' @param lsoa_sf An `sf` object containing LSOA geometries and the attributes
#'   to aggregate.
#' @param msoa_sf An `sf` object containing MSOA geometries.
#' @param msoa_id Character scalar naming the MSOA identifier in `msoa_sf`.
#'   Defaults to `"MSOA21CD"`.
#' @param sum_vars Optional character vector of numeric count or total columns
#'   in `lsoa_sf` to sum within each MSOA.
#' @param cont_vars Optional character vector of numeric continuous columns in
#'   `lsoa_sf` to aggregate as area-weighted means.
#' @param cat_vars Optional character vector of categorical columns in
#'   `lsoa_sf`; the class covering the greatest intersected area is returned.
#' @param copy_vars Optional character vector of columns in `lsoa_sf` to copy
#'   only if there is one distinct non-missing value within an MSOA. Otherwise
#'   the result is missing.
#'
#' @details
#' The inputs are transformed to a common coordinate reference system before
#' intersection. Use a projected CRS with metre-based units for meaningful area
#' weighting.
#'
#' `sum_vars` are summed as supplied. This is appropriate when every LSOA falls
#' wholly within one MSOA, as is normally true for matched official geography
#' vintages. If LSOA boundaries cross MSOA boundaries, values are repeated in
#' every intersected fragment and may be double counted; use explicit
#' area-weighted allocation before summing in that case.
#'
#' @return An `sf` object based on `msoa_sf`, with the requested aggregate
#'   variables joined by `msoa_id`. MSOAs without intersecting LSOAs are kept.
#'
#' @examples
#' \dontrun{
#' msoa_with_population <- aggregate_lsoa_to_msoa(
#'   lsoa_sf = lsoa_population_sf,
#'   msoa_sf = msoa_2021_sf,
#'   sum_vars = c("total_population", "female_population"),
#'   cont_vars = "smoking_prevalence",
#'   cat_vars = "rural_urban_classification",
#'   copy_vars = "region_name"
#' )
#' }
#'
#' @export
aggregate_lsoa_to_msoa <- function(
    lsoa_sf,
    msoa_sf,
    msoa_id = "MSOA21CD",
    sum_vars = NULL,
    cont_vars = NULL,
    cat_vars = NULL,
    copy_vars = NULL
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
  
  result <- inter |>
    st_drop_geometry() |>
    group_by(.data[[msoa_id]]) |>
    summarise(.groups = "drop")
  
  if (!is.null(sum_vars) && length(sum_vars) > 0) {
    sum_res <- inter |>
      st_drop_geometry() |>
      group_by(.data[[msoa_id]]) |>
      summarise(
        across(all_of(sum_vars), ~ sum(.x, na.rm = TRUE)),
        .groups = "drop"
      )
    
    result <- left_join(result, sum_res, by = msoa_id)
  }
  
  if (!is.null(copy_vars) && length(copy_vars) > 0) {
    copy_res <- inter |>
      st_drop_geometry() |>
      group_by(.data[[msoa_id]]) |>
      summarise(
        across(
          all_of(copy_vars),
          ~ {
            if (dplyr::n_distinct(.x, na.rm = TRUE) == 1) {
              dplyr::first(.x)
            } else {
              .x[NA_integer_]
            }
          }
        ),
        .groups = "drop"
      )
    
    result <- left_join(result, copy_res, by = msoa_id)
  }
  
  if (!is.null(cont_vars) && length(cont_vars) > 0) {
    cont_res <- inter |>
      st_drop_geometry() |>
      group_by(.data[[msoa_id]]) |>
      summarise(
        across(all_of(cont_vars), ~ weighted.mean(.x, w = int_area, na.rm = TRUE)),
        .groups = "drop"
      )
    
    result <- left_join(result, cont_res, by = msoa_id)
  }
  
  if (!is.null(cat_vars) && length(cat_vars) > 0) {
    dominant_class <- function(x, w) {
      tmp <- data.frame(x = x, w = w) |>
        filter(!is.na(x)) |>
        group_by(x) |>
        summarise(w = sum(w, na.rm = TRUE), .groups = "drop") |>
        arrange(desc(w))
      
      if (nrow(tmp) == 0) return(NA)
      tmp$x[1]
    }
    
    for (v in cat_vars) {
      cat_res <- inter |>
        st_drop_geometry() |>
        group_by(.data[[msoa_id]]) |>
        summarise(value = dominant_class(.data[[v]], int_area), .groups = "drop")
      
      names(cat_res)[2] <- v
      result <- left_join(result, cat_res, by = msoa_id)
    }
  }
  
  left_join(msoa_sf, result, by = msoa_id)
}
