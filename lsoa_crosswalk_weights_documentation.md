# LSOA 2001–2021 Area-Weighted Crosswalks

## Purpose

This workflow creates **area-based correspondence weights** between Lower-layer Super Output Area (LSOA) geographies for England across the 2001, 2011, and 2021 boundary vintages.

It produces three crosswalk tables:

| Output | Source geography | Target geography | Weight column |
|---|---|---|---|
| `lookup_wgt_01_11` | LSOA 2001 | LSOA 2011 | `LSOA01WGT` |
| `lookup_wgt_11_21` | LSOA 2011 | LSOA 2021 | `LSOA11WGT` |
| `lookup_wgt_01_21` | LSOA 2001 | LSOA 2021 | `LSOA01WGT21` |

Weights describe the share of a **source LSOA's polygon area** allocated to each target LSOA. They can be used to re-express additive data—such as counts or totals—from historic LSOA boundaries to newer ones.

> **Important:** These are geographic area weights, not population-, household-, address-, or land-use-weighted estimates. Applying them assumes that the value being transferred is uniformly distributed within each source LSOA.

## Geographic scope

The input datasets cover England and Wales, but the workflow filters all source and target geographies to **England only**. English LSOA codes begin with `E`.

All boundary layers are transformed to the **British National Grid** coordinate reference system (`EPSG:27700`) before areas are calculated. This is essential because it provides metre-based coordinates suitable for area calculations.

## Source data

Download the following datasets and place the extracted shapefiles and CSV lookup files beneath `data/lsoa/`. The code searches this directory recursively.

### Boundary files

| Geography | Dataset |
|---|---|
| LSOA 2001 | [Lower Layer Super Output Areas December 2001 Boundaries EW (BFE)](https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2001-boundaries-ew-bfe/about) |
| LSOA 2011 | [Lower Layer Super Output Areas December 2011 Boundaries EW (BFC), V3](https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-ew-bfc-v3/about) |
| LSOA 2021 | Obtain the LSOA 2021 EW BFE boundary release used by the script, expected as `LSOA_2021_EW_BFE_V10.shp`. |

The expected shapefile names are:

```text
LSOA_2001_EW_BFE_V2.shp
LSOA_2011_EW_BFC_V3.shp
LSOA_2021_EW_BFE_V10.shp
```

A London-hosted alternative for 2011 census geography boundaries is available from the [London Datastore](https://data.london.gov.uk/dataset/2011-census-geography-boundary-files-29jwj/).

### Lookup files

| Crosswalk | Dataset |
|---|---|
| 2001 to 2011 | [LSOA 2001 to LSOA 2011 to LAD 2011 Lookup in England and Wales](https://www.data.gov.uk/dataset/4048a518-3eaf-457a-905c-9e04f4fffca8/lower-layer-super-output-area-2001-to-lower-layer-super-output-area-2011-to-local-authority-district-2011-lookup-in-england-and-wales) |
| 2011 to 2021 | [LSOA 2011 to LSOA 2021 to LAD 2022 Exact Fit Lookup for EW, V3](https://www.data.gov.uk/dataset/03a52a27-36e7-4f33-a632-83282faea36f/lsoa-2011-to-lsoa-2021-to-local-authority-district-2022-exact-fit-lookup-for-ew-v3) |

The script expects these CSV names:

```text
Lower_Layer_Super_Output_Area_(2001)_to_Lower_Layer_Super_Output_Area_(2011)_to_Local_Authority_District_(2011)_Lookup_in_England_and_Wales.csv
LSOA_(2011)_to_LSOA_(2021)_to_Local_Authority_District_(2022)_Exact_Fit_Lookup_for_EW_(V3).csv
```

## Software requirements

The workflow is written in **R** and requires:

```r
library(sf)
library(dplyr)
library(data.table)
```

It also uses `here()` to define the data directory, so the project should either load the `here` package or replace the `here("data", "lsoa")` call with an appropriate path.

## Input discovery and preparation

The script:

1. Finds every shapefile whose name matches `LSOA.*(BFE|BFC).*\\.shp` below `data/lsoa/`.
2. Finds all CSV files below the same directory.
3. Reads shapefiles into a named list (`lsoa_shp`) and CSV files into a named list (`lsoa_csv`).
4. Extracts the three expected boundary layers by filename.
5. Retains English LSOAs only, using the relevant code field:
   - `LSOA01CD` for 2001;
   - `LSOA11CD` for 2011;
   - `LSOA21CD` for 2021.
6. Reprojects each layer to `EPSG:27700`.

The official lookup files determine which source–target pairs are eligible. Polygon intersections are only used to calculate weights for lookup relationships where one source LSOA maps to more than one target LSOA.

## Methodology

### Identifying one-to-one and one-to-many relationships

For each source vintage, the workflow counts the number of distinct target codes in the published lookup:

- **One-to-one:** a source code has one target code. Its weight is assigned as `1`.
- **One-to-many:** a source code has more than one target code. Its target weights are calculated from geometric intersections.

This approach avoids unnecessary spatial processing for unchanged or directly matched areas.

### Calculating area weights

For every one-to-many source LSOA, the source polygons are intersected with target polygons. For each intersected piece, the weight is:

$$
w_{s,t} = \frac{A(s \cap t)}{A(s)}
$$

where:

- $$w_{s,t}$$ is the weight from source LSOA $$s$$ to target LSOA $$t$$;
- $$A(s \cap t)$$ is the area of their polygon intersection;
- $$A(s)$$ is the total area of source LSOA $$s$$.

The resulting data include one row per source–target pair.

### Normalisation

Spatial operations can introduce tiny gaps, overlaps, or floating-point differences. Therefore, weights are normalised within each source LSOA:

$$
w'_{s,t} = \frac{w_{s,t}}{\sum_t w_{s,t}}
$$

After normalisation, weights for every source LSOA sum to one, subject to numerical precision.

### Building the 2001 to 2021 crosswalk

The 2001-to-2021 crosswalk is constructed via the intermediate 2011 geography. The workflow joins the 2001-to-2011 and 2011-to-2021 weight tables by `LSOA11CD`, multiplies the weights along each possible path, and sums duplicate 2001-to-2021 pairs:

$$
w_{01,21}(i,k) = \sum_j w_{01,11}(i,j) \times w_{11,21}(j,k)
$$

where:

- $$i$$ is an LSOA 2001 code;
- $$j$$ is an LSOA 2011 code;
- $$k$$ is an LSOA 2021 code.

The final table is normalised again within each 2001 source LSOA.

## Outputs

### `lookup_wgt_11_21`

A table linking `LSOA11CD` to `LSOA21CD`.

| Column | Description |
|---|---|
| `LSOA11CD` | 2011 source LSOA code |
| `LSOA21CD` | 2021 target LSOA code |
| `LSOA11WGT` | Share of the 2011 source LSOA area allocated to the 2021 target LSOA |

### `lookup_wgt_01_11`

A table linking `LSOA01CD` to `LSOA11CD`.

| Column | Description |
|---|---|
| `LSOA01CD` | 2001 source LSOA code |
| `LSOA11CD` | 2011 target LSOA code |
| `LSOA01WGT` | Share of the 2001 source LSOA area allocated to the 2011 target LSOA |

### `lookup_wgt_01_21`

A derived table linking `LSOA01CD` directly to `LSOA21CD`.

| Column | Description |
|---|---|
| `LSOA01CD` | 2001 source LSOA code |
| `LSOA21CD` | 2021 target LSOA code |
| `LSOA01WGT21` | Composite 2001-to-2021 area weight, calculated through 2011 |

All outputs are sorted by source code and then target code.

## Applying a crosswalk to data

For an additive measure held at source LSOA level, join the data to the appropriate crosswalk and multiply the measure by the weight. Then aggregate by the target code.

For example, to transfer a 2001 LSOA count to 2021 LSOAs:

$$
V_{21}(k) = \sum_i V_{01}(i) \times w_{01,21}(i,k)
$$

where $$V_{01}(i)$$ is the value for source LSOA $$i$$ and $$V_{21}(k)$$ is the estimated value for target LSOA $$k$$.

Illustrative R pattern:

```r
values_2021 <- merge(
  values_2001,
  lookup_wgt_01_21,
  by = "LSOA01CD",
  allow.cartesian = TRUE
)[
  , .(value = sum(value * LSOA01WGT21)),
  by = LSOA21CD
]
```

Use this approach for counts and totals. Do **not** directly area-weight rates, percentages, means, medians, or other non-additive indicators. Where possible, transfer the underlying numerators and denominators separately, then recalculate the indicator.

## Quality assurance

The script includes optional checks inside `if (FALSE)`. Set this to `if (TRUE)` to inspect the source-level sum of weights for each output table.

A successful result should have:

$$
\sum_t w_{s,t} = 1
$$

for every source LSOA $$s$$, up to a small floating-point tolerance. The commented diagnostic notes that, before normalisation, two 2011 source LSOAs differed from one by more than $$0.001$$, while none differed by more than $$0.005$$. Normalisation resolves these small discrepancies.

Recommended additional checks:

- Confirm all expected input filenames are present and uniquely identified.
- Confirm that every source code in a lookup has at least one output row.
- Check for missing, invalid, or empty geometries before running intersections.
- Review very small intersection weights, particularly around coastlines and boundary slivers.
- Reconcile transferred totals with source totals after applying a crosswalk.

## Limitations and interpretation

- **Uniform-distribution assumption:** Area weights are appropriate only when area is a reasonable proxy for the spatial distribution of the measure.
- **Boundary precision:** Differences between boundary vintages, coastline treatment, and topology can create small sliver polygons or minor deviations before normalisation.
- **Exact-fit lookup does not itself provide quantitative weights:** The published lookup supplies valid geographic relationships; the workflow derives area shares where a source maps to multiple targets.
- **Intermediate geography:** The direct 2001-to-2021 weights are a composition of two crosswalks, rather than a direct polygon intersection between 2001 and 2021 boundaries.
- **England only:** Wales is deliberately excluded by the code-prefix filter.

## Reproducibility notes

For reproducible results, retain the original downloaded files, including their release versions, alongside the generated crosswalk outputs. Changes to boundary releases, geometry repairs, projection handling, or `sf` software versions can cause small changes in calculated intersection areas.
