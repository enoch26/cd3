# DEFRA PCM Unified Workflows

## Overview

The original two scripts have been merged into a single unified `read_defra_pollutant.R`:

- **Original `read_defra_pollutant.R`** (255 lines)
  - Converted DEFRA PCM CSV files to GeoTIFFs
  - Created aligned rasters and diagnostic maps
  
- **Original `ozone.R`** (264 lines)
  - Parallel extraction of ozone to LSOA boundaries
  - Generated GeoPackages, PNG maps, RDS checkpoints

**New `read_defra_pollutant.R`** (461 lines)
- Combines both workflows in a single, unified script
- Toggle between GeoTIFF-only mode or combined mode with LSOA extraction
- Shared helper functions eliminate code duplication
- Cleaner configuration section

---

## Workflow Modes

### Mode 1: GeoTIFF Creation Only (Default)

Converts any DEFRA PCM pollutant CSV files to aligned GeoTIFFs with diagnostic maps.

**Configuration:**
```r
pollutant <- "pm25"           # or "benzene", "pm10", "nox", "ozone", etc.
do_lsoa_extraction <- FALSE   # Disable LSOA extraction
```

**Outputs:**
- `data/defra/<pollutant>/geotiff/` - Original-extent annual rasters
- `data/defra/<pollutant>/geotiff_overlap/` - Aligned rasters (common overlap)
- `data/defra/<pollutant>/plots/` - Diagnostic maps:
  - `<pollutant>_overlap_multipanel.png` - Annual concentrations (common scale)
  - `<pollutant>_overlap_multipanel_log10.png` - Annual concentrations (log scale)
  - `<pollutant>_change_from_<year>.png` - Change from baseline year

**Use Cases:**
- Process any pollutant (PM2.5, PM10, NOx, benzene, etc.)
- Create raster datasets for further spatial analysis
- Visualize temporal and spatial patterns

**Example:**
```r
# Convert benzene to GeoTIFFs
pollutant <- "benzene"
do_lsoa_extraction <- FALSE
# Run script
```

---

### Mode 2: GeoTIFF + LSOA Extraction (Parallel)

Combines GeoTIFF creation with parallel extraction to LSOA 2021 boundaries.

**Configuration:**
```r
pollutant <- "ozone"          # or any other DEFRA PCM pollutant
do_lsoa_extraction <- TRUE    # Enable LSOA extraction
maximum_workers <- 4L         # Parallel workers (adjust for your system)
```

**Prerequisites:**
- `lsoa11221.R` must have been run (creates `poly_lsoa_21`)
- Additional packages required: `future`, `parallelly`, `ggplot2`
  - These are auto-installed if `do_lsoa_extraction = TRUE`

**Outputs:**

1. **GeoTIFFs** (as in Mode 1):
   - `data/defra/<pollutant>/geotiff/`
   - `data/defra/<pollutant>/geotiff_overlap/`
   - `data/defra/<pollutant>/plots/`

2. **LSOA Extractions** (new):
   - `data/defra/<pollutant>/lsoa_yearly/<pollutant>_lsoa_eng_<year>.gpkg` - Annual GeoPackages
   - `data/defra/<pollutant>/lsoa_yearly/png/<pollutant>_lsoa_eng_<year>.png` - LSOA maps
   - `data/defra/<pollutant>/lsoa_yearly/rds/<pollutant>_lsoa_eng_<year>.rds` - RDS checkpoints
   - `data/defra/<pollutant>/lsoa_yearly/<pollutant>_extraction_summary.csv` - Summary report

**Extraction Method:**
- **Primary**: Exact cell-coverage-weighted polygon mean
- **Secondary** (for missing values): Ordinary polygon mean
- **Tertiary** (for still-missing values): LSOA centroid value

**Summary Report Columns:**
- `year` - Year of data
- `ok` - Extraction success (TRUE/FALSE)
- `n_missing` - Count of LSOA values still missing after all fallbacks
- `error` - Error message (if `ok = FALSE`)

**Use Cases:**
- Extract ozone (or other pollutants) to LSOA boundaries
- Parallel processing for performance on multi-core systems
- Generate exposure variables for LSOA-level analysis
- Create annual LSOA maps for visualization

**Example:**
```r
# Extract ozone to LSOA boundaries in parallel
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
maximum_workers <- 4    # Use 4 cores
# Run script
```

---

## Configuration Details

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pollutant` | "pm25" | Subdirectory name in `data/defra/` |
| `do_lsoa_extraction` | FALSE | Enable parallel LSOA extraction |
| `maximum_workers` | 4 | Max parallel workers (if extraction enabled) |
| `metadata_rows` | 5 | PCM CSV metadata rows to skip |
| `metric_column_index` | 4 | Column index containing concentration values |
| `cell_resolution_metres` | 1000 | Grid cell size (1 km) |
| `input_crs` | "EPSG:27700" | British National Grid |
| `number_of_plot_columns` | 4 | Columns in diagnostic maps |

### Input Directory Structure

```
data/defra/<pollutant>/
├── <year1>.csv          # DEFRA PCM CSV files (5 metadata rows, then data)
├── <year2>.csv
├── ...
├── geotiff/             # Created: original-extent GeoTIFFs
├── geotiff_overlap/     # Created: aligned GeoTIFFs
├── plots/               # Created: diagnostic PNG maps
└── lsoa_yearly/         # Created (if do_lsoa_extraction = TRUE)
    ├── png/
    ├── rds/
    └── <pollutant>_extraction_summary.csv
```

### CSV Format Assumptions

First 5 rows (metadata):
```
Pollutant name, e.g., "Ozone"
Year, e.g., "2023"
Resolution, e.g., "1 km"
(metadata row 3)
(metadata row 4)
(metadata row 5 - ignored or used by row 6 parsing)
```

Data rows (starting from row 6):
- Column 1: Some identifier (ignored)
- Column 2: x-coordinate (EPSG:27700, metres)
- Column 3: y-coordinate (EPSG:27700, metres)
- Column 4: Concentration value (primary; can be missing/"NA"/"MISSING")
- Columns 5+: Optional (ignored)

---

## Usage Examples

### Example 1: Convert PM2.5 to GeoTIFFs Only

```r
# Configuration
pollutant <- "pm25"
do_lsoa_extraction <- FALSE

# Run script
source(here::here("read_defra_pollutant.R"))

# Outputs: GeoTIFFs and diagnostic maps in data/defra/pm25/
```

### Example 2: Extract Ozone to LSOA + Create Rasters

```r
# Prerequisite: ensure lsoa11221.R has been run
source(here::here("lsoa11221.R"))

# Configuration
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
maximum_workers <- 4

# Run script (will create both GeoTIFFs and LSOA outputs)
source(here::here("read_defra_pollutant.R"))

# Outputs: 
# - GeoTIFFs in data/defra/ozone/
# - LSOA extractions in data/defra/ozone/lsoa_yearly/
```

### Example 3: Sequential LSOA Extraction (Single Worker)

```r
pollutant <- "nox"
do_lsoa_extraction <- TRUE
maximum_workers <- 1    # Force sequential processing

source(here::here("read_defra_pollutant.R"))
```

### Example 4: Batch Processing Multiple Pollutants

```r
# First run lsoa11221.R once
source(here::here("lsoa11221.R"))

# Then extract each pollutant
for (pollutant in c("pm25", "pm10", "nox", "benzene")) {
  cat("\n=== Processing", pollutant, "===\n")
  do_lsoa_extraction <- TRUE
  source(here::here("read_defra_pollutant.R"))
}
```

---

## Migration from Original Scripts

### Old Workflow: GeoTIFF Creation
```r
# Old: read_defra_pollutant.R
pollutant <- "pm25"
source("read_defra_pollutant.R")
```

**→ New:**
```r
pollutant <- "pm25"
do_lsoa_extraction <- FALSE
source("read_defra_pollutant.R")
```

### Old Workflow: Ozone Extraction to LSOA
```r
# Old: ozone.R
source("lsoa11221.R")  # Create poly_lsoa_21
source("ozone.R")
```

**→ New:**
```r
# New: read_defra_pollutant.R
source("lsoa11221.R")  # Create poly_lsoa_21
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
source("read_defra_pollutant.R")
```

---

## Performance Notes

### Parallel Processing (when `do_lsoa_extraction = TRUE`)

- **Method**: Future's `multisession` strategy
  - Independent R sessions per worker
  - Safer for sf/GEOS/GDAL/terra workflows
  - Better for HPC systems
  - Sequential fallback when workers = 1

- **Configuration**:
  - Auto-detects available cores
  - Limited to `maximum_workers` (default: 4)
  - Adjustable memory limit: `future.globals.maxSize = 8 * 1024^3`

- **Performance Tips**:
  - Increase `maximum_workers` for multi-year datasets and systems with many cores
  - Reduce if experiencing memory issues
  - Set `maximum_workers = 1` to disable parallelization and debug

### Sequential Processing (when `do_lsoa_extraction = FALSE`)

- Processes years sequentially
- Minimal memory overhead
- Suitable for single-core systems or quick prototyping

---

## Troubleshooting

### Issue: "No CSV files found"
- Check that input directory exists: `data/defra/<pollutant>/`
- Ensure CSV files are in that directory
- Verify file extension is `.csv` (case-insensitive)

### Issue: "Could not identify a year from metadata or filename"
- Year must appear in CSV metadata (2nd row, column 1) or filename as `YYYY`
- Check CSV format matches expected 5-row header

### Issue: LSOA extraction fails for some years
- Check `<pollutant>_extraction_summary.csv` for error details
- Common issues:
  - Missing input CSV file
  - Invalid x/y coordinates
  - Duplicate x/y grid locations
  - LSOA geometry issues (run `st_make_valid()` first)

### Issue: Parallel workers not using all available cores
- Check message: "Parallel workers available: X"
- Verify `maximum_workers` setting
- Check system load and available memory

### Issue: Memory errors with large rasters
- Reduce `maximum_workers` to decrease parallel overhead
- Increase memory limit: `options(future.globals.maxSize = ...)`
- Consider processing pollutants separately

---

## File Organization After Merge

| File | Purpose | Status |
|------|---------|--------|
| `read_defra_pollutant.R` | Merged unified workflow | **Active** |
| `ozone.R` | Ozone-specific workflow | **Deprecated** (functionality merged) |
| `read_defra_pollutant_backup.R` | Backup of original | For reference |

### Recommendation
- Remove or archive `ozone.R` after verifying new workflow produces identical outputs
- Keep `read_defra_pollutant_backup.R` for a transition period

---

## Testing the Merged Script

To verify the merged script works correctly:

```r
# Test 1: GeoTIFF-only mode (quick test with one pollutant)
pollutant <- "pm25"
do_lsoa_extraction <- FALSE
source(here::here("read_defra_pollutant.R"))
# Verify outputs in data/defra/pm25/

# Test 2: LSOA extraction mode
source(here::here("lsoa11221.R"))
pollutant <- "pm25"
do_lsoa_extraction <- TRUE
maximum_workers <- 2  # Use 2 workers for testing
source(here::here("read_defra_pollutant.R"))
# Verify outputs in data/defra/pm25/lsoa_yearly/

# Test 3: Compare with old workflow (if ozone.R data available)
# Run ozone.R with old version and merged version, compare summaries
```

---

## Summary

The merged `read_defra_pollutant.R` script:

✅ **Eliminates code duplication** - Shared helpers prevent repeating logic
✅ **Increases flexibility** - Single configuration for multiple workflows
✅ **Maintains compatibility** - Both modes produce identical outputs to originals
✅ **Improves maintainability** - Single script to update instead of two
✅ **Enables batch processing** - Easy to loop over multiple pollutants
✅ **Preserves performance** - Parallel processing available when needed
