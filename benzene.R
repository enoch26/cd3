# read a loop -------------------------------------------------------------

library(readr)
library(dplyr)
library(terra)
library(stringr)

# folder containing CSVs
in_dir  <- paste0(here::here(), "/data/defra/benzene")
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
  
  out_file <- file.path(out_tif, paste0("benzene_", yr, ".tif"))
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
    file.path(out_tif, paste0("benzene_", years[i], "_overlap.tif")),
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
  file.path(out_png, "benzene_overlap_multipanel.png"),
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


# difference plot ---------------------------------------------------------
# difference plot using first year as baseline, with one common legend
# centred on zero

baseline_year <- years[1]
baseline <- r_stack[[1]]

r_diff <- r_stack - baseline
names(r_diff) <- names(r_stack)

# symmetric scale around zero
diff_min <- global(r_diff, "min", na.rm = TRUE)[1, 1]
diff_max <- global(r_diff, "max", na.rm = TRUE)[1, 1]
max_abs  <- max(abs(c(diff_min, diff_max)))
max_abs  <- ceiling(max_abs * 10) / 10
zlim_diff <- c(-max_abs, max_abs)

# diverging palette
cols_diff <- hcl.colors(31, "Blue-Red 3", rev = TRUE)

# symmetric tick marks centred on zero
ticks <- round(seq(-max_abs, max_abs, length.out = 5), 1)

n <- nlyr(r_diff)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)

png(
  file.path(out_png, paste0("benzene_change_from_", baseline_year, "_multipanel_common_legend.png")),
  width = 3400,
  height = 600 * nrow_plot,
  res = 200
)

par(
  mfrow = c(nrow_plot, ncol_plot),
  mar = c(2, 2, 3, 1),
  oma = c(0, 0, 0, 10),
  xpd = NA
)

# plot panels without legends
for (i in 1:nlyr(r_diff)) {
  plot(
    r_diff[[i]],
    col = cols_diff,
    zlim = zlim_diff,
    main = paste0(years[i], " - ", baseline_year),
    axes = FALSE,
    box = FALSE,
    legend = FALSE
  )
}

# legend in a new figure region on the right
par(fig = c(0.91, 0.95, 0.18, 0.82), new = TRUE, mar = c(1, 1, 1, 3))
plot.new()
plot.window(xlim = c(0, 1), ylim = zlim_diff)

# draw vertical colour bar
ybreaks <- seq(zlim_diff[1], zlim_diff[2], length.out = length(cols_diff) + 1)

for (j in seq_along(cols_diff)) {
  rect(
    xleft   = 0,
    ybottom = ybreaks[j],
    xright  = 0.5,
    ytop    = ybreaks[j + 1],
    col     = cols_diff[j],
    border  = NA
  )
}

# border and axis
rect(0, zlim_diff[1], 0.5, zlim_diff[2], border = "black", lwd = 1)
axis(4, at = ticks, labels = ticks, las = 1, cex.axis = 0.9)
mtext("Difference", side = 4, line = 2)

dev.off()
