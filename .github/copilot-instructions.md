# Copilot Instructions for cd3

This repository contains an R data pipeline for preparing environmental and contextual datasets for English 2021 Lower-layer Super Output Areas (LSOAs). The codebase emphasizes reproducible workflows for geographic crosswalks, population harmonisation, and environmental exposure variables.

## Repository Overview

**Purpose:** Transform various input datasets (ONS population estimates, DEFRA air pollution rasters, OHID Fingertips indicators, JAXA binary grids, and historical LSOA boundaries) into harmonised 2021 LSOA-level exposure datasets.

**Key characteristics:**
- R-based scripted workflows (no framework or package; direct R scripts with helper modules)
- All scripts use `here::here()` for path resolution—always run from the repository root
- Inputs and outputs are intentionally versioned out of the repository; users must obtain source data separately
- Area-weighted allocation and LAD-to-LSOA transfers are **contextual/exposure values**, not independently estimated small-area measurements
- Results must always be validated against source metadata, crosswalk weights, and missing-value patterns

## Project Structure

```
.
├── lsoa11221.R                  # Creates 2021 LSOA spatial objects and area-weighted crosswalks
├── pop.R                        # Harmonises ONS population 2002–2024 to LSOA 2021
├── read_defra_pollutant.R       # Standalone: converts DEFRA PCM CSVs to GeoTIFFs (per pollutant)
├── air_extract.R                # Extracts area-weighted means from DEFRA rasters to LSOA 2021
├── ozone.R                      # Processes ozone PCM CSVs to LSOA-level values
├── fingertips.R                 # Downloads APS smoking from OHID Fingertips and joins to LSOA 2021
├── read_jaxa.R                  # Reads JAXA binary grids and exports GeoTIFFs/PNGs
├── functions/                   # Reusable R modules (source these to use in your scripts)
│   ├── lsoa_area_weight_functions.R
│   ├── lsoa_population_functions.R
│   ├── lsoa_fingertips_functions.R
│   ├── lsoa_msoa_aggregation_functions.R
│   ├── read_defra_functions.R
│   └── join_ndvi_adm3.py        # Python utility for NDVI joins
└── README.md, LICENSE
```

## Running Scripts

### General Pattern

1. All scripts must be run from the **repository root** directory (where `cd3.Rproj` lives).
2. Scripts use `here::here()` to resolve paths—this ensures portability and correct behaviour even when R working directory changes.
3. Each script includes a **Configuration** section near the top where filenames, date ranges, indicator codes, and other parameters are set.
4. Check each script's header comments for the expected project layout, input filenames, and output locations.

### Standard Execution Order

1. **`lsoa11221.R`** — Must run first. Creates `poly_lsoa_21` (sf spatial object) and three area-weight CSVs.
   - Outputs: `data/derived/lsoa_*_area_weights.csv`

2. **`pop.R`** — Depends on output from `lsoa11221.R`.
   - Outputs: `data/pop_regrouped_2002_2024.csv`

3. **`read_defra_pollutant.R`** — Run once per pollutant (benzene, pm25, pm10, nox).
   - Must configure `pollutant` variable in the script before each run.
   - Outputs GeoTIFFs and diagnostic maps.

4. **`air_extract.R`** — Depends on `lsoa11221.R` and DEFRA raster outputs.
   - Outputs: `outputs/air_lsoa_eng.gpkg`

5. **`ozone.R`** — Independent workflow; doesn't depend on earlier scripts.
   - Outputs: `outputs/ozone_lsoa_yearly/`

6. **`fingertips.R`** — Downloads from the OHID Fingertips API; independent of spatial workflows.
   - Outputs: `data/derived/lsoa2021_smoking_aps_{long,wide}.csv`

7. **`read_jaxa.R`** — Independent; no dependencies on LSOA workflows.
   - Outputs: `outputs/swr/`

### Using Function Modules

To reuse functions in your own scripts or workflows:

```r
# Source only the modules you need
source(here::here("functions/lsoa_area_weight_functions.R"))
source(here::here("functions/lsoa_population_functions.R"))

# Now call functions like build_lsoa_area_weights() or build_lsoa_population_2002_2024()
```

Each module is self-contained; read its header comments and function documentation (via `?function_name`) to understand parameters and return values.

## Key Conventions

### Path Resolution

- Use `here::here()` for all file paths, never hardcoded absolute paths.
- Example: `here::here("data", "lsoa", "my_file.csv")` not `"C:/Users/me/data/lsoa/my_file.csv"`
- This ensures scripts work on any machine and any working directory, as long as the repository structure is preserved.

### Configuration Sections

Each script has a **Configuration** section that collects all user-editable parameters (filenames, dates, codes, coordinate systems). Always edit these sections, never hardcode paths or parameters into the script body.

### Area-Weighted Allocation Rules

- **Additive counts** (totals, sums): Apply weights directly; multiply counts by weights and aggregate.
- **Rates, percentages, means**: Do NOT apply weights directly; allocate numerators and denominators separately, then recalculate rates.
- **Area weights** sum to 1.0 within each source unit. Validate this before use.

### Geospatial Practices

- Use projected coordinate systems (British National Grid by default) for distance and area calculations.
- Always check coordinate reference systems (CRS) match before spatial joins, intersections, or raster extraction.
- Input boundary files should be non-generalised, full-extent versions from the ONS Open Geography Portal.

### Expected Data Validations

After running any workflow, check for:
1. **Missing values** — Expected rows present? Any unexpected nulls?
2. **Year/period coverage** — Do outputs cover the intended date range?
3. **Crosswalk weight sums** — Each source unit's weights should sum to ~1.0 (allow small floating-point error).
4. **Duplicate rows** — Any unintended duplication in identifier columns?
5. **Geographic coverage** — Do counts, means, or areas match expectations for England's LSOAs?
6. **Source metadata** — Download dates, versions, and any special imputations or replacements documented?

## Important Limitations and Assumptions

- **LAD-to-LSOA allocation:** Fingertips assigns one LAD-level value to all constituent LSOAs; use only where LSOA-level variation is not critical.
- **Area-weighted transfers:** Population and other counts are transferred under a uniform-within-source-area assumption; do not apply to rates or densities without recalculating.
- **Ozone point fallback:** `ozone.R` may fall back to point extraction if polygon extraction is unavailable; record this in your outputs.
- **No independent small-area estimation:** These are contextual/exposure variables derived from higher-level data, not independently estimated LSOA-level measurements.

## Required R Packages

Common packages across workflows: `sf`, `terra`, `here`, `dplyr`, `data.table`, `readr`, `readxl`, `tidyr`, `purrr`, `stringr`, `tibble`, `future`, `parallelly`, `ggplot2`.

Workflow-specific:
- `fingertipsR` — Required for the Fingertips workflow.
- `exactextractr` — Required for ozone exact extraction.

Install missing packages before running scripts:

```r
install.packages(c("sf", "terra", "here", "dplyr", "data.table"))
```

Spatial packages may also require system libraries: GDAL, GEOS, PROJ, UDUNITS.

## Python Utilities

The NDVI join utility (`functions/join_ndvi_adm3.py`) requires Python with `geopandas` and `pandas`:

```bash
python -m pip install geopandas pandas
python functions/join_ndvi_adm3.py --help
```

## Debugging and Troubleshooting

- **`poly_lsoa_21` not found:** Ensure `lsoa11221.R` has been sourced or run first; this script creates the required spatial object.
- **Path not found errors:** Check that you are running scripts from the repository root, and that source data is in the expected `data/` subdirectories.
- **CRS mismatches:** Before spatial operations, check that all objects use the same or compatible coordinate systems. Transform as needed with `sf::st_transform()`.
- **API timeouts (Fingertips):** If the OHID Fingertips API is slow, the workflow may time out. Run `fingertips.R` in isolation and check internet connectivity.
- **Raster alignment issues:** DEFRA rasters from different years may have slight alignment differences. `read_defra_pollutant.R` handles this by creating overlaps; review the diagnostic maps.

## When Adding or Modifying Code

- **Source data:** Always document source names, versions, download dates, and URLs in script comments.
- **Function documentation:** Use roxygen2-style comments (`#'`) for any new functions in the `functions/` directory.
- **Outputs:** Record metadata alongside results (coordinate systems, units, methods, years covered).
- **Area weights:** If modifying the area-weight calculation, validate against official sources and compare weight distributions.
- **Git commits:** Include data versions and processing parameters in commit messages where they affect reproducibility.

## External Data Sources

- **ONS Open Geography Portal:** LSOA boundaries and lookup files.
- **ONS small-area population estimates:** Population workbooks by single year of age.
- **DEFRA UK-AIR PCM data:** Annual pollutant model-output CSVs.
- **OHID Fingertips:** `https://fingertips.phe.org.uk/` — Adult smoking and other indicators.
- **JAXA MODIS/SeaWiFS:** Binary grids for solar-weighted reflectance (if applicable to your analysis).
