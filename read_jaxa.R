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

# Choose grid:
# GLI:
nl <- 7200; ml <- 3601
# MODIS / SeaWiFS:
# nl <- 1440; ml <- 721

path <- "./data/jaxa_swr/2000/MOD02SSH_A20000224Av6_v601_7200_3601_swr__le/MOD02SSH_A20000224Av6_v601_7200_3601_swr__le"

# PAR example (scale 0.01):
out <- read_product(path, nl, ml, data_scale = 0.01, data_offset = 0.0, endian = "little")

# If you want SWR instead:
# GLI uses 0.02; MODIS/SeaWiFS uses 0.01
swr_gli <- out$raw * 0.02 + 0.0

# Printing every pixel is enormous; here’s how to inspect a few:
cat("Header para:", out$header$para, "\n")
cat("PAR sample [n=1..5, m=1]:\n")
print(out$par[1:5, 1])
cat("SWR (GLI) sample [n=1..5, m=1]:\n")
print(swr_gli[1:5, 1])
