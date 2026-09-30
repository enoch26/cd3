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
  
  result <- inter %>%
    st_drop_geometry() %>%
    group_by(.data[[msoa_id]]) %>%
    summarise(
      .groups = "drop"
    )
  
  if (!is.null(sum_vars) && length(sum_vars) > 0) {
    sum_res <- inter %>%
      st_drop_geometry() %>%
      group_by(.data[[msoa_id]]) %>%
      summarise(
        across(
          all_of(sum_vars),
          ~ sum(.x, na.rm = TRUE)
        ),
        .groups = "drop"
      )
    
    result <- left_join(
      result,
      sum_res,
      by = msoa_id
    )
  }
  
  if (!is.null(copy_vars) && length(copy_vars) > 0) {
    copy_res <- inter %>%
      st_drop_geometry() %>%
      group_by(.data[[msoa_id]]) %>%
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
    
    result <- left_join(
      result,
      copy_res,
      by = msoa_id
    )
  }
  
  if (!is.null(cont_vars) && length(cont_vars) > 0) {
    cont_res <- inter %>%
      st_drop_geometry() %>%
      group_by(.data[[msoa_id]]) %>%
      summarise(
        across(
          all_of(cont_vars),
          ~ weighted.mean(.x, w = int_area, na.rm = TRUE)
        ),
        .groups = "drop"
      )
    
    result <- left_join(
      result,
      cont_res,
      by = msoa_id
    )
  }
  
  if (!is.null(cat_vars) && length(cat_vars) > 0) {
    
    dominant_class <- function(x, w) {
      tmp <- data.frame(x = x, w = w) %>%
        filter(!is.na(x)) %>%
        group_by(x) %>%
        summarise(
          w = sum(w, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        arrange(desc(w))
      
      if (nrow(tmp) == 0) {
        return(NA)
      }
      
      tmp$x[1]
    }
    
    for (v in cat_vars) {
      cat_res <- inter %>%
        st_drop_geometry() %>%
        group_by(.data[[msoa_id]]) %>%
        summarise(
          value = dominant_class(.data[[v]], int_area),
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
