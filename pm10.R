# read a loop -------------------------------------------------------------

library(readr)
library(dplyr)
library(terra)
library(stringr)

# folder containing CSVs
in_dir  <- paste0(here::here(), "/data/defra/pm10")
out_tif <- file.path(in_dir, "geotiff")
out_png <- file.path(in_dir, "plots")

dir.create(out_tif, showWarnings = FALSE, recursive = TRUE)
dir.create(out_png, showWarnings = FALSE, recursive = TRUE)

# list all csv files
files <- list.files(in_dir, pattern = "\\.csv$", full.names = TRUE)

# helper: read one file and make raster
read_pm_raster <- function(f) {
  # metadata rows
  meta <- read_csv(f, n_max = 5, col_names = FALSE, show_col_types = FALSE)
  
  # try to get year from row 2, col 1
  year_meta <- suppressWarnings(as.integer(meta[[1]][2]))
  
  # data
  dat <- read_csv(f, skip = 5, na = "MISSING", show_col_types = FALSE)
  
  # find metric column = 4th column
  metric_col <- names(dat)[4]
  
  dat[[metric_col]] <- as.numeric(dat[[metric_col]])
  
  # drop rows with missing coordinates
  dat <- dat %>% filter(!is.na(x), !is.na(y))
  
  # make template raster from centroid extent
  r_template <- rast(
    xmin = min(dat$x) - 500,
    xmax = max(dat$x) + 500,
    ymin = min(dat$y) - 500,
    ymax = max(dat$y) + 500,
    resolution = 1000,
    crs = "EPSG:27700"
  )
  
  # points to SpatVector
  v <- vect(dat, geom = c("x", "y"), crs = "EPSG:27700")
  
  # rasterize
  r <- rasterize(v, r_template, field = metric_col)
  
  # get year from file name if metadata failed
  if (is.na(year_meta)) {
    yr <- str_extract(basename(f), "(19|20)\\d{2}")
    year_meta <- as.integer(yr)
  }
  
  names(r) <- paste0("y", year_meta)
  
  list(
    raster = r,
    year = year_meta,
    metric = metric_col,
    file = f
  )
}

# read all rasters
rasters_list <- lapply(files, read_pm_raster)

# sort by year
yrs <- sapply(rasters_list, `[[`, "year")
ord <- order(yrs)
rasters_list <- rasters_list[ord]

# save each GeoTIFF
for (obj in rasters_list) {
  yr <- obj$year
  r  <- obj$raster
  
  out_file <- file.path(out_tif, paste0("pm10_", yr, ".tif"))
  writeRaster(r, out_file, overwrite = TRUE)
}



# sort by year
ord <- order(sapply(rasters_list, `[[`, "year"))
rasters_list <- rasters_list[ord]
years <- sapply(rasters_list, `[[`, "year")
# extract rasters
rasters <- lapply(rasters_list, `[[`, "raster")
exts <- lapply(rasters, ext)

common_ext <- ext(
  max(sapply(exts, xmin)),
  min(sapply(exts, xmax)),
  max(sapply(exts, ymin)),
  min(sapply(exts, ymax))
)

rasters_crop <- lapply(rasters, function(r) crop(r, common_ext))
for (i in 2:length(rasters_crop)) {
  print(compareGeom(rasters_crop[[1]], rasters_crop[[i]], stopOnError = FALSE))
}
out_tif <- file.path(in_dir, "geotiff_overlap")
dir.create(out_tif, showWarnings = FALSE, recursive = TRUE)
for (i in seq_along(rasters_crop)) {
  writeRaster(
    rasters_crop[[i]],
    file.path(out_tif, paste0("pm10_", years[i], "_overlap.tif")),
    overwrite = TRUE
  )
}


r_stack <- rast(rasters_crop)

global_min <- global(r_stack, "min", na.rm = TRUE)[1, 1]
global_max <- global(r_stack, "max", na.rm = TRUE)[1, 1]

cols <- hcl.colors(30, "YlOrRd")

n <- length(rasters_crop)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)

png(
  file.path(out_png, "pm10_overlap_multipanel.png"),
  width = 2200,
  height = 600 * nrow_plot,
  res = 200
)

par(mfrow = c(nrow_plot, ncol_plot), mar = c(2, 2, 3, 5))

for (i in seq_along(rasters_crop)) {
  plot(
    rasters_crop[[i]],
    col = cols,
    zlim = c(global_min, global_max),
    main = years[i],
    axes = FALSE,
    box = FALSE,
    legend = (i == n)
  )
}

dev.off()

