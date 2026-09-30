"""
Transfer annual NDVI means from ADM3 polygons to England LSOA 2021 areas.
call join_ndvi_adm3.py first to create the ADM3 NDVI file.

Expected inputs:
- LSOA 2021 boundary shapefile
- ADM3 polygon file containing annual NDVI variables

This script:
1. Reads LSOA polygons
2. Reads ADM3 polygons with NDVI attributes
3. Reprojects both layers to a projected CRS
4. Intersects LSOAs and ADM3 polygons
5. Computes overlap areas
6. Produces area-weighted annual NDVI estimates for each LSOA
7. Writes a CSV with one row per LSOA

Example:

PYTHONPATH=./pydeps python lsoa_ndvi_from_adm3.py \
  --lsoa "./data/lsoa/LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3)/LSOA_2021_EW_BFE_V10.shp" \
  --adm3 "./outputs/GBR_ADM3_NDVI.gpkg" \
  --id-field LSOA21CD \
  --output "./outputs/lsoa_ndvi_annual.csv"
"""

import argparse

import geopandas as gpd
import pandas as pd


def main():

    parser = argparse.ArgumentParser(
        description="Area-weighted transfer of ADM3 NDVI values to LSOA polygons"
    )

    parser.add_argument(
        "--lsoa",
        required=True,
        help="LSOA boundary shapefile"
    )

    parser.add_argument(
        "--adm3",
        required=True,
        help="ADM3 polygons containing NDVI attributes"
    )

    parser.add_argument(
        "--id-field",
        default="LSOA21CD",
        help="LSOA identifier field"
    )

    parser.add_argument(
        "--output",
        required=True,
        help="Output CSV"
    )

    args = parser.parse_args()

    print("Reading LSOA polygons...")
    lsoa = gpd.read_file(args.lsoa)

    print("Reading ADM3 polygons...")
    adm3 = gpd.read_file(args.adm3)

    print(f"LSOAs: {len(lsoa):,}")
    print(f"ADM3 polygons: {len(adm3):,}")

    # Use British National Grid for area calculations
    target_crs = "EPSG:27700"

    print(f"Reprojecting to {target_crs}...")
    lsoa = lsoa.to_crs(target_crs)
    adm3 = adm3.to_crs(target_crs)

    # Find all annual NDVI columns
    ndvi_cols = [
        c for c in adm3.columns
        if c.startswith("ltdr_avhrr_ndvi")
    ]

    if len(ndvi_cols) == 0:
        raise ValueError(
            "No NDVI columns found. Expected columns beginning with "
            "'ltdr_avhrr_ndvi'"
        )

    print(f"Found {len(ndvi_cols)} NDVI variables")

    adm3 = adm3[
        ["asdf_id"] + ndvi_cols + ["geometry"]
    ]

    print("Calculating intersections...")
    intersections = gpd.overlay(
        lsoa[[args.id_field, "geometry"]],
        adm3,
        how="intersection"
    )

    print(f"Created {len(intersections):,} intersected features")

    intersections["area_m2"] = intersections.geometry.area

    # Area-weighted numerator
    for col in ndvi_cols:
        intersections[f"weighted_{col}"] = (
            intersections[col]
            * intersections["area_m2"]
        )

    agg_dict = {
        "area_m2": "sum"
    }

    for col in ndvi_cols:
        agg_dict[f"weighted_{col}"] = "sum"

    print("Aggregating to LSOA level...")

    result = (
        intersections
        .groupby(args.id_field)
        .agg(agg_dict)
        .reset_index()
    )

    for col in ndvi_cols:
        result[col] = (
            result[f"weighted_{col}"]
            / result["area_m2"]
        )

    weighted_cols = [
        c for c in result.columns
        if c.startswith("weighted_")
    ]

    result = result.drop(
        columns=weighted_cols + ["area_m2"]
    )

    print(f"Writing {len(result):,} LSOAs...")
    result.to_csv(args.output, index=False)

    print("Done.")
    print(f"Output written to: {args.output}")


if __name__ == "__main__":
    main()