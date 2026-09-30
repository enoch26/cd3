# =========================================================
# Robust ozone extraction to LSOA polygons, parallel by year
# Data source:
#   https://uk-air.defra.gov.uk/data/pcm-data
# - safer for HPC / sf / terra
# - uses multisession, not multicore
# - writes one GPKG per completed year
# - writes one PNG per completed year
# - tryCatch prevents one failed year killing all
# =========================================================

# -----------------------------
# packages
# -----------------------------
library(sf)
library(terra)
library(here)
library(parallelly)
library(future)
library(ggplot2)
source("lsoa11221.R")
# -----------------------------
# parallel setup
# -----------------------------
options(
  parallelly.availableCores.methods = c(
    "cgroups.cpuset",
    "nproc",
    "/proc/self/status",
    "system"
  ),
  future.globals.maxSize = 8 * 1024^3
)

# use fewer than max for stability
n_workers <- min(4, parallelly::availableCores())
message("Workers used by this R session: ", n_workers)

if (n_workers > 1) {
  future::plan(future::multisession, workers = n_workers)
  message("Running with multisession on ", n_workers, " workers")
} else {
  future::plan(future::sequential)
  message("Only 1 worker available")
}

# -----------------------------
# user inputs
# -----------------------------
data_dir <- file.path(here::here(), "data", "defra")
out_dir  <- here::here("ozone_lsoa_yearly")
plot_dir <- file.path(out_dir, "png")
rds_dir  <- file.path(out_dir, "rds")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(rds_dir, recursive = TRUE, showWarnings = FALSE)

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

# ---------------------------------------------------
# assumes poly_lsoa_21 already exists in your session
# ---------------------------------------------------
if (!exists("poly_lsoa_21")) {
  stop("Object `poly_lsoa_21` not found in the current environment.")
}

if (!inherits(poly_lsoa_21, "sf")) {
  stop("`poly_lsoa_21` must be an sf object.")
}

# -----------------------------
# checks and geometry prep
# -----------------------------
if (is.na(sf::st_crs(poly_lsoa_21))) {
  stop("`poly_lsoa_21` has no CRS.")
}

if (sf::st_crs(poly_lsoa_21)$epsg != 27700) {
  message("Transforming polygons to EPSG:27700 ...")
  poly_lsoa_21 <- sf::st_transform(poly_lsoa_21, 27700)
}

invalid_n <- sum(!sf::st_is_valid(poly_lsoa_21))
if (invalid_n > 0) {
  message("Making ", invalid_n, " invalid polygon(s) valid ...")
  poly_lsoa_21 <- sf::st_make_valid(poly_lsoa_21)
}

# -----------------------------
# helper: read one ozone file
# -----------------------------
read_ozone_csv_as_raster <- function(f) {
  dat <- read.csv(
    f,
    skip = 5,
    header = FALSE,
    na.strings = "MISSING",
    stringsAsFactors = FALSE
  )
  
  dat <- dat[-1, , drop = FALSE]
  
  if (ncol(dat) < 4) {
    stop(sprintf("File %s: expected at least 4 columns, got %s", f, ncol(dat)))
  }
  
  names(dat)[1:4] <- c("gridcode", "x", "y", "value")
  dat <- dat[, 1:4, drop = FALSE]
  
  dat$x <- as.numeric(dat$x)
  dat$y <- as.numeric(dat$y)
  dat$value <- as.numeric(dat$value)
  
  dat <- dat[!is.na(dat$x) & !is.na(dat$y), , drop = FALSE]
  
  if (nrow(dat) == 0) {
    stop(sprintf("File %s has no usable x/y rows after cleaning.", f))
  }
  
  terra::rast(dat[, c("x", "y", "value")], type = "xyz", crs = "EPSG:27700")
}

# -----------------------------
# helper: save one png
# -----------------------------
save_ozone_plot <- function(x, value_col, year, plot_file) {
  p <- ggplot2::ggplot(x) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[value_col]]), color = NA) +
    ggplot2::scale_fill_viridis_c(
      option = "C",
      na.value = "grey85",
      name = paste0("Ozone ", year)
    ) +
    ggplot2::labs(
      title = paste("LSOA ozone exposure", year),
      subtitle = value_col
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "right"
    )
  
  ggplot2::ggsave(
    filename = plot_file,
    plot = p,
    width = 8,
    height = 10,
    dpi = 300
  )
}

# -----------------------------
# helper: extract one year safely
# -----------------------------
extract_ozone_year <- function(i, files, data_dir, poly_sf) {
  tryCatch({
    yr <- 2002 + i
    f <- file.path(data_dir, "ozone", files[i])
    
    message("Year ", yr, ": reading ", basename(f))
    
    if (!file.exists(f)) {
      stop(sprintf("Year %s: file not found: %s", yr, f))
    }
    
    # create terra objects inside worker
    poly_vect <- terra::vect(poly_sf)
    r <- read_ozone_csv_as_raster(f)
    
    # 1) weighted exact mean
    vals <- terra::extract(
      r, poly_vect,
      fun = mean,
      na.rm = TRUE,
      ID = FALSE,
      weights = TRUE,
      exact = TRUE
    )[[1]]
    
    # 2) fallback unweighted mean
    miss1 <- is.na(vals)
    if (any(miss1)) {
      vals[miss1] <- terra::extract(
        r, poly_vect[miss1],
        fun = mean,
        na.rm = TRUE,
        ID = FALSE
      )[[1]]
    }
    
    # 3) fallback centroid value
    miss2 <- is.na(vals)
    if (any(miss2)) {
      cent <- sf::st_centroid(poly_sf[miss2, ])
      vals[miss2] <- terra::extract(
        r,
        terra::vect(cent),
        ID = FALSE
      )[[1]]
    }
    
    list(
      ok = TRUE,
      year = yr,
      values = vals,
      n_na = sum(is.na(vals)),
      error = NULL
    )
  }, error = function(e) {
    list(
      ok = FALSE,
      year = 2002 + i,
      values = NULL,
      n_na = NA_integer_,
      error = conditionMessage(e)
    )
  })
}

# -----------------------------
# launch one future per year
# -----------------------------
futs <- lapply(seq_along(files), function(i) {
  future::future(
    extract_ozone_year(
      i = i,
      files = files,
      data_dir = data_dir,
      poly_sf = poly_lsoa_21
    ),
    seed = TRUE
  )
})

done <- rep(FALSE, length(futs))
summary_list <- vector("list", length(futs))

# -----------------------------
# collect results as they finish
# -----------------------------
while (!all(done)) {
  for (j in seq_along(futs)) {
    if (!done[j] && future::resolved(futs[[j]])) {
      res <- future::value(futs[[j]])
      done[j] <- TRUE
      summary_list[[j]] <- res
      
      if (!isTRUE(res$ok)) {
        message("Year ", res$year, " failed: ", res$error)
        next
      }
      
      yr_col <- paste0("ozone", res$year)
      
      out_sf <- poly_lsoa_21
      out_sf[[yr_col]] <- res$values
      
      gpkg_file <- file.path(
        out_dir,
        paste0("ozone_lsoa_eng_", res$year, ".gpkg")
      )
      
      png_file <- file.path(
        plot_dir,
        paste0("ozone_lsoa_eng_", res$year, ".png")
      )
      
      rds_file <- file.path(
        rds_dir,
        paste0("ozone_lsoa_eng_", res$year, ".rds")
      )
      
      message("Completed ", yr_col, "; remaining NAs = ", res$n_na)
      
      # write gpkg
      message("Writing ", gpkg_file)
      if (file.exists(gpkg_file)) {
        file.remove(gpkg_file)
      }
      sf::st_write(
        out_sf,
        gpkg_file,
        delete_dsn = TRUE,
        quiet = FALSE
      )
      
      # save png
      message("Saving plot ", png_file)
      save_ozone_plot(
        x = out_sf,
        value_col = yr_col,
        year = res$year,
        plot_file = png_file
      )
      
      # save rds checkpoint
      saveRDS(out_sf, rds_file)
      message("Saved checkpoint ", rds_file)
      
      # clean up
      rm(out_sf)
      invisible(gc())
    }
  }
  
  Sys.sleep(1)
}

# -----------------------------
# summary
# -----------------------------
summary_df <- data.frame(
  year = vapply(summary_list, function(x) x$year, integer(1)),
  ok   = vapply(summary_list, function(x) isTRUE(x$ok), logical(1)),
  n_na = vapply(summary_list, function(x) {
    if (is.null(x$n_na)) NA_integer_ else x$n_na
  }, integer(1)),
  error = vapply(summary_list, function(x) {
    if (is.null(x$error)) NA_character_ else ifelse(is.null(x$error), NA_character_, x$error)
  }, character(1))
)

summary_df <- summary_df[order(summary_df$year), ]
print(summary_df)

message("Done.")
message("GPKG files: ", out_dir)
message("PNG files: ", plot_dir)
message("RDS checkpoints: ", rds_dir)
