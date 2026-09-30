# Parallel annual ozone extraction to 2021 English LSOAs ----------------------
#
# Purpose:
#   Read annual DEFRA PCM ozone CSV grids, calculate LSOA-level mean exposure,
#   and write a GeoPackage, PNG map and RDS checkpoint for each completed year.
#
# Data source:
#   https://uk-air.defra.gov.uk/data/pcm-data
#
# Expected project layout:
#   <project root>/
#   ├── build_lsoa_ozone_exposure_parallel.R
#   ├── lsoa11221.R                         # creates `poly_lsoa_21`
#   └── data/
#       └── defra/
#           └── ozone/
#               ├── mapdaysgt12003_2.csv
#               ├── mapdgt12004.csv
#               └── ...
#
# Method:
#   * Each annual grid is converted from x/y/value rows to a 1 km SpatRaster
#     in British National Grid (EPSG:27700).
#   * The primary estimate is an exact, cell-coverage-weighted polygon mean.
#   * Where no raster cells overlap an LSOA, a regular polygon mean is tried,
#     followed by the value at the LSOA centroid.
#   * Years are processed in separate multisession workers. File writing occurs
#     in the main R session after each worker completes, avoiding concurrent
#     writes to GeoPackages or graphics devices.
#
# Important:
#   The exact extraction requires the `exactextractr` package through terra.
#   Review any remaining missing values in `ozone_extraction_summary.csv` before
#   analysis. Centroid fallback values are not area-weighted estimates.

# Packages ------------------------------------------------------------------
required_packages <- c("sf", "terra", "here", "future", "parallelly", "ggplot2", "readr")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing_packages) > 0L) install.packages(missing_packages)
invisible(lapply(required_packages, library, character.only = TRUE))

# Parallel configuration ----------------------------------------------------
# `multisession` uses independent R sessions and is generally safer than
# multicore processing for sf/GEOS/GDAL/terra workflows and on HPC systems.
options(
  parallelly.availableCores.methods = c(
    "cgroups.cpuset", "nproc", "/proc/self/status", "system"
  ),
  future.globals.maxSize = 8 * 1024^3
)

maximum_workers <- 4L
n_workers <- min(maximum_workers, parallelly::availableCores())
future::plan(
  if (n_workers > 1L) future::multisession else future::sequential,
  workers = if (n_workers > 1L) n_workers else NULL
)
on.exit(future::plan(future::sequential), add = TRUE)
message("Workers used by this R session: ", n_workers)

# Paths and annual source files --------------------------------------------
# `lsoa11221.R` must create `poly_lsoa_21`, an sf object of 2021 English LSOA
# polygons with an `LSOA21CD` field.
source(here::here("lsoa11221.R"))

data_dir <- here::here("data", "defra", "ozone")
output_dir <- here::here("outputs", "ozone_lsoa_yearly")
plot_dir <- file.path(output_dir, "png")
rds_dir <- file.path(output_dir, "rds")
summary_file <- file.path(output_dir, "ozone_extraction_summary.csv")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(rds_dir, recursive = TRUE, showWarnings = FALSE)

# The source file names are irregular, so retain an explicit year-to-file map.
ozone_files <- data.frame(
  year = 2003:2024,
  file = c(
    "mapdaysgt12003_2.csv", "mapdgt12004.csv", "mapdgt120_2005r.csv",
    "mapdgt120_06.csv", "mapdgt120_07.csv", "mapdgt120_08.csv",
    "mapdgt120_09.csv", "mapdgt120_10.csv", "mapdgt120_11.csv",
    "mapdgt120_12.csv", "mapdgt12013.csv", "mapdgt12014.csv",
    "mapdgt12015.csv", "mapdgt12016.csv", "mapdgt12017.csv",
    "mapdgt12018.csv", "mapdgt12019.csv", "mapdgt12020.csv",
    "mapdgt12021.csv", "mapdgt12022.csv", "mapdgt12023.csv",
    "mapdgt12024.csv"
  ),
  stringsAsFactors = FALSE
)
ozone_files$path <- file.path(data_dir, ozone_files$file)

if (!dir.exists(data_dir)) stop("Ozone input directory not found: ", data_dir, call. = FALSE)

# Validate and prepare LSOA geometry ---------------------------------------
if (!exists("poly_lsoa_21") || !inherits(poly_lsoa_21, "sf")) {
  stop("`lsoa11221.R` must create `poly_lsoa_21` as an sf object.", call. = FALSE)
}
if (!"LSOA21CD" %in% names(poly_lsoa_21)) {
  stop("`poly_lsoa_21` must contain an `LSOA21CD` column.", call. = FALSE)
}
if (is.na(sf::st_crs(poly_lsoa_21))) stop("`poly_lsoa_21` has no CRS.", call. = FALSE)

# DEFRA PCM grid coordinates are expected in British National Grid metres.
poly_lsoa_21 <- sf::st_transform(poly_lsoa_21, 27700)
invalid <- !sf::st_is_valid(poly_lsoa_21)
if (any(invalid)) {
  message("Repairing ", sum(invalid), " invalid LSOA polygon(s) ...")
  poly_lsoa_21 <- sf::st_make_valid(poly_lsoa_21)
}

# Helpers -------------------------------------------------------------------
read_ozone_csv_as_raster <- function(path, cell_resolution_metres = 1000) {
  # PCM CSV files have five metadata rows. The first apparent data row can be
  # a header-like record, so parse numbers and retain valid coordinates only.
  raw <- readr::read_csv(
    path,
    skip = 5L,
    col_names = FALSE,
    na = c("MISSING", "NA", ""),
    show_col_types = FALSE
  )
  if (ncol(raw) < 4L) {
    stop("Expected at least four columns in: ", basename(path), call. = FALSE)
  }
  
  dat <- data.frame(
    x = readr::parse_number(as.character(raw[[2L]])),
    y = readr::parse_number(as.character(raw[[3L]])),
    value = readr::parse_number(as.character(raw[[4L]]))
  )
  dat <- dat[!is.na(dat$x) & !is.na(dat$y), , drop = FALSE]
  if (nrow(dat) == 0L) stop("No usable x/y rows in: ", basename(path), call. = FALSE)
  if (anyDuplicated(dat[c("x", "y")])) stop("Duplicate x/y locations in: ", basename(path), call. = FALSE)
  
  template <- terra::rast(
    xmin = min(dat$x) - cell_resolution_metres / 2,
    xmax = max(dat$x) + cell_resolution_metres / 2,
    ymin = min(dat$y) - cell_resolution_metres / 2,
    ymax = max(dat$y) + cell_resolution_metres / 2,
    resolution = cell_resolution_metres,
    crs = "EPSG:27700"
  )
  points <- terra::vect(dat, geom = c("x", "y"), crs = "EPSG:27700")
  terra::rasterize(points, template, field = "value")
}

extract_ozone_year <- function(year, path, lsoa_sf) {
  # All terra objects are made inside the worker rather than passed between
  # processes. This is safer on network filesystems and HPC installations.
  tryCatch({
    if (!file.exists(path)) stop("Input file not found: ", path, call. = FALSE)
    message("Reading ozone grid for ", year, ": ", basename(path))
    
    raster <- read_ozone_csv_as_raster(path)
    lsoa_vect <- terra::vect(lsoa_sf)
    
    # `exact = TRUE` calculates coverage fractions for intersected grid cells.
    values <- terra::extract(
      raster, lsoa_vect, fun = mean, na.rm = TRUE, ID = FALSE, exact = TRUE
    )[[1L]]
    
    # Some small/coastal polygons may not overlap a valid raster cell. First
    # retry with terra's ordinary polygon extraction, then use centroid values.
    missing_after_exact <- is.na(values)
    if (any(missing_after_exact)) {
      values[missing_after_exact] <- terra::extract(
        raster, lsoa_vect[missing_after_exact], fun = mean, na.rm = TRUE, ID = FALSE
      )[[1L]]
    }
    
    missing_after_polygon <- is.na(values)
    if (any(missing_after_polygon)) {
      centroids <- sf::st_point_on_surface(lsoa_sf[missing_after_polygon, ])
      values[missing_after_polygon] <- terra::extract(
        raster, terra::vect(centroids), ID = FALSE
      )[[1L]]
    }
    
    list(ok = TRUE, year = year, values = values, n_na = sum(is.na(values)), error = NA_character_)
  }, error = function(error) {
    list(ok = FALSE, year = year, values = NULL, n_na = NA_integer_, error = conditionMessage(error))
  })
}

save_ozone_plot <- function(lsoa_sf, value_column, year, output_file) {
  map <- ggplot2::ggplot(lsoa_sf) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[value_column]]), colour = NA) +
    ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey85", name = "Ozone") +
    ggplot2::labs(title = paste("LSOA ozone exposure", year), subtitle = value_column) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "right"
    )
  ggplot2::ggsave(output_file, map, width = 8, height = 10, dpi = 300)
}

# Submit a job for each available year -------------------------------------
# Missing files return an error record rather than stopping all other years.
jobs <- lapply(seq_len(nrow(ozone_files)), function(index) {
  future::future(
    extract_ozone_year(
      year = ozone_files$year[index],
      path = ozone_files$path[index],
      lsoa_sf = poly_lsoa_21
    ),
    seed = TRUE
  )
})

# Collect outputs as each task completes -----------------------------------
completed <- rep(FALSE, length(jobs))
results <- vector("list", length(jobs))

while (!all(completed)) {
  for (index in seq_along(jobs)) {
    if (completed[index] || !future::resolved(jobs[[index]])) next
    
    result <- future::value(jobs[[index]])
    completed[index] <- TRUE
    results[[index]] <- result
    
    if (!isTRUE(result$ok)) {
      message("Year ", result$year, " failed: ", result$error)
      next
    }
    
    value_column <- paste0("ozone", result$year)
    yearly_lsoa <- poly_lsoa_21
    yearly_lsoa[[value_column]] <- result$values
    
    gpkg_file <- file.path(output_dir, paste0("ozone_lsoa_eng_", result$year, ".gpkg"))
    png_file <- file.path(plot_dir, paste0("ozone_lsoa_eng_", result$year, ".png"))
    rds_file <- file.path(rds_dir, paste0("ozone_lsoa_eng_", result$year, ".rds"))
    
    message("Completed ", value_column, "; remaining missing values: ", result$n_na)
    sf::st_write(yearly_lsoa, gpkg_file, delete_dsn = TRUE, quiet = TRUE)
    save_ozone_plot(yearly_lsoa, value_column, result$year, png_file)
    saveRDS(yearly_lsoa, rds_file)
    
    rm(yearly_lsoa)
    invisible(gc())
  }
  Sys.sleep(1)
}

# Completion report ---------------------------------------------------------
summary_df <- data.frame(
  year = vapply(results, `[[`, integer(1), "year"),
  ok = vapply(results, `[[`, logical(1), "ok"),
  n_missing = vapply(results, `[[`, integer(1), "n_na"),
  error = vapply(results, `[[`, character(1), "error")
)
summary_df <- summary_df[order(summary_df$year), ]
readr::write_csv(summary_df, summary_file)
print(summary_df)

message("Done. GeoPackages: ", output_dir)
message("PNG maps: ", plot_dir)
message("RDS checkpoints: ", rds_dir)
message("Summary: ", summary_file)
