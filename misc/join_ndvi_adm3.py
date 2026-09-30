#!/usr/bin/env python3
"""Join LTDR AVHRR NDVI summary statistics to administrative polygons.

The NDVI data used with this workflow can be obtained from AidData's
LTDR AVHRR NDVI V5 yearly GeoQuery dataset:
https://www.aiddata.org/geoquery-datasets/ltdr-avhrr-ndvi-v5-yearly

The script performs a left join: every input administrative polygon remains
in the output, while matching NDVI fields from the CSV are appended.

Examples
--------
Write GeoJSON:
    PYTHONPATH=./pydeps python ./data/ndvi/join_ndvi_adm3.py \
      --boundaries ./data/ndvi/GBR_ADM3.geojson \
      --table ./data/ndvi/6a7b64f0fee22a6cb94a5c82_results.csv \
      --output ./outputs/GBR_ADM3_NDVI.geojson

Write GeoPackage:
    PYTHONPATH=./pydeps python ./data/ndvi/join_ndvi_adm3.py \
      --boundaries ./data/ndvi/GBR_ADM3.geojson \
      --table ./data/ndvi/6a7b64f0fee22a6cb94a5c82_results.csv \
      --output ./outputs/GBR_ADM3_NDVI.gpkg \
      --layer ndvi_adm3

Dependencies
------------
    pip install geopandas pandas
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

import geopandas as gpd
import pandas as pd

SUPPORTED_OUTPUTS = {".geojson": "GeoJSON", ".json": "GeoJSON", ".gpkg": "GPKG"}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Join NDVI summary statistics from a CSV to administrative boundary "
            "polygons and write a GeoJSON or GeoPackage."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--boundaries",
        "--geojson",
        dest="boundaries",
        required=True,
        help="Input administrative boundary file readable by GeoPandas.",
    )
    parser.add_argument(
        "--table",
        "--csv",
        dest="table",
        required=True,
        help="CSV containing NDVI summary statistics.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Destination file ending in .geojson, .json, or .gpkg.",
    )
    parser.add_argument(
        "--join-field",
        default="asdf_id",
        help="Shared identifier column in the boundary file and CSV.",
    )
    parser.add_argument(
        "--layer",
        default="ndvi",
        help="GeoPackage layer name; ignored for GeoJSON output.",
    )
    parser.add_argument(
        "--allow-duplicate-table-keys",
        action="store_true",
        help=(
            "Allow duplicate join keys in the CSV. This may duplicate polygons "
            "in the output, so it is disabled by default."
        ),
    )
    return parser.parse_args(argv)


def require_column(frame: pd.DataFrame, column: str, source_name: str) -> None:
    """Raise a clear error if a required column is absent."""
    if column not in frame.columns:
        available = ", ".join(map(str, frame.columns))
        raise ValueError(
            f"Join field '{column}' was not found in {source_name}. "
            f"Available columns: {available}"
        )


def normalise_join_key(series: pd.Series) -> pd.Series:
    """Return a nullable string join key with surrounding whitespace removed."""
    return series.astype("string").str.strip()


def summarise_join(
    boundaries: gpd.GeoDataFrame,
    table: pd.DataFrame,
    join_field: str,
) -> None:
    """Print concise diagnostics for the requested left join."""
    boundary_keys = set(boundaries[join_field].dropna())
    table_keys = set(table[join_field].dropna())
    matched = boundary_keys & table_keys

    print(f"Boundary polygons: {len(boundaries):,}")
    print(f"NDVI table rows: {len(table):,}")
    print(f"Unique boundary keys: {len(boundary_keys):,}")
    print(f"Unique NDVI keys: {len(table_keys):,}")
    print(f"Matching keys: {len(matched):,}")
    print(f"Boundary keys without NDVI data: {len(boundary_keys - table_keys):,}")
    print(f"NDVI keys without a boundary polygon: {len(table_keys - boundary_keys):,}")


def write_output(gdf: gpd.GeoDataFrame, output_path: Path, layer: str) -> None:
    """Write a GeoDataFrame to a supported spatial output format."""
    suffix = output_path.suffix.lower()
    driver = SUPPORTED_OUTPUTS.get(suffix)
    if driver is None:
        valid = ", ".join(SUPPORTED_OUTPUTS)
        raise ValueError(f"Unsupported output extension '{suffix}'. Use one of: {valid}.")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if driver == "GPKG":
        print(f"Writing GeoPackage layer '{layer}': {output_path}")
        gdf.to_file(output_path, layer=layer, driver=driver)
    else:
        print(f"Writing GeoJSON: {output_path}")
        gdf.to_file(output_path, driver=driver)


def main(argv: Sequence[str] | None = None) -> None:
    """Run the NDVI-to-boundary join workflow."""
    args = parse_args(argv)
    boundaries_path = Path(args.boundaries)
    table_path = Path(args.table)
    output_path = Path(args.output)

    if not boundaries_path.is_file():
        raise FileNotFoundError(f"Boundary file not found: {boundaries_path}")
    if not table_path.is_file():
        raise FileNotFoundError(f"NDVI CSV file not found: {table_path}")

    print(f"Reading boundaries: {boundaries_path}")
    boundaries = gpd.read_file(boundaries_path)
    if boundaries.empty:
        raise ValueError("The boundary file contains no features.")

    print(f"Reading NDVI table: {table_path}")
    ndvi = pd.read_csv(table_path)
    if ndvi.empty:
        raise ValueError("The NDVI CSV contains no rows.")

    require_column(boundaries, args.join_field, "the boundary file")
    require_column(ndvi, args.join_field, "the NDVI CSV")

    boundaries = boundaries.copy()
    ndvi = ndvi.copy()
    boundaries[args.join_field] = normalise_join_key(boundaries[args.join_field])
    ndvi[args.join_field] = normalise_join_key(ndvi[args.join_field])

    duplicate_table_keys = ndvi[args.join_field].duplicated(keep=False)
    if duplicate_table_keys.any() and not args.allow_duplicate_table_keys:
        examples = ndvi.loc[duplicate_table_keys, args.join_field].dropna().unique()[:5]
        example_text = ", ".join(map(str, examples))
        raise ValueError(
            "The NDVI CSV has duplicate join keys, which would duplicate polygons "
            f"after merging. Example key(s): {example_text}. Aggregate the table "
            "first, or explicitly use --allow-duplicate-table-keys."
        )

    print(f"Joining on '{args.join_field}'")
    summarise_join(boundaries, ndvi, args.join_field)

    merged = boundaries.merge(
        ndvi,
        on=args.join_field,
        how="left",
        validate=None if args.allow_duplicate_table_keys else "many_to_one",
    )

    if len(merged) != len(boundaries) and not args.allow_duplicate_table_keys:
        raise RuntimeError("Unexpected output row count after a validated left join.")

    print(f"Output polygons: {len(merged):,}")
    print(f"Output columns: {len(merged.columns):,}")
    write_output(merged, output_path, args.layer)
    print("Done.")


if __name__ == "__main__":
    main()
