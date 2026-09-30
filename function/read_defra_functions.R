# DEFRA PCM annual pollutant raster workflow -----------------------------------
#
# Purpose
# -------
# Reusable functions for reading DEFRA PCM annual-mean model-output CSV files,
# converting their 1 km grid centroids to British National Grid rasters,
# writing GeoTIFFs, aligning them to a common overlap, and creating maps.
#
# Data source
# -----------
# Download annual PCM model-output CSV files from:
#   https://uk-air.defra.gov.uk/data/pcm-data
#
# Place each pollutant's CSV files in a directory such as:
#   data/defra/pm25/
#   data/defra/pm10/
#   data/defra/benzene/
#
# Model values are annual means in micrograms per cubic metre.
#
# Important
# ---------
# Check each downloaded file before comparing years. For example, the 2003
# benzene data may have a markedly higher maximum than later years, so assess
# its metadata, units, coverage, and values before interpreting temporal maps.
#
# Required packages
# -----------------
# install.packages(c("terra", "readr", "dplyr", "stringr"))
#
# Example
# -------
# source("read_defra_pollutant.R")
#
# process_defra_pollutants(
#   pollutants = c("pm25", "pm10", "benzene"),
#   data_root = here::here("data", "defra")
# )
#
# To process one pollutant:
# result <- process_defra_pollutant(
#   pollutant = "pm25",
#   data_root = here::here("data", "defra")
# )

.require_defra_packages <- function() {
  packages <- c("terra", "readr", "dplyr", "stringr")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Install required package(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

.draw_colour_legend <- function(zlim, colours, ticks, title) {
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = zlim)
  breaks <- seq(zlim[1], zlim[2], length.out = length(colours) + 1L)
  
  for (i in seq_along(colours)) {
    graphics::rect(0.18, breaks[i], 0.38, breaks[i + 1L],
                   col = colours[i], border = NA)
  }
  graphics::rect(0.18, zlim[1], 0.38, zlim[2], border = "black")
  graphics::axis(4, at = ticks, labels = format(round(ticks, 2), trim = TRUE),
                 las = 1, cex.axis = 0.9)
  graphics::mtext(title, side = 3, line = 0.5, cex = 0.95, font = 2)
}

#' Read one DEFRA PCM CSV as a 1 km raster
#'
#' The function expects the standard PCM layout: five metadata rows, followed
#' by data containing `x`, `y`, and a pollutant-value field in column four.
#'
#' @param path Path to a PCM CSV file.
#' @param resolution Grid-cell size in metres. Defaults to 1000.
#' @param crs Coordinate reference system for PCM coordinates.
#' @return A list containing a `SpatRaster`, year, metric-column name, and path.
#' @export
read_defra_pollutant_raster <- function(
    path,
    resolution = 1000,
    crs = "EPSG:27700") {
  
  .require_defra_packages()
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  
  metadata <- readr::read_csv(
    path, n_max = 5, col_names = FALSE, show_col_types = FALSE
  )
  year <- suppressWarnings(as.integer(metadata[[1]][2]))
  
  data <- readr::read_csv(
    path, skip = 5, na = "MISSING", show_col_types = FALSE
  )
  if (!all(c("x", "y") %in% names(data)) || ncol(data) < 4L) {
    stop("Expected x, y, and a value field in PCM CSV: ", path, call. = FALSE)
  }
  
  metric <- names(data)[4L]
  data <- data |>
    dplyr::mutate(
      x = suppressWarnings(as.numeric(.data$x)),
      y = suppressWarnings(as.numeric(.data$y)),
      "{metric}" := suppressWarnings(as.numeric(.data[[metric]]))
    ) |>
    dplyr::filter(!is.na(.data$x), !is.na(.data$y))
  
  if (!nrow(data)) stop("No valid PCM grid coordinates in: ", path, call. = FALSE)
  
  if (is.na(year)) {
    year <- suppressWarnings(as.integer(stringr::str_extract(
      basename(path), "(19|20)\\d{2}"
    )))
  }
  if (is.na(year)) stop("Could not determine year from file: ", path, call. = FALSE)
  
  template <- terra::rast(
    xmin = min(data$x) - resolution / 2,
    xmax = max(data$x) + resolution / 2,
    ymin = min(data$y) - resolution / 2,
    ymax = max(data$y) + resolution / 2,
    resolution = resolution,
    crs = crs
  )
  points <- terra::vect(data, geom = c("x", "y"), crs = crs)
  raster <- terra::rasterize(points, template, field = metric)
  names(raster) <- paste0("y", year)
  
  list(raster = raster, year = year, metric = metric, file = path)
}

#' Write common-scale annual-level and log-scale pollutant maps
#'
#' @param rasters List of aligned single-layer `SpatRaster` objects.
#' @param years Corresponding numeric years.
#' @param pollutant Pollutant name used in map titles and filenames.
#' @param output_dir Directory for PNG output.
#' @param ncol Number of map columns.
#' @return Invisibly returns the two PNG paths.
#' @export
plot_defra_pollutant_levels <- function(
    rasters, years, pollutant, output_dir, ncol = 4L) {
  
  .require_defra_packages()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  colours <- grDevices::hcl.colors(30, "YlOrRd")
  nrow <- ceiling(length(rasters) / ncol)
  
  make_plot <- function(plot_rasters, suffix, legend_title) {
    mins <- vapply(plot_rasters, function(x) terra::global(x, "min", na.rm = TRUE)[1, 1], numeric(1))
    maxs <- vapply(plot_rasters, function(x) terra::global(x, "max", na.rm = TRUE)[1, 1], numeric(1))
    zlim <- c(min(mins, na.rm = TRUE), max(maxs, na.rm = TRUE))
    ticks <- pretty(zlim, n = 5)
    ticks <- ticks[ticks >= zlim[1] & ticks <= zlim[2]]
    output <- file.path(output_dir, paste0(pollutant, suffix, ".png"))
    
    grDevices::png(output, width = 3600, height = 650 * nrow, res = 200)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::par(mfrow = c(nrow, ncol), mar = c(2, 2, 3, 1), oma = c(0, 0, 0, 16), xpd = NA)
    for (i in seq_along(plot_rasters)) {
      terra::plot(plot_rasters[[i]], col = colours, zlim = zlim, main = years[i],
                  axes = FALSE, box = FALSE, legend = FALSE)
    }
    graphics::par(fig = c(0.92, 0.96, 0.20, 0.80), new = TRUE, mar = c(0, 0, 0, 4))
    .draw_colour_legend(zlim, colours, ticks, legend_title)
    grDevices::dev.off()
    on.exit(NULL, add = FALSE)
    output
  }
  
  level_path <- make_plot(rasters, "_overlap_multipanel_commonlegend", paste0(pollutant, " (ug m-3)"))
  log_rasters <- lapply(rasters, function(x) terra::ifel(x > 0, log10(x), NA))
  log_path <- make_plot(log_rasters, "_overlap_multipanel_log10_commonlegend", paste0("log10 ", pollutant, " (ug m-3)"))
  invisible(c(level = level_path, log10 = log_path))
}

#' Plot baseline level and changes from that baseline
#'
#' @param stack Multi-layer aligned `SpatRaster`.
#' @param years Numeric years corresponding to stack layers.
#' @param pollutant Pollutant name used in the output filename.
#' @param output_dir Directory for PNG output.
#' @param ncol Number of map columns.
#' @return Invisibly returns the PNG path.
#' @export
plot_defra_pollutant_change <- function(
    stack, years, pollutant, output_dir, ncol = 4L) {
  
  .require_defra_packages()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  baseline <- stack[[1]]
  baseline_year <- years[1]
  differences <- stack - baseline
  
  zlim_base <- c(terra::global(baseline, "min", na.rm = TRUE)[1, 1],
                 terra::global(baseline, "max", na.rm = TRUE)[1, 1])
  range_diff <- c(terra::global(differences, "min", na.rm = TRUE)[, 1],
                  terra::global(differences, "max", na.rm = TRUE)[, 1])
  max_abs <- ceiling(max(abs(range_diff), na.rm = TRUE) * 10) / 10
  zlim_diff <- c(-max_abs, max_abs)
  
  n <- terra::nlyr(stack)
  nrow <- ceiling(n / ncol)
  nslots <- nrow * ncol
  layout_matrix <- matrix(0, nrow = nrow, ncol = ncol + 1L)
  layout_matrix[, seq_len(ncol)] <- matrix(seq_len(nslots), nrow = nrow, byrow = TRUE)
  layout_matrix[seq_len(max(1, ceiling(nrow / 2))), ncol + 1L] <- nslots + 1L
  if (nrow > 1L) layout_matrix[(ceiling(nrow / 2) + 1L):nrow, ncol + 1L] <- nslots + 2L
  
  output <- file.path(output_dir, paste0(pollutant, "_change_from_", baseline_year, "_baseline_plus_diff.png"))
  grDevices::png(output, width = 4800, height = 750 * nrow, res = 200)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::layout(layout_matrix, widths = c(rep(1, ncol), 0.6))
  graphics::par(mar = c(2, 2, 4, 1))
  terra::plot(baseline, col = grDevices::hcl.colors(30, "YlOrRd"), zlim = zlim_base,
              main = baseline_year, axes = FALSE, box = FALSE, legend = FALSE)
  if (n > 1L) for (i in 2:n) {
    terra::plot(differences[[i]], col = grDevices::hcl.colors(31, "Blue-Red 3"), zlim = zlim_diff,
                main = years[i], axes = FALSE, box = FALSE, legend = FALSE)
  }
  if (n < nslots) for (i in seq_len(nslots - n)) graphics::plot.new()
  graphics::par(mar = c(2, 1, 3, 4))
  .draw_colour_legend(zlim_base, grDevices::hcl.colors(30, "YlOrRd"), pretty(zlim_base, n = 5),
                      paste0(baseline_year, " level (ug m-3)"))
  graphics::par(mar = c(2, 1, 3, 4))
  .draw_colour_legend(zlim_diff, grDevices::hcl.colors(31, "Blue-Red 3"), pretty(zlim_diff, n = 5),
                      paste0("Change from ", baseline_year, " (ug m-3)"))
  grDevices::dev.off()
  on.exit(NULL, add = FALSE)
  invisible(output)
}

#' Process annual CSV files for one DEFRA PCM pollutant
#'
#' @param pollutant Folder name below `data_root`, for example `"pm25"`.
#' @param data_root Parent directory containing pollutant folders.
#' @param resolution PCM grid-cell size in metres.
#' @param make_plots Whether to write level, log-scale, and change maps.
#' @return A list with years, aligned raster stack, files, and output paths.
#' @export
process_defra_pollutant <- function(
    pollutant,
    data_root = file.path(getwd(), "data", "defra"),
    resolution = 1000,
    make_plots = TRUE) {
  
  .require_defra_packages()
  input_dir <- file.path(data_root, pollutant)
  if (!dir.exists(input_dir)) stop("Pollutant directory not found: ", input_dir, call. = FALSE)
  files <- list.files(input_dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) stop("No CSV files found in: ", input_dir, call. = FALSE)
  
  objects <- lapply(files, read_defra_pollutant_raster, resolution = resolution)
  years <- vapply(objects, `[[`, numeric(1), "year")
  if (anyDuplicated(years)) stop("More than one CSV resolved to the same year.", call. = FALSE)
  objects <- objects[order(years)]
  years <- sort(years)
  rasters <- lapply(objects, `[[`, "raster")
  
  geotiff_dir <- file.path(input_dir, "geotiff")
  overlap_dir <- file.path(input_dir, "geotiff_overlap")
  plot_dir <- file.path(input_dir, "plots")
  dir.create(geotiff_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(overlap_dir, recursive = TRUE, showWarnings = FALSE)
  
  for (i in seq_along(rasters)) {
    terra::writeRaster(rasters[[i]], file.path(geotiff_dir, paste0(pollutant, "_", years[i], ".tif")), overwrite = TRUE)
  }
  
  extents <- lapply(rasters, terra::ext)
  common_extent <- terra::ext(
    max(vapply(extents, terra::xmin, numeric(1))), min(vapply(extents, terra::xmax, numeric(1))),
    max(vapply(extents, terra::ymin, numeric(1))), min(vapply(extents, terra::ymax, numeric(1)))
  )
  aligned <- lapply(rasters, function(x) terra::crop(x, common_extent))
  reference <- aligned[[1]]
  if (length(aligned) > 1L && any(!vapply(aligned[-1], terra::compareGeom, logical(1), y = reference, stopOnError = FALSE))) {
    stop("Cropped rasters do not have identical geometry; inspect source grids.", call. = FALSE)
  }
  
  for (i in seq_along(aligned)) {
    terra::writeRaster(aligned[[i]], file.path(overlap_dir, paste0(pollutant, "_", years[i], "_overlap.tif")), overwrite = TRUE)
  }
  stack <- terra::rast(aligned)
  names(stack) <- paste0("y", years)
  
  plot_paths <- character()
  if (make_plots) {
    plot_paths <- c(
      plot_defra_pollutant_levels(aligned, years, pollutant, plot_dir),
      change = plot_defra_pollutant_change(stack, years, pollutant, plot_dir)
    )
  }
  invisible(list(pollutant = pollutant, years = years, stack = stack, files = files, plots = plot_paths))
}

#' Process multiple DEFRA PCM pollutant folders
#'
#' @param pollutants Character vector, for example `c("pm25", "pm10")`.
#' @param ... Further arguments passed to `process_defra_pollutant()`.
#' @return Named list of results, one item per pollutant.
#' @export
process_defra_pollutants <- function(pollutants, ...) {
  results <- lapply(pollutants, process_defra_pollutant, ...)
  names(results) <- pollutants
  invisible(results)
}
