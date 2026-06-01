library(terra)
library(here)
source("lsoa11221.R")
# folder containing the csv files
data_dir  <- paste0(here::here(), "/data/defra")

files <- c(
  "mapdaysgt12003_2.csv",
  "mapdgt12004.csv",
  "mapdgt120_2005r.csv",
  "mapdgt120_06.csv",
  "mapdgt120_07.csv",
  "mapdgt120_08.csv",
  "mapdgt120_09.csv",
  "mapdgt120_10.csv",
  "mapdgt120_11.csv",
  "mapdgt120_12.csv",
  "mapdgt12013.csv",
  "mapdgt12014.csv",
  "mapdgt12015.csv",
  "mapdgt12016.csv",
  "mapdgt12017.csv",
  "mapdgt12018.csv",
  "mapdgt12019.csv",
  "mapdgt12020.csv",
  "mapdgt12021.csv",
  "mapdgt12022.csv",
  "mapdgt12023.csv",
  "mapdgt12024.csv"
)

library(terra)
library(sf)
library(here)

source("lsoa11221.R")

data_dir <- file.path(here::here(), "data", "defra")

files <- c(
  "mapdaysgt12003_2.csv",
  "mapdgt12004.csv",
  "mapdgt120_2005r.csv",
  "mapdgt120_06.csv",
  "mapdgt120_07.csv",
  "mapdgt120_08.csv",
  "mapdgt120_09.csv",
  "mapdgt120_10.csv",
  "mapdgt120_11.csv",
  "mapdgt120_12.csv",
  "mapdgt12013.csv",
  "mapdgt12014.csv",
  "mapdgt12015.csv",
  "mapdgt12016.csv",
  "mapdgt12017.csv",
  "mapdgt12018.csv",
  "mapdgt12019.csv",
  "mapdgt12020.csv",
  "mapdgt12021.csv",
  "mapdgt12022.csv",
  "mapdgt12023.csv",
  "mapdgt12024.csv"
)

# Convert once for terra::extract
poly_lsoa_21_vect <- terra::vect(poly_lsoa_21)

for (i in seq_along(files)) {
  yr <- 2002 + i
  f <- file.path(data_dir, "ozone", files[i])
  
  cat("Reading", yr, ":", f, "\n")
  
  dat <- read.csv(
    f,
    skip = 5,
    header = FALSE,
    na.strings = "MISSING",
    stringsAsFactors = FALSE
  )
  
  # Drop the source header row
  dat <- dat[-1, ]
  
  if (ncol(dat) < 4) {
    stop(sprintf("Year %s: expected at least 4 columns, got %s", yr, ncol(dat)))
  }
  
  names(dat)[1:4] <- c("gridcode", "x", "y", "value")
  dat <- dat[, 1:4]
  
  dat$x <- as.numeric(dat$x)
  dat$y <- as.numeric(dat$y)
  dat$value <- as.numeric(dat$value)
  
  r <- rast(dat[, c("x", "y", "value")], type = "xyz", crs = "EPSG:27700")
  print(paste0(yr, "terra::extracting"))
  vals <- terra::extract(
    r, poly_lsoa_21_vect,
    fun = mean, na.rm = TRUE, ID = FALSE, weights = TRUE
  )[[1]]
  
  poly_lsoa_21[[paste0("ozone", yr)]] <- vals
}

sf::st_write(
  poly_lsoa_21,
  here("ozone_lsoa_eng.gpkg"),
  delete_dsn = TRUE
)

