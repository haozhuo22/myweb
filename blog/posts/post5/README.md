# Rent Is Taking a Bigger Bite

This repository contains the complete, reproducible project for Blog Post 5: a GIS analysis of county-level renter cost burden in the United States using the 2019 and 2024 American Community Survey (ACS) five-year estimates.

## Research question

Where were renters most cost burdened in 2024, and how did county and state patterns change after 2019?

## Repository contents

- `index.qmd` — finished Quarto article
- `R/01_download_data.R` — downloads official Census source files
- `R/02_analysis.R` — cleans data, calculates rates, joins GIS boundaries, and creates figures
- `data/raw/` — archived official ACS and cartographic-boundary source files
- `data/processed/` — analysis-ready county and state CSV files
- `data/source_metadata.csv` — source URLs and access date
- `figures/` — three publication-ready PNG figures

## Reproduce the analysis

Open `blog-post-5-renter-cost-burden.Rproj` in RStudio. Install the required packages if needed:

```r
install.packages(c("dplyr", "tidyr", "readr", "ggplot2", "scales", "sf"))
```

Then run:

```r
source("R/01_download_data.R")
source("R/02_analysis.R")
```

Render `index.qmd` with the RStudio **Render** button or with `quarto render index.qmd`.

## Data and measurement

The analysis uses U.S. Census Bureau ACS table B25070. A renter household is cost burdened when gross rent is at least 30% of household income. Households for which the ratio is not computed are excluded from the denominator. State and national rates are calculated from summed household counts rather than unweighted county averages.

The maps show the contiguous United States for readability. Alaska, Hawaii, and the territories remain in the cleaned data. Connecticut is omitted from the county change map because Census county geography changed to planning regions after 2019.

