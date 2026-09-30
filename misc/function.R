# functions

# files: files to be read
# year: extract which years

files_for_year <- function(files, year) {
  # year must be 4 digits
  yr <- sprintf("%04d", as.integer(year))
  # adjust pattern if needed (here: any occurrence of 4-digit year)
  matches <- grepl(yr, basename(files))
  files[matches]
}

make_map <- function(r, code, unit) {
  # Check if log10 is safe (all values > 0)
  rng <- terra::global(r, range, na.rm = TRUE)
  use_log <- is.finite(rng[1,1]) && rng[1,1] > 0
  
  ggplot() +
    geom_spatraster(data = r) +
    scale_fill_viridis_c(
      option = "magma",
      trans  = if (use_log) "log10" else "identity",
      name   = if (use_log) bquote(.(code) ~ log[10]*"("*.(unit)*")") else paste0(code, " (", unit, ")"),
      na.value = "transparent"
      # labels = label_number(accuracy = 1)
    ) 
    # coord_equal() +
    # theme_minimal() +
    # theme(panel.grid = element_blank())
}
