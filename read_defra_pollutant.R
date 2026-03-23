# read a loop ---------------------------------------------------------------
# Model outputs are annual means, represented in µg m-3.
# folders
in_dir <- file.path(here::here(), "data", "defra", pollutant)
out_tif <- file.path(in_dir, "geotiff")
out_png <- file.path(in_dir, "plots")

dir.create(out_tif, showWarnings = FALSE, recursive = TRUE)
dir.create(out_png, showWarnings = FALSE, recursive = TRUE)

# list all csv files
files <- list.files(in_dir, pattern = "\\.csv$", full.names = TRUE)

# helper: read one file and make raster
read_pollutant_raster <- function(f) {
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
rasters_list <- lapply(files, read_pollutant_raster)

# sort by year
yrs <- sapply(rasters_list, `[[`, "year")
ord <- order(yrs)
rasters_list <- rasters_list[ord]

# save each GeoTIFF
for (obj in rasters_list) {
  yr <- obj$year
  r <- obj$raster

  out_file <- file.path(out_tif, paste0(pollutant, "_", yr, ".tif"))
  writeRaster(r, out_file, overwrite = TRUE)
}

# align extents -------------------------------------------------------------

years <- sapply(rasters_list, `[[`, "year")
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

out_tif_overlap <- file.path(in_dir, "geotiff_overlap")
dir.create(out_tif_overlap, showWarnings = FALSE, recursive = TRUE)

for (i in seq_along(rasters_crop)) {
  writeRaster(
    rasters_crop[[i]],
    file.path(out_tif_overlap, paste0(pollutant, "_", years[i], "_overlap.tif")),
    overwrite = TRUE
  )
}

# stack rasters
r_stack <- rast(rasters_crop)

# Multipanel plot across years -------------------------------------------------------
# Use original rasters directly
rasters_plot <- rasters_crop

# Common min/max across all rasters
mins <- sapply(rasters_plot, function(r) global(r, "min", na.rm = TRUE)[1, 1])
maxs <- sapply(rasters_plot, function(r) global(r, "max", na.rm = TRUE)[1, 1])

global_min <- min(mins, na.rm = TRUE)
global_max <- max(maxs, na.rm = TRUE)

# Colour palette
cols <- hcl.colors(30, "YlOrRd")

# Layout
n <- length(rasters_plot)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)

png(
  file.path(out_png, paste0(pollutant, "_overlap_multipanel_commonlegend.png")),
  width = 3600,
  height = 600 * nrow_plot,
  res = 200
)

# Main plotting region leaves room on right for legend
par(
  mfrow = c(nrow_plot, ncol_plot),
  mar = c(2, 2, 3, 1),
  oma = c(0, 0, 0, 16),
  xpd = NA
)

# Plot each raster without legend
for (i in seq_along(rasters_plot)) {
  plot(
    rasters_plot[[i]],
    col = cols,
    zlim = c(global_min, global_max),
    main = years[i], cex.main = 2.4,
    axes = FALSE,
    box = FALSE,
    legend = FALSE
  )
}

# Shared legend in a separate figure region
par(fig = c(0.92, 0.96, 0.20, 0.80), new = TRUE, mar = c(0, 0, 0, 4))
plot.new()
plot.window(xlim = c(0, 1), ylim = c(global_min, global_max))

# Draw vertical colour bar
ybreaks <- seq(global_min, global_max, length.out = length(cols) + 1)

for (j in seq_along(cols)) {
  rect(
    xleft   = 0,
    ybottom = ybreaks[j],
    xright  = 0.45,
    ytop    = ybreaks[j + 1],
    col     = cols[j],
    border  = NA
  )
}

# Border
rect(0, global_min, 0.45, global_max, border = "black", lwd = 1)

# Regular ticks on original scale
ticks <- pretty(c(global_min, global_max), n = 5)
ticks <- ticks[ticks >= global_min & ticks <= global_max]

axis(
  4,
  at = ticks,
  labels = format(round(ticks, 2), trim = TRUE),
  las = 1,
  cex.axis = 0.9
)

mtext(
  bquote(pollutant~"("*mu*g~m^{-3}*")"),
  side = 4,
  line = 2.5,
  cex = 0.9
)

# mtext(
#   pollutant,
#   side = 4,
#   line = 2.5,
#   cex = 0.9
# )

dev.off()

# Multipanel plot across years in log 10 scale -------------------------------------------------------
# Log-transform rasters safely: keep only positive values
rasters_log <- lapply(rasters_crop, function(r) {
  ifel(r > 0, log10(r), NA)
})

# Common min/max across all log-transformed rasters
mins <- sapply(rasters_log, function(r) global(r, "min", na.rm = TRUE)[1, 1])
maxs <- sapply(rasters_log, function(r) global(r, "max", na.rm = TRUE)[1, 1])

global_min <- min(mins, na.rm = TRUE)
global_max <- max(maxs, na.rm = TRUE)

# Colour palette
cols <- hcl.colors(30, "YlOrRd")

# Layout
n <- length(rasters_log)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)

png(
  file.path(out_png, paste0(pollutant, "_overlap_multipanel_log10_commonlegend.png")),
  width = 3600,
  height = 600 * nrow_plot,
  res = 200
)

# Main plotting region leaves room on right for legend
par(
  mfrow = c(nrow_plot, ncol_plot),
  mar = c(2, 2, 3, 1),
  oma = c(0, 0, 0, 16),
  xpd = NA
)

# Plot each raster without legend
for (i in seq_along(rasters_log)) {
  plot(
    rasters_log[[i]],
    col = cols,
    zlim = c(global_min, global_max),
    main = years[i], cex.main = 2.4,
    axes = FALSE,
    box = FALSE,
    legend = FALSE
  )
}

# Shared legend in a separate figure region farther right
par(fig = c(0.92, 0.96, 0.20, 0.80), new = TRUE, mar = c(0, 0, 0, 4))
plot.new()
plot.window(xlim = c(0, 1), ylim = c(global_min, global_max))

# Draw vertical colour bar
ybreaks <- seq(global_min, global_max, length.out = length(cols) + 1)

for (j in seq_along(cols)) {
  rect(
    xleft   = 0,
    ybottom = ybreaks[j],
    xright  = 0.45,
    ytop    = ybreaks[j + 1],
    col     = cols[j],
    border  = NA
  )
}

# Border
rect(0, global_min, 0.45, global_max, border = "black", lwd = 1)

# Legend ticks shown on log10 scale
ticks_log <- pretty(c(global_min, global_max), n = 5)
ticks_log <- ticks_log[ticks_log >= global_min & ticks_log <= global_max]

axis(
  4,
  at = ticks_log,
  labels = format(round(ticks_log, 2), trim = TRUE),
  las = 1,
  cex.axis = 0.9
)

mtext(
  bquote(log[10](.(pollutant)~"("*mu*g~m^{-3}*")")),
  side = 4,
  line = 2.5,
  cex = 0.9
)


dev.off()


# difference plot -----------------------------------------------------------
baseline_year <- years[1]
baseline <- r_stack[[1]]

# Differences from baseline
r_diff <- r_stack - baseline
names(r_diff) <- names(r_stack)

# Baseline scale
base_min <- global(baseline, "min", na.rm = TRUE)[1, 1]
base_max <- global(baseline, "max", na.rm = TRUE)[1, 1]
zlim_base <- c(base_min, base_max)
ticks_base <- pretty(zlim_base, n = 5)
ticks_base <- ticks_base[ticks_base >= zlim_base[1] & ticks_base <= zlim_base[2]]

# Difference scale: symmetric around zero
diff_min <- global(r_diff, "min", na.rm = TRUE)[, 1]
diff_max <- global(r_diff, "max", na.rm = TRUE)[, 1]
max_abs <- max(abs(c(diff_min, diff_max)))
max_abs <- ceiling(max_abs * 10) / 10
zlim_diff <- c(-max_abs, max_abs)
ticks_diff <- round(seq(-max_abs, max_abs, length.out = 5), 1)

# Palettes
cols_base <- hcl.colors(30, "YlOrRd")
cols_diff <- hcl.colors(31, "Blue-Red 3", rev = FALSE)

n <- nlyr(r_stack)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)

png(
  file.path(out_png, paste0(pollutant, "_change_from_", baseline_year, "_baseline_plus_diff_common_legends.png")),
  width = 4800,
  height = 700 * nrow_plot,
  res = 200
)

par(
  mfrow = c(nrow_plot, ncol_plot),
  mar = c(2, 2, 3, 1),
  oma = c(0, 0, 0, 24),
  xpd = NA,
  cex.main = 1.3
)

# Panel 1: baseline raster
plot(
  baseline,
  col = cols_base,
  zlim = zlim_base,
  main = as.character(baseline_year), cex.main = 2.4,
  axes = FALSE,
  box = FALSE,
  legend = FALSE
)

# Remaining panels: differences
for (i in 2:nlyr(r_diff)) {
  plot(
    r_diff[[i]],
    col = cols_diff,
    zlim = zlim_diff,
    main = paste0(years[i]), cex.main = 2.4,
    axes = FALSE,
    box = FALSE,
    legend = FALSE
  )
}

# ----- Baseline legend -----
par(fig = c(0.90, 0.97, 0.58, 0.88), new = TRUE, mar = c(0, 0, 0, 6))
plot.new()
plot.window(xlim = c(0, 1), ylim = zlim_base)

ybreaks_base <- seq(zlim_base[1], zlim_base[2], length.out = length(cols_base) + 1)

for (j in seq_along(cols_base)) {
  rect(
    xleft   = 0,
    ybottom = ybreaks_base[j],
    xright  = 0.6,
    ytop    = ybreaks_base[j + 1],
    col     = cols_base[j],
    border  = NA
  )
}

rect(0, zlim_base[1], 0.6, zlim_base[2], border = "black", lwd = 1.2)

axis(
  4,
  at = ticks_base,
  labels = round(ticks_base, 2),
  las = 1,
  cex.axis = 1.3
)

mtext(
  paste0(baseline_year, " level"),
  side = 4,
  line = 3.5,
  cex = 1.2
)

# ----- Difference legend -----
par(fig = c(0.90, 0.97, 0.14, 0.50), new = TRUE, mar = c(0, 0, 0, 6))
plot.new()
plot.window(xlim = c(0, 1), ylim = zlim_diff)

ybreaks_diff <- seq(zlim_diff[1], zlim_diff[2], length.out = length(cols_diff) + 1)

for (j in seq_along(cols_diff)) {
  rect(
    xleft   = 0,
    ybottom = ybreaks_diff[j],
    xright  = 0.6,
    ytop    = ybreaks_diff[j + 1],
    col     = cols_diff[j],
    border  = NA
  )
}

rect(0, zlim_diff[1], 0.6, zlim_diff[2], border = "black", lwd = 1.2)

axis(
  4,
  at = ticks_diff,
  labels = ticks_diff,
  las = 1,
  cex.axis = 1.3
)

mtext(
  paste0("Difference from", baseline_year),
  side = 4,
  line = 3.5,
  cex = 1.2
)

dev.off()


# another version of difference plot --------------------------------------


library(terra)

baseline_year <- years[1]
baseline <- r_stack[[1]]

# Differences from baseline
r_diff <- r_stack - baseline
names(r_diff) <- names(r_stack)

# Baseline scale
base_min <- global(baseline, "min", na.rm = TRUE)[1, 1]
base_max <- global(baseline, "max", na.rm = TRUE)[1, 1]
zlim_base <- c(base_min, base_max)

ticks_base <- pretty(zlim_base, n = 5)
ticks_base <- ticks_base[ticks_base >= zlim_base[1] & ticks_base <= zlim_base[2]]

# Difference scale: symmetric around zero
diff_min <- global(r_diff, "min", na.rm = TRUE)[, 1]
diff_max <- global(r_diff, "max", na.rm = TRUE)[, 1]
max_abs <- max(abs(c(diff_min, diff_max)))
max_abs <- ceiling(max_abs * 10) / 10
zlim_diff <- c(-max_abs, max_abs)

ticks_diff <- round(seq(-max_abs, max_abs, length.out = 5), 1)

# Palettes
cols_base <- hcl.colors(30, "YlOrRd")
cols_diff <- hcl.colors(31, "Blue-Red 3", rev = FALSE)

# Layout
n <- nlyr(r_stack)
ncol_plot <- 4
nrow_plot <- ceiling(n / ncol_plot)
n_map_slots <- nrow_plot * ncol_plot

# Layout matrix: map panels + 1 legend column
lay <- matrix(0, nrow = nrow_plot, ncol = ncol_plot + 1)
lay[, 1:ncol_plot] <- matrix(seq_len(n_map_slots), nrow = nrow_plot, byrow = TRUE)

id_base_legend <- n_map_slots + 1
id_diff_legend <- n_map_slots + 2

top_rows <- seq_len(max(1, ceiling(nrow_plot / 2)))
bottom_rows <- seq(ceiling(nrow_plot / 2) + 1, nrow_plot)

lay[top_rows, ncol_plot + 1] <- id_base_legend
if (length(bottom_rows) > 0 && all(bottom_rows >= 1) && all(bottom_rows <= nrow_plot)) {
  lay[bottom_rows, ncol_plot + 1] <- id_diff_legend
} else {
  lay[top_rows, ncol_plot + 1] <- id_diff_legend
}

png(
  file.path(
    out_png,
    paste0(pollutant, "_change_from_", baseline_year, "_baseline_plus_diff_legends_layout_v2.png")
  ),
  width = 4800,
  height = 750 * nrow_plot,
  res = 200
)

layout(
  lay,
  widths = c(rep(1, ncol_plot), 0.55),
  heights = rep(1, nrow_plot)
)

# ----- Map panels -----
par(mar = c(2, 2, 4, 1), cex.main = 2.0)

# Panel 1: baseline raster
plot(
  baseline,
  col = cols_base,
  zlim = zlim_base,
  main = as.character(baseline_year),
  axes = FALSE,
  box = FALSE,
  legend = FALSE
)

# Remaining panels: differences
for (i in 2:nlyr(r_diff)) {
  plot(
    r_diff[[i]],
    col = cols_diff,
    zlim = zlim_diff,
    main = paste0(years[i]),
    axes = FALSE,
    box = FALSE,
    legend = FALSE
  )
}

# Fill unused map slots if needed
if (n < n_map_slots) {
  for (k in seq_len(n_map_slots - n)) {
    par(mar = c(0, 0, 0, 0))
    plot.new()
  }
}

# ----- Baseline legend -----
par(mar = c(2, 1, 3, 4))
plot.new()
plot.window(xlim = c(0, 1), ylim = zlim_base)

ybreaks_base <- seq(zlim_base[1], zlim_base[2], length.out = length(cols_base) + 1)

for (j in seq_along(cols_base)) {
  rect(
    xleft = 0.18,
    ybottom = ybreaks_base[j],
    xright = 0.38,
    ytop = ybreaks_base[j + 1],
    col = cols_base[j],
    border = NA
  )
}

rect(0.18, zlim_base[1], 0.38, zlim_base[2], border = "black", lwd = 1)

axis(
  4,
  at = ticks_base,
  labels = round(ticks_base, 2),
  las = 1,
  cex.axis = 1.0
)

mtext(
  paste0(baseline_year, " level"),
  side = 3,
  line = 0.5,
  cex = 1.0,
  font = 2
)

# ----- Difference legend -----
par(mar = c(2, 1, 3, 4))
plot.new()
plot.window(xlim = c(0, 1), ylim = zlim_diff)

ybreaks_diff <- seq(zlim_diff[1], zlim_diff[2], length.out = length(cols_diff) + 1)

for (j in seq_along(cols_diff)) {
  rect(
    xleft = 0.18,
    ybottom = ybreaks_diff[j],
    xright = 0.38,
    ytop = ybreaks_diff[j + 1],
    col = cols_diff[j],
    border = NA
  )
}

rect(0.18, zlim_diff[1], 0.38, zlim_diff[2], border = "black", lwd = 1)

axis(
  4,
  at = ticks_diff,
  labels = ticks_diff,
  las = 1,
  cex.axis = 1.0
)

mtext(
  paste0("Difference from ", baseline_year),
  side = 3,
  line = 0.5,
  cex = 1.0,
  font = 2
)

dev.off()

