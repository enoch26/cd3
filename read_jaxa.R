# https://suzaku.eorc.jaxa.jp/GLI/data/final/landpar/index.html
# https://kuroshio.eorc.jaxa.jp/JASMES/docs/PAR_Thai.html 
# Translate the Fortran77 direct-access unformatted read into R
# - Record 1: header stored as ASCII inside a fixed-length record
# - Records 2..(ml+1): each record is one row of nl int16 values (2 bytes each)
#
# IMPORTANT:
# 1) This assumes "true direct access": no Fortran sequential record markers.
# 2) Endianness matters. Try endian="little" first; if values look wrong, use "big".
# 3) The Fortran uses rec=1+m, i.e. it SKIPS record 1 (header) and starts data at record 2.

read_product <- function(path,
                         nl, ml,
                         header_chars = 1000,
                         header_record_bytes = nl * 2,  # header record is same length as a data record in your note
                         data_scale = 0.01, data_offset = 0.0,
                         endian = c("little", "big"),
                         skip_first_record = TRUE) {
  endian <- match.arg(endian)
  
  # Helper to parse the fixed-width header using the Fortran format:
  # (2i6,2f8.2,f8.4,2e12.5,a1,a8,a1,a40)
  parse_header <- function(head_str) {
    # Ensure we have enough characters for all fields; pad with spaces
    head_str <- sprintf("%-s", head_str)
    
    pos <- 1
    cut_field <- function(width) {
      s <- substr(head_str, pos, pos + width - 1)
      pos <<- pos + width
      s
    }
    
    npixel  <- as.integer(trimws(cut_field(6)))
    nline   <- as.integer(trimws(cut_field(6)))
    lon_min <- as.numeric(trimws(cut_field(8)))
    lat_max <- as.numeric(trimws(cut_field(8)))
    reso    <- as.numeric(trimws(cut_field(8)))
    slope   <- as.numeric(trimws(cut_field(12)))
    offset  <- as.numeric(trimws(cut_field(12)))
    comma1  <- cut_field(1)          # a1, usually ","
    para    <- trimws(cut_field(8))  # a8
    comma2  <- cut_field(1)          # a1, usually ","
    outfile <- trimws(cut_field(40)) # a40
    
    list(npixel=npixel, nline=nline, lon_min=lon_min, lat_max=lat_max,
         reso=reso, slope=slope, offset=offset,
         comma1=comma1, para=para, comma2=comma2, outfile=outfile)
  }
  
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  
  # ---- Read header: record 1 ----
  # Seek to start of record 1 (0 bytes from start)
  seek(con, where = 0, origin = "start")
  
  # Read the whole fixed-length record, then take the first `header_chars` as the header text.
  # (If your header is shorter/longer, adjust header_chars.)
  head_raw <- readBin(con, what = "raw", n = header_record_bytes)
  head_txt <- rawToChar(head_raw[seq_len(min(length(head_raw), header_chars))])
  
  hdr <- parse_header(head_txt)
  
  # ---- Read data records: records 2..(ml+1) in Fortran, i.e. rec=1+m ----
  recl_bytes <- nl * 2
  start_rec <- if (skip_first_record) 2L else 1L
  
  # Allocate: Fortran i2buf(nl,ml). In R we’ll store as matrix [nl x ml]
  i2buf <- matrix(NA_integer_, nrow = nl, ncol = ml)
  
  for (m in seq_len(ml)) {
    rec <- start_rec + (m - 1L)              # Fortran record number
    offset_bytes <- (rec - 1L) * recl_bytes  # 0-based byte offset
    
    seek(con, where = offset_bytes, origin = "start")
    
    # signed=TRUE gives int16, size=2 reads 2-byte integers
    row <- readBin(con, what = "integer", n = nl, size = 2, signed = TRUE, endian = endian)
    if (length(row) != nl) stop(sprintf("Unexpected EOF at m=%d (record %d)", m, rec))
    
    i2buf[, m] <- row
  }
  
  # Convert to physical units (matches your Fortran examples)
  # par = raw * 0.01 + 0.0
  par <- i2buf * data_scale + data_offset
  
  # Return everything
  list(header = hdr, raw = i2buf, par = par)
}


# ---------------- Example usage ----------------



# MYD: Aqua MODIS, MOD: Terra MODIS
# - Data size:
# MODIS: 2880byte header + 2byte x 1440(pixel) x 721(line)
# - Grid:
# MODIS: upper-left grid location (grid center): 90N, 0E;  grid interbal: 0.25 deg
# MODIS / SeaWiFS:
# swr__le : daily mean shortwave radiation [W/m^2] = DN * 0.10000E-01
# nl <- 1440; ml <- 721

path <- "./data/jaxa_swr/2003/MOD02SSH_A20030101Avh_v811_7200_3601_swr__le/MOD02SSH_A20030101Avh_v811_7200_3601_swr__le"
# for some reason, readme say this
# nl <- 3601; ml <- 7200
# Choose grid:
# SWR:
# but actually this looks more plausible
ml <- 3601
nl <- 7200


# PAR example (scale 0.01):
# or swr=i2buf(n,m)*0.01+0.0 (MODIS and SeaWiFS)
out <- read_product(path, nl, ml, data_scale = 0.01, data_offset = 0.0, endian = "little")

# png("filename.png")
# plot(out$par)
# dev.off()

# If you want SWR instead:
# GLI uses 0.02; MODIS/SeaWiFS uses 0.01

# modis_param <- 0.02
# swr_gli <- out$raw * modis_param + 0.0

# Printing every pixel is enormous; here’s how to inspect a few:
cat("Header para:", out$header$para, "\n")
cat("SWR (GLI) sample [n=1..5, m=1]:\n")
print(out$par[1:5, 1])


swr <- t(out$par)

r <- rast(swr)
# if it’s lon/lat global grid, you likely also want:
# ext(r) <- c(-180, 180, -90, 90)
# crs(r) <- "EPSG:4326"

plot(r)

# lets cont ----------------------------------------------------------------

res <- 0.05
lon_ul <- 0
lat_ul <- 90

xmin <- lon_ul - res/2
ymax <- lat_ul + res/2
xmax <- xmin + ncol(r) * res
ymin <- ymax - nrow(r) * res

ext(r) <- ext(xmin, xmax, ymin, ymax)
crs(r) <- "EPSG:4326"
r_180 <- rotate(r)

plot(r_180)

library(geodata)

# import a world countries map:
countries <- world(resolution = 5, path = "maps") 

plot(r_180, col = hcl.colors(256, "viridis"), axes = TRUE)
plot(countries, add = TRUE, col = NA, border = "black", lwd = 2)

# im not sure now 
ggplot() + geom_spatraster(data = r) +
  geom_sf(data = countries, fill = NA, color = "black", size = 0.1) +
  scale_fill_viridis_c(option = "C")


# here comes the problem --------------------------------------------------

gb <- {st_read("./data/Countries_December_2021_UK_BUC_2022_6943641446890634176/CTRY_DEC_2021_UK_BUC.shp")} 

gb_4326 <- gb %>% st_transform(crs = st_crs(r_180))

ggplot() + geom_spatraster(data = r) +
  geom_sf(data = gb_4326, fill = NA, color = "black", size = 0.1) +
  scale_fill_viridis_c(option = "C")

# add world ---------------------------------------------------------------

world <- st_read("./data/World_Countries_(Generalized)_-573431906301700955/World_Countries_Generalized.shp") %>% st_transform(crs = st_crs(r))

# Fill values; terra stores from top row to bottom row, which matches lat=90..-90
values(r) <- as.vector(swr)   # note: t() to go row-by-row into the raster
ggplot() + geom_spatraster(data = r) +
  # geom_sf(data = world, fill = NA, color = "black", size = 0.1) +
  scale_fill_viridis_c(option = "C")
ggsave("./outputs/swr_modis.pdf")
ggsave("./outputs/swr_modis.png")

png("filename.png")
plot(r, col = hcl.colors(100, "YlOrRd"), main = "Daily SWR (MODIS)")
dev.off()
 