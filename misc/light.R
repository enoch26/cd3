out_dir <- "data/nightlight_gb"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

out_file <- list.files(out_dir, pattern = "^ntl_.*_gb\\.tif$", full.names = TRUE)
# out_file <- file.path(out_dir, paste0("ntl_", nm, "_gb.tif"))
  
if (any(file.exists(out_file))) {
  # read it if already written
  light <- lapply(out_file, rast)
  names(light) <- sub(".*ntl_(\\d{4})_gb\\.tif$", "\\1", out_file)
  gb_v <- as_spatvector(st_transform(gb_buffer, crs(light[[1]])))
} else {
  # read file ---------------------------------------------------------------
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
  
  lights_all <- c(lights, lights_)
  gb_v <- as_spatvector(st_transform(gb_buffer, crs(lights_all[[1]])))
  
  light <- lapply(lights_all, function(r) {
    mask(crop(r, gb_v), gb_v)
  })
  
  if(FALSE){
# FOR SOME REASON, EXT NOT THE SAME FOR 2009 2010 2011
    # light is a list of SpatRaster
    ext_list <- lapply(light, ext)
    
    # Compare each extent to the first one
    same_ext <- vapply(ext_list, function(e) all(as.vector(e) == as.vector(ext_list[[1]])),
                       logical(1))
    
    table(same_ext)
    which(!same_ext)          # indices that differ (if any)
    names(light)[!same_ext]   # names/years that differ
    ext_list[!same_ext]       # print the differing extents
    
  }
  
  for (nm in names(light)) {
    
    out_file <- file.path(out_dir, paste0("ntl_", nm, "_gb.tif"))
    
    if (file.exists(out_file)) {
      message("Skipping (already exists): ", out_file)
      next
    }
    
    writeRaster(light[[nm]], out_file, overwrite = TRUE, filetype = "GTiff")
    
    message("Wrote: ", out_file)
  }
}

for (nm in names(light)) {
  out_dir <- "outputs/nightlight_gb/"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  p <- ggplot() +
    geom_spatraster(data = light[[nm]] %>% mask(gb_v)) +
    geom_sf(data = gb, fill = NA, linewidth = 0.2, colour = "white") +
    scale_fill_viridis_c(name = "Digital Numbers (DN)", na.value = "transparent") +
    coord_sf() +
    labs(title = paste("Night lights", nm)) +
    theme_minimal()
  
  ggsave(filename = file.path(out_dir, paste0("ntl_", nm, ".png")),
         plot = p, width = 6, height = 5, dpi = 300)
}

# multiplot ---------------------------------------------------------------

baseline_year <- "1992"
base <- light[[baseline_year]]

light_aligned <- lapply(light, function(r) terra::resample(r, base, method = "bilinear"))
light_diff <- lapply(light_aligned, \(r) r - base)
names(light_diff) <- names(light)

yrs_show <- as.character(c(seq(1993, 2023, by = 5), 2024))
yrs_show <- intersect(yrs_show, names(light_diff))

# symmetric limits around 0 for comparable panels
mx <- max(abs(unlist(lapply(light_diff[yrs_show], function(r) {
  terra::global(r, "max", na.rm = TRUE)[1,1]
}))), na.rm = TRUE)

plots <- lapply(yrs_show, function(nm) {
  ggplot() +
    geom_spatraster(data = light_diff[[nm]]) +
    geom_sf(data = gb, fill = NA, linewidth = 0.2, colour = "white") +
    scale_fill_gradient2(
      name = "DN change\n(vs 1992)",
      low = "#2b8cbe", mid = "white", high = "#d7301f",
      midpoint = 0, limits = c(-mx, mx),
      na.value = "transparent"
    ) +
    coord_sf() +
    labs(title = nm) 
    # theme_minimal() 
    # theme(legend.position = "none")
})

p_all <- wrap_plots(plots, ncol = 4, guides = "collect") + 
  plot_annotation(title = "Night-time lights change relative to 1992 (DN)")

ggsave("outputs/nightlight_gb/ntl_diff_vs_1992.png",
       p_all, width = 12, height = 9, dpi = 300)

# example -----------------------------------------------------------------



# Example: access 1992 raster
# light_1992 <- lights[["1992"]]
# 
# # Example: stack into a multi-layer SpatRaster (one layer per year)
# light_stack <- rast(lights)
# names(light_stack) <- paste0("ntl_", years)