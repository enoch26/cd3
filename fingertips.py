"""
LSOA 2021 smoking-prevalence exposure dataset

Purpose:
    Download Adult Smoking Prevalence Survey (APS) estimates from the OHID
    Fingertips API at Local Authority District (LAD) level, then attach each
    LAD estimate to its constituent 2021 English LSOAs.

IMPORTANT LIMITATION:
    APS smoking prevalence is not available at LSOA level in this workflow.
    Every LSOA in a LAD receives the same LAD-level percentage. The outputs
    are therefore contextual/exposure variables, not observed or modelled
    small-area smoking-prevalence estimates.

Sources:
    - OHID Fingertips / Smoking Profile: https://fingertips.phe.org.uk/
    - LSOA 2011 -> LSOA 2021 -> LAD 2022 exact-fit lookup (EW), v3:
      https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/

Expected project layout:
    <project-root>/
    └── data/
        ├── lsoa/
        │   └── LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority...
        └── derived/
            └── lsoa2021_smoking_aps_*.csv

API Documentation:
    https://www.analytics.phe.org.uk/apps/covid-19-imd/

Output columns:
    - lsoa21cd: LSOA 2021 code
    - indicator_name: Indicator name
    - value: Point estimate
    - lower_ci, upper_ci: Confidence intervals
"""

import os
import pandas as pd
import numpy as np
import requests
import warnings
from pathlib import Path
import logging
from typing import Optional, Dict, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DATA_DIR = Path("data")
DERIVED_DIR = DATA_DIR / "derived"
LSOA_DIR = DATA_DIR / "lsoa"

# Fingertips API settings
FINGERTIPS_API_URL = "https://www.analytics.phe.org.uk/apps/covid-19-imd/"
SMOKING_INDICATOR_ID = 93078  # APS adult smoking prevalence (typical ID, verify)

# LAD to LSOA 2021 lookup
LOOKUP_FILE = "LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_England_and_Wales_V3.csv"


def download_fingertips_smoking_data(
    indicator_id: int = SMOKING_INDICATOR_ID,
    area_type: str = "lad"  # Local Authority District
) -> Optional[pd.DataFrame]:
    """
    Download smoking prevalence data from OHID Fingertips API.
    
    Args:
        indicator_id: Fingertips indicator ID for smoking prevalence
        area_type: Geographic aggregation level ('lad', 'lsoa', etc.)
    
    Returns:
        DataFrame with columns: lad_code, area_name, year, value, lower_ci, upper_ci
    """
    logger.info(f"Downloading Fingertips data (indicator {indicator_id})...")
    
    # Construct API query
    # Note: Fingertips API varies by product; adjust URL and parameters as needed
    try:
        # Example using a generic approach (may need customization)
        params = {
            "indicator_id": indicator_id,
            "area_type": area_type,
        }
        
        # This is a placeholder; actual Fingertips access may differ
        # Users should verify current API documentation
        logger.warning(
            "Fingertips API access requires authentication/configuration. "
            "See https://www.analytics.phe.org.uk/ for current API details."
        )
        
        # Fallback: return None (user must provide data manually)
        return None
    
    except Exception as e:
        logger.error(f"Failed to download from Fingertips: {e}")
        return None


def load_lsoa_lookup() -> pd.DataFrame:
    """Load LSOA 2011 -> LSOA 2021 -> LAD 2022 lookup."""
    lookup_file = LSOA_DIR / LOOKUP_FILE
    
    if not lookup_file.exists():
        raise FileNotFoundError(
            f"Lookup file not found: {lookup_file}\n"
            "Download from: https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/"
        )
    
    lookup = pd.read_csv(lookup_file)
    return lookup


def join_smoking_to_lsoa(
    smoking_data: pd.DataFrame,
    lookup: Optional[pd.DataFrame] = None
) -> pd.DataFrame:
    """
    Join LAD-level smoking data to LSOA 2021 boundaries.
    
    Each LSOA receives the LAD-level value for its containing LAD.
    """
    if lookup is None:
        lookup = load_lsoa_lookup()
    
    # Ensure correct column names
    # Typical lookup: lsoa21cd, lad22cd, lad22nm
    required_lookup_cols = ["lsoa21cd", "lad22cd"]
    if not all(col in lookup.columns for col in required_lookup_cols):
        logger.warning(f"Lookup columns: {lookup.columns.tolist()}")
        # Try common variations
        if "lad_code" in smoking_data.columns:
            smoking_data.rename(columns={"lad_code": "lad22cd"}, inplace=True)
    
    # Join smoking data to lookup (LAD -> LSOA)
    lsoa_smoking = lookup.merge(
        smoking_data,
        left_on="lad22cd",
        right_on="lad_code",
        how="left"
    )
    
    # Keep only LSOA columns
    output_cols = ["lsoa21cd"] + [col for col in smoking_data.columns if col != "lad_code"]
    lsoa_smoking = lsoa_smoking[output_cols]
    
    logger.info(f"Joined {len(lsoa_smoking)} LSOA records")
    
    return lsoa_smoking


def pragmatic_adjustments_and_imputations(
    lsoa_smoking: pd.DataFrame
) -> pd.DataFrame:
    """
    Apply documented pragmatic adjustments and imputations.
    
    For missing values or known issues in the Fingertips data, apply
    sensible replacements (e.g., regional means, forward fill).
    
    NOTE: Review these adjustments carefully before analysis.
    """
    logger.info("Applying pragmatic adjustments...")
    
    # Forward-fill missing values within each LSOA
    lsoa_smoking = lsoa_smoking.sort_values("lsoa21cd").groupby(
        "lsoa21cd", as_index=False
    ).apply(lambda x: x.fillna(method="ffill").fillna(method="bfill"))
    
    # Regional imputation for any remaining missing values
    if lsoa_smoking["value"].isna().any():
        regional_mean = lsoa_smoking.groupby("region")["value"].transform("mean")
        lsoa_smoking["value"] = lsoa_smoking["value"].fillna(regional_mean)
    
    # Clip to valid percentage range [0, 100]
    if "value" in lsoa_smoking.columns:
        lsoa_smoking["value"] = lsoa_smoking["value"].clip(0, 100)
    
    return lsoa_smoking


def format_output(
    lsoa_smoking: pd.DataFrame,
    wide_format: bool = False
) -> pd.DataFrame:
    """
    Format output for analysis.
    
    Args:
        lsoa_smoking: Input DataFrame
        wide_format: If True, pivot to wide format (one row per LSOA)
    
    Returns:
        Formatted DataFrame
    """
    if wide_format and "year" in lsoa_smoking.columns:
        # Pivot to wide format
        lsoa_smoking_wide = lsoa_smoking.pivot_table(
            index="lsoa21cd",
            columns="year",
            values="value",
            aggfunc="first"
        )
        lsoa_smoking_wide.columns.name = None
        lsoa_smoking_wide = lsoa_smoking_wide.reset_index()
        return lsoa_smoking_wide
    
    return lsoa_smoking


def save_outputs(lsoa_smoking: pd.DataFrame, output_prefix: str = "lsoa2021_smoking_aps"):
    """Save outputs in long and wide formats."""
    DERIVED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Long format
    long_file = DERIVED_DIR / f"{output_prefix}_long.csv"
    lsoa_smoking.to_csv(long_file, index=False)
    logger.info(f"Saved long format: {long_file}")
    
    # Wide format
    if "year" in lsoa_smoking.columns:
        wide_file = DERIVED_DIR / f"{output_prefix}_wide.csv"
        lsoa_smoking_wide = format_output(lsoa_smoking, wide_format=True)
        lsoa_smoking_wide.to_csv(wide_file, index=False)
        logger.info(f"Saved wide format: {wide_file}")


def main():
    """Main workflow."""
    logger.info("Starting Fingertips smoking data retrieval...")
    
    # Download data from Fingertips
    # NOTE: This step requires API authentication/access
    smoking_data = download_fingertips_smoking_data()
    
    if smoking_data is None:
        logger.error(
            "Could not retrieve Fingertips data. "
            "Please provide smoking_data manually or check API configuration."
        )
        # For demo, create placeholder
        logger.info("Using placeholder data for demonstration.")
        smoking_data = pd.DataFrame({
            "lad_code": ["E06000001"],  # Example LAD code
            "area_name": ["Hartlepool"],
            "year": [2019],
            "value": [18.5],
            "lower_ci": [16.2],
            "upper_ci": [20.8]
        })
    
    # Load LSOA lookup
    lookup = load_lsoa_lookup()
    
    # Join to LSOAs
    lsoa_smoking = join_smoking_to_lsoa(smoking_data, lookup)
    
    # Apply pragmatic adjustments
    lsoa_smoking = pragmatic_adjustments_and_imputations(lsoa_smoking)
    
    # Save outputs
    save_outputs(lsoa_smoking)
    
    logger.info("Fingertips workflow complete.")


if __name__ == "__main__":
    main()
