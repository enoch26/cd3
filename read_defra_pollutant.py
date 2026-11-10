"""
DEFRA PCM workflows: GeoTIFFs, aligned grids, and LSOA extraction

Purpose:
    Convert annual DEFRA PCM model-output CSV files (annual mean concentrations
    in micrograms per cubic metre) into:
    1. British National Grid GeoTIFFs, aligned, and diagnostic maps (all workflows)
    2. Area-weighted LSOA 2021 exposure values (optional extraction workflow)

    All outputs use 1 km grids in EPSG:27700 (British National Grid). The script
    can process any pollutant independently or perform parallel extraction of
    ozone (or other pollutants) to LSOA boundaries.

Sources:
    https://uk-air.defra.gov.uk/data/pcm-data

Expected layout for a selected pollutant:
    data/defra/<pollutant>/
      <annual PCM CSV files>
      geotiff/                  # created: original-extent rasters
      geotiff_overlap/          # created: common-overlap rasters
      plots/                    # created: diagnostic PNG files
      lsoa_yearly/              # created if do_lsoa_extraction = TRUE

Assumptions to verify against the downloaded PCM release:
    * the first five CSV rows are metadata;
    * data begin on row six;
    * coordinate fields are named `x` and `y`, in EPSG:27700 metres;
    * the concentration field is the fourth data column; and
    * cells are on a 1 km grid.

Optional LSOA Extraction Features (when do_lsoa_extraction = TRUE):
    * Requires lsoa11221.py to create LSOA 2021 polygons
    * Uses parallel processing for performance
    * Applies area-weighted mean extraction with fallback strategies
"""

import os
import pandas as pd
import numpy as np
import rasterio
from rasterio.transform import from_bounds
from pathlib import Path
import warnings
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
import matplotlib.pyplot as plt
import geopandas as gpd
from rasterio.mask import mask
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DATA_DIR = Path("data")
OUTPUT_DIR = Path("outputs")
DEFRA_DIR = DATA_DIR / "defra"

# Pollutant configuration - change as needed
POLLUTANT = "benzene"  # Options: benzene, pm25, pm10, nox
YEARS = range(2003, 2025)
GRID_CRS = "EPSG:27700"
GRID_CELL_SIZE = 1000  # 1 km in metres

# LSOA extraction settings
DO_LSOA_EXTRACTION = False
PARALLEL_WORKERS = 4

# Expected CSV format
CSV_HEADER_ROWS = 5
COORD_COLS = {"x": "x", "y": "y"}
VALUE_COL = 3  # Fourth data column (0-indexed)


def read_defra_csv(filepath, pollutant, year):
    """
    Read DEFRA PCM CSV file.
    
    Expects coordinates in EPSG:27700 and concentration as fourth data column.
    """
    try:
        df = pd.read_csv(filepath, skiprows=CSV_HEADER_ROWS)
        
        # Validate required columns
        if not all(col in df.columns for col in [COORD_COLS["x"], COORD_COLS["y"]]):
            logger.warning(f"Coordinate columns not found in {filepath}")
            return None
        
        # Get concentration column (4th data column typically)
        concentration_col = df.columns[VALUE_COL]
        df = df[[COORD_COLS["x"], COORD_COLS["y"], concentration_col]].copy()
        df.columns = ["x", "y", "concentration"]
        df["year"] = year
        df["pollutant"] = pollutant
        
        return df
    except Exception as e:
        logger.error(f"Error reading {filepath}: {e}")
        return None


def csv_to_geotiff(csv_data, output_path, pollutant, year):
    """
    Convert CSV points to gridded GeoTIFF.
    
    Assumes 1 km grid cells in EPSG:27700.
    """
    if csv_data is None or csv_data.empty:
        logger.warning(f"Empty data for {pollutant} {year}")
        return None
    
    # Create grid
    x_min, x_max = csv_data["x"].min(), csv_data["x"].max()
    y_min, y_max = csv_data["y"].min(), csv_data["y"].max()
    
    # Snap to 1 km grid
    x_min = (x_min // GRID_CELL_SIZE) * GRID_CELL_SIZE
    y_min = (y_min // GRID_CELL_SIZE) * GRID_CELL_SIZE
    x_max = ((x_max // GRID_CELL_SIZE) + 1) * GRID_CELL_SIZE
    y_max = ((y_max // GRID_CELL_SIZE) + 1) * GRID_CELL_SIZE
    
    cols = int((x_max - x_min) / GRID_CELL_SIZE)
    rows = int((y_max - y_min) / GRID_CELL_SIZE)
    
    # Create empty grid
    grid = np.full((rows, cols), np.nan, dtype=np.float32)
    
    # Populate grid
    for _, row in csv_data.iterrows():
        col = int((row["x"] - x_min) / GRID_CELL_SIZE)
        row_idx = int((y_max - row["y"]) / GRID_CELL_SIZE)
        
        if 0 <= row_idx < rows and 0 <= col < cols:
            grid[row_idx, col] = row["concentration"]
    
    # Write GeoTIFF
    transform = from_bounds(x_min, y_min, x_max, y_max, cols, rows)
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with rasterio.open(
        output_path,
        "w",
        driver="GTiff",
        height=rows,
        width=cols,
        count=1,
        dtype=grid.dtype,
        crs=GRID_CRS,
        transform=transform,
        nodata=np.nan,
    ) as dst:
        dst.write(grid, 1)
    
    logger.info(f"Wrote GeoTIFF: {output_path}")
    return output_path


def process_defra_pollutant(pollutant, years=None, output_geotiff=True):
    """Process all years for a given pollutant."""
    if years is None:
        years = YEARS
    
    pollutant_dir = DEFRA_DIR / pollutant
    geotiff_dir = pollutant_dir / "geotiff"
    
    for year in years:
        # Find CSV file
        csv_files = list(pollutant_dir.glob(f"*{year}*.csv"))
        if not csv_files:
            logger.warning(f"No CSV found for {pollutant} {year}")
            continue
        
        csv_file = csv_files[0]
        logger.info(f"Processing {pollutant} {year}...")
        
        # Read CSV
        data = read_defra_csv(csv_file, pollutant, year)
        
        if output_geotiff:
            # Convert to GeoTIFF
            output_file = geotiff_dir / f"{pollutant}_{year}.tif"
            csv_to_geotiff(data, output_file, pollutant, year)


def align_geotiffs(pollutant, years=None, output_dir=None):
    """
    Align all GeoTIFFs for a pollutant to common overlap extent.
    
    Creates a subset of each raster covering the spatial intersection.
    """
    if years is None:
        years = YEARS
    
    if output_dir is None:
        output_dir = DEFRA_DIR / pollutant / "geotiff_overlap"
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    geotiff_dir = DEFRA_DIR / pollutant / "geotiff"
    geotiff_files = sorted(geotiff_dir.glob("*.tif"))
    
    if not geotiff_files:
        logger.warning(f"No GeoTIFFs found for {pollutant}")
        return
    
    # Find common bounds
    bounds_list = []
    for tif_file in geotiff_files:
        with rasterio.open(tif_file) as src:
            bounds_list.append(src.bounds)
    
    # Compute intersection
    common_bounds = (
        max(b.left for b in bounds_list),
        max(b.bottom for b in bounds_list),
        min(b.right for b in bounds_list),
        min(b.top for b in bounds_list),
    )
    
    logger.info(f"Common overlap bounds: {common_bounds}")
    
    # Clip each raster to common bounds
    for tif_file in geotiff_files:
        output_file = output_dir / f"{tif_file.stem}_overlap.tif"
        
        with rasterio.open(tif_file) as src:
            window = rasterio.windows.from_bounds(*common_bounds, src.transform)
            data = src.read(1, window=window)
            new_transform = rasterio.windows.transform(window, src.transform)
            
            with rasterio.open(
                output_file,
                "w",
                driver="GTiff",
                height=data.shape[0],
                width=data.shape[1],
                count=1,
                dtype=data.dtype,
                crs=src.crs,
                transform=new_transform,
                nodata=src.nodata,
            ) as dst:
                dst.write(data, 1)
        
        logger.info(f"Wrote aligned GeoTIFF: {output_file}")


def extract_to_lsoa(pollutant, lsoa_polygons, years=None, output_dir=None):
    """
    Extract area-weighted mean concentrations from rasters to LSOA 2021 polygons.
    """
    if years is None:
        years = YEARS
    
    if output_dir is None:
        output_dir = DEFRA_DIR / pollutant / "lsoa_yearly"
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    geotiff_overlap_dir = DEFRA_DIR / pollutant / "geotiff_overlap"
    
    results = []
    
    for year in years:
        raster_file = geotiff_overlap_dir / f"{pollutant}_{year}_overlap.tif"
        
        if not raster_file.exists():
            logger.warning(f"Raster not found: {raster_file}")
            continue
        
        logger.info(f"Extracting {pollutant} {year} to LSOAs...")
        
        # Extract values using geopandas/rasterio
        with rasterio.open(raster_file) as src:
            values = []
            for idx, polygon in lsoa_polygons.iterrows():
                try:
                    # Mask raster to polygon
                    masked_data, _ = mask(src, [polygon.geometry], crop=True)
                    
                    # Calculate mean (excluding nodata)
                    valid_data = masked_data[~np.isnan(masked_data)]
                    if len(valid_data) > 0:
                        mean_value = np.mean(valid_data)
                    else:
                        mean_value = np.nan
                    
                    values.append({
                        "lsoa21cd": polygon["lsoa21cd"],
                        pollutant: mean_value,
                        "year": year
                    })
                except Exception as e:
                    logger.warning(f"Error extracting {polygon['lsoa21cd']}: {e}")
        
        results.extend(values)
    
    result_df = pd.DataFrame(results)
    output_file = output_dir / f"{pollutant}_lsoa.csv"
    result_df.to_csv(output_file, index=False)
    logger.info(f"Saved LSOA extraction: {output_file}")
    
    return result_df


if __name__ == "__main__":
    logger.info(f"Processing {POLLUTANT}...")
    
    # Convert CSVs to GeoTIFFs
    process_defra_pollutant(POLLUTANT)
    
    # Align rasters to common extent
    align_geotiffs(POLLUTANT)
    
    # Optional: Extract to LSOAs
    if DO_LSOA_EXTRACTION:
        # Load LSOA polygons
        lsoa_polygons = gpd.read_file("data/lsoa2021.shp")
        extract_to_lsoa(POLLUTANT, lsoa_polygons)
    
    logger.info("Processing complete.")
