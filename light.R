

years <- 1992:2013

lights <- setNames(
  lapply(years, function(y) {
    f <- sprintf("./data/9828827/Harmonized_DN_NTL_%d_calDMSP.tif", y)
    rast(f)
  }),
  years
)

years <- 2014:2024
lights_ <- setNames(
  lapply(years, function(y) {
    f <- sprintf("./data/9828827/Harmonized_DN_NTL_%d_simVIIRS.tif", y)
    rast(f)
  }),
  years
)




# crop and mask -----------------------------------------------------------

gb_union <- st_union(gb)

lights_all <- c(lights, lights_)
gb_v <- as_spatvector(st_transform(gb_union, crs(lights_all[[1]])))

light <- lapply(lights, function(r) {
  mask(crop(r, gb_v), gb_v)
})

for (nm in names(light)) {
  p <- ggplot() +
    geom_spatraster(data = light[[nm]]) +
    geom_sf(data = gb, fill = NA, linewidth = 0.2, colour = "white") +
    scale_fill_viridis_c(name = "Digital Numbers (DN)", na.value = "transparent") +
    coord_sf() +
    labs(title = paste("Night lights", nm)) +
    theme_minimal()
  
  ggsave(filename = file.path("outputs", paste0("ntl_", nm, ".png")),
         plot = p, width = 6, height = 5, dpi = 300)
}

# # 1) Make sure gb is in the same CRS as the raster
# gb_raster_crs <- st_transform(gb, crs(light))
# 
# # 2) Convert sf -> terra vector
# gb_v <- vect(gb_raster_crs)
# 
# # 3) Crop to bounding box of gb (fast)
# light_crop <- crop(light, gb_v)
# 
# # 4) Mask to the exact gb boundary (optional but typical)
# light_gb <- mask(light_crop, gb_v)

# example -----------------------------------------------------------------



# Example: access 1992 raster
# light_1992 <- lights[["1992"]]
# 
# # Example: stack into a multi-layer SpatRaster (one layer per year)
# light_stack <- rast(lights)
# names(light_stack) <- paste0("ntl_", years)