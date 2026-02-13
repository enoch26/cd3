# https://humaniverse.github.io/geographr/

libs_name <- c("INLA", "inlabru", "sf", "terra", "here", "tidyterra", "ggplot2","readxl")

lapply(libs_name, require, character.only = TRUE)

# source("./functions.R")
# Read data
root_dir <- here() 


# JAXA --------------------------------------------------------------------

if(FALSE){
  tif_files <- list.files(
    root_dir,
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
}

# Pesticide ---------------------------------------------------------------

# All GeoTIFFs
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


# metal -------------------------------------------------------------------

# metal <- read.csv("./data/metal/def15f47-6aba-43db-a833-5844628a658b/data/CS1998_SOIL_METALS.csv")

# https://www.bgs.ac.uk/datasets/uk-topsoil-geochemistry/#grids
# IARC Group 1 / high-priority (as represented by total element rasters)
arsenic  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/As_v1.tif"))
cadmium  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Cd_v1.tif"))
chromium <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Cr_v1.tif"))  # total Cr (not Cr(VI) speciation)
nickel   <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Ni_v1.tif"))  # total Ni (speciation varies)
thorium  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Th_v1.tif"))
uranium  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/U_v1.tif"))

# Possibly/Probably carcinogenic (IARC Group 2A/2B depending on compound)
lead     <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Pb_v1.tif"))
cobalt   <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Co_v1.tif"))
antimony <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Sb_v1.tif"))
vanadium <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/V_v1.tif"))
tungsten <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/W_v1.tif"))

# Generally not classed as carcinogenic as elements in typical environmental forms
bromine  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Br_v1.tif"))
iodine   <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/I_v1.tif"))
selenium <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Se_v1.tif"))

library(ggplot2)
library(tidyterra)
library(viridis)
library(scales)

# Named list of rasters
rasters <- list(
  As = arsenic,
  Cd = cadmium,
  Cr = chromium,
  Ni = nickel,
  Th = thorium,
  U  = uranium,
  
  Pb = lead,
  Co = cobalt,
  Sb = antimony,
  V  = vanadium,
  W  = tungsten,
  
  Br = bromine,
  I  = iodine,
  Se = selenium
)

# Units: all of these are mg/kg in your table
units <- c(
  As="mg/kg", Cd="mg/kg", Cr="mg/kg", Ni="mg/kg", Th="mg/kg", U="mg/kg",
  Pb="mg/kg", Co="mg/kg", Sb="mg/kg", V="mg/kg", W="mg/kg",
  Br="mg/kg", I="mg/kg", Se="mg/kg"
)

out_dir <- here::here("./outputs/topsoil_maps")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

for (code in names(rasters)) {
  p <- make_map(rasters[[code]], code, units[[code]])
  ggsave(
    filename = file.path(out_dir, paste0("topsoil_", code, ".png")),
    plot = p,
    width = 7, height = 7, dpi = 300
  )
}




# radon -------------------------------------------------------------------
# https://maps-bgs.opendata.arcgis.com/datasets/bgs::radon-indicative-atlas/about
# CLASS
# https://services3.arcgis.com/7bJVHfju2RXdGZa4/arcgis/rest/services/Radon_Indicative_Atlas_v3/FeatureServer/0
radon <- read_sf("./data/Radon_Indicative_Atlas/Radon_Indicative_Atlas.shp")
radon <- read_sf("./data/Radon_indicative_atlas_GB_v3_ESRI/Radon_Indicative_Atlas_v3.shp")


# gamma -------------------------------------------------------------------

# https://www.data.gov.uk/dataset/568e58c0-6404-4a8a-9654-4440245fb6e4/ambient-gamma-radiation-dose-rates-across-the-uk
# https://webarchive.nationalarchives.gov.uk/ukgwa/20130103015143/http://www.decc.gov.uk/en/content/cms/statistics/rimnet/rimnet.aspx#

# ONS ---------------------------------------------------------------------


# https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/lowersuperoutputareamidyearpopulationestimatesnationalstatistics

