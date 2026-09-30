library(sf)
library(dplyr)
library(here)

out_dir <- here::here("ozone_lsoa_yearly")

gpkg_files <- sort(list.files(
  out_dir,
  pattern = "^ozone_lsoa_eng_[0-9]{4}\\.gpkg$",
  full.names = TRUE
))

id_col <- "LSOA21CD"

sf_list <- lapply(gpkg_files, function(f) {
  x <- st_read(f, quiet = TRUE)
  
  if (!id_col %in% names(x)) {
    stop("ID column not found in: ", f)
  }
  
  ozone_col <- grep("^ozone\\d{4}$", names(x), value = TRUE)
  
  if (length(ozone_col) != 1) {
    stop("Expected exactly one ozone column in: ", f)
  }
  
  x[, c(id_col, ozone_col, attr(x, "sf_column"))]
})

ozone_all <- sf_list[[1]]

for (i in 2:length(sf_list)) {
  ozone_all <- ozone_all %>%
    left_join(
      st_drop_geometry(sf_list[[i]]),
      by = id_col
    )
}

fill_na_nearest <- function(sf_obj, value_col) {
  vals <- sf_obj[[value_col]]
  miss <- is.na(vals)
  
  if (!any(miss)) {
    message(value_col, ": no NA values")
    return(sf_obj)
  }
  
  if (all(miss)) {
    warning(value_col, ": all values are NA; cannot fill")
    return(sf_obj)
  }
  
  cent_all <- st_centroid(sf_obj)
  cent_miss <- cent_all[miss, ]
  cent_ok   <- cent_all[!miss, ]
  
  nn <- st_nearest_feature(cent_miss, cent_ok)
  
  vals[miss] <- vals[!miss][nn]
  sf_obj[[value_col]] <- vals
  
  message(value_col, ": filled ", sum(miss), " NA values")
  sf_obj
}

ozone_cols <- grep("^ozone\\d{4}$", names(ozone_all), value = TRUE)

for (col in ozone_cols) {
  ozone_all <- fill_na_nearest(ozone_all, col)
}

st_write(
  ozone_all,
  file.path(out_dir, "ozone_lsoa_all_years_filled.gpkg"),
  delete_dsn = TRUE,
  quiet = FALSE
)
