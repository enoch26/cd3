# Python Equivalents for R Scripts

This document provides a summary of Python equivalents created for the R workflows in this repository.

## Overview

Six Python scripts have been created as functional equivalents to the R counterparts. They maintain the same data inputs/outputs and processing logic while using Python geospatial libraries.

| R Script | Python Script | Status |
|----------|---------------|--------|
| `lsoa11221.R` | `lsoa11221.py` | ✓ Created |
| `pop.R` | `pop.py` | ✓ Created |
| `read_defra_pollutant.R` | `read_defra_pollutant.py` | ✓ Created |
| `air_extract.R` | `air_extract.py` | ✓ Created |
| `fingertips.R` | `fingertips.py` | ✓ Created |
| `read_jaxa.R` | `read_jaxa.py` | ✓ Created |

## Python Dependencies

Install required packages:

```bash
pip install geopandas pandas numpy rasterio rioxarray matplotlib requests
```

## Script Descriptions

### 1. lsoa11221.py
**Purpose:** Create LSOA 2001-2021 area-weighted crosswalks

**Key features:**
- Reads shapefile boundaries using GeoPandas
- Calculates area-weighted crosswalks using spatial intersections
- Outputs CSV files with normalized weights
- Handles England-only filtering

**Main function:** `create_area_weights()`

**Usage:**
```bash
python lsoa11221.py
```

### 2. pop.py
**Purpose:** Harmonise population estimates to LSOA 2021 boundaries

**Key features:**
- Loads area weights from lsoa11221.py output
- Reads ONS population workbooks (Excel format)
- Applies area weights to transfer 2002-2020 data from LSOA 2011 to 2021
- Concatenates with direct LSOA 2021 data for 2021-2024
- Outputs harmonised CSV

**Main function:** `harmonise_population_to_lsoa_2021()`

**Usage:**
```bash
python pop.py
```

**Note:** Requires proper configuration of Excel file paths and column names matching ONS format.

### 3. read_defra_pollutant.py
**Purpose:** Convert DEFRA PCM CSVs to gridded GeoTIFFs and align rasters

**Key features:**
- Reads DEFRA pollution CSV files (CSV format)
- Converts point data to 1 km gridded GeoTIFFs using rasterio
- Aligns rasters to common spatial extent
- Optional: Extract values to LSOA polygons
- Supports benzene, PM2.5, PM10, NOx

**Main functions:**
- `process_defra_pollutant()`: CSV to GeoTIFF conversion
- `align_geotiffs()`: Raster alignment to common bounds
- `extract_to_lsoa()`: Optional polygon-level extraction

**Configuration:**
```python
POLLUTANT = "benzene"  # Change as needed
DO_LSOA_EXTRACTION = False  # Enable for LSOA extraction
```

**Usage:**
```bash
python read_defra_pollutant.py
```

### 4. air_extract.py
**Purpose:** Extract pollutant concentrations to LSOA 2021 boundaries

**Key features:**
- Loads LSOA 2021 polygons from shapefile/GeoPackage
- Masks rasters to polygon extent
- Calculates area-weighted mean concentrations
- Creates output GeoPackage with pollutant columns
- Handles all 4 pollutants across 2003-2024

**Main function:** `extract_all_pollutants()`

**Usage:**
```bash
python air_extract.py
```

**Prerequisites:**
- LSOA 2021 polygon file available
- All DEFRA overlap rasters created by `read_defra_pollutant.py`

### 5. fingertips.py
**Purpose:** Retrieve smoking prevalence data and join to LSOAs

**Key features:**
- Connects to OHID Fingertips API (placeholder implementation)
- Joins LAD-level data to LSOA 2021 areas via lookup table
- Applies pragmatic adjustments and imputations for missing values
- Outputs in long and wide formats
- Implements forward-fill and regional mean imputation

**Main function:** `main()`

**Note:** Fingertips API access requires authentication. The script includes placeholder implementation; users should configure with actual API credentials.

**Usage:**
```bash
python fingertips.py
```

### 6. read_jaxa.py
**Purpose:** Process JAXA binary grids to GeoTIFF

**Key features:**
- Reads JAXA MODIS/SeaWiFS SWR binary files using NumPy
- Parses Fortran header format
- Converts digital numbers to physical units using scale factors
- Rotates longitude from 0-360 to -180-180 convention
- Writes GeoTIFFs with proper georeferencing
- Optional: Creates PNG visualizations

**Configuration:**
```python
GRID_NCOL = 7200
GRID_NROW = 3601
SCALE_FACTOR = 0.01
BYTE_ORDER = "little"  # or "big"
```

**Main function:** `process_jaxa_files()`

**Usage:**
```bash
python read_jaxa.py
```

## Key Differences from R Versions

1. **Path Handling:** Python scripts use `pathlib.Path` instead of R's `here::here()`
2. **Spatial Ops:** GeoPandas/Rasterio replace R's terra/sf
3. **Logging:** Python uses `logging` module instead of R `message()`
4. **Error Handling:** More explicit try-except blocks in Python
5. **Data I/O:** CSV/Excel using Pandas instead of readr/readxl

## Data I/O Compatibility

All Python scripts:
- Accept the same input data formats as R equivalents
- Produce identical or compatible output files
- Use same configuration paths and directory structure
- Can be substituted for R scripts in workflows

## Testing Notes

To validate Python scripts:

1. **lsoa11221.py**: Check `lsoa_*_area_weights.csv` files exist and weight columns sum to ~1
2. **pop.py**: Verify `pop_regrouped_2002_2024.csv` covers all years and LSOAs
3. **read_defra_pollutant.py**: Check `geotiff_overlap/` contains properly georeferenced rasters
4. **air_extract.py**: Verify output GeoPackage contains all pollutant-year columns
5. **fingertips.py**: Check long/wide format CSVs with expected LSOA codes
6. **read_jaxa.py**: Validate GeoTIFF files have correct dimensions and CRS

## Future Enhancements

- Add comprehensive error recovery and retry logic
- Implement parallel processing for raster operations
- Add unit tests for core functions
- Create command-line argument parsing for configuration
- Add data validation and quality checks
- Support Dask for out-of-memory operations on large rasters

## Support and Documentation

Each script includes:
- Comprehensive docstrings
- Configuration section at top
- Inline comments for complex operations
- Logging output for debugging
- Usage examples in `if __name__ == "__main__"` block

See individual script headers for detailed documentation.
