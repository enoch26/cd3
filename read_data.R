# https://humaniverse.github.io/geographr/
# https://bristol.libguides.com/maps/map-data
# https://osdatahub.os.uk/data/downloads/open

libs_name <- c(
  "INLA", "inlabru", "sf", "terra", "here", "tidyterra", "ggplot2",
  "readxl", "viridis", "scales", "dplyr", "future", "patchwork"
)

missing_pkgs <- libs_name[!sapply(libs_name, requireNamespace, quietly = TRUE)]

if ("INLA" %in% missing_pkgs) {
  install.packages("INLA",repos=c(getOption("repos"),INLA="https://inla.r-inla-download.org/R/testing"), dep=TRUE)
}


if ("inlabru" %in% missing_pkgs) {
  # Enable universe(s) by inlabru-org
  options(repos = c(
    inlabruorg = "https://inlabru-org.r-universe.dev",
    INLA = "https://inla.r-inla-download.org/R/testing",
    CRAN = "https://cloud.r-project.org"
  ))
  
  # Install some packages
  install.packages("inlabru")}


if ("fmesher" %in% missing_pkgs) {
  # Enable universe(s) by inlabru-org
  options(repos = c(
    inlabruorg = "https://inlabru-org.r-universe.dev",
    getOption("repos")
  ))
  install.packages("fmesher")
}

if (length(missing_pkgs) > 0) {
  install.packages(setdiff(missing_pkgs, c("INLA", "inlabru", "fmesher")))}

# load all libraries
invisible(lapply(libs_name, library, character.only = TRUE))

# source("./functions.R")
# Read data
root_dir <- here() 

# gb shapefile ------------------------------------------------------------
# https://www.data.gov.uk/dataset/2e17269d-10b9-4e43-b67b-57f9b02bd0f8/countries-december-2021-boundaries-uk-buc
# gb %<-% {st_read("./data/Countries_December_2021_UK_BUC_2022_6943641446890634176/CTRY_DEC_2021_UK_BUC.shp")} 
gb <- {st_read("./data/Countries_December_2021_UK_BUC_2022_6943641446890634176/CTRY_DEC_2021_UK_BUC.shp")} 
buffer_len <- .02
gb_buffer <- gb %>%
  st_make_valid() %>%
  st_union() %>%
  fm_nonconvex_hull(convex = -buffer_len)

ggplot(gb_buffer) + geom_sf(fill = "steelblue", colour = "white", linewidth = 0.2) +
  geom_sf(data = gb, fill = NA, colour = "black") + 
  theme_minimal()
ggsave("gb_buffer.pdf")

# Greenspace --------------------------------------------------------------

# https://osdatahub.os.uk/data/downloads/open/OpenGreenspace
# TODO may turn into a distance metrics 
greenspace %<-% {st_read("./data/opgrsp_essh_gb/OS Open Greenspace (ESRI Shape File) GB/data/GB_GreenspaceSite.shp")}

# Check Z feature-by-feature:
if(FALSE){
  has_z <- vapply(seq_len(nrow(greenspace)), function(i) {
    g <- st_geometry(greenspace)[i]
    cc <- tryCatch(st_coordinates(g), error = function(e) NULL)
    !is.null(cc) && "Z" %in% colnames(cc)
  }, logical(1))
  
  which(has_z)        # feature indices that have Z
  table(has_z)
  
  # has_z
  # FALSE   TRUE
  # 8362 157225
  
}

greenspace2 <- st_zm(greenspace, drop = TRUE, what = "ZM")

ggplot() +
  geom_sf(data = gb, fill = "white", color = "grey80")+
  geom_sf(data = greenspace2,
          aes(fill = function., col = function.),
          alpha = .5) +
  scale_fill_viridis_d(name = "function", na.value = "transparent") +
  scale_color_viridis_d(name = "function", na.value = "transparent")


# theme_minimal() +
# theme(panel.grid = element_blank())
ggsave("./outputs/greenspace.pdf", width = 8, height = 6)
ggsave("./outputs/greenspace.png", width = 8, height = 6, dpi = 300)


# blue space --------------------------------------------------------------

# https://www.data.gov.uk/dataset/eb171454-0a52-4d0b-bef9-cc58a99eeff2/blue-space-access-points-in-england
# 3 versions of the dataset are available: 
# Scenario 1 (All blue space): includes all walkable blue spaces that are at least 50 m^2 (0.005 ha) in area or at least 50 m in length.
# Scenario 2 (Substantial blue space): includes walkable blue spaces that are at least 0.5 ha in area and have at least 250 m of walkable waterside route.
# Scenario 3 (Substantial blue space): includes Scenario 2 blue spaces, but excludes those requiring walking along A or B roads to experience them.
# point data
bluespace %<-% {st_read("./data/England_blue_space_access_points.shp/scenario_1.shp")}
ggplot() +
  geom_sf(data = gb, fill = "white", color = "grey80")+
  geom_sf(data = bluespace, size = 0.0001)

# ggsave("./outputs/bluespace.pdf", width = 9, height = 16)
ggsave("./outputs/bluespace.png", width = 9, height = 16, dpi = 300)

bluespace2 %<-% {st_read("./data/England_blue_space_access_points.shp/scenario_2.shp")}
ggplot() +
  geom_sf(data = gb, fill = "white", color = "grey80")+
  geom_sf(data = bluespace2, size = 0.0001)

# ggsave("./outputs/bluespace.pdf", width = 9, height = 16)
ggsave("./outputs/bluespace2.png", width = 9, height = 16, dpi = 300)

bluespace3 %<-% {st_read("./data/England_blue_space_access_points.shp/scenario_3.shp")}
ggplot() +
  geom_sf(data = gb, fill = "white", color = "grey80")+
  geom_sf(data = bluespace2, size = 0.0001)

# ggsave("./outputs/bluespace.pdf", width = 9, height = 16)
ggsave("./outputs/bluespace3.png", width = 9, height = 16, dpi = 300)

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
rasters <- setNames(lapply(tifs[1:3], \(f) rast(f, lyrs = 1)), years[1:3]) # 1900 2000 and 2007 

e <- ext(50000, 660000, 10000, 1220000)

rasters_crop <- lapply(rasters, crop, y = e)

levels(rasters_crop[["1990"]])
# 2000 has 27 classes
levels(rasters_crop[["2000"]])
r <- rasters_crop[["2000"]]
r[r == 0] <- NA
urban_vals <- c(171, 172)

# green_vals <- c(
#   11, 21,              # woodland (broad-leaved/mixed, coniferous)
#   41, 42, 43,          # arable
#   51, 52, 61, 71, 81,  # grasslands
#   91,                  # bracken
#   101, 102,            # heath
#   111, 121,            # fen/bog
#   151                  # montane habitats
#   # optionally include 212 (saltmarsh) as green instead of blue; see note below
# )
# 
# blue_vals <- c(
#   131,
#   212,       # inland water
#   221        # sea/estuary
# )
# 
# # Reclass matrix: from, to, new_value
# # We'll create: 1=Urban, 2=Green, 0=Other (including Unclassified=0)
# m <- rbind(
#   cbind(urban_vals, 1),
#   cbind(green_vals, 2),
#   cbind(blue_vals, 3)
# )

grp <- classify(r, m, others = 0)

# Make it a factor with labels
levels(grp) <- data.frame(ID = c(0, 1), GROUP = c("Non-Urban", "Urban"))
# levels(grp) <- data.frame(ID = c(0, 1, 2, 3), GROUP = c("Other", "Urban", "Green", "Blue"))

ggplot() +
  geom_spatraster(data = grp) +
  labs(title = paste("LCM2000")) +
  scale_fill_viridis_d(name = "Land Cover Class", na.value = "transparent")
  # coord_equal() +
  theme_minimal()

ggsave(file.path("outputs", paste0("lcm_2000_grp",".png")), width = 7, height = 4, dpi = 300)

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
        
brownfield_ <- st_read("./data/brownfield/brownfield-land.geojson")         
brownfield <- st_read("./data/brownfield/brownfield-land.geojson") %>% st_transform(st_crs(gb))

idx_within <- st_within(brownfield, gb_buffer, sparse = FALSE)  # matrix [n_pts x n_polys]
pts_outside <- brownfield[!apply(idx_within, 1, any), ]        
pts_outside$hectares <- as.numeric(pts_outside$hectares)

pts_outside_ <- pts_outside %>% st_transform(4326) # 19 pts fall way outside of GB

ggplot() + geom_sf(data = gb, fill = "white", color = "grey80") +
  geom_sf(data = pts_outside, size = 0.001, aes(col = hectares)) +
  scale_color_viridis_c(name = "Brownfield sites", na.value = "transparent") +
  theme_minimal() +
  theme(panel.grid = element_blank())

ggsave("./outputs/brownfield_outside.pdf", width = 9, height = 16)

ggplot() + geom_sf(data = gb, fill = "white", color = "grey80") +
  geom_sf(data = brownfield, size = 0.001) +
  scale_color_viridis_c(name = "Brownfield sites", na.value = "transparent") +
  theme_minimal() +
  theme(panel.grid = element_blank())

ggsave("./outputs/brownfield_sites.pdf", width = 9, height = 16)
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
out_dir_radon <- here::here("./outputs/radon/")
dir.create(out_dir_radon, recursive = TRUE, showWarnings = FALSE)
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
  scale_color_brewer(palette = "BuPu", direction = 1, drop = FALSE, name = "RnP") +
  scale_fill_brewer(palette = "BuPu", direction = 1, drop = FALSE, name = "RnP")
  # ggplot() + geom_spatraster(data = radon, aes(fill = CLASS_MAX))
  ggsave(paste0(out_dir_radon, "radon_atlas.pdf"), width = 8, height = 6)
  ggsave(paste0(out_dir_radon, "radon_atlas.png"), width = 8, height = 6, dpi = 300)



# light emission ----------------------------------------------------------

source("light.R")



# air pollution -----------------------------------------------------------


  
  
# gamma -------------------------------------------------------------------

# https://www.data.gov.uk/dataset/568e58c0-6404-4a8a-9654-4440245fb6e4/ambient-gamma-radiation-dose-rates-across-the-uk
# https://webarchive.nationalarchives.gov.uk/ukgwa/20130103015143/http://www.decc.gov.uk/en/content/cms/statistics/rimnet/rimnet.aspx#

# ONS ---------------------------------------------------------------------


# https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/lowersuperoutputareamidyearpopulationestimatesnationalstatistics

# Noise ----------------------------------------------------------
# https://environment.data.gov.uk/explore/562c9d56-7c2d-4d42-83bb-578d6e97a517?download=true