#!/usr/bin/env python3
"""
Compute annual average raster values per polygon from NetCDF grids.

Expected inputs:
- One or more NetCDF files with gridded data over Europe
- An LSOA shapefile for England or England+Wales (or any polygon file readable by GeoPandas)

This script:
1. Opens all matching NetCDF files
2. Selects a data variable
3. Averages over the time dimension to annual means if needed
4. Reprojects polygons to the raster CRS if needed
5. Computes zonal statistics (mean) for each polygon
6. Writes one combined CSV

Useful for LSOA analysis. If you pass an England+Wales LSOA shapefile,
use --england-only to keep only codes beginning with 'E'.

Example:
PYTHONPATH=./pydeps python annual_lsoa_average_england.py \
  --nc-glob "./data/drought_data/VHI_ref_to_month_europe_*.nc" \
  --shapefile "./data/lsoa/LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3)/LSOA_2021_EW_BFE_V10.shp" \
  --id-field LSOA21CD \
  --output "./outputs/vci_lsoa_annual_mean.csv" \
  --variable VCI \
  --england-only \
  --force-crs EPSG:4326

python annual_lsoa_average_england.py \
  --nc-glob "./drought_data/VHI_ref_to_month_europe_*.nc" \
  --shapefile "./LSOA_2021_EW_BFE_V10.shp" \
  --id-field LSOA21CD \
  --output "./outputs/vhi_lsoa_annual_mean.csv" \
  --variable VHI \
  --england-only
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import warnings
from typing import Optional

import geopandas as gpd
import numpy as np
import pandas as pd
import rioxarray  # noqa: F401  # activates the .rio accessor
import xarray as xr
from rasterio.crs import CRS
from rasterio.transform import from_bounds
from rasterstats import zonal_stats

YEAR_RE = re.compile(r"(19|20)\d{2}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Annual average per polygon from NetCDF grids")
    parser.add_argument(
        "--nc-glob",
        required=True,
        help="Glob for NetCDF files, e.g. './drought_data/VHI_ref_to_month_europe_*.nc'",
    )
    parser.add_argument("--shapefile", required=True, help="Path to polygon shapefile")
    parser.add_argument("--id-field", required=True, help="Unique polygon ID field, e.g. LSOA11CD or LSOA21CD")
    parser.add_argument("--output", required=True, help="Output CSV path")
    parser.add_argument(
        "--variable",
        default=None,
        help="NetCDF variable name. If omitted, first likely 2D/3D numeric data variable is used",
    )
    parser.add_argument("--all-touched", action="store_true", help="Use all_touched=True in zonal stats")
    parser.add_argument(
        "--england-only",
        action="store_true",
        help="Keep only polygons whose ID starts with 'E' (useful for England-only filtering from EW files)",
    )
    parser.add_argument(
        "--min-time-steps-warning",
        type=int,
        default=12,
        help="Warn if a file has fewer than this many time steps before averaging; default is 12",
    )
    parser.add_argument(
        "--force-crs",
        default=None,
        help="Force raster CRS, e.g. 'EPSG:4326'. Optional, but useful if NetCDF CRS metadata are inconsistent.",
    )
    return parser.parse_args()


def infer_year(path: str) -> Optional[int]:
    m = YEAR_RE.search(os.path.basename(path))
    return int(m.group(0)) if m else None


def pick_data_var(ds: xr.Dataset, requested: Optional[str] = None) -> str:
    if requested:
        if requested not in ds.data_vars:
            raise ValueError(f"Variable '{requested}' not found. Available: {list(ds.data_vars)}")
        return requested

    candidates = []
    for name, da in ds.data_vars.items():
        if da.ndim >= 2 and np.issubdtype(da.dtype, np.number):
            candidates.append(name)
    if not candidates:
        raise ValueError("No suitable numeric raster variable found in dataset")
    return candidates[0]


def standardize_spatial_dims(da: xr.DataArray) -> xr.DataArray:
    rename_map = {}
    for dim in da.dims:
        low = dim.lower()
        if low in {"longitude", "lon", "x"}:
            rename_map[dim] = "x"
        elif low in {"latitude", "lat", "y"}:
            rename_map[dim] = "y"
    da = da.rename(rename_map)
    if "x" not in da.dims or "y" not in da.dims:
        raise ValueError(f"Could not identify spatial dims in {da.dims}")
    return da


def infer_raster_crs(ds: xr.Dataset, da: xr.DataArray, forced: Optional[str] = None):
    """
    Infer CRS from common NetCDF conventions.

    For the CEH drought files, data are lon/lat grids with a scalar CF grid-mapping
    variable named 'crs'. Some environments do not expose this cleanly through rioxarray,
    so we explicitly inspect CF metadata and fall back to EPSG:4326.
    """
    if forced:
        return CRS.from_string(forced)

    try:
        crs = da.rio.crs
        if crs is not None:
            return crs
    except Exception:
        pass

    grid_mapping_name = da.attrs.get("grid_mapping") or ds.attrs.get("grid_mapping")
    if grid_mapping_name and grid_mapping_name in ds.variables:
        crs_var = ds[grid_mapping_name]

        epsg_code = crs_var.attrs.get("EPSG_code") or crs_var.attrs.get("epsg_code")
        if epsg_code:
            try:
                return CRS.from_string(str(epsg_code))
            except Exception:
                pass

        if crs_var.attrs.get("grid_mapping_name") == "latitude_longitude":
            return CRS.from_epsg(4326)

    dim_names = {d.lower() for d in da.dims}
    coord_names = {c.lower() for c in ds.coords}
    if (
        {"lon", "lat"}.issubset(dim_names)
        or {"longitude", "latitude"}.issubset(dim_names)
        or {"lon", "lat"}.issubset(coord_names)
        or {"longitude", "latitude"}.issubset(coord_names)
    ):
        return CRS.from_epsg(4326)

    return CRS.from_epsg(4326)


def annual_mean_from_file(
    path: str,
    variable: Optional[str] = None,
    min_time_steps_warning: int = 12,
    force_crs: Optional[str] = None,
) -> tuple[int, xr.DataArray]:
    ds = xr.open_dataset(path)
    var = pick_data_var(ds, variable)
    da = standardize_spatial_dims(ds[var])

    raster_crs = infer_raster_crs(ds, da, forced=force_crs)
    da = da.rio.write_crs(raster_crs)

    year = infer_year(path)
    if year is None:
        if "time" in da.coords:
            year = pd.to_datetime(da["time"].values[0]).year
        else:
            raise ValueError(f"Could not infer year from filename: {path}")

    if "time" in da.dims:
        n_time = int(da.sizes["time"])
        if n_time < min_time_steps_warning:
            warnings.warn(
                f"File '{os.path.basename(path)}' has only {n_time} time steps; "
                f"annual mean will be based on available steps, not necessarily a full year."
            )
        da = da.mean(dim="time", skipna=True)

    return year, da.squeeze()


def make_transform(da: xr.DataArray):
    x = np.asarray(da["x"].values)
    y = np.asarray(da["y"].values)
    if x.ndim != 1 or y.ndim != 1:
        raise ValueError("This script expects 1D x/y coordinates")

    arr = np.asarray(da.values)
    if x[0] > x[-1]:
        x = x[::-1]
        arr = arr[:, ::-1]
    if y[0] > y[-1]:
        y = y[::-1]
        arr = arr[::-1, :]

    dx = float(np.mean(np.diff(x)))
    dy = float(np.mean(np.diff(y)))
    west = float(x.min() - dx / 2)
    east = float(x.max() + dx / 2)
    south = float(y.min() - dy / 2)
    north = float(y.max() + dy / 2)
    transform = from_bounds(west, south, east, north, arr.shape[1], arr.shape[0])
    return arr, transform


def zonal_mean_for_year(gdf: gpd.GeoDataFrame, da: xr.DataArray, all_touched: bool = False) -> list[float]:
    arr, transform = make_transform(da)
    nodata = np.nan
    stats = zonal_stats(
        vectors=gdf.geometry,
        raster=arr,
        affine=transform,
        stats=["mean"],
        nodata=nodata,
        all_touched=all_touched,
        geojson_out=False,
    )
    return [item.get("mean", np.nan) for item in stats]


def main() -> None:
    args = parse_args()

    nc_files = sorted(glob.glob(args.nc_glob))
    if not nc_files:
        raise FileNotFoundError(f"No NetCDF files matched: {args.nc_glob}")

    gdf = gpd.read_file(args.shapefile)
    if args.id_field not in gdf.columns:
        raise ValueError(f"ID field '{args.id_field}' not found in shapefile. Available: {list(gdf.columns)}")

    print(f"Loaded shapefile: {args.shapefile}")
    print(f"Original feature count: {len(gdf)}")
    print(f"Shapefile CRS: {gdf.crs}")

    gdf = gdf[[args.id_field, "geometry"]].copy()
    gdf = gdf[gdf.geometry.notnull()].copy()
    gdf = gdf[gdf.is_valid].copy()
    gdf = gdf.drop_duplicates(subset=[args.id_field]).copy()

    if args.england_only:
        before = len(gdf)
        gdf = gdf[gdf[args.id_field].astype(str).str.startswith("E")].copy()
        print(f"Applied England-only filter on {args.id_field}: {before} -> {len(gdf)} features")

    if gdf.empty:
        raise ValueError("No polygons remain after filtering/validation")
    if gdf.crs is None:
        raise ValueError("Shapefile has no CRS defined. Please define it before running.")

    results = []

    for i, path in enumerate(nc_files, start=1):
        year, da = annual_mean_from_file(
            path,
            variable=args.variable,
            min_time_steps_warning=args.min_time_steps_warning,
            force_crs=args.force_crs,
        )

        raster_crs = da.rio.crs
        if raster_crs is None:
            raster_crs = CRS.from_epsg(4326)
            da = da.rio.write_crs(raster_crs)

        gdf_year = gdf
        if gdf.crs != raster_crs:
            gdf_year = gdf.to_crs(raster_crs)

        means = zonal_mean_for_year(gdf_year, da, all_touched=args.all_touched)
        year_df = pd.DataFrame(
            {
                args.id_field: gdf[args.id_field].values,
                "year": year,
                "annual_mean": means,
                "source_file": os.path.basename(path),
            }
        )
        results.append(year_df)
        print(f"[{i}/{len(nc_files)}] Finished {os.path.basename(path)}")

    out_df = pd.concat(results, ignore_index=True)
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    out_df.to_csv(args.output, index=False)
    print(f"Saved: {args.output}")


if __name__ == "__main__":
    main()
