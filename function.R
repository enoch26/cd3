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