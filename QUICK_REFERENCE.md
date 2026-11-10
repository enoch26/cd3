# Quick Reference: read_defra_pollutant.R Unified Workflow

## Configuration Summary

```r
# ============================================================================
# BASIC CONFIGURATION
# ============================================================================

# Select pollutant (any in data/defra/<pollutant>/)
pollutant <- "pm25"    # or: "benzene", "pm10", "nox", "ozone", etc.

# Enable LSOA extraction (requires lsoa11221.R to be run first)
do_lsoa_extraction <- FALSE   # Set to TRUE for LSOA workflow

# Parallel processing (only used if do_lsoa_extraction = TRUE)
maximum_workers <- 4   # Adjust based on your system

# Then run the script
source(here::here("read_defra_pollutant.R"))
```

---

## Workflow Decision Tree

```
Do you want LSOA-level exposure values?
├─ NO  → do_lsoa_extraction = FALSE
│         • Output: GeoTIFFs + diagnostic maps
│         • Time: ~minutes (sequential)
│         • Use: Raster analysis, spatial visualization
│
└─ YES → do_lsoa_extraction = TRUE
          • Prerequisite: source("lsoa11221.R") first
          • Output: GeoTIFFs + LSOA GeoPackages + PNG maps + RDS
          • Time: ~minutes per year (parallel)
          • Use: Epidemiology, LSOA exposure assessment
```

---

## Output Locations

### Mode 1: GeoTIFF Only

```
data/defra/<pollutant>/
├── geotiff/                      # Original extent (one file per year)
│   └── <pollutant>_YYYY.tif
├── geotiff_overlap/              # Aligned overlap (one file per year)
│   └── <pollutant>_YYYY_overlap.tif
└── plots/                        # Diagnostic maps
    ├── <pollutant>_overlap_multipanel.png
    ├── <pollutant>_overlap_multipanel_log10.png
    └── <pollutant>_change_from_YYYY.png
```

### Mode 2: GeoTIFF + LSOA Extraction

```
data/defra/<pollutant>/
├── [Mode 1 outputs - all of above]
└── lsoa_yearly/
    ├── <pollutant>_lsoa_eng_YYYY.gpkg        # One per year
    ├── <pollutant>_extraction_summary.csv    # Summary report
    ├── png/
    │   └── <pollutant>_lsoa_eng_YYYY.png     # One per year
    └── rds/
        └── <pollutant>_lsoa_eng_YYYY.rds     # One per year
```

---

## Common Use Cases

### 1. Convert Single Pollutant to Rasters
```r
pollutant <- "pm25"
do_lsoa_extraction <- FALSE
source(here::here("read_defra_pollutant.R"))
```
⏱️ Time: Minutes | 💾 Output: 10-20 files (GeoTIFFs + PNGs)

### 2. Extract Ozone to LSOA
```r
source(here::here("lsoa11221.R"))  # Creates poly_lsoa_21
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
maximum_workers <- 4
source(here::here("read_defra_pollutant.R"))
```
⏱️ Time: ~5-10 min per year (parallel) | 💾 Output: Rasters + LSOA boundaries

### 3. Batch Process All Pollutants
```r
source(here::here("lsoa11221.R"))  # Once

for (p in c("pm25", "pm10", "nox", "benzene", "ozone")) {
  pollutant <- p
  do_lsoa_extraction <- TRUE
  maximum_workers <- 4
  source(here::here("read_defra_pollutant.R"))
  message("Completed ", p)
}
```
⏱️ Time: ~30-50 min total | 💾 Output: 5 pollutants × (rasters + LSOA data)

### 4. Sequential Processing (Debug/Low Memory)
```r
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
maximum_workers <- 1  # Force single worker
source(here::here("read_defra_pollutant.R"))
```
⏱️ Time: ~15-20 min | 💾 Output: Rasters + LSOA boundaries (sequential)

---

## Key Parameters Explained

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `pollutant` | character | "pm25" | Subdirectory name in `data/defra/` |
| `do_lsoa_extraction` | logical | FALSE | Enable parallel LSOA extraction |
| `maximum_workers` | integer | 4 | Max parallel workers (ignored if extraction = FALSE) |
| `metadata_rows` | integer | 5 | CSV rows to skip (PCM standard) |
| `metric_column_index` | integer | 4 | Column containing concentration values |
| `cell_resolution_metres` | integer | 1000 | Grid cell size (1 km for DEFRA PCM) |
| `input_crs` | character | "EPSG:27700" | Coordinate system (British National Grid) |
| `number_of_plot_columns` | integer | 4 | Columns in diagnostic maps |

---

## LSOA Extraction Summary Report

File: `data/defra/<pollutant>/lsoa_yearly/<pollutant>_extraction_summary.csv`

```
year, ok,   n_missing, error
2003, TRUE,  0,         
2004, TRUE,  1,         
2005, FALSE, NA,        "GDAL: unsupported raster type"
...
```

- **year**: Data year
- **ok**: Extraction success (TRUE/FALSE)
- **n_missing**: Count of LSOA polygons with no overlap or data
- **error**: Error message (if ok = FALSE)

---

## Extraction Fallback Strategy

If no value at LSOA from primary method, tries:

```
1. Exact cell-coverage-weighted mean
   (coverage fractions for intersected cells)
       ↓ if missing
2. Ordinary polygon mean
   (standard polygon extraction)
       ↓ if still missing
3. LSOA centroid value
   (point-based extraction at polygon center)
   * Note: Not area-weighted; use as last resort
```

---

## Performance Tips

### For GeoTIFF-Only Mode
- Sequential processing (always)
- Fast (~5 min for typical dataset)
- Minimal memory (~500 MB)
- No prerequisites needed

### For LSOA Extraction Mode
- Parallel processing recommended
- Speed: ~5 min/year with 4 workers vs ~15-20 min sequential
- Memory: ~2 GB per worker
- `maximum_workers`: Set based on:
  - **High-performance PC**: 4-8 workers
  - **Laptop**: 2-4 workers
  - **HPC cluster**: 8-16 workers
  - **Low memory**: 1-2 workers

### Troubleshooting Performance
- If slow: Check CPU/memory usage, reduce workers
- If memory errors: Reduce `maximum_workers` or set to 1
- If stuck on one year: May indicate file I/O issue; check logs

---

## Validation Checklist Before Running

- [ ] Input CSV files exist in `data/defra/<pollutant>/`
- [ ] CSV files have 5 metadata rows + data
- [ ] CSV columns: index, x, y, value, ... (at minimum)
- [ ] LSOA extraction? Run `lsoa11221.R` first
- [ ] Sufficient disk space for outputs
- [ ] Sufficient memory for parallel workers (if extraction)

---

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Input directory does not exist" | Wrong pollutant name | Check `data/defra/<pollutant>/` exists |
| "No CSV files found" | No data in directory | Place DEFRA PCM CSV files in directory |
| "Could not identify a year" | Year not in metadata or filename | Add year to CSV metadata row 2 or filename |
| "No common spatial overlap" | Rasters don't overlap | Verify all years have data in same grid area |
| "`poly_lsoa_21` not found" | Skipped lsoa11221.R | Run `source("lsoa11221.R")` first |
| "GDAL error" | Corrupted raster data | Check CSV file format; may need cleaning |
| Memory error with extraction | Too many workers | Reduce `maximum_workers` |

---

## Files to Review

- **MERGED_WORKFLOWS.md** - Full documentation (workflows, examples, troubleshooting)
- **MERGE_SUMMARY.md** - Technical details (code comparison, architecture)
- **read_defra_pollutant.R** - Source code (well-commented)
- **read_defra_pollutant_backup.R** - Original version (for reference)

---

## Migration from Old Scripts

### Old Code
```r
# GeoTIFF creation
pollutant <- "pm25"
source("read_defra_pollutant.R")

# LSOA extraction
source("lsoa11221.R")
source("ozone.R")
```

### New Code
```r
# GeoTIFF creation
pollutant <- "pm25"
do_lsoa_extraction <- FALSE
source("read_defra_pollutant.R")

# LSOA extraction
source("lsoa11221.R")
pollutant <- "ozone"
do_lsoa_extraction <- TRUE
source("read_defra_pollutant.R")
```

Both produce identical outputs. The new version is simpler and more flexible.

---

## Questions?

See **MERGED_WORKFLOWS.md** for:
- Detailed workflow descriptions
- 4 complete usage examples
- Input/output structure
- Troubleshooting guide
- Performance analysis
