# https://humaniverse.github.io/geographr/

libs_name <- c("INLA", "inlabru", "sf", "terra", "here", "tidyterra", "ggplot2", 
               "readxl", "viridis", "scales", "dplyr", "future")

lapply(libs_name, require, character.only = TRUE)

# source("./functions.R")
# Read data
root_dir <- here() 

# gb shapefile ------------------------------------------------------------
# https://www.data.gov.uk/dataset/2e17269d-10b9-4e43-b67b-57f9b02bd0f8/countries-december-2021-boundaries-uk-buc
gb %<-% {st_read("./data/Countries_December_2021_UK_BUC_2022_6943641446890634176/CTRY_DEC_2021_UK_BUC.shp")}

# landcover ---------------------------------------------------------------
# https://catalogue.ceh.ac.uk/eidc/documents seach land cover map 
base <- "./data/ukceh/lcm"

# 1) folders to use: start with lcm- and do NOT contain "-ni_"
dirs <- list.dirs(base, recursive = FALSE, full.names = TRUE)
dirs <- dirs[grepl("^lcm-", basename(dirs)) & !grepl("-ni_", basename(dirs))]

# 2) find the tif in each folder (adjust pattern if you want stricter matching)
tifs <- list.files(dirs, pattern = "\\.tif$", full.names =TRUE)

# keep only ones that actually exist (safety)
tifs <- tifs[file.exists(tifs)]

# 3) read into a named list (names = year)
years <- sub("^lcm-(\\d{4})-.*$", "\\1", basename(dirname(tifs)))
rasters <- setNames(lapply(tifs[1:3], \(f) rast(f, lyrs = 1)), years[1:3]) # 1900 2000 and 2007 has 23

e <- ext(50000, 660000, 10000, 1220000)

rasters_crop <- lapply(rasters, crop, y = e)

# 1900 2000 and 2007 has 23 classes

for (yr in names(rasters_crop)) {
  p <- ggplot() +
    geom_spatraster(data = rasters_crop[[yr]]) +
    labs(title = paste("LCM", yr)) +
    # coord_equal() +
    theme_minimal()
  
  ggsave(file.path("outputs", paste0("lcm_", yr, ".png")), p, width = 7, height = 4, dpi = 200)
}

# 4) convert each raster to categorical (factor-like)
rasters_fac <- lapply(rasters_crop, as.factor)

for (yr in names(rasters_fac)) {
  p <- ggplot() +
    geom_spatraster(data = rasters_fac[[yr]]) +
    labs(title = paste("LCM", yr)) +
    # coord_equal() +
    theme_minimal()
  
  ggsave(file.path("outputs", paste0("lcm_", yr, ".png")), p, width = 7, height = 4, dpi = 200)
}


# doesnt seem sth im looking for
r %<-% {rast("./data/ukceh/lcm/lcm-2024-25m_6230369/gblcm2024_25m.tif")}
r1 <- lcm2024$gblcm2024_25m_1
lcm2024$lcm_class <- as.factor(values(r1))


ggplot() +
  geom_spatraster(data = r$lcm_class) +
  scale_fill_viridis_c(name = "Land Cover Class", na.value = "transparent") +
  theme_minimal() +
  theme(panel.grid = element_blank())
        ggsave("./outputs/lcm2024_map.pdf", width = 8, height = 6)
        ggsave("./outputs/lcm2024_map.png", width = 8, height = 6, dpi = 300)
        

# brownfield --------------------------------------------------------------

        # https://www.planning.data.gov.uk/dataset/brownfield-land
        
brownfield <- st_read("./data/brownfield/brownfield-land.geojson") %>% st_transform(st_crs(gb))
        
ggplot() + geom_sf(data = gb, fill = "white", color = "grey80") +
  geom_sf(data = brownfield, size = 0.01) +
  scale_color_viridis_c(name = "Brownfield sites (2018)", na.value = "transparent") +
  theme_minimal() +
  theme(panel.grid = element_blank())

ggsave("./outputs/brownfield_sites.pdf", width = 8, height = 6)
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
pesticide_dir <- here("data/ukceh/Land-Cover-plus-Pesticides_6248559/") 

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
# antimony <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Sb_v1.tif"))
# vanadium <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/V_v1.tif"))
# tungsten <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/W_v1.tif"))

# Generally not classed as carcinogenic as elements in typical environmental forms
# bromine  <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Br_v1.tif"))
# iodine   <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/I_v1.tif"))
# selenium <- rast(here("./data/metal/BGS/UK Topsoil geochemistry/Se_v1.tif"))



# Named list of rasters
rasters <- list(
  As = arsenic,
  Cd = cadmium,
  Cr = chromium,
  Ni = nickel,
  Th = thorium,
  U  = uranium,
  
  Pb = lead,
  Co = cobalt
  # Sb = antimony,
  # V  = vanadium,
  # W  = tungsten,
  
  # Br = bromine,
  # I  = iodine,
  # Se = selenium
)

# Units: all of these are mg/kg in your table
units <- c(
  As="mg/kg", Cd="mg/kg", Cr="mg/kg", Ni="mg/kg", Th="mg/kg", U="mg/kg",
  Pb="mg/kg", Co="mg/kg"
  # Sb="mg/kg", V="mg/kg", W="mg/kg",
  # Br="mg/kg", I="mg/kg", Se="mg/kg"
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


# landfill ----------------------------------------------------------------
# https://www.data.gov.uk/dataset/17edf94f-6de3-4034-b66b-004ebd0dd010/historic-landfill-sites1
landfill <- st_read("./data/Historic_Landfill_Sites.shp/Historic_Landfill_Sites.shp")

landfill_ <-landfill %>%
  rowwise() %>%
  mutate(
    waste_types = {
      x <- c_across(c(industrial, commercial, household))
      labs <- c("Industrial", "Commercial", "Household")
      out <- paste(labs[!is.na(x) & x == "Yes"], collapse = ", ")
      ifelse(out == "", "None", out)
    }
  ) %>%
  ungroup()

ggplot() + 
  geom_sf(data=st_geometry(gb), fill = "white", color = "grey80") +
  geom_sf(data = landfill_, aes(color = waste_types, fill = waste_types)) +
  theme_minimal() +
  theme(panel.grid = element_blank())
ggsave("./outputs/landfill_sites.pdf", width = 8, height = 6)
ggsave("./outputs/landfill_sites.png", width = 8, height = 6, dpi = 300)





# radon -------------------------------------------------------------------
# https://maps-bgs.opendata.arcgis.com/datasets/bgs::radon-indicative-atlas/about
# CLASS
# https://services3.arcgis.com/7bJVHfju2RXdGZa4/arcgis/rest/services/Radon_Indicative_Atlas_v3/FeatureServer/0
out_dir <- here::here("./outputs/radon/")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
# radon_ <- read_sf("./data/Radon_indicative_atlas_GB_v3_ESRI/Radon_Indicative_Atlas_v3.shp")
radon <- read_sf("./data/Radon_Indicative_Atlas/Radon_Indicative_Atlas.shp")
radon$CLASS_MAX <- as.factor(radon$CLASS_MAX)

radon <- radon %>% dplyr::mutate(
  CLASS_MAX_ = factor(
    CLASS_MAX,
    levels = c("1","2","3","4","5","6"),
    labels = c("0–1","1–3","3–5","5–10","10–30","≥30"),
    ordered = TRUE
  )
)

ggplot() + geom_sf(data = radon, aes(fill = CLASS_MAX_, color = CLASS_MAX_)) +
  scale_color_brewer(palette = "YlGn", direction = 1, drop = FALSE, name = "RnP") +
  scale_fill_brewer(palette = "YlGn", direction = 1, drop = FALSE, name = "RnP")
  # ggplot() + geom_spatraster(data = radon, aes(fill = CLASS_MAX))
  ggsave(paste0(out_dir, "radon_atlas.pdf"), width = 8, height = 6)
  ggsave(paste0(out_dir, "radon_atlas.png"), width = 8, height = 6, dpi = 300)



# gamma -------------------------------------------------------------------

# https://www.data.gov.uk/dataset/568e58c0-6404-4a8a-9654-4440245fb6e4/ambient-gamma-radiation-dose-rates-across-the-uk
# https://webarchive.nationalarchives.gov.uk/ukgwa/20130103015143/http://www.decc.gov.uk/en/content/cms/statistics/rimnet/rimnet.aspx#

# ONS ---------------------------------------------------------------------


# https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/lowersuperoutputareamidyearpopulationestimatesnationalstatistics

