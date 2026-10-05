library(dplyr)
library(readr)
library(lubridate)
library(tidyr)
library(ggplot2)
library(scales)

read_fred <- function(series_id) {
  path <- file.path("data", "raw", paste0(series_id, ".csv"))
  raw <- read_csv(path, show_col_types = FALSE)
  names(raw) <- c("date", "value")
  raw |>
    mutate(
      date = as.Date(date),
      value = suppressWarnings(as.numeric(na_if(as.character(value), ".")))
    ) |>
    filter(!is.na(value))
}

price <- read_fred("MSPUS") |>
  transmute(quarter = floor_date(date, "quarter"),
            home_price = value)

mortgage <- read_fred("MORTGAGE30US") |>
  mutate(quarter = floor_date(date, "quarter")) |>
  group_by(quarter) |>
  summarise(mortgage_rate = mean(value), .groups = "drop")

cpi_monthly <- read_fred("CPIAUCSL")
cpi_quarterly <- cpi_monthly |>
  mutate(quarter = floor_date(date, "quarter")) |>
  group_by(quarter) |>
  summarise(cpi = mean(value), .groups = "drop")
cpi_annual <- cpi_monthly |>
  mutate(year = year(date)) |>
  group_by(year) |>
  summarise(cpi_annual = mean(value), .groups = "drop")

income <- read_fred("MEHOINUSA646N") |>
  transmute(year = year(date), household_income = value) |>
  left_join(cpi_annual, by = "year")

recession <- read_fred("USRECQ") |>
  transmute(quarter = floor_date(date, "quarter"),
            recession = as.integer(value))

mortgage_payment <- function(price, annual_rate, down_payment = 0.20,
                             years = 30) {
  principal <- price * (1 - down_payment)
  monthly_rate <- annual_rate / 100 / 12
  months <- years * 12
  principal * monthly_rate * (1 + monthly_rate)^months /
    ((1 + monthly_rate)^months - 1)
}

housing <- price |>
  left_join(mortgage, by = "quarter") |>
  left_join(cpi_quarterly, by = "quarter") |>
  left_join(recession, by = "quarter") |>
  mutate(year = year(quarter)) |>
  inner_join(income, by = "year") |>
  filter(quarter >= as.Date("2000-01-01"),
         !is.na(home_price), !is.na(mortgage_rate), !is.na(cpi)) |>
  arrange(quarter)

latest_year <- max(housing$year)
target_cpi <- unique(housing$cpi_annual[housing$year == latest_year])

housing <- housing |>
  mutate(
    real_home_price = home_price * target_cpi / cpi,
    real_household_income = household_income * target_cpi / cpi_annual,
    monthly_payment = mortgage_payment(home_price, mortgage_rate),
    annual_payment = 12 * monthly_payment,
    payment_income_pct = 100 * annual_payment / household_income,
    home_price_income_ratio = home_price / household_income,
    down_payment = 0.20 * home_price
  )

base_index <- housing |> filter(quarter == min(quarter))
housing <- housing |>
  mutate(
    real_home_price_index =
      100 * real_home_price / base_index$real_home_price,
    real_income_index =
      100 * real_household_income / base_index$real_household_income
  )

baseline <- housing |> filter(quarter == as.Date("2019-10-01"))
latest <- housing |> filter(quarter == max(quarter))

stopifnot(nrow(baseline) == 1, nrow(latest) == 1,
          all(housing$mortgage_rate > 0),
          all(housing$payment_income_pct > 0),
          latest$quarter == as.Date(paste0(latest_year, "-10-01")))

scenario_values <- c(
  100 * 12 * mortgage_payment(
    baseline$home_price, baseline$mortgage_rate) / baseline$household_income,
  100 * 12 * mortgage_payment(
    latest$home_price, baseline$mortgage_rate) / baseline$household_income,
  100 * 12 * mortgage_payment(
    latest$home_price, latest$mortgage_rate) / baseline$household_income,
  100 * 12 * mortgage_payment(
    latest$home_price, latest$mortgage_rate) / latest$household_income
)

scenarios <- data.frame(
  stage = factor(
    c("2019 Q4\nconditions",
      paste0(latest_year, " price\n+ 2019 rate & income"),
      paste0(latest_year, " rate\n+ 2019 income"),
      paste0(latest_year, " income\n(actual)")),
    levels = c("2019 Q4\nconditions",
               paste0(latest_year, " price\n+ 2019 rate & income"),
               paste0(latest_year, " rate\n+ 2019 income"),
               paste0(latest_year, " income\n(actual)"))
  ),
  payment_income_pct = scenario_values,
  change_from_previous = c(NA, diff(scenario_values))
)

key_years <- housing |>
  filter(quarter %in% as.Date(c(
    "2000-10-01", "2006-10-01", "2012-10-01",
    "2019-10-01", "2021-10-01", paste0(latest_year, "-10-01")
  ))) |>
  transmute(
    quarter = paste0(year, " Q4"),
    median_new_home_price = round(home_price),
    mortgage_rate = round(mortgage_rate, 2),
    median_household_income = round(household_income),
    annual_payment_share_pct = round(payment_income_pct, 1)
  )

write_csv(housing, "data/processed/housing_affordability_quarterly.csv")
write_csv(scenarios, "data/processed/scenario_decomposition.csv")
write_csv(key_years, "data/processed/key_years.csv")

theme_blog <- theme_minimal(base_size = 12) +
  theme(
    plot.title.position = "plot",
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(color = "grey30", margin = margin(b = 10)),
    plot.caption = element_text(color = "grey40", hjust = 0),
    panel.grid.minor = element_blank(),
    legend.position = "top",
    legend.title = element_blank()
  )

indexed <- housing |>
  select(quarter, real_home_price_index, real_income_index) |>
  pivot_longer(-quarter, names_to = "series", values_to = "index") |>
  mutate(series = recode(
    series,
    real_home_price_index = "Median new-home price",
    real_income_index = "Median household income"
  ))

fig1 <- ggplot(indexed, aes(quarter, index, color = series)) +
  geom_hline(yintercept = 100, color = "grey75", linewidth = 0.5) +
  geom_line(linewidth = 1.15) +
  scale_color_manual(values = c(
    "Median new-home price" = "#C44E52",
    "Median household income" = "#246B8E"
  )) +
  scale_x_date(date_breaks = "5 years", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.02))) +
  scale_y_continuous(labels = label_number(accuracy = 1)) +
  labs(
    title = "Real home prices pulled away from real household income",
    subtitle = paste0("Inflation-adjusted indexes, 2000 Q1 = 100; through ",
                      latest_year, " Q4"),
    x = NULL, y = "Index (2000 Q1 = 100)",
    caption = "Sources: U.S. Census Bureau, HUD, and BLS via FRED. Income is annual and repeated within each year."
  ) +
  theme_blog

recession_spans <- housing |>
  filter(recession == 1) |>
  transmute(xmin = quarter, xmax = quarter %m+% months(3))

fig2 <- ggplot(housing, aes(quarter, payment_income_pct)) +
  geom_rect(
    data = recession_spans,
    aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
    inherit.aes = FALSE, fill = "grey85"
  ) +
  geom_line(color = "#246B8E", linewidth = 1.15) +
  geom_point(
    data = bind_rows(baseline, latest),
    color = "#C44E52", size = 2.8
  ) +
  geom_text(
    data = bind_rows(baseline, latest),
    aes(label = paste0(year, " Q4: ", round(payment_income_pct, 1), "%")),
    vjust = c(-0.9, -0.9), hjust = c(0.05, 1.05), color = "#C44E52",
    size = 3.5
  ) +
  scale_x_date(date_breaks = "5 years", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.03))) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.02, 0.10))) +
  labs(
    title = "The illustrative mortgage burden climbed sharply after 2019",
    subtitle = "Annual principal and interest on a 30-year mortgage with 20% down, as a share of median household income",
    x = NULL, y = "Annual payment / household income",
    caption = "Grey bands mark NBER recessions. Excludes property taxes, insurance, maintenance, and closing costs."
  ) +
  theme_blog

scenarios <- scenarios |>
  mutate(
    label = paste0(round(payment_income_pct, 1), "%"),
    delta_label = ifelse(
      is.na(change_from_previous), "",
      paste0(ifelse(change_from_previous >= 0, "+", ""),
             round(change_from_previous, 1), " pp")
    )
  )

fig3 <- ggplot(scenarios, aes(stage, payment_income_pct, fill = stage)) +
  geom_col(width = 0.68, show.legend = FALSE) +
  geom_text(aes(label = label), vjust = -0.55, fontface = "bold", size = 4) +
  geom_text(aes(label = delta_label), vjust = 1.6, color = "white",
            fontface = "bold", size = 3.5) +
  scale_fill_manual(values = c("#6C757D", "#D07629", "#C44E52", "#246B8E")) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.14))) +
  labs(
    title = "Higher rates added more pressure after prices had already risen",
    subtitle = paste0("Sequential counterfactual from 2019 Q4 to ",
                      latest_year, " Q4; the final income update partially offsets the increase"),
    x = NULL, y = "Annual payment / household income",
    caption = "The decomposition is order-dependent. It changes one observed input at a time and is descriptive, not causal."
  ) +
  theme_blog +
  theme(axis.text.x = element_text(size = 10))

ggsave("figures/figure1_real_prices_vs_income.png", fig1,
       width = 9, height = 5.4, dpi = 300, bg = "white")
ggsave("figures/figure2_mortgage_burden.png", fig2,
       width = 9, height = 5.4, dpi = 300, bg = "white")
ggsave("figures/figure3_affordability_decomposition.png", fig3,
       width = 9, height = 5.4, dpi = 300, bg = "white")
