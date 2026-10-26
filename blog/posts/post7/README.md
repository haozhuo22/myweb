# Does More Income Buy More Years?

This repository contains Blog Post 7, an interactive Plotly analysis of the global relationship between GDP per capita and life expectancy from 1990 through 2023.

## Research question

Does a given level of income buy the same longevity across countries, and how has the global income–health gradient changed since 1990?

## Project contents

- `index.qmd` — finished Quarto article
- `analysis.py` — downloads World Bank data, cleans the panel, calculates summaries, and builds both Plotly figures
- `data/raw/` — archived JSON responses from the World Bank API
- `data/processed/world_income_health_panel.csv` — analysis-ready country-year panel
- `data/processed/regional_weighted_trends.csv` — population-weighted regional series
- `data/processed/annual_summary.csv` — annual global statistics and income–health slopes
- `data/processed/latest_year_income_health_residuals.csv` — 2023 deviations from the income–health regression
- `data/source_metadata.csv` — exact API endpoints and access date
- `figures/` — two self-contained interactive HTML visualizations

## Reproduce

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis.py
quarto render index.qmd
```

The interactive HTML files embed the Plotly JavaScript library, so they remain interactive when opened locally without a separate Python process.

## Data source

All data come from the World Bank Open Data API:

- `NY.GDP.PCAP.PP.KD`: GDP per capita, PPP (constant 2021 international dollars)
- `SP.DYN.LE00.IN`: life expectancy at birth, total
- `SP.POP.TOTL`: total population

Country metadata are also downloaded from the World Bank API. Regional aggregates are excluded before merging the indicators.

