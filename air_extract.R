# LSOA-level annual air-pollution concentrations ---------------------------------
#
# Purpose:
#   Extract area-weighted mean values from annual DEFRA PCM rasters to 2021
#   English Lower-layer Super Output Areas (LSOAs), then save the enriched
#   boundary layer as a GeoPackage.
#
# Data source:
#   https://uk-air.defra.gov.uk/data/pcm-data
#
# Expected project structure:
#   <project-root>/
#   ├── lsoa11221.R                     # Creates `poly_lsoa_21` as an sf object
#   ├── ozone.R                          # Optional project-specific preparation code
#   └── data/
#       └── defra/
#           ├── benzene/geotiff_overlap/benzene_2003_overlap.tif
#           ├── pm25/geotiff_overlap/pm25_2003_overlap.tif
#           ├── pm10/geotiff_overlap/pm10_2003_overlap.tif
#           └── nox/geotiff_overlap/nox_2003_overlap.tif
#
# Each raster is expected to have one layer and to be named:
#   <pollutant>_<year>_overlap.tif
#
# The output columns use names such as `benzene2003`, `pm252010`, and `nox2024`.

# Packages -----------------------------------------------------------------
library(terra)
library(sf)
library(here)

# Load project-specific geography setup ------------------------------------
# This file must create `poly_lsoa_21`: an `sf` object containing 2021 English
# LSOA polygons. Its coordinate reference system should be appropriate for the
# raster data, or it will be transformed below.
source(here::here("lsoa11221.R"))

# Retain this only if it performs setup required elsewhere in your project.
# It is not otherwise used directly in this extraction workflow.
if (file.exists(here::here("ozone.R"))) {
  source(here::here("ozone.R"))
}

if (!exists("poly_lsoa_21") || !inherits(poly_lsoa_21, "sf")) {
  stop("`lsoa11221.R` must create `poly_lsoa_21` as an sf object.")
}

# Configuration ------------------------------------------------------------
data_dir <- here::here("data")
output_file <- here::here("air_lsoa_eng.gpkg")

pollutants <- c("benzene", "pm25", "pm10", "nox")
years <- 2003:2024

# Construct and validate the expected raster path for one pollutant-year.
raster_path <- function(pollutant, year, data_directory = data_dir) {
  path <- file.path(
    data_directory,
    "defra",
    pollutant,
    "geotiff_overlap",
    sprintf("%s_%d_overlap.tif", pollutant, year)
  )
  
  if (!file.exists(path)) {
    stop("Raster not found: ", path, call. = FALSE)
  }
  
  path
}

# Extract a polygon-level, coverage-weighted mean from a one-layer raster.
# `weights = TRUE` assigns fractional weights to raster cells intersecting an
# LSOA boundary. `na.rm = TRUE` ignores missing raster values.
extract_lsoa_mean <- function(raster_file, lsoa_polygons) {
  raster <- terra::rast(raster_file)
  
  if (terra::nlyr(raster) != 1L) {
    stop("Expected a single-layer raster: ", raster_file, call. = FALSE)
  }
  
  # terra::extract requires matching coordinate reference systems.
  lsoa_vector <- terra::vect(lsoa_polygons)
  if (!terra::same.crs(raster, lsoa_vector)) {
    lsoa_vector <- terra::project(lsoa_vector, terra::crs(raster))
  }
  
  values <- terra::extract(
    raster,
    lsoa_vector,
    fun = mean,
    na.rm = TRUE,
    weights = TRUE,
    ID = FALSE
  )
  
  values[[1L]]
}

# Extract every pollutant-year combination --------------------------------
# Values are appended to the original `sf` layer so that LSOA identifiers and
# attributes supplied by `lsoa11221.R` are preserved.
for (pollutant in pollutants) {
  for (year in years) {
    message("Extracting ", pollutant, " for ", year, " ...")
    
    column_name <- paste0(pollutant, year)
    poly_lsoa_21[[column_name]] <- extract_lsoa_mean(
      raster_file = raster_path(pollutant, year),
      lsoa_polygons = poly_lsoa_21
    )
  }
}

# Write output -------------------------------------------------------------
# `delete_dsn = TRUE` replaces an existing GeoPackage at this path. Change it
# to FALSE, or provide a versioned output filename, if the existing file must
# be retained.
sf::st_write(
  poly_lsoa_21,
  dsn = output_file,
  layer = "air_lsoa_eng",
  delete_dsn = TRUE,
  quiet = FALSE
)

# Optional raster maps -----------------------------------------------------
# Set to TRUE to plot all four pollutants for a selected year. These maps show
# raster values rather than LSOA-level extracted values.
make_maps <- FALSE
plot_year <- 2010L

if (make_maps) {
  if (!requireNamespace("ggplot2", quietly = TRUE) ||
      !requireNamespace("tidyterra", quietly = TRUE) ||
      !requireNamespace("viridis", quietly = TRUE)) {
    stop(
      "Install ggplot2, tidyterra, and viridis to create maps.",
      call. = FALSE
    )
  }
  
  for (pollutant in pollutants) {
    raster <- terra::rast(raster_path(pollutant, plot_year))
    
    print(
      ggplot2::ggplot() +
        tidyterra::geom_spatraster(data = raster) +
        viridis::scale_fill_viridis_c(na.value = "transparent") +
        ggplot2::labs(
          title = sprintf("%s concentration in %d", pollutant, plot_year),
          fill = pollutant
        ) +
        ggplot2::theme_minimal()
    )
  }
}
