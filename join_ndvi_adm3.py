"""
Join NDVI summary statistics to administrative boundary polygons (GeoJSON).

Expected inputs:
- A GeoJSON polygon file (e.g. GBR_ADM3.geojson)
- A CSV file containing NDVI metrics keyed by `asdf_id`

This script:
1. Reads the administrative boundary GeoJSON with GeoPandas
2. Reads the NDVI CSV with Pandas
3. Ensures the join field (`asdf_id`) has a consistent type
4. Merges NDVI attributes onto the polygons
5. Preserves geometry and all administrative attributes
6. Writes a spatial output (GeoJSON or GeoPackage)

Useful for mapping and spatial analysis of NDVI trends at the ADM3 level.

Example:

PYTHONPATH=./pydeps python ./data/ndvi/join_ndvi_adm3.py \
  --geojson "./data/ndvi/GBR_ADM3.geojson" \
  --csv "./data/ndvi/6a7b64f0fee22a6cb94a5c82_results.csv" \
  --output "./outputs/GBR_ADM3_NDVI.geojson"

PYTHONPATH=./pydeps python ./data/ndvi/join_ndvi_adm3.py \
  --geojson "./data/ndvi/GBR_ADM3.geojson" \
  --csv "./data/ndvi/6a7b64f0fee22a6cb94a5c82_results.csv" \
  --output "./outputs/GBR_ADM3_NDVI.gpkg"
"""

import argparse
from pathlib import Path

import geopandas as gpd
import pandas as pd


def main():
    parser = argparse.ArgumentParser(
        description="Join NDVI statistics to administrative polygons."
    )

    parser.add_argument(
        "--geojson",
        required=True,
        help="Input GeoJSON polygon file"
    )

    parser.add_argument(
        "--csv",
        required=True,
        help="Input NDVI CSV file"
    )

    parser.add_argument(
        "--output",
        required=True,
        help="Output GeoJSON or GeoPackage file"
    )

    parser.add_argument(
        "--join-field",
        default="asdf_id",
        help="Field used to join spatial and tabular data (default: asdf_id)"
    )

    args = parser.parse_args()

    print(f"Reading GeoJSON: {args.geojson}")
    gdf = gpd.read_file(args.geojson)

    print(f"Reading CSV: {args.csv}")
    df = pd.read_csv(args.csv)

    if args.join_field not in gdf.columns:
        raise ValueError(
            f"Join field '{args.join_field}' not found in GeoJSON."
        )

    if args.join_field not in df.columns:
        raise ValueError(
            f"Join field '{args.join_field}' not found in CSV."
        )

    # Ensure consistent join types
    gdf[args.join_field] = gdf[args.join_field].astype(str)
    df[args.join_field] = df[args.join_field].astype(str)

    print(
        f"Joining on '{args.join_field}' "
        f"({len(gdf)} polygons, {len(df)} table rows)"
    )

    gdf_merged = gdf.merge(
        df,
        on=args.join_field,
        how="left"
    )

    print(f"Output records: {len(gdf_merged)}")
    print(f"Output columns: {len(gdf_merged.columns)}")

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.suffix.lower() == ".gpkg":
        print(f"Writing GeoPackage: {output_path}")
        gdf_merged.to_file(
            output_path,
            layer="ndvi",
            driver="GPKG"
        )

    elif output_path.suffix.lower() in [".geojson", ".json"]:
        print(f"Writing GeoJSON: {output_path}")
        gdf_merged.to_file(
            output_path,
            driver="GeoJSON"
        )

    else:
        raise ValueError(
            "Output must end with .geojson or .gpkg"
        )

    print("Done.")


if __name__ == "__main__":
    main()