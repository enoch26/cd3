library(terra)
library(here)

ozone <- read.csv(
  here(data_dir, "ozone/mapdaysgt12003_2.csv"),
  skip = 5,
  na.strings = "MISSING"
)

ozone$daysgt12003_2 <- as.numeric(ozone$daysgt12003_2)

ozone_sub <- ozone[, c("x", "y", "daysgt12003_2")]

r <- rast(
  ozone_sub,
  type = "xyz",
  crs = "EPSG:27700"
)

plot(r)
