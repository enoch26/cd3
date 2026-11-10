# Quick Start Guide: Python Scripts

This guide provides a quick reference for using Python equivalents of the R scripts.

## Installation

1. **Install Python 3.8+**
   ```bash
   python --version
   ```

2. **Install dependencies**
   ```bash
   pip install geopandas pandas numpy rasterio rioxarray matplotlib requests
   ```

3. **Verify installation**
   ```bash
   python -c "import geopandas, pandas, rasterio; print('All packages installed!')"
   ```

## Quick Reference

### 1. Create LSOA Area Weights
```bash
python lsoa11221.py
```
**Input:** Shapefile boundaries (LSOA 2001, 2011, 2021)  
**Output:** `data/derived/lsoa_*_area_weights.csv`  
**Time:** ~5-10 minutes depending on shapefile size

### 2. Harmonise Population Data
```bash
python pop.py
```
**Input:** ONS population workbooks (Excel files)  
**Output:** `data/pop_regrouped_2002_2024.csv`  
**Dependencies:** Must run lsoa11221.py first  
**Time:** ~3-5 minutes

### 3. Convert DEFRA Pollutants to Rasters
```bash
# Edit read_defra_pollutant.py to set POLLUTANT
python read_defra_pollutant.py
```
**Input:** DEFRA PCM CSV files  
**Output:** GeoTIFFs in `data/defra/<pollutant>/geotiff_overlap/`  
**Pollutants:** benzene, pm25, pm10, nox  
**Note:** Run once per pollutant  
**Time:** ~10-20 minutes per pollutant

### 4. Extract to LSOA Boundaries
```bash
python air_extract.py
```
**Input:** LSOA 2021 polygons + DEFRA overlap rasters  
**Output:** `outputs/air_lsoa_eng.gpkg`  
**Dependencies:** Must run steps 1-3 first  
**Time:** ~15-30 minutes

### 5. Join Smoking Prevalence Data
```bash
python fingertips.py
```
**Input:** OHID Fingertips API + LSOA lookup table  
**Output:** `data/derived/lsoa2021_smoking_aps_{long,wide}.csv`  
**Note:** Requires Fingertips API configuration  
**Time:** ~5 minutes

### 6. Process JAXA Binary Grids
```bash
python read_jaxa.py
```
**Input:** JAXA SWR binary files  
**Output:** GeoTIFFs + optional PNGs in `outputs/swr/`  
**Note:** Independent of other workflows  
**Time:** ~5-10 minutes

## Configuration

Each script has a configuration section at the top. Common settings:

### lsoa11221.py
```python
DATA_DIR = Path("data/lsoa")
AREA_CRS = 27700  # British National Grid
```

### pop.py
```python
YEARS = range(2002, 2025)
```

### read_defra_pollutant.py
```python
POLLUTANT = "benzene"  # Change as needed
YEARS = range(2003, 2025)
```

### read_jaxa.py
```python
GRID_NCOL = 7200
GRID_NROW = 3601
SCALE_FACTOR = 0.01
BYTE_ORDER = "little"  # or "big"
```

## Full Workflow

To run the complete pipeline:

```bash
# 1. Create area weights
python lsoa11221.py

# 2. Harmonise population
python pop.py

# 3. Process each pollutant
for pollutant in benzene pm25 pm10 nox; do
  # Edit POLLUTANT = "$pollutant" in read_defra_pollutant.py
  python read_defra_pollutant.py
done

# 4. Extract to LSOAs
python air_extract.py

# 5. Get smoking data
python fingertips.py

# 6. Process JAXA data (optional)
python read_jaxa.py
```

## Troubleshooting

### Import Errors
```bash
# Verify all packages installed
pip install --upgrade geopandas pandas numpy rasterio matplotlib requests
```

### File Not Found Errors
- Verify data files are in expected locations
- Check `data/` directory structure matches R scripts
- See script configuration section for paths

### CRS Mismatches
- Ensure shapefiles are in EPSG:27700 (British National Grid)
- Check `AREA_CRS = 27700` in lsoa11221.py

### Raster Alignment Issues
- Verify DEFRA CSV coordinates are in EPSG:27700
- Check grid dimensions match product documentation
- See read_defra_pollutant.py configuration

### Memory Issues
- Large rasters may require more RAM
- Consider processing one year/pollutant at a time
- Use subset of data for testing

## Output Validation

### Check CSV outputs
```python
import pandas as pd
df = pd.read_csv("data/derived/lsoa_2011_2021_area_weights.csv")
print(df.groupby("lsoa21cd")["weight"].sum())  # Should be ~1.0
```

### Check GeoTIFF outputs
```python
import rasterio
with rasterio.open("data/defra/benzene/geotiff/benzene_2003.tif") as src:
    print(f"Shape: {src.shape}")
    print(f"CRS: {src.crs}")
    print(f"Bounds: {src.bounds}")
```

### Check GeoPackage output
```python
import geopandas as gpd
gdf = gpd.read_file("outputs/air_lsoa_eng.gpkg")
print(gdf.head())
print(gdf.columns)
```

## Next Steps

- See [PYTHON_EQUIVALENTS.md](PYTHON_EQUIVALENTS.md) for detailed documentation
- Check individual script headers for advanced options
- Review [README.md](README.md) for data sources and interpretation notes

## Support

Each script includes logging output. Enable debug logging by editing:

```python
logging.basicConfig(level=logging.DEBUG)  # Change from INFO
```

For issues, check:
1. Script configuration section
2. Input data format and paths
3. Dependencies installation
4. Error messages in logging output
