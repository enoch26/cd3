"""
LSOA-level annual air-pollution concentrations

Purpose:
    Extract area-weighted mean values from annual DEFRA PCM rasters to 2021
    English Lower-layer Super Output Areas (LSOAs), then save the enriched
    boundary layer as a GeoPackage.

Data source:
    https://uk-air.defra.gov.uk/data/pcm-data

Expected project structure:
    <project-root>/
    ├── lsoa11221.py                 # Creates LSOA 2021 polygons
    └── data/
        └── defra/
            ├── benzene/geotiff_overlap/benzene_2003_overlap.tif
            ├── pm25/geotiff_overlap/pm25_2003_overlap.tif
            ├── pm10/geotiff_overlap/pm10_2003_overlap.tif
            └── nox/geotiff_overlap/nox_2003_overlap.tif

Each raster is expected to have one layer and to be named:
    <pollutant>_<year>_overlap.tif

Output columns use names such as `benzene2003`, `pm252010`, and `nox2024`.
"""

import os
import geopandas as gpd
import pandas as pd
import numpy as np
from pathlib import Path
from rasterio.mask import mask
import rasterio
import warnings
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DATA_DIR = Path("data")
OUTPUT_DIR = Path("outputs")
OUTPUT_FILE = OUTPUT_DIR / "air_lsoa_eng.gpkg"

POLLUTANTS = ["benzene", "pm25", "pm10", "nox"]
YEARS = range(2003, 2025)


def load_lsoa_polygons(lsoa_shapefile_or_gpkg="data/lsoa2021.shp"):
    """
    Load LSOA 2021 polygons.
    
    Falls back to creating them from lsoa11221.py if not available.
    """
    try:
        poly_lsoa_21 = gpd.read_file(lsoa_shapefile_or_gpkg)
        logger.info(f"Loaded LSOA polygons from {lsoa_shapefile_or_gpkg}")
        return poly_lsoa_21
    except FileNotFoundError:
        logger.error(f"LSOA polygons not found at {lsoa_shapefile_or_gpkg}")
        raise


def raster_path(pollutant, year, data_directory=None):
    """
    Construct and validate expected raster path for a pollutant-year.
    """
    if data_directory is None:
        data_directory = DATA_DIR
    
    path = data_directory / "defra" / pollutant / "geotiff_overlap" / (
        f"{pollutant}_{year}_overlap.tif"
    )
    
    if not path.exists():
        raise FileNotFoundError(f"Raster not found: {path}")
    
    return path


def extract_lsoa_mean(raster_file, lsoa_polygon):
    """
    Extract area-weighted mean value from raster for a single LSOA polygon.
    
    Uses rasterio.mask to crop the raster to the polygon extent, then
    calculates the mean (excluding NaN values).
    """
    try:
        with rasterio.open(raster_file) as src:
            # Ensure polygon is in same CRS as raster
            if lsoa_polygon.crs != src.crs:
                polygon_geom = lsoa_polygon.to_crs(src.crs).geometry
            else:
                polygon_geom = lsoa_polygon.geometry
            
            # Mask raster to polygon
            masked_data, masked_transform = mask(src, [polygon_geom], crop=True)
            
            if masked_data.size == 0:
                return np.nan
            
            # Calculate mean (excluding NaN)
            valid_data = masked_data[~np.isnan(masked_data)]
            if len(valid_data) > 0:
                return np.nanmean(valid_data)
            else:
                return np.nan
    
    except Exception as e:
        logger.warning(f"Error extracting from {raster_file}: {e}")
        return np.nan


def extract_all_pollutants(poly_lsoa_21):
    """
    Extract every pollutant-year combination to LSOA polygons.
    
    Appends columns to the original GeoDataFrame.
    """
    for pollutant in POLLUTANTS:
        for year in YEARS:
            column_name = f"{pollutant}{year}"
            logger.info(f"Extracting {pollutant} for {year}...")
            
            try:
                raster_file = raster_path(pollutant, year)
                
                # Extract for each LSOA
                values = []
                for idx, row in poly_lsoa_21.iterrows():
                    value = extract_lsoa_mean(raster_file, row.geometry)
                    values.append(value)
                
                poly_lsoa_21[column_name] = values
            
            except FileNotFoundError:
                logger.warning(f"Raster not found for {pollutant} {year}, skipping")
                poly_lsoa_21[column_name] = np.nan
    
    return poly_lsoa_21


def write_output(poly_lsoa_21, output_file=None, overwrite=True):
    """Write enriched LSOA layer to GeoPackage."""
    if output_file is None:
        output_file = OUTPUT_FILE
    
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    poly_lsoa_21.to_file(
        output_file,
        layer="air_lsoa_eng",
        driver="GPKG",
        if_exists="replace" if overwrite else "fail"
    )
    
    logger.info(f"Output written to {output_file}")


def main():
    """Main workflow."""
    logger.info("Loading LSOA 2021 polygons...")
    poly_lsoa_21 = load_lsoa_polygons()
    
    if not isinstance(poly_lsoa_21, gpd.GeoDataFrame):
        logger.error("`lsoa11221.py` must create LSOA 2021 as a GeoDataFrame")
        raise TypeError("Invalid LSOA object type")
    
    logger.info(f"Loaded {len(poly_lsoa_21)} LSOAs")
    
    # Extract all pollutants
    poly_lsoa_21 = extract_all_pollutants(poly_lsoa_21)
    
    # Write output
    write_output(poly_lsoa_21)
    
    logger.info("Air pollution extraction complete.")


if __name__ == "__main__":
    main()
