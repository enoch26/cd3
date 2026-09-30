# LSOA, DEFRA, and NDVI Function Modules

This folder contains reusable R and Python modules for harmonising England LSOA data, retrieving and allocating OHID Fingertips indicators, aggregating LSOAs to MSOAs, processing DEFRA PCM annual pollutant rasters, and joining NDVI summaries to administrative boundaries.

## Modules

| File | Purpose |
|---|---|
| `lsoa_area_weight_functions.R` | Builds area-based correspondence weights between England LSOA 2001, 2011, and 2021 geography. |
| `lsoa_population_functions.R` | Produces a harmonised LSOA 2021 population time series from ONS small-area population-estimate workbooks. |
| `lsoa_fingertips_functions.R` | Retrieves a district-level OHID Fingertips indicator and allocates its LAD-level value to constituent LSOA 2021 areas. Despite the allocation, these are not independently estimated LSOA indicator values. |
| `lsoa_msoa_aggregation_functions.R` | Aggregates attributes attached to LSOA polygons to MSOA geography. |
| `read_defra_functions.R` | Reads DEFRA PCM annual model-output CSVs, creates British National Grid pollutant rasters, exports GeoTIFFs, aligns annual rasters to their common overlap, and writes comparison maps. |
| `join_ndvi_adm3.py` | Left-joins LTDR AVHRR NDVI summary statistics from a CSV to administrative boundary polygons, then writes GeoJSON or GeoPackage output. |

> **Important:** Area-weighted transfers and LAD-to-LSOA allocations are not independently estimated small-area values. Use them only where their assumptions are appropriate, and document the method in outputs.

## Setup

Put the function files in your project directory and source only the R modules required for your analysis:

```r
source("lsoa_area_weight_functions.R")
source("lsoa_population_functions.R")
source("lsoa_fingertips_functions.R")
source("lsoa_msoa_aggregation_functions.R")
source("read_defra_functions.R")
```

Install the R packages used by the modules you plan to run:

```r
install.packages(c(
  "sf", "terra", "data.table", "dplyr", "purrr", "readxl",
  "readr", "stringr", "tibble", "tidyr", "fingertipsR"
))
```

For the NDVI join script, install its Python dependencies in your Python environment:

```bash
pip install geopandas pandas
```

---

## LSOA area-weight lookups

### `lsoa_area_weight_functions.R`

Creates normalised area-based correspondence tables for LSOA 2001 to 2011, LSOA 2011 to 2021, and LSOA 2001 to 2021 through the LSOA 2011 geography.

Use full-extent, non-generalised LSOA boundary files in a projected coordinate reference system. The functions use British National Grid by default for meaningful area calculations.

```r
source("lsoa_area_weight_functions.R")

paths <- list(
  lsoa01_shp = "data/lsoa/LSOA_2001_EW_BFE_V2.shp",
  lsoa11_shp = "data/lsoa/LSOA_2011_EW_BFC_V3.shp",
  lsoa21_shp = "data/lsoa/LSOA_2021_EW_BFE_V10.shp",
  lookup01_11_csv = "data/lsoa/lsoa_2001_to_2011.csv",
  lookup11_21_csv = "data/lsoa/lsoa_2011_to_2021.csv"
)

weights <- do.call(build_lsoa_area_weights, paths)
data.table::fwrite(
  weights$wgt_11_21,
  "data/lsoa/lsoa_area_weights_2011_2021.csv"
)
```

Official sources include the ONS Open Geography Portal and the associated ONS lookup datasets. See the header comments in `lsoa_area_weight_functions.R` for direct links.

---

## LSOA population harmonisation

### `lsoa_population_functions.R`

Builds an England LSOA 2021 population series from ONS small-area population-estimate workbooks.

- Historical LSOA 2011 estimates are allocated to LSOA 2021 using area weights.
- Estimates already released on LSOA 2021 geography are retained directly.
- The output contains total population and broad sex-by-age bands.

```r
source("lsoa_area_weight_functions.R")
source("lsoa_population_functions.R")

population <- build_lsoa_population_2002_2024(
  population_dir = "data/lsoa_pop_est_sing",
  area_weight_args = paths,
  weights_cache = "data/lsoa/lsoa_area_weights_2011_2021.csv",
  output_csv = "data/pop_regrouped_2002_2024.csv"
)
```

Historical values are area-weighted allocations rather than population-weighted re-estimates. This is especially important for small LSOAs and age-specific counts.

---

## Generic Fingertips LAD-to-LSOA indicators

### `lsoa_fingertips_functions.R`

Downloads or reuses the official LSOA 2011 to LSOA 2021 to LAD 2022 lookup, retrieves an England district-level indicator from the OHID Fingertips API, and assigns each LSOA 2021 the value of its LAD.

The generic workflow accepts any suitable Fingertips `IndicatorID`:

```r
source("lsoa_fingertips_functions.R")

result <- build_lsoa_indicator(
  indicator_id = 92443L,
  sex = "Persons",
  age = "18+ yrs",
  area_pattern = "Districts",
  output_dir = "data/fingertips"
)
```

Use the [fingertipsR GitHub repository](https://github.com/ropensci/fingertipsR) to identify suitable indicator IDs and inspect valid geography, sex, age, and time-period dimensions before running an extraction.

Example IDs used in previous analyses include:

```r
indicator_ids <- c(
  92763, 92772,
  92538, 92308,
  93088, 93105, 93881, 94174, 94124, 93553
)
```

`build_lsoa_aps_smoking()` remains available as a convenience wrapper for APS current-smoking prevalence, including its specified LAD replacement rules.

---

## LSOA-to-MSOA aggregation

### `lsoa_msoa_aggregation_functions.R`

Aggregates LSOA `sf` attributes to MSOA polygons using a method selected for each field:

- `sum_vars`: sums count or total fields;
- `cont_vars`: calculates area-weighted means for continuous fields;
- `cat_vars`: returns the class with the greatest intersected area;
- `copy_vars`: copies a value only when it is consistent within the MSOA.

```r
source("lsoa_msoa_aggregation_functions.R")

msoa_data <- aggregate_lsoa_to_msoa(
  lsoa_sf = lsoa_data,
  msoa_sf = msoa_boundaries,
  msoa_id = "MSOA21CD",
  sum_vars = c("total_population"),
  cont_vars = c("smoking_prevalence"),
  cat_vars = c("rural_urban_classification"),
  copy_vars = c("region_name")
)
```

For count variables, direct summation is appropriate only where each LSOA lies wholly within its destination MSOA. If boundary vintages cross, use an explicit allocation method before summing.

---

## DEFRA PCM annual pollutant rasters

### `read_defra_functions.R`

Processes annual DEFRA Pollution Climate Mapping model-output CSVs. Data are available from the [DEFRA PCM data page](https://uk-air.defra.gov.uk/data/pcm-data).

Place CSV files by pollutant, for example:

```text
data/defra/pm25/
data/defra/pm10/
data/defra/benzene/
```

Then run:

```r
source("read_defra_functions.R")

results <- process_defra_pollutants(
  pollutants = c("pm25", "pm10", "benzene"),
  data_root = here::here("data", "defra")
)
```

For every pollutant, the workflow:

1. Reads annual PCM CSV model output.
2. Converts grid centroids to annual British National Grid rasters.
3. Writes annual GeoTIFFs.
4. Crops annual rasters to their shared spatial overlap and writes overlap GeoTIFFs.
5. Produces common-scale annual-level maps, log-scale maps, and maps of change from the first year.

Outputs are written beneath each pollutant directory in `geotiff/`, `geotiff_overlap/`, and `plots/`.

> **Data check:** Inspect metadata, units, coverage, and ranges before interpreting temporal change. In particular, the 2003 benzene output can have a substantially larger maximum than later years.

---

## NDVI administrative-boundary join

### `join_ndvi_adm3.py`

Joins tabular NDVI statistics to administrative polygons using a left join: every input boundary feature is retained, and matching NDVI fields are appended. It supports GeoJSON and GeoPackage outputs.

The intended NDVI source is AidData's [LTDR AVHRR NDVI V5 yearly GeoQuery dataset](https://www.aiddata.org/geoquery-datasets/ltdr-avhrr-ndvi-v5-yearly).

```bash
python join_ndvi_adm3.py \
  --boundaries data/ndvi/GBR_ADM3.geojson \
  --table data/ndvi/ndvi_results.csv \
  --output outputs/GBR_ADM3_NDVI.geojson
```

The default join column is `asdf_id`. Override it with `--join-field` when necessary. The script validates input files and join columns, reports matching-key diagnostics, and prevents duplicate table keys by default because they would duplicate polygons in the output.

To write a GeoPackage, set an optional layer name:

```bash
python join_ndvi_adm3.py \
  --geojson data/ndvi/GBR_ADM3.geojson \
  --csv data/ndvi/ndvi_results.csv \
  --output outputs/GBR_ADM3_NDVI.gpkg \
  --layer ndvi_adm3
```

---

## Reproducibility notes

- Keep downloaded source files outside version control where licensing or file size requires it.
- Record the boundary version, lookup version, data download date, and indicator filters used in analysis outputs.
- Check joins, missing values, and weight totals before using generated datasets in modelling or reporting.
- Document all allocation assumptions, particularly area-weighted geographic transfers and LAD-to-LSOA indicator assignments.
