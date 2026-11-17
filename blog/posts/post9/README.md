# Can Gradient Boosting Predict Stock Returns?

This repository contains the complete reproducible analysis for Blog Post 9. It compares the class XGBoost stock-return model, a regularized improved model, and simple benchmarks on a strictly held-out 2024+ period.

## Reproduce

1. Open `index.qmd` or `analysis.R` in RStudio.
2. Install the required packages:

```r
install.packages(c(
  "tidyverse", "tidyquant", "lubridate", "slider", "scales",
  "xgboost", "jsonlite"
))
```

3. Run `source("analysis.R")` from the repository root.
4. Render the article with `quarto render index.qmd`.

The analysis uses a fixed random seed. `analysis.R` downloads adjusted daily prices through `tidyquant` on the first run and then uses the cached compressed file. Generated artifacts include the clean modeling panel, held-out predictions, model-selection results, performance tables, and four figures.

The results are an educational backtest, not investment advice. The sample has survivorship bias and does not represent a deployable trading strategy.

