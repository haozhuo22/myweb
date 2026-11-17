suppressPackageStartupMessages({
  library(tidyverse)
  library(tidyquant)
  library(lubridate)
  library(slider)
  library(scales)
})

.libPaths(c(file.path(getwd(), ".Rlib"), .libPaths()))
library(xgboost)

set.seed(6400)
dir.create("data", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

# A diversified version of the universe used in the class script.
tickers <- c(
  "AAPL","MSFT","NVDA","GOOG","META","AMZN","AVGO","ORCL","ADBE","CRM",
  "CSCO","AMD","INTC","QCOM","TXN","IBM","NOW","INTU","AMAT","MU",
  "JPM","BAC","WFC","GS","MS","BLK","C","SCHW","SPGI","AXP","USB","PNC","TFC","COF",
  "UNH","JNJ","LLY","PFE","MRK","ABBV","TMO","DHR","ABT","BMY","AMGN","GILD","CVS","ISRG","MDT",
  "TSLA","HD","MCD","NKE","SBUX","LOW","TJX","BKNG","CMG","ORLY",
  "WMT","COST","PG","KO","PEP","PM","MO","CL","EL",
  "CAT","GE","HON","UPS","BA","RTX","DE","LMT","MMM","ETN",
  "XOM","CVX","COP","SLB","EOG",
  "NFLX","DIS","CMCSA","TMUS","VZ",
  "AMT","PLD","NEE","DUK","SO","LIN","APD"
)

cache_file <- "data/raw_adjusted_prices.csv.gz"
if (file.exists(cache_file)) {
  prices_all <- read_csv(cache_file, show_col_types = FALSE) %>% mutate(date = as.Date(date))
} else {
  message("Downloading adjusted prices from Yahoo Finance...")
  prices <- tq_get(tickers, from = "2017-01-01", to = Sys.Date(), get = "stock.prices")
  spy_raw <- tq_get("SPY", from = "2017-01-01", to = Sys.Date(), get = "stock.prices") %>%
    mutate(symbol = "SPY")
  prices_all <- bind_rows(prices, spy_raw) %>%
    select(symbol, date, open, high, low, close, volume, adjusted) %>%
    arrange(symbol, date)
  write_csv(prices_all, cache_file)
}

spy <- prices_all %>%
  filter(symbol == "SPY") %>%
  arrange(date) %>%
  transmute(
    date,
    spy_price = adjusted,
    spy_ret = adjusted / lag(adjusted) - 1,
    spy_mom_1m = lag(adjusted, 1) / lag(adjusted, 21) - 1,
    spy_mom_3m = lag(adjusted, 1) / lag(adjusted, 63) - 1,
    spy_target = lead(adjusted, 20) / lead(adjusted, 1) - 1
  )

safe_beta <- function(x, y) {
  if (sum(is.finite(x) & is.finite(y)) < 40 || var(y, na.rm = TRUE) == 0) return(NA_real_)
  cov(x, y, use = "complete.obs") / var(y, na.rm = TRUE)
}

panel <- prices_all %>%
  filter(symbol != "SPY") %>%
  group_by(symbol) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(return = adjusted / lag(adjusted) - 1) %>%
  ungroup() %>%
  left_join(spy, by = "date") %>%
  group_by(symbol) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    # Class-script signals (kept unchanged for the original model).
    base_mom_1m = lag(adjusted, 21) / lag(adjusted, 1) - 1,
    base_mom_3m = lag(adjusted, 63) / lag(adjusted, 1) - 1,
    base_mom_6m = lag(adjusted, 126) / lag(adjusted, 1) - 1,
    base_vol_1m = slide_dbl(lag(return), sd, .before = 21, .complete = TRUE),
    base_ret_5d = lag(adjusted, 5) / lag(adjusted, 1) - 1,
    base_excess_ret = return - spy_ret,
    # Improved signals use only information observable at the formation close.
    mom_1m = lag(adjusted, 1) / lag(adjusted, 21) - 1,
    mom_3m = lag(adjusted, 1) / lag(adjusted, 63) - 1,
    mom_6m = lag(adjusted, 1) / lag(adjusted, 126) - 1,
    reversal_5d = lag(adjusted, 1) / lag(adjusted, 6) - 1,
    vol_1m = slide_dbl(lag(return), sd, .before = 20, .complete = TRUE),
    beta_3m = slide2_dbl(lag(return), lag(spy_ret), safe_beta, .before = 62, .complete = TRUE),
    idio_vol_3m = slide_dbl(lag(return - spy_ret), sd, .before = 62, .complete = TRUE),
    relative_mom_3m = mom_3m - spy_mom_3m,
    distance_52w_high = lag(adjusted, 1) /
      slide_dbl(lag(adjusted), max, .before = 251, .complete = TRUE, na.rm = TRUE) - 1,
    log_dollar_volume = log1p(lag(adjusted * volume)),
    target = lead(adjusted, 20) / lead(adjusted, 1) - 1,
    target_end = lead(date, 20)
  ) %>%
  ungroup()

base_features <- c("base_mom_1m","base_mom_3m","base_mom_6m","base_vol_1m","base_ret_5d","base_excess_ret")
improved_features <- c("mom_1m","mom_3m","mom_6m","reversal_5d","vol_1m","beta_3m",
                       "idio_vol_3m","relative_mom_3m","distance_52w_high","log_dollar_volume",
                       "spy_mom_1m","spy_mom_3m")

complete_panel <- panel %>%
  filter(if_all(all_of(c(base_features, improved_features, "target")), is.finite))

make_matrix <- function(dat, features) {
  xgb.DMatrix(as.matrix(dat[, features]), label = dat$target, missing = NA_real_)
}

# The original class specification, trained on the original 2022-2023 window.
base_train <- complete_panel %>% filter(date >= as.Date("2022-01-01"), target_end < as.Date("2024-01-01"))
test <- complete_panel %>% filter(date >= as.Date("2024-01-01"), !is.na(target_end))

base_params <- list(
  objective = "reg:squarederror", eval_metric = "rmse", eta = 0.05,
  max_depth = 5, min_child_weight = 10, subsample = 1, colsample_bytree = 1,
  seed = 6400, nthread = 4
)
base_fit <- xgb.train(base_params, make_matrix(base_train, base_features), nrounds = 300, verbose = 0)

# Tune the improved model on 2023 only; the 2024+ test data are never used for model selection.
tune_train <- complete_panel %>% filter(date >= as.Date("2018-01-01"), target_end < as.Date("2023-01-01"))
validation <- complete_panel %>% filter(date >= as.Date("2023-01-01"), target_end < as.Date("2024-01-01"))

grid <- tribble(
  ~max_depth, ~eta, ~min_child_weight, ~subsample, ~colsample_bytree,
  2L, 0.03, 20, 0.8, 0.8,
  3L, 0.03, 20, 0.8, 0.8,
  3L, 0.05, 30, 0.7, 0.8,
  4L, 0.03, 30, 0.7, 0.7
)

dtrain <- make_matrix(tune_train, improved_features)
dvalid <- make_matrix(validation, improved_features)
tuning_results <- pmap_dfr(grid, function(max_depth, eta, min_child_weight, subsample, colsample_bytree) {
  params <- list(
    objective = "reg:squarederror", eval_metric = "rmse", max_depth = max_depth,
    eta = eta, min_child_weight = min_child_weight, subsample = subsample,
    colsample_bytree = colsample_bytree, lambda = 10, alpha = 0.5,
    seed = 6400, nthread = 4
  )
  fit <- xgb.train(params, dtrain, nrounds = 300, verbose = 0)
  validation_prediction <- predict(fit, dvalid)
  tibble(max_depth, eta, min_child_weight, subsample, colsample_bytree,
         best_iteration = 300L,
         validation_rmse = sqrt(mean((validation$target - validation_prediction)^2)))
}) %>% arrange(validation_rmse)

best <- tuning_results %>% slice(1)
improved_params <- list(
  objective = "reg:squarederror", eval_metric = "rmse", max_depth = best$max_depth,
  eta = best$eta, min_child_weight = best$min_child_weight,
  subsample = best$subsample, colsample_bytree = best$colsample_bytree,
  lambda = 10, alpha = 0.5, seed = 6400, nthread = 4
)
final_train <- complete_panel %>% filter(date >= as.Date("2018-01-01"), target_end < as.Date("2024-01-01"))
improved_fit <- xgb.train(improved_params, make_matrix(final_train, improved_features),
                          nrounds = best$best_iteration, verbose = 0)

predictions <- test %>%
  select(symbol, date, target_end, target, spy_target) %>%
  mutate(
    baseline_prediction = predict(base_fit, make_matrix(test, base_features)),
    improved_prediction = predict(improved_fit, make_matrix(test, improved_features)),
    historical_mean_prediction = mean(base_train$target)
  )

# One prediction date per calendar month matches the 20-trading-day target horizon.
monthly_predictions <- predictions %>%
  mutate(month = floor_date(date, "month")) %>%
  group_by(month) %>%
  filter(date == min(date)) %>%
  ungroup()

prediction_metrics <- function(actual, predicted, model) {
  tibble(
    model = model,
    RMSE = sqrt(mean((actual - predicted)^2)),
    MAE = mean(abs(actual - predicted)),
    R_squared = 1 - sum((actual - predicted)^2) / sum((actual - mean(actual))^2),
    directional_accuracy = mean(sign(actual) == sign(predicted))
  )
}

metrics <- bind_rows(
  prediction_metrics(monthly_predictions$target, monthly_predictions$historical_mean_prediction, "Historical mean"),
  prediction_metrics(monthly_predictions$target, monthly_predictions$baseline_prediction, "Class XGBoost"),
  prediction_metrics(monthly_predictions$target, monthly_predictions$improved_prediction, "Improved XGBoost")
)

monthly_ic <- monthly_predictions %>%
  group_by(month) %>%
  summarise(
    baseline_rank_ic = cor(baseline_prediction, target, method = "spearman"),
    improved_rank_ic = cor(improved_prediction, target, method = "spearman"),
    .groups = "drop"
  )
metrics <- metrics %>%
  mutate(mean_rank_IC = c(NA_real_, mean(monthly_ic$baseline_rank_ic), mean(monthly_ic$improved_rank_ic)))

portfolio_returns <- function(dat, prediction_col, strategy_name) {
  pred_sym <- rlang::sym(prediction_col)
  selected <- dat %>%
    group_by(month) %>%
    slice_max(order_by = !!pred_sym, n = 10, with_ties = FALSE) %>%
    summarise(date = first(date), gross_return = mean(target), holdings = list(symbol), .groups = "drop") %>%
    arrange(month)
  turnover <- numeric(nrow(selected))
  for (i in seq_len(nrow(selected))) {
    current <- selected$holdings[[i]]
    if (i == 1) turnover[i] <- 1 else {
      previous <- selected$holdings[[i - 1]]
      turnover[i] <- 1 - length(intersect(current, previous)) / 10
    }
  }
  selected %>%
    mutate(strategy = strategy_name, turnover = turnover,
           net_return = gross_return - 0.001 * turnover) %>%
    select(month, date, strategy, gross_return, turnover, net_return)
}

strategy_returns <- bind_rows(
  portfolio_returns(monthly_predictions, "baseline_prediction", "Class XGBoost: top 10"),
  portfolio_returns(monthly_predictions, "improved_prediction", "Improved XGBoost: top 10"),
  monthly_predictions %>% group_by(month) %>%
    summarise(date = first(date), gross_return = mean(target), .groups = "drop") %>%
    mutate(strategy = "Equal-weight universe", turnover = 0, net_return = gross_return) %>%
    select(month, date, strategy, gross_return, turnover, net_return),
  monthly_predictions %>% group_by(month) %>%
    summarise(date = first(date), gross_return = first(spy_target), .groups = "drop") %>%
    mutate(strategy = "SPY buy-and-hold", turnover = 0, net_return = gross_return) %>%
    select(month, date, strategy, gross_return, turnover, net_return)
) %>%
  group_by(strategy) %>%
  arrange(month, .by_group = TRUE) %>%
  mutate(growth_of_one = cumprod(1 + net_return)) %>%
  ungroup()

max_drawdown <- function(r) {
  wealth <- cumprod(1 + r)
  min(wealth / cummax(wealth) - 1)
}

strategy_metrics <- strategy_returns %>%
  group_by(strategy) %>%
  summarise(
    months = n(),
    annualized_return = prod(1 + net_return)^(12 / n()) - 1,
    annualized_volatility = sd(net_return) * sqrt(12),
    Sharpe = mean(net_return) / sd(net_return) * sqrt(12),
    max_drawdown = max_drawdown(net_return),
    average_turnover = mean(turnover),
    .groups = "drop"
  )

importance <- xgb.importance(feature_names = improved_features, model = improved_fit) %>%
  as_tibble() %>%
  transmute(feature = Feature, gain = Gain, cover = Cover, frequency = Frequency)

deciles <- monthly_predictions %>%
  group_by(month) %>%
  mutate(predicted_decile = ntile(improved_prediction, 10)) %>%
  group_by(predicted_decile) %>%
  summarise(mean_realized_return = mean(target), standard_error = sd(target) / sqrt(n()), .groups = "drop")

write_csv(tuning_results, "data/tuning_results.csv")
write_csv(metrics, "data/out_of_sample_prediction_metrics.csv")
write_csv(monthly_ic, "data/monthly_rank_correlations.csv")
write_csv(strategy_returns, "data/out_of_sample_strategy_returns.csv")
write_csv(strategy_metrics, "data/out_of_sample_strategy_metrics.csv")
write_csv(importance, "data/improved_model_feature_importance.csv")
write_csv(deciles, "data/predicted_decile_returns.csv")
write_csv(monthly_predictions, "data/out_of_sample_predictions.csv")
write_csv(complete_panel %>% select(symbol, date, target_end, all_of(improved_features), target),
          "data/clean_model_panel.csv.gz")

theme_set(theme_minimal(base_size = 12))
model_colors <- c("Historical mean" = "#7f8c8d", "Class XGBoost" = "#e67e22", "Improved XGBoost" = "#1f77b4")

p1 <- metrics %>%
  select(model, RMSE, MAE) %>%
  pivot_longer(c(RMSE, MAE), names_to = "metric", values_to = "value") %>%
  ggplot(aes(model, value, fill = model)) +
  geom_col(width = 0.68, show.legend = FALSE) +
  facet_wrap(~metric, scales = "free_y") +
  scale_fill_manual(values = model_colors) +
  scale_y_continuous(labels = percent_format(accuracy = 0.1)) +
  labs(title = "Sophistication does not guarantee a smaller forecast error",
       subtitle = "Monthly formation dates in the 2024+ held-out period; lower is better",
       x = NULL, y = NULL, caption = "Source: Yahoo Finance; author's calculations") +
  theme(axis.text.x = element_text(angle = 16, hjust = 1), plot.title.position = "plot")
ggsave("figures/figure1_forecast_errors.png", p1, width = 9, height = 5.4, dpi = 200)

p2 <- deciles %>%
  ggplot(aes(predicted_decile, mean_realized_return)) +
  geom_hline(yintercept = 0, color = "grey65") +
  geom_col(fill = "#1f77b4", width = 0.75) +
  geom_errorbar(aes(ymin = mean_realized_return - 1.96 * standard_error,
                    ymax = mean_realized_return + 1.96 * standard_error), width = 0.18) +
  scale_x_continuous(breaks = 1:10) +
  scale_y_continuous(labels = percent_format(accuracy = 0.1)) +
  labs(title = "Do higher model scores correspond to higher realized returns?",
       subtitle = "Mean subsequent 20-day return by improved-model prediction decile",
       x = "Predicted return decile (10 = highest)", y = "Mean realized return",
       caption = "Whiskers are 95% normal-approximation intervals; observations overlap across nearby securities") +
  theme(plot.title.position = "plot")
ggsave("figures/figure2_decile_returns.png", p2, width = 9, height = 5.4, dpi = 200)

strategy_colors <- c("Class XGBoost: top 10" = "#e67e22", "Improved XGBoost: top 10" = "#1f77b4",
                     "Equal-weight universe" = "#7f8c8d", "SPY buy-and-hold" = "#2ca02c")
p3 <- strategy_returns %>%
  ggplot(aes(date, growth_of_one, color = strategy)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = strategy_colors) +
  scale_y_continuous(labels = dollar_format()) +
  labs(title = "A realistic comparison includes passive alternatives and trading costs",
       subtitle = "Growth of $1; model portfolios rebalance monthly and pay 10 bps per one-way turnover",
       x = NULL, y = "Portfolio value", color = NULL,
       caption = "Out-of-sample backtest from 2024; excludes taxes and market impact") +
  theme(legend.position = "bottom", plot.title.position = "plot")
ggsave("figures/figure3_strategy_growth.png", p3, width = 9, height = 5.7, dpi = 200)

feature_labels <- c(
  mom_1m = "1-month momentum", mom_3m = "3-month momentum", mom_6m = "6-month momentum",
  reversal_5d = "5-day return", vol_1m = "1-month volatility", beta_3m = "3-month beta",
  idio_vol_3m = "Idiosyncratic volatility", relative_mom_3m = "Relative momentum",
  distance_52w_high = "Distance from 52-week high", log_dollar_volume = "Dollar volume",
  spy_mom_1m = "SPY 1-month momentum", spy_mom_3m = "SPY 3-month momentum"
)
p4 <- importance %>%
  slice_max(gain, n = 10) %>%
  mutate(label = recode(feature, !!!feature_labels), label = fct_reorder(label, gain)) %>%
  ggplot(aes(gain, label)) +
  geom_col(fill = "#4c78a8") +
  scale_x_continuous(labels = percent_format()) +
  labs(title = "What information did the improved model use?",
       subtitle = "XGBoost gain importance; importance does not establish causality",
       x = "Share of total gain", y = NULL, caption = "Source: fitted improved XGBoost model") +
  theme(plot.title.position = "plot")
ggsave("figures/figure4_feature_importance.png", p4, width = 9, height = 5.7, dpi = 200)

summary_values <- list(
  data_start = as.character(min(complete_panel$date)),
  data_end = as.character(max(complete_panel$target_end, na.rm = TRUE)),
  n_symbols = n_distinct(complete_panel$symbol),
  n_test_rows = nrow(monthly_predictions),
  test_months = n_distinct(monthly_predictions$month),
  best_depth = best$max_depth,
  best_eta = best$eta,
  best_rounds = best$best_iteration
)
jsonlite::write_json(summary_values, "data/analysis_summary.json", pretty = TRUE, auto_unbox = TRUE)

cat("Analysis complete.\n")
print(metrics)
print(strategy_metrics)
