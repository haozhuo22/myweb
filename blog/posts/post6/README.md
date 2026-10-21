# From Family IDs to Mobility

This repository contains Blog Post 6, a reproducible tutorial showing how SQL inside Python can match parents and children in longitudinal data and how income measurement affects the intergenerational elasticity (IGE).

The project uses a fixed-seed, synthetic PSID-style panel. The data-generating IGE is 0.40, so readers can observe life-cycle bias and attenuation from annual income noise against a known benchmark. The estimates are pedagogical and should not be interpreted as empirical estimates for the United States.

## Contents

- `index.qmd` — finished Quarto tutorial
- `analysis.py` — data generation, SQLite construction, SQL queries, estimation, and figures
- `data/family_panel.sqlite` — complete SQLite database
- `data/raw/people.csv` — person and family identifiers
- `data/raw/income_panel.csv` — longitudinal person-year income records
- `data/processed/matched_parent_child.csv` — analysis-ready matched dataframe
- `data/processed/ige_estimates.csv` — main model comparison
- `data/processed/ige_by_child_age.csv` — life-cycle bias estimates
- `data/processed/ige_by_averaging_window.csv` — multi-year averaging comparison
- `figures/` — three publication-ready figures

## Reproduce

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis.py
quarto render index.qmd
```

The analysis requires Python 3.9 or newer. SQLite is accessed through Python's standard-library `sqlite3` module.

## Main result

The IGE is 0.218 when child income is measured once at age 25, 0.312 when measured once at age 35, and 0.405 when income is averaged over eleven years for each generation. Multi-year averages recover the known 0.40 benchmark because they reduce transitory-income noise and use more representative life-cycle windows.

