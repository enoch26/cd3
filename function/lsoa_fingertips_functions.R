# Generic LSOA 2021 Fingertips indicator workflow -----------------------------
#
# Maps England district-level Fingertips indicators to 2021 LSOAs using the
# official ONS LSOA 2011 -> LSOA 2021 -> LAD 2022 Exact Fit Lookup.
# Every LSOA in a LAD receives its LAD-level value: this is an allocation, not
# an independently estimated small-area indicator.
#
# Find and inspect IndicatorIDs, available geographies, and dimensions here:
# https://github.com/ropensci/fingertipsR
#
# Official lookup dataset:
# https://geoportal.statistics.gov.uk/datasets/ons::lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3/about

.lsoa_lookup_url <- paste0(
  "https://open-geography-portalx-ons.hub.arcgis.com/api/download/v1/items/",
  "cbfe64cc03d74af982c1afec639bafd1/csv?layers=0"
)

.require_lsoa_packages <- function() {
  packages <- c("dplyr", "tidyr", "fingertipsR")
  absent <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(absent)) {
    stop("Install required package(s): ", paste(absent, collapse = ", "), call. = FALSE)
  }
}

#' Download the ONS lookup if no valid local cache exists.
#'
#' @param path Local cache file.
#' @param overwrite Re-download even if a valid cache exists.
#' @param url Official ONS CSV endpoint.
#' @return Cache path, invisibly.
download_lsoa_lad_lookup <- function(
    path = file.path("data", "LSOA_2011_to_LSOA_2021_to_LAD_2022_Exact_Fit_Lookup_EW_V3.csv"),
    overwrite = FALSE,
    url = .lsoa_lookup_url) {
  
  required <- c("LSOA21CD", "LAD22CD")
  valid <- FALSE
  if (file.exists(path) && !overwrite) {
    header <- tryCatch(names(utils::read.csv(path, nrows = 1L, check.names = FALSE)),
                       error = function(e) character())
    valid <- all(required %in% header)
  }
  
  if (!valid) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    temporary <- paste0(path, ".download")
    on.exit(unlink(temporary), add = TRUE)
    utils::download.file(url, temporary, mode = "wb", quiet = FALSE)
    header <- names(utils::read.csv(temporary, nrows = 1L, check.names = FALSE))
    if (!all(required %in% header)) {
      stop("Downloaded lookup lacks LSOA21CD and LAD22CD.", call. = FALSE)
    }
    if (file.exists(path)) unlink(path)
    if (!file.rename(temporary, path)) stop("Could not cache lookup.", call. = FALSE)
  }
  invisible(path)
}

#' Read the distinct England LSOA 2021 to LAD 2022 lookup.
read_england_lsoa_lad_lookup <- function(path = download_lsoa_lad_lookup()) {
  .require_lsoa_packages()
  dplyr::as_tibble(utils::read.csv(path, check.names = FALSE)) |>
    dplyr::filter(substr(.data$LAD22CD, 1L, 1L) == "E") |>
    dplyr::transmute(
      LSOA21CD = as.character(.data$LSOA21CD),
      LAD22CD = as.character(.data$LAD22CD)
    ) |>
    dplyr::distinct()
}

#' Retrieve one England district-level Fingertips indicator.
#'
#' Consult https://github.com/ropensci/fingertipsR to identify a suitable
#' IndicatorID and inspect valid Sex, Age, AreaType, and Timeperiod values.
get_lad_indicator_data <- function(
    indicator_id,
    sex = "Persons",
    age = NULL,
    area_pattern = "Districts",
    area_type_id = "All",
    value_name = "indicator_value") {
  
  .require_lsoa_packages()
  raw <- fingertipsR::fingertips_data(
    IndicatorID = as.integer(indicator_id), AreaTypeID = area_type_id
  )
  required <- c("IndicatorID", "AreaType", "AreaCode", "Timeperiod", "Value")
  absent <- setdiff(required, names(raw))
  if (length(absent)) stop("Fingertips response lacks: ", paste(absent, collapse = ", "), call. = FALSE)
  
  result <- dplyr::as_tibble(raw) |>
    dplyr::filter(
      .data$IndicatorID == as.integer(indicator_id),
      grepl(area_pattern, .data$AreaType),
      substr(.data$AreaCode, 1L, 1L) == "E"
    )
  
  if (!is.null(sex)) {
    if (!"Sex" %in% names(result)) stop("No Sex column: set sex = NULL.", call. = FALSE)
    result <- dplyr::filter(result, .data$Sex == sex)
  }
  if (!is.null(age)) {
    if (!"Age" %in% names(result)) stop("No Age column: set age = NULL.", call. = FALSE)
    result <- dplyr::filter(result, .data$Age == age)
  }
  
  result <- result |>
    dplyr::transmute(
      Timeperiod = as.character(.data$Timeperiod),
      LAD22CD = as.character(.data$AreaCode),
      indicator_value = suppressWarnings(as.numeric(.data$Value))
    ) |>
    dplyr::distinct()
  
  duplicates <- result |>
    dplyr::count(.data$Timeperiod, .data$LAD22CD) |>
    dplyr::filter(.data$n > 1L)
  if (nrow(duplicates)) {
    stop("Multiple records remain per LAD/time period; refine sex, age, or area_pattern.", call. = FALSE)
  }
  if (!nrow(result)) stop("No England district records matched the filters.", call. = FALSE)
  names(result)[names(result) == "indicator_value"] <- value_name
  result
}

#' Allocate a LAD-level indicator to its constituent 2021 LSOAs.
#'
#' @param replacement_lads Named list: target LAD code = predecessor LAD codes.
#' @param england_mean_lads LADs to fill from the England unweighted LAD mean.
#' @param fill_within_lad Fill missing values from another period in the same LAD.
make_lsoa_indicator <- function(
    lookup_eng,
    indicator_data,
    value_name = "indicator_value",
    replacement_lads = list(),
    england_mean_lads = character(),
    fill_within_lad = FALSE,
    annual_pattern = "^[0-9]{4}$",
    wide_prefix = "indicator_") {
  
  .require_lsoa_packages()
  target_lads <- dplyr::distinct(lookup_eng, .data$LAD22CD)
  periods <- sort(unique(as.character(indicator_data$Timeperiod)))
  
  lad <- indicator_data |>
    dplyr::transmute(
      Timeperiod = as.character(.data$Timeperiod),
      LAD22CD = as.character(.data$LAD22CD),
      indicator_value = as.numeric(.data[[value_name]])
    ) |>
    dplyr::semi_join(target_lads, by = "LAD22CD") |>
    tidyr::complete(LAD22CD = target_lads$LAD22CD, Timeperiod = periods)
  
  for (target in names(replacement_lads)) {
    sources <- as.character(replacement_lads[[target]])
    replacement <- lad |>
      dplyr::filter(.data$LAD22CD %in% sources) |>
      dplyr::group_by(.data$Timeperiod) |>
      dplyr::summarise(replacement = mean(.data$indicator_value, na.rm = TRUE), .groups = "drop")
    lad <- lad |>
      dplyr::left_join(replacement, by = "Timeperiod") |>
      dplyr::mutate(indicator_value = dplyr::if_else(
        .data$LAD22CD == target & is.na(.data$indicator_value),
        .data$replacement, .data$indicator_value
      )) |>
      dplyr::select(-.data$replacement)
  }
  
  if (length(england_mean_lads)) {
    means <- lad |>
      dplyr::group_by(.data$Timeperiod) |>
      dplyr::summarise(england_mean = mean(.data$indicator_value, na.rm = TRUE), .groups = "drop")
    lad <- lad |>
      dplyr::left_join(means, by = "Timeperiod") |>
      dplyr::mutate(indicator_value = dplyr::if_else(
        .data$LAD22CD %in% england_mean_lads & is.na(.data$indicator_value),
        .data$england_mean, .data$indicator_value
      )) |>
      dplyr::select(-.data$england_mean)
  }
  
  if (fill_within_lad) {
    lad <- lad |>
      dplyr::arrange(.data$LAD22CD, .data$Timeperiod) |>
      dplyr::group_by(.data$LAD22CD) |>
      tidyr::fill(.data$indicator_value, .direction = "downup") |>
      dplyr::ungroup()
  }
  
  lsoa_long <- lookup_eng |>
    dplyr::left_join(lad, by = "LAD22CD") |>
    dplyr::arrange(.data$LSOA21CD, .data$Timeperiod)
  
  lsoa_wide <- lsoa_long |>
    dplyr::filter(grepl(annual_pattern, .data$Timeperiod)) |>
    dplyr::mutate(Timeperiod = paste0(wide_prefix, .data$Timeperiod)) |>
    dplyr::select(.data$LSOA21CD, .data$LAD22CD, .data$Timeperiod, .data$indicator_value) |>
    tidyr::pivot_wider(names_from = .data$Timeperiod, values_from = .data$indicator_value) |>
    dplyr::arrange(.data$LSOA21CD)
  
  names(lad)[names(lad) == "indicator_value"] <- value_name
  names(lsoa_long)[names(lsoa_long) == "indicator_value"] <- value_name
  value_columns <- setdiff(names(lsoa_wide), c("LSOA21CD", "LAD22CD"))
  names(lsoa_wide)[match(value_columns, names(lsoa_wide))] <- value_columns
  
  list(lad = lad, lsoa_long = lsoa_long, lsoa_wide = lsoa_wide)
}

#' Download, allocate, and optionally export any district-level indicator.
build_lsoa_indicator <- function(
    indicator_id,
    sex = "Persons",
    age = NULL,
    area_pattern = "Districts",
    area_type_id = "All",
    value_name = "indicator_value",
    replacement_lads = list(),
    england_mean_lads = character(),
    fill_within_lad = FALSE,
    output_directory = "data",
    export = TRUE) {
  
  lookup <- read_england_lsoa_lad_lookup()
  indicator <- get_lad_indicator_data(
    indicator_id, sex, age, area_pattern, area_type_id, value_name
  )
  output <- make_lsoa_indicator(
    lookup, indicator, value_name, replacement_lads, england_mean_lads,
    fill_within_lad, wide_prefix = paste0("indicator", indicator_id, "_")
  )
  
  if (export) {
    dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(output$lsoa_long,
                     file.path(output_directory, paste0("lsoa2021_indicator_", indicator_id, "_long.csv")),
                     row.names = FALSE
    )
    utils::write.csv(output$lsoa_wide,
                     file.path(output_directory, paste0("lsoa2021_indicator_", indicator_id, "_wide.csv")),
                     row.names = FALSE
    )
  }
  output
}

# Examples -----------------------------------------------------------------
# Find a suitable indicator and its available dimensions first:
# https://github.com/ropensci/fingertipsR
# fingertipsR::profiles()
# fingertipsR::indicators(ProfileID = 18L)
# fingertipsR::fingertips_data(IndicatorID = 92443L, AreaTypeID = "All")
#
# Example IndicatorIDs:
# indicator_ids <- c(
#   92763, 92772,                 # alcohol
#   92538, 92308,                 # smoking
#   93088, 93105, 93881, 94174, 94124, 93553 # obesity
# )
#
# Generic example (change Sex/Age after checking the indicator's dimensions):
# result <- build_lsoa_indicator(
#   indicator_id = 92443L,
#   sex = "Persons",
#   age = "18+ yrs",
#   replacement_lads = list(
#     E06000061 = c("E07000150", "E07000152", "E07000153", "E07000156"),
#     E06000062 = c("E07000151", "E07000154", "E07000155")
#   ),
#   england_mean_lads = c("E09000001", "E06000053"),
#   fill_within_lad = TRUE
# )
#
# Run multiple indicators, retaining only those with compatible dimensions:
# # outputs <- lapply(indicator_ids, function(id) {
# #   build_lsoa_indicator(id, sex = NULL, age = NULL)
# # })
