# DEFRA PCM annual CSV grids -> aligned GeoTIFFs and diagnostic maps ----------
#
# Purpose:
#   Convert annual DEFRA PCM model-output CSV files (annual mean concentrations
#   in micrograms per cubic metre) into British National Grid GeoTIFFs. The
#   script also crops all annual grids to their common spatial overlap so that
#   they can be compared cell by cell.
#
# Source:
#   https://uk-air.defra.gov.uk/data/pcm-data
#
# Expected layout for a selected pollutant:
#   data/defra/<pollutant>/
#     <annual PCM CSV files>
#     geotiff/                  # created: original-extent rasters
#     geotiff_overlap/          # created: common-overlap rasters
#     plots/                    # created: diagnostic PNG files
#
# Assumptions to verify against the downloaded PCM release:
#   * the first five CSV rows are metadata;
#   * data begin on row six;
#   * coordinate fields are named `x` and `y`, in EPSG:27700 metres;
#   * the concentration field is the fourth data column; and
#   * cells are on a 1 km grid.

# Packages ------------------------------------------------------------------
required_packages <- c("terra", "dplyr", "readr", "stringr", "here")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing_packages) > 0L) install.packages(missing_packages)
invisible(lapply(required_packages, library, character.only = TRUE))

# Configuration -------------------------------------------------------------
# Run once per pollutant, e.g. "benzene", "pm25", "pm10", or "nox".
pollutant <- "pm25"
input_dir <- here::here("data", "defra", pollutant)
raw_tif_dir <- file.path(input_dir, "geotiff")
overlap_tif_dir <- file.path(input_dir, "geotiff_overlap")
plot_dir <- file.path(input_dir, "plots")

metadata_rows <- 5L
metric_column_index <- 4L
cell_resolution_metres <- 1000
input_crs <- "EPSG:27700"
number_of_plot_columns <- 4L

if (!dir.exists(input_dir)) {
  stop("Input directory does not exist: ", input_dir, call. = FALSE)
}
dir.create(raw_tif_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(overlap_tif_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

csv_files <- list.files(
  input_dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE
)
if (length(csv_files) == 0L) {
  stop("No CSV files found in: ", input_dir, call. = FALSE)
}

# Helpers -------------------------------------------------------------------
extract_year <- function(path, metadata_year = NA_integer_) {
  if (!is.na(metadata_year)) return(metadata_year)

  file_year <- stringr::str_extract(basename(path), "(?:19|20)\\d{2}")
  year <- suppressWarnings(as.integer(file_year))
  if (is.na(year)) {
    stop("Could not identify a year from metadata or filename: ", basename(path), call. = FALSE)
  }
  year
}

# Read a PCM CSV and rasterise its 1 km centroid grid. `rast()` is created
# from the observed centroid extent, with half a cell added on every side.
read_pcm_raster <- function(path) {
  metadata <- readr::read_csv(
    path, n_max = metadata_rows, col_names = FALSE, show_col_types = FALSE
  )
  metadata_year <- suppressWarnings(as.integer(metadata[[1L]][2L]))

  data <- readr::read_csv(
    path, skip = metadata_rows, na = c("MISSING", "NA", ""), show_col_types = FALSE
  )
  required_columns <- c("x", "y")
  if (!all(required_columns %in% names(data))) {
    stop("CSV must contain `x` and `y` columns: ", basename(path), call. = FALSE)
  }
  if (ncol(data) < metric_column_index) {
    stop("CSV has fewer than ", metric_column_index, " columns: ", basename(path), call. = FALSE)
  }

  metric_column <- names(data)[metric_column_index]
  data <- data |>
    dplyr::mutate(
      x = readr::parse_number(as.character(x)),
      y = readr::parse_number(as.character(y)),
      value = readr::parse_number(as.character(.data[[metric_column]]))
    ) |>
    dplyr::filter(!is.na(x), !is.na(y))

  if (nrow(data) == 0L) stop("No valid coordinate rows in: ", basename(path), call. = FALSE)
  if (anyDuplicated(data[c("x", "y")])) {
    stop("Duplicate x/y grid locations in: ", basename(path), call. = FALSE)
  }

  template <- terra::rast(
    xmin = min(data$x) - cell_resolution_metres / 2,
    xmax = max(data$x) + cell_resolution_metres / 2,
    ymin = min(data$y) - cell_resolution_metres / 2,
    ymax = max(data$y) + cell_resolution_metres / 2,
    resolution = cell_resolution_metres,
    crs = input_crs
  )
  points <- terra::vect(data, geom = c("x", "y"), crs = input_crs)
  raster <- terra::rasterize(points, template, field = "value")

  year <- extract_year(path, metadata_year)
  names(raster) <- paste0("y", year)
  list(raster = raster, year = year, metric = metric_column, file = path)
}

common_extent <- function(rasters) {
  extents <- lapply(rasters, terra::ext)
  overlap <- terra::ext(
    max(vapply(extents, terra::xmin, numeric(1))),
    min(vapply(extents, terra::xmax, numeric(1))),
    max(vapply(extents, terra::ymin, numeric(1))),
    min(vapply(extents, terra::ymax, numeric(1)))
  )
  if (terra::xmin(overlap) >= terra::xmax(overlap) ||
      terra::ymin(overlap) >= terra::ymax(overlap)) {
    stop("The annual rasters have no common spatial overlap.", call. = FALSE)
  }
  overlap
}

raster_range <- function(rasters) {
  mins <- vapply(rasters, function(x) terra::global(x, "min", na.rm = TRUE)[1, 1], numeric(1))
  maxs <- vapply(rasters, function(x) terra::global(x, "max", na.rm = TRUE)[1, 1], numeric(1))
  c(min(mins, na.rm = TRUE), max(maxs, na.rm = TRUE))
}

# Produce a panel plot with a common concentration scale and one legend.
plot_multipanel <- function(rasters, years, filename, title_suffix = "", log10_scale = FALSE) {
  if (log10_scale) rasters <- lapply(rasters, function(x) terra::ifel(x > 0, log10(x), NA))
  zlim <- raster_range(rasters)
  colours <- hcl.colors(30, "YlOrRd")
  n_rows <- ceiling(length(rasters) / number_of_plot_columns)

  grDevices::png(filename, width = 3600, height = 600 * n_rows, res = 200)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(n_rows, number_of_plot_columns), mar = c(2, 2, 3, 1), oma = c(0, 0, 0, 16), xpd = NA)

  for (i in seq_along(rasters)) {
    terra::plot(rasters[[i]], col = colours, zlim = zlim, main = years[i],
                axes = FALSE, box = FALSE, legend = FALSE)
  }

  graphics::par(fig = c(0.92, 0.96, 0.20, 0.80), new = TRUE, mar = c(0, 0, 0, 4))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = zlim)
  breaks <- seq(zlim[1], zlim[2], length.out = length(colours) + 1L)
  for (j in seq_along(colours)) graphics::rect(0, breaks[j], 0.45, breaks[j + 1L], col = colours[j], border = NA)
  graphics::rect(0, zlim[1], 0.45, zlim[2], border = "black")
  ticks <- pretty(zlim, n = 5)
  ticks <- ticks[ticks >= zlim[1] & ticks <= zlim[2]]
  graphics::axis(4, at = ticks, labels = format(round(ticks, 2), trim = TRUE), las = 1)
  legend_label <- if (log10_scale) {
    paste0("log10 ", pollutant, " (micrograms per cubic metre)")
  } else {
    paste0(pollutant, " (micrograms per cubic metre)")
  }
  graphics::mtext(legend_label, side = 4, line = 2.5)
  graphics::mtext(title_suffix, side = 3, outer = TRUE, line = -1)
}

# Read, write and align rasters --------------------------------------------
products <- lapply(csv_files, read_pcm_raster)
years <- vapply(products, `[[`, integer(1), "year")
if (anyDuplicated(years)) stop("More than one input CSV was assigned to a year.", call. = FALSE)
products <- products[order(years)]
years <- vapply(products, `[[`, integer(1), "year")
rasters <- lapply(products, `[[`, "raster")

for (i in seq_along(products)) {
  terra::writeRaster(
    rasters[[i]], file.path(raw_tif_dir, sprintf("%s_%d.tif", pollutant, years[i])), overwrite = TRUE
  )
}

overlap_extent <- common_extent(rasters)
# `snap = "in"` retains only complete cells within the overlap. This avoids
# partial edge cells and makes the resulting rasters directly comparable.
overlap_rasters <- lapply(rasters, terra::crop, y = overlap_extent, snap = "in")
reference <- overlap_rasters[[1L]]
for (i in seq_along(overlap_rasters)[-1L]) {
  if (!terra::compareGeom(reference, overlap_rasters[[i]], stopOnError = FALSE)) {
    stop("Rasters are not geometrically aligned after cropping; inspect grid origins.", call. = FALSE)
  }
}

for (i in seq_along(overlap_rasters)) {
  terra::writeRaster(
    overlap_rasters[[i]],
    file.path(overlap_tif_dir, sprintf("%s_%d_overlap.tif", pollutant, years[i])),
    overwrite = TRUE
  )
}

# Diagnostic maps ----------------------------------------------------------
plot_multipanel(
  overlap_rasters, years,
  file.path(plot_dir, paste0(pollutant, "_overlap_multipanel.png")),
  title_suffix = "Annual concentration: common scale"
)
plot_multipanel(
  overlap_rasters, years,
  file.path(plot_dir, paste0(pollutant, "_overlap_multipanel_log10.png")),
  title_suffix = "Annual concentration: common log10 scale",
  log10_scale = TRUE
)

# Change from the first available year. Layer one is the baseline level;
# subsequent layers show annual absolute differences in the native units.
raster_stack <- terra::rast(overlap_rasters)
baseline_year <- years[1L]
baseline <- raster_stack[[1L]]
differences <- raster_stack - baseline
names(differences) <- names(raster_stack)

difference_limit <- max(abs(c(
  terra::global(differences, "min", na.rm = TRUE)[, 1],
  terra::global(differences, "max", na.rm = TRUE)[, 1]
)))
difference_limit <- ceiling(difference_limit * 10) / 10

n_rows <- ceiling(terra::nlyr(raster_stack) / number_of_plot_columns)
grDevices::png(
  file.path(plot_dir, sprintf("%s_change_from_%d.png", pollutant, baseline_year)),
  width = 3600, height = 600 * n_rows, res = 200
)
graphics::par(mfrow = c(n_rows, number_of_plot_columns), mar = c(2, 2, 3, 1))
terra::plot(baseline, col = hcl.colors(30, "YlOrRd"), main = baseline_year,
            axes = FALSE, box = FALSE)
for (i in 2:terra::nlyr(differences)) {
  terra::plot(differences[[i]], col = hcl.colors(31, "Blue-Red 3"),
              zlim = c(-difference_limit, difference_limit), main = years[i],
              axes = FALSE, box = FALSE)
}
grDevices::dev.off()

message("Wrote raw GeoTIFFs to: ", raw_tif_dir)
message("Wrote aligned GeoTIFFs to: ", overlap_tif_dir)
message("Wrote diagnostic maps to: ", plot_dir)
