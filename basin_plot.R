library(dplyr)
library(stars)
library(sf)
library(fmesher)
library(INLA)
library(inlabru)
library(here)
library(ggplot2)
library(terra)
library(tidyterra)
library(future)
library(patchwork)

CV_chess <- FALSE; CV_thin <- FALSE
# https://github.com/riatelab/maptiles
# get_providers()
source("read_data.R")

basin <- rast(here("data", "lsdtt", fdr, "cop30dem_AllBasins.bil")) %>%
  project(crs_nepal$input)

tile <- maptiles::get_tiles(st_as_sfc(bnd_out), provider = "Esri.WorldImagery", crop = TRUE, zoom = 13) 

basin_zm <- basin %>% filter(cop30dem_AllBasins == c(14982, 2228, 15329, 17757, 22048))
basin_zm_sf <- as_sf(as.polygons(basin_zm))

basin_zm_sf$cop30dem_AllBasins <- as.character(basin_zm_sf$cop30dem_AllBasins)

ggplot() +
  geom_spatraster_rgb(data = tile) + 
  geom_sf(data = bnd, fill = NA, colour = "red", linewidth = 0.4) +
  geom_sf(
    data = basin_zm_sf,
    aes(fill = factor(cop30dem_AllBasins)),
    colour = NA
  ) +
  geom_sf(data = bnd, fill = NA, colour = "red", linewidth = 0.4) +
  scale_fill_brewer(palette = "Set3", name = "Basin index") +
  ggspatial::annotation_scale(location = "br") +
  ggspatial::annotation_north_arrow(
    location = "br",
    which_north = "true",
    pad_x = unit(0.0, "in"),
    pad_y = unit(0.3, "in")
  )

# ggplot() +
#   geom_sf(
#     data = basin_zm_sf,
#     aes(fill = factor(cop30dem_AllBasins)),
#     colour = NA
#   ) +
#   scale_fill_viridis_d(name = "Basin index", option = "turbo")

ggsave("basin_selected.png", width = 9, height = 6, dpi = 150)