"""
JAXA GLI / MODIS / SeaWiFS SWR and PAR binary-grid reader

Purpose:
    Read JAXA EORC Level-3 direct-access, unformatted binary files, convert
    digital numbers to physical units, build a longitude/latitude raster,
    and optionally export a GeoTIFF and PNG map for every file.

Data and format documentation:
    https://suzaku.eorc.jaxa.jp/GLI/data/final/landpar/index.html
    https://kuroshio.eorc.jaxa.jp/JASMES/docs/PAR_Thai.html

Assumptions for MOD02SSH / MYD02SSH SWR files named `*_7200_3601_swr__le`:
    * 2,880-byte ASCII header;
    * 7,200 longitude pixels by 3,601 latitude lines;
    * signed, 16-bit integer values; and
    * direct-access binary layout, with NO Fortran sequential record markers.

The native grid has centres beginning at 0 degrees E and 90 degrees N,
at 0.05-degree resolution. It is converted from 0–360 degrees longitude to
-180–180 degrees longitude with rasterio/rioxarray rotation.

IMPORTANT:
    Confirm the dimensions, header size, byte order, scale factor, and missing
    value convention against the readme supplied with the particular product.
    If values are implausible, first try endian = "big".
"""

import struct
import numpy as np
import rasterio
from rasterio.transform import from_bounds
from pathlib import Path
import logging
import warnings
from typing import Optional, Tuple
import matplotlib.pyplot as plt

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
INPUT_DIR = Path("data/jaxa_swr")
OUTPUT_DIR = Path("outputs/swr")

# MODIS / SeaWiFS SWR product settings
# ADJUST THESE for another product or format
GRID_NCOL = 7200
GRID_NROW = 3601
HEADER_BYTES = 2880
CELL_SIZE = 0.05
SCALE_FACTOR = 0.01
ADD_OFFSET = 0
BYTE_ORDER = "little"  # Options: "little" or "big"
MISSING_RAW_VALUES = [-9999]  # Values to treat as missing data


class JAXAHeaderParser:
    """Parse fixed-width JAXA Fortran header format."""
    
    # Format: (2I6, 2F8.2, F8.4, 2E12.5, A1, A8, A1, A40)
    # Maps to positions in the header string
    
    @staticmethod
    def parse_header(header_text: str) -> dict:
        """
        Parse JAXA fixed-width header.
        
        Returns dict with extracted fields.
        """
        try:
            # Extract fields by position (adjust if format differs)
            header = {
                "ncol": int(header_text[0:6].strip()),
                "nrow": int(header_text[6:12].strip()),
                "west": float(header_text[12:20].strip()),
                "south": float(header_text[20:28].strip()),
                "cellsize": float(header_text[28:36].strip()),
                # Additional fields as needed
            }
            return header
        except (ValueError, IndexError) as e:
            logger.warning(f"Failed to parse header: {e}")
            return None


def read_jaxa_binary(
    filepath: Path,
    ncol: int = GRID_NCOL,
    nrow: int = GRID_NROW,
    header_bytes: int = HEADER_BYTES,
    dtype_code: str = "h",  # signed short (16-bit)
    byte_order: str = BYTE_ORDER,
    scale_factor: float = SCALE_FACTOR,
    add_offset: float = ADD_OFFSET,
    missing_values: list = None
) -> Optional[np.ndarray]:
    """
    Read JAXA binary file and convert to physical units.
    
    Args:
        filepath: Path to binary file
        ncol, nrow: Grid dimensions
        header_bytes: Bytes to skip (Fortran header)
        dtype_code: NumPy dtype code (e.g., 'h' for int16)
        byte_order: '<' for little-endian, '>' for big-endian
        scale_factor: Multiply raw values by this
        add_offset: Add this after scaling
        missing_values: List of raw values to treat as missing
    
    Returns:
        2D NumPy array, or None on error
    """
    if missing_values is None:
        missing_values = MISSING_RAW_VALUES
    
    try:
        with open(filepath, "rb") as f:
            # Skip header
            f.seek(header_bytes)
            
            # Read grid data
            n_cells = ncol * nrow
            dtype_str = f"{byte_order}{dtype_code}"
            data = np.fromfile(f, dtype=np.dtype(dtype_str), count=n_cells)
            
            if len(data) != n_cells:
                logger.warning(
                    f"Expected {n_cells} cells, read {len(data)} "
                    f"(check dimensions and byte order)"
                )
            
            # Reshape to grid
            grid = data.reshape((nrow, ncol))
            
            # Convert to physical units
            # Replace missing values with NaN first
            for missing_val in missing_values:
                grid[grid == missing_val] = np.nan
            
            # Scale and offset
            grid = grid.astype(np.float32) * scale_factor + add_offset
            
            return grid
    
    except FileNotFoundError:
        logger.error(f"File not found: {filepath}")
        return None
    except Exception as e:
        logger.error(f"Error reading {filepath}: {e}")
        return None


def build_raster_transform(
    cell_size: float = CELL_SIZE,
    grid_width: int = GRID_NCOL,
    grid_height: int = GRID_NROW,
    west: float = 0.0,
    north: float = 90.0
) -> rasterio.transform.Affine:
    """
    Build geospatial transform for regular grid.
    
    Assumes north-up orientation with origin at top-left.
    """
    # Calculate bounds
    east = west + (grid_width * cell_size)
    south = north - (grid_height * cell_size)
    
    # Rasterio transform: (x_res, 0, west, 0, -y_res, north)
    transform = from_bounds(west, south, east, north, grid_width, grid_height)
    
    return transform


def save_geotiff(
    data: np.ndarray,
    output_path: Path,
    crs: str = "EPSG:4326",
    transform: Optional[rasterio.transform.Affine] = None
) -> bool:
    """Save array to GeoTIFF."""
    try:
        if transform is None:
            transform = build_raster_transform()
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with rasterio.open(
            output_path,
            "w",
            driver="GTiff",
            height=data.shape[0],
            width=data.shape[1],
            count=1,
            dtype=data.dtype,
            crs=crs,
            transform=transform,
            nodata=np.nan,
        ) as dst:
            dst.write(data, 1)
        
        logger.info(f"Saved GeoTIFF: {output_path}")
        return True
    
    except Exception as e:
        logger.error(f"Failed to save {output_path}: {e}")
        return False


def save_png(
    data: np.ndarray,
    output_path: Path,
    title: str = "",
    cmap: str = "viridis"
) -> bool:
    """Save array as PNG with color mapping."""
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        fig, ax = plt.subplots(figsize=(12, 8), dpi=100)
        
        # Plot data (excluding NaN)
        im = ax.imshow(data, cmap=cmap, interpolation="nearest")
        
        ax.set_title(title)
        fig.colorbar(im, ax=ax, label="Value")
        
        plt.tight_layout()
        plt.savefig(output_path, dpi=100)
        plt.close()
        
        logger.info(f"Saved PNG: {output_path}")
        return True
    
    except Exception as e:
        logger.error(f"Failed to save PNG {output_path}: {e}")
        return False


def rotate_180_360_to_minus180_180(data: np.ndarray) -> np.ndarray:
    """
    Rotate longitude axis from 0-360 to -180-180 convention.
    
    Assumes data is in 0-360 format (west-most column at 0° E).
    """
    ncol = data.shape[1]
    mid = ncol // 2
    
    # Roll to move 0-180 (east) to the left and 180-360 (west) to the right
    rotated = np.roll(data, mid, axis=1)
    
    return rotated


def process_jaxa_files(
    input_directory: Optional[Path] = None,
    output_directory: Optional[Path] = None,
    pattern: str = "*.bin",
    save_geotiff: bool = True,
    save_png: bool = False,
    rotate_180: bool = True
):
    """
    Process all JAXA binary files in a directory.
    
    Args:
        input_directory: Path to folder with .bin files
        output_directory: Path for outputs
        pattern: Glob pattern for input files
        save_geotiff: Write GeoTIFF outputs
        save_png: Write PNG visualization
        rotate_180: Convert 0-360 longitude to -180-180
    """
    if input_directory is None:
        input_directory = INPUT_DIR
    if output_directory is None:
        output_directory = OUTPUT_DIR
    
    output_directory.mkdir(parents=True, exist_ok=True)
    
    binary_files = list(input_directory.glob(pattern))
    logger.info(f"Found {len(binary_files)} files matching '{pattern}'")
    
    for binary_file in binary_files:
        logger.info(f"Processing {binary_file.name}...")
        
        # Read binary file
        data = read_jaxa_binary(binary_file)
        
        if data is None:
            continue
        
        # Optional: rotate longitude axis
        if rotate_180:
            data = rotate_180_360_to_minus180_180(data)
        
        # Build transform for rotated grid
        if rotate_180:
            west = -180.0
        else:
            west = 0.0
        
        transform = build_raster_transform(west=west)
        
        # Save outputs
        stem = binary_file.stem
        
        if save_geotiff:
            tif_path = output_directory / f"{stem}.tif"
            save_geotiff(data, tif_path, transform=transform)
        
        if save_png:
            png_path = output_directory / f"{stem}.png"
            save_png(data, png_path, title=f"JAXA SWR: {stem}")


def main():
    """Main workflow."""
    logger.info("Starting JAXA binary grid processing...")
    
    # Process all .bin files in input directory
    process_jaxa_files(
        input_directory=INPUT_DIR,
        output_directory=OUTPUT_DIR,
        pattern="*.bin",
        save_geotiff=True,
        save_png=False,  # Set to True if ggplot2-like visualization desired
        rotate_180=True
    )
    
    logger.info("Processing complete.")


if __name__ == "__main__":
    main()
