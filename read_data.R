libs_name <- c("INLA", "inlabru", "sf", "terra", "here", "tidyterra", "ggplot2")

lapply(libs_name, require, character.only = TRUE)

source("functions.R")
# Read data
root_dir <- here() 

# All GeoTIFFs in pesticides
# https://catalogue.ceh.ac.uk/documents/99a2d3a8-1c7d-421e-ac9f-87a2c37bda62
# downloaded from edina
pesticide_dir <- here("data/pesticide/Land-Cover-plus-Pesticides_6248559/") 

# (optional) verify they exist
stopifnot(all(file.exists(tif_files)))

tif_files <- file.path(
  pesticide_dir,
  c("Glyphosate.tif", "Imazalil.tif", "Pendimethalin.tif", "MCPA.tif")
)

for (nm in names(pesticide)) {
  p <- ggplot() +
    geom_spatraster(data = pesticide[[nm]]) +
    ggtitle(nm) +
    scale_fill_viridis_c(name = expression(kg/km^2/yr),   # legend title with km², 
                         na.value = "transparent") +
    theme_minimal()
  
  print(p)
  ggsave(
    filename = file.path(paste0(nm, ".pdf")),
    plot = p,
    device = cairo_pdf,   # good embedded text; requires cairo support
    width = 8, height = 6
  )
}


ggplot() +
  geom_spatraster(data = pesticide_rast) +
  facet_wrap(~lyr, ncol = 2) +
  scale_fill_viridis_c(na.value = "transparent") +
  theme_minimal()

ggplot() +
  tidyterra::geom_spatraster(data = pesticide_rast) +
  facet_wrap(~lyr, ncol = 2) +
  scale_fill_viridis_c(na.value = "transparent") +
  theme_minimal()


tif_files <- list.files(
  pesticide_dir,
  pattern = "\\.tif(f)?$",
  recursive = TRUE,
  full.names = TRUE
)

# All shapefiles
shp_files <- list.files(
  root_dir,
  pattern = "\\.shp$",
  recursive = TRUE,
  full.names = TRUE
)

qdeg_files <- tif_files[grepl("GeoTIFF_Qdeg_monthly_summaries", tif_files)]
qdeg_2021  <- files_for_year(qdeg_files, 2021)

qdeg_rasters_2021 <- rasters[qdeg_2021]

wildrasters <- lapply(tif_files, terra::rast)