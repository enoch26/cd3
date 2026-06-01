library(terra)
library(here)
source("lsoa11221.R")
source("ozone.R")
# https://uk-air.defra.gov.uk/data/pcm-data
data_dir <- here("data")
pollutants <- c("benzene", "pm25", "pm10", "nox")
for (pol in pollutants) {
  for (yr in 2003:2024) {
    r <- rast(here(data_dir, sprintf("defra/%s/geotiff_overlap/%s_%d_overlap.tif", pol, pol, yr)))
    poly_lsoa_21[[paste0(pol, yr)]] <- extract(
      r, poly_lsoa_21,
      fun = mean, na.rm = TRUE, ID = FALSE, weights = TRUE
    )[[1]]
  }
}

st_write(
  poly_lsoa_21,
  here("air_lsoa_eng.gpkg"),
  delete_dsn = TRUE
)



for (yr in 2003:2024) {
  ben <- rast(here(data_dir, sprintf("defra/benzene/geotiff_overlap/benzene_%d_overlap.tif", yr)))
  
  lsoa_eng[[paste0("ben", yr)]] <- extract(
    ben,
    lsoa_eng,
    fun = mean,
    na.rm = TRUE,
    ID = FALSE,
    weights = TRUE
  )[[1]]
}



pm25 <- rast("data/pm25_2010_overlap.tif")
pm10 <- rast("data/pm10_2010_overlap.tif")
nox <- rast("data/nox_2010_overlap.tif")

ggplot() + tidyterra::geom_spatraster(data = ben) +
  scale_fill_viridis_c() +
  labs(title = "Benzene in 2010")

ggplot() + tidyterra::geom_spatraster(data = log(pm25)) + 
  scale_fill_viridis_c() + 
  labs(title = "PM2.5 in 2010") 

ggplot() + tidyterra::geom_spatraster(data = pm10) +
  scale_fill_viridis_c() + 
  labs(title = "PM10 in 2010")

ggplot() + tidyterra::geom_spatraster(data = nox) +
  scale_fill_viridis_c() +
  labs(title = "NOx in 2010")


