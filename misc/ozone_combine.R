library(sf)
library(dplyr)
library(here)

out_dir <- here::here("ozone_lsoa_yearly")
gpkg_files <- sort(list.files(out_dir, pattern = "\\.gpkg$", full.names = TRUE))

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

st_write(
  ozone_all,
  file.path(out_dir, "ozone_lsoa_all_years.gpkg"),
  delete_dsn = TRUE,
  quiet = FALSE
)
