"""
LSOA 2001-2021 area-weighted crosswalks

Purpose:
    Build England-only LSOA correspondence weights for:
    - LSOA 2001 -> LSOA 2011
    - LSOA 2011 -> LSOA 2021
    - LSOA 2001 -> LSOA 2021 (via 2011)

    Weights are area-based. They are suitable for transferring additive measures
    (for example, counts or totals) only where a uniform within-LSOA distribution
    is an acceptable assumption.

Data downloads:
    - 2001 -> 2011 lookup:
      https://www.data.gov.uk/dataset/4048a518-3eaf-457a-905c-9e04f4fffca8/
    - 2011 -> 2021 lookup:
      https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/
    - 2001 boundary: ONS Geoportal (LSOA_2001_EW_BFE_V2.shp)
    - 2011 boundary: ONS Geoportal (LSOA_2011_EW_BFC_V3.shp)
    - 2021 boundary: ONS Geoportal (LSOA_2021_EW_BFE_V10.shp)

Expected project layout:
    <project-root>/
    └── data/
        └── lsoa/
            ├── LSOA_2001_EW_BFE_V2.shp (+ companion files)
            ├── LSOA_2011_EW_BFC_V3.shp (+ companion files)
            ├── LSOA_2021_EW_BFE_V10.shp (+ companion files)
            ├── Lower_Layer_Super_Output_Area_(2001)_to_...
            └── LSOA_(2011)_to_LSOA_(2021)_to_...
"""

import os
import geopandas as gpd
import pandas as pd
from pathlib import Path

# Configuration
AREA_CRS = 27700  # British National Grid (EPSG:27700)
DATA_DIR = Path("data/lsoa")

# File paths
LSOA_2001_SHAPEBASE = "LSOA_2001_EW_BFE_V2"
LSOA_2011_SHAPEBASE = "LSOA_2011_EW_BFC_V3"
LSOA_2021_SHAPEBASE = "LSOA_2021_EW_BFE_V10"
LOOKUP_2001_2011 = "Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv"
LOOKUP_2011_2021 = "LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_England_and_Wales_V3.csv"


def load_lsoa_boundaries():
    """Load LSOA boundary shapefiles for 2001, 2011, and 2021."""
    lsoa_2001 = gpd.read_file(DATA_DIR / f"{LSOA_2001_SHAPEBASE}.shp")
    lsoa_2011 = gpd.read_file(DATA_DIR / f"{LSOA_2011_SHAPEBASE}.shp")
    lsoa_2021 = gpd.read_file(DATA_DIR / f"{LSOA_2021_SHAPEBASE}.shp")
    
    # Ensure all use the same CRS for area calculations
    lsoa_2001 = lsoa_2001.to_crs(AREA_CRS)
    lsoa_2011 = lsoa_2011.to_crs(AREA_CRS)
    lsoa_2021 = lsoa_2021.to_crs(AREA_CRS)
    
    # Filter to England only (country code or similar field)
    # Adjust filter condition based on actual shapefile attributes
    lsoa_2001 = lsoa_2001[lsoa_2001["lsoa01cd"].str.startswith("E")]
    lsoa_2011 = lsoa_2011[lsoa_2011["lsoa11cd"].str.startswith("E")]
    lsoa_2021 = lsoa_2021[lsoa_2021["lsoa21cd"].str.startswith("E")]
    
    return lsoa_2001, lsoa_2011, lsoa_2021


def compute_area_weights_2d(source_gdf, target_gdf, source_col, target_col):
    """
    Compute area-based weights for geographic crosswalks.
    
    For each target area, calculate the fraction of its area covered by each
    source area. Returns a DataFrame with columns: source_col, target_col, weight.
    """
    # Spatial join to identify overlaps
    overlap = gpd.sjoin(source_gdf[[source_col, "geometry"]], 
                        target_gdf[[target_col, "geometry"]], 
                        how="inner", 
                        predicate="intersects")
    
    # Calculate intersection areas
    intersections = []
    for idx, row in overlap.iterrows():
        source_id = row[source_col]
        target_id = row[target_col]
        source_geom = source_gdf[source_gdf[source_col] == source_id].geometry.iloc[0]
        target_geom = target_gdf[target_gdf[target_col] == target_id].geometry.iloc[0]
        
        intersection = source_geom.intersection(target_geom)
        if not intersection.is_empty:
            intersection_area = intersection.area
            target_area = target_geom.area
            weight = intersection_area / target_area if target_area > 0 else 0
            intersections.append({
                source_col: source_id,
                target_col: target_id,
                "weight": weight
            })
    
    weights_df = pd.DataFrame(intersections)
    
    # Normalize weights to sum to 1 within each target area
    weights_df["weight"] = weights_df.groupby(target_col)["weight"].transform(
        lambda x: x / x.sum()
    )
    
    return weights_df


def create_area_weights():
    """Create all area-weight crosswalks."""
    print("Loading LSOA boundaries...")
    lsoa_2001, lsoa_2011, lsoa_2021 = load_lsoa_boundaries()
    
    print("Computing 2001 -> 2011 weights...")
    weights_2001_2011 = compute_area_weights_2d(
        lsoa_2001, lsoa_2011, "lsoa01cd", "lsoa11cd"
    )
    weights_2001_2011.to_csv(
        DATA_DIR.parent / "derived" / "lsoa_2001_2011_area_weights.csv", 
        index=False
    )
    
    print("Computing 2011 -> 2021 weights...")
    weights_2011_2021 = compute_area_weights_2d(
        lsoa_2011, lsoa_2021, "lsoa11cd", "lsoa21cd"
    )
    weights_2011_2021.to_csv(
        DATA_DIR.parent / "derived" / "lsoa_2011_2021_area_weights.csv", 
        index=False
    )
    
    print("Creating transitive 2001 -> 2021 weights...")
    # Chain weights through 2011
    weights_chained = weights_2001_2011.merge(
        weights_2011_2021, 
        left_on="lsoa11cd", 
        right_on="lsoa11cd"
    )
    weights_chained["weight"] = (
        weights_chained["weight_x"] * weights_chained["weight_y"]
    )
    weights_2001_2021 = weights_chained[["lsoa01cd", "lsoa21cd", "weight"]].copy()
    weights_2001_2021.columns = ["lsoa01cd", "lsoa21cd", "weight"]
    weights_2001_2021.to_csv(
        DATA_DIR.parent / "derived" / "lsoa_2001_2021_area_weights.csv", 
        index=False
    )
    
    print("All crosswalks created successfully.")
    return lsoa_2001, lsoa_2011, lsoa_2021


if __name__ == "__main__":
    # Ensure output directory exists
    output_dir = Path("data/derived")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    create_area_weights()
