# JAXA GLI / MODIS / SeaWiFS SWR and PAR binary-grid reader ------------------
#
# Purpose:
#   Read JAXA EORC Level-3 direct-access, unformatted binary files, convert
#   digital numbers to physical units, build a longitude/latitude SpatRaster,
#   and optionally export a GeoTIFF and PNG map for every file.
#
# Data and format documentation:
#   https://suzaku.eorc.jaxa.jp/GLI/data/final/landpar/index.html
#   https://kuroshio.eorc.jaxa.jp/JASMES/docs/PAR_Thai.html
#
# Assumptions for MOD02SSH / MYD02SSH SWR files named `*_7200_3601_swr__le`:
#   * 2,880-byte ASCII header;
#   * 7,200 longitude pixels by 3,601 latitude lines;
#   * signed, 16-bit integer values; and
#   * direct-access binary layout, with NO Fortran sequential record markers.
#
# The native grid has centres beginning at 0 degrees E and 90 degrees N,
# at 0.05-degree resolution. It is converted from 0–360 degrees longitude to
# -180–180 degrees longitude with terra::rotate().
#
# Important:
#   Confirm the dimensions, header size, byte order, scale factor, and missing
#   value convention against the readme supplied with the particular product.
#   If values are implausible, first try `endian = "big"`.

# Packages -----------------------------------------------------------------
library(terra)
library(here)

# Configuration ------------------------------------------------------------
# `here::here()` makes all paths relative to the root of the R project.
input_dir <- here::here("data", "jaxa_swr")
output_dir <- here::here("outputs", "swr")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# MODIS / SeaWiFS SWR product settings. Change these for another product.
grid_ncol <- 7200L
grid_nrow <- 3601L
header_bytes <- 2880L
cell_size <- 0.05
scale_factor <- 0.01
add_offset <- 0
byte_order <- "little"
missing_raw_values <- integer(0)  # e.g., c(-9999) if documented for a product

# Fixed-width header parser -------------------------------------------------
# The documented Fortran layout is:
# (2I6, 2F8.2, F8.4, 2E12.5, A1, A8, A1, A40)
parse_jaxa_header <- function(header_text) {
  position <- 1L
  
  take_field <- function(width) {
    field <- substr(header_text, position, position + width - 1L)
    position <<- position + width
    trimws(field)
  }
  
  as_number <- function(x) {
    # Supports Fortran-style D exponents as well as E exponents.
    as.numeric(gsub("[dD]", "E", x))
  }
  
  list(
    npixel = as.integer(take_field(6L)),
    nline = as.integer(take_field(6L)),
    lon_min = as_number(take_field(8L)),
    lat_max = as_number(take_field(8L)),
    resolution = as_number(take_field(8L)),
    slope = as_number(take_field(12L)),
    offset = as_number(take_field(12L)),
    separator_1 = take_field(1L),
    parameter = take_field(8L),
    separator_2 = take_field(1L),
    output_name = take_field(40L)
  )
}

# Binary reader -------------------------------------------------------------
# Reads all image values after the fixed-length header. `raw` is returned as a
# matrix with rows from north to south and columns from west to east.
read_jaxa_product <- function(path,
                              ncol = grid_ncol,
                              nrow = grid_nrow,
                              header_nbytes = header_bytes,
                              scale = scale_factor,
                              offset = add_offset,
                              endian = c("little", "big"),
                              missing_values = integer(0)) {
  endian <- match.arg(endian)
  
  if (!file.exists(path)) {
    stop("Input file was not found: ", path, call. = FALSE)
  }
  
  bytes_per_value <- 2L
  expected_bytes <- header_nbytes + ncol * nrow * bytes_per_value
  actual_bytes <- file.info(path)$size
  if (actual_bytes < expected_bytes) {
    stop(
      sprintf(
        "File is too small (%s bytes). Expected at least %s bytes for a %d x %d grid plus header.",
        format(actual_bytes, big.mark = ","),
        format(expected_bytes, big.mark = ","),
        ncol,
        nrow
      ),
      call. = FALSE
    )
  }
  if (actual_bytes > expected_bytes) {
    warning(
      "File is larger than expected; check `header_nbytes`, grid dimensions, and format assumptions.",
      call. = FALSE
    )
  }
  
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  
  # Read the full first record as text. `multiple = TRUE` prevents embedded
  # null bytes from truncating conversion if a header has trailing padding.
  header_raw <- readBin(connection, what = "raw", n = header_nbytes)
  header_text <- rawToChar(header_raw, multiple = FALSE)
  header <- parse_jaxa_header(header_text)
  
  # The remaining bytes are signed 16-bit DNs. R fills matrices down columns,
  # whereas the file is organised as consecutive image rows. Read a vector,
  # make a [longitude x latitude] matrix, then transpose it to [latitude x
  # longitude], preserving north-to-south file order.
  raw_vector <- readBin(
    connection,
    what = "integer",
    n = ncol * nrow,
    size = bytes_per_value,
    signed = TRUE,
    endian = endian
  )
  
  if (length(raw_vector) != ncol * nrow) {
    stop("Unexpected end of file while reading raster values.", call. = FALSE)
  }
  
  raw_matrix <- t(matrix(raw_vector, nrow = ncol, ncol = nrow))
  if (length(missing_values) > 0L) {
    raw_matrix[raw_matrix %in% missing_values] <- NA_integer_
  }
  
  list(
    header = header,
    raw = raw_matrix,
    values = raw_matrix * scale + offset
  )
}

# Raster constructor --------------------------------------------------------
# The coordinates supplied are the centre coordinates of the upper-left cell.
make_jaxa_raster <- function(value_matrix,
                             resolution = cell_size,
                             upper_left_lon = 0,
                             upper_left_lat = 90) {
  raster <- terra::rast(value_matrix)
  
  xmin <- upper_left_lon - resolution / 2
  ymax <- upper_left_lat + resolution / 2
  xmax <- xmin + terra::ncol(raster) * resolution
  ymin <- ymax - terra::nrow(raster) * resolution
  
  terra::ext(raster) <- terra::ext(xmin, xmax, ymin, ymax)
  terra::crs(raster) <- "EPSG:4326"
  
  # Convert native 0–360 longitude to conventional -180–180 longitude.
  terra::rotate(raster)
}

# Locate source files -------------------------------------------------------
# Each JAXA data file has no extension and ends with the product identifier.
# Amend the pattern if your downloaded file names differ.
product_files <- list.files(
  input_dir,
  pattern = "MOD02SSH_.*_7200_3601_swr__le$",
  full.names = TRUE,
  recursive = TRUE
)

if (length(product_files) == 0L) {
  stop("No MOD02SSH SWR files found below: ", input_dir, call. = FALSE)
}

# Process every daily file --------------------------------------------------
# Set `write_png` to FALSE when only GeoTIFF output is needed.
write_png <- TRUE

for (product_file in product_files) {
  message("Reading: ", basename(product_file))
  
  product <- read_jaxa_product(
    path = product_file,
    ncol = grid_ncol,
    nrow = grid_nrow,
    header_nbytes = header_bytes,
    scale = scale_factor,
    offset = add_offset,
    endian = byte_order,
    missing_values = missing_raw_values
  )
  
  swr_raster <- make_jaxa_raster(product$values)
  file_stub <- basename(product_file)
  
  # GeoTIFF retains the numeric SWR values, coordinate system, and extent.
  geotiff_file <- file.path(output_dir, paste0(file_stub, "_swr.tif"))
  terra::writeRaster(swr_raster, geotiff_file, overwrite = TRUE)
  
  if (write_png) {
    png_file <- file.path(output_dir, paste0(file_stub, "_swr.png"))
    grDevices::png(png_file, width = 2200, height = 1200, res = 200)
    plot(
      swr_raster,
      col = hcl.colors(256, "viridis"),
      axes = TRUE,
      main = paste("Daily SWR:", file_stub)
    )
    grDevices::dev.off()
  }
  
  message(
    "  Header parameter: ", product$header$parameter,
    "; output: ", basename(geotiff_file)
  )
}

# Optional: inspect one output ---------------------------------------------
# example <- read_jaxa_product(product_files[[1L]])
# print(example$header)
# print(example$values[1:5, 1:5])
# plot(make_jaxa_raster(example$values))

# Notes --------------------------------------------------------------------
# * For GLI SWR, use the product-specific scale (often 0.02) rather than 0.01.
# * For PAR, use its documented scale and units rather than assuming SWR units.
# * Add country outlines only after transforming vectors to EPSG:4326:
#
#   library(sf)
#   countries <- geodata::world(resolution = 5, path = here::here("maps"))
#   countries <- st_transform(countries, "EPSG:4326")
#   plot(swr_raster)
#   plot(vect(countries), add = TRUE, col = NA, border = "black")
#
# * Do not use `here(data_dir, ...)` when `data_dir` is already an absolute
#   path generated by `here::here()`. Use `file.path(data_dir, ...)` instead.
