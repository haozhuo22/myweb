# Blog Post 8: Simulation-Based Statistical Inference

This reproducible project explains bootstrap confidence intervals, repeated-sampling coverage, rejection regions, and p-values through simulation and interactive Plotly graphics.

## Reproduce

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analysis.py
quarto render index.qmd
```

The simulation uses a fixed seed (`6400`). All generated CSV files are in `data/`, and the self-contained interactive figures are in `figures/`.
