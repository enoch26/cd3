"""
Annual population estimates on 2021 English LSOAs

Purpose:
    Build a consistent 2002–2024 annual population dataset on 2021 English
    Lower-layer Super Output Area (LSOA) boundaries. The output contains total
    population and sex-by-age-group counts.

Data sources:
    - ONS small-area population estimates (SAPE) by single year of age:
      https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/smallareapopulationestimatesinenglandandwales
    - Geography and supporting data:
      https://humaniverse.github.io/geographr/

Expected project layout:
    <project root>/
    ├── lsoa11221.py
    └── data/
        ├── lsoa_pop_est_sing/
        │   └── <ONS population workbooks>
        └── derived/
            └── lsoa_*_area_weights.csv  (from lsoa11221.py)

Outputs:
    - data/pop_regrouped_2002_2024.csv (harmonised to 2021 LSOA boundaries)
"""

import os
import pandas as pd
import numpy as np
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import warnings

# Configuration
DATA_DIR = Path("data")
POP_EST_DIR = DATA_DIR / "lsoa_pop_est_sing"
DERIVED_DIR = DATA_DIR / "derived"
OUTPUT_FILE = DATA_DIR / "pop_regrouped_2002_2024.csv"

YEARS = range(2002, 2025)
MIN_YEAR_LSOA_2011 = 2002
MAX_YEAR_LSOA_2011 = 2020
MIN_YEAR_LSOA_2021 = 2021
MAX_YEAR_LSOA_2021 = 2024


def load_area_weights(source_year, target_year=2021):
    """Load area-weighted crosswalk for the specified years."""
    if source_year == target_year:
        return None
    
    if source_year == 2011 and target_year == 2021:
        weights_file = DERIVED_DIR / "lsoa_2011_2021_area_weights.csv"
    elif source_year == 2001 and target_year == 2021:
        weights_file = DERIVED_DIR / "lsoa_2001_2021_area_weights.csv"
    else:
        raise ValueError(f"Unsupported crosswalk: {source_year} -> {target_year}")
    
    if not weights_file.exists():
        raise FileNotFoundError(
            f"Area weights file not found: {weights_file}. "
            "Run lsoa11221.py first."
        )
    
    return pd.read_csv(weights_file)


def read_population_workbook(year, lsoa_version=2011):
    """
    Read ONS population workbook for a specific year and LSOA version.
    
    Expected structure: Excel workbook with worksheets for each age/sex group.
    """
    workbook_pattern = f"*{year}*" if lsoa_version == 2021 else f"*{year}*"
    workbook_files = list(POP_EST_DIR.glob(f"*.xlsx"))
    
    if not workbook_files:
        raise FileNotFoundError(f"No population workbooks found in {POP_EST_DIR}")
    
    # Find matching file (implementation depends on ONS naming convention)
    matching_files = [f for f in workbook_files if str(year) in f.name]
    if not matching_files:
        warnings.warn(f"No population file found for year {year}, LSOA {lsoa_version}")
        return None
    
    workbook_file = matching_files[0]
    
    # Read all sheets and concatenate
    xls = pd.ExcelFile(workbook_file)
    dfs = []
    
    for sheet_name in xls.sheet_names:
        try:
            df = pd.read_excel(workbook_file, sheet_name=sheet_name)
            dfs.append(df)
        except Exception as e:
            warnings.warn(f"Failed to read sheet {sheet_name} from {workbook_file}: {e}")
    
    if not dfs:
        return None
    
    pop_data = pd.concat(dfs, ignore_index=True)
    return pop_data


def harmonise_population_to_lsoa_2021():
    """
    Harmonise all years to LSOA 2021 boundaries.
    
    - 2002–2020: Load from LSOA 2011, apply area weights to 2021
    - 2021–2024: Load directly from LSOA 2021
    """
    all_years = []
    
    # Process 2002-2020 (LSOA 2011)
    print("Processing 2002-2020 (LSOA 2011 with area weights)...")
    weights_2011_2021 = load_area_weights(2011, 2021)
    
    for year in range(MIN_YEAR_LSOA_2011, MAX_YEAR_LSOA_2011 + 1):
        print(f"  Reading year {year}...")
        pop_data = read_population_workbook(year, lsoa_version=2011)
        
        if pop_data is None:
            continue
        
        # Merge with weights
        pop_weighted = pop_data.merge(
            weights_2011_2021,
            left_on="lsoa11cd",
            right_on="lsoa11cd",
            how="left"
        )
        
        # Apply weights to population counts
        pop_weighted["population"] = pop_weighted["population"] * pop_weighted["weight"]
        
        # Aggregate to LSOA 2021
        pop_2021 = pop_weighted.groupby("lsoa21cd", as_index=False).agg({
            "population": "sum",
            "year": "first"
        })
        pop_2021["year"] = year
        all_years.append(pop_2021)
    
    # Process 2021-2024 (LSOA 2021)
    print("Processing 2021-2024 (LSOA 2021)...")
    for year in range(MIN_YEAR_LSOA_2021, MAX_YEAR_LSOA_2021 + 1):
        print(f"  Reading year {year}...")
        pop_data = read_population_workbook(year, lsoa_version=2021)
        
        if pop_data is None:
            continue
        
        pop_data["year"] = year
        all_years.append(pop_data)
    
    # Combine all years
    harmonised = pd.concat(all_years, ignore_index=True)
    harmonised = harmonised.sort_values(["lsoa21cd", "year"]).reset_index(drop=True)
    
    # Save output
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    harmonised.to_csv(OUTPUT_FILE, index=False)
    print(f"Harmonised population data saved to {OUTPUT_FILE}")
    
    return harmonised


if __name__ == "__main__":
    harmonised = harmonise_population_to_lsoa_2021()
    print(f"\nSummary: {len(harmonised)} records for {len(harmonised['lsoa21cd'].unique())} LSOAs")
