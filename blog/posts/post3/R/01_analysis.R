suppressPackageStartupMessages({
  library(ipumsr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(readr)
  library(scales)
})

dir.create("figures", showWarnings = FALSE, recursive = TRUE)
dir.create("derived", showWarnings = FALSE, recursive = TRUE)

xml_files <- list.files("data", pattern = "\\.xml$", full.names = TRUE)
if (length(xml_files) != 1) {
  stop("Place exactly one IPUMS CPS DDI .xml file and its .dat.gz file in data/.")
}

ddi <- read_ipums_ddi(xml_files)
cps_raw <- read_ipums_micro(
  ddi,
  data_file = sub("\\.xml$", ".dat.gz", xml_files),
  verbose = FALSE
)

required <- c("YEAR", "MONTH", "AGE", "EDUC", "EMPSTAT", "WTFINL")
stopifnot(all(required %in% names(cps_raw)))

cps <- cps_raw |>
  transmute(
    year = as.integer(YEAR),
    month = as.integer(MONTH),
    age = as.integer(AGE),
    educ_code = as.integer(EDUC),
    empstat_code = as.integer(EMPSTAT),
    weight = as.numeric(WTFINL)
  ) |>
  filter(age >= 25, age <= 64, weight > 0) |>
  mutate(
    education = case_when(
      educ_code %in% c(2, 10, 20, 30, 40, 50, 60, 71) ~ "Less than high school",
      educ_code == 73 ~ "High school",
      educ_code %in% c(81, 91, 92) ~ "Some college / associate",
      educ_code %in% c(111, 123, 124, 125) ~ "Bachelor's or higher",
      TRUE ~ NA_character_
    ),
    labor_status = case_when(
      empstat_code >= 10 & empstat_code < 20 ~ "Employed",
      empstat_code >= 20 & empstat_code < 30 ~ "Unemployed",
      empstat_code >= 30 & empstat_code < 40 ~ "Not in labor force",
      TRUE ~ NA_character_
    ),
    in_labor_force = labor_status %in% c("Employed", "Unemployed"),
    unemployed = labor_status == "Unemployed"
  ) |>
  filter(!is.na(education), !is.na(labor_status))

education_levels <- c(
  "Less than high school", "High school",
  "Some college / associate", "Bachelor's or higher"
)
cps$education <- factor(cps$education, levels = education_levels)

weighted_rate <- function(x, w) weighted.mean(as.numeric(x), w, na.rm = TRUE)

unemployment_trend <- cps |>
  filter(in_labor_force) |>
  group_by(year, education) |>
  summarise(
    unemployment_rate = weighted_rate(unemployed, weight),
    weighted_labor_force = sum(weight),
    unweighted_n = n(),
    .groups = "drop"
  )

shock_years <- unemployment_trend |>
  filter(year %in% c(2007, 2010, 2019, 2020, 2025)) |>
  mutate(
    period = factor(
      year,
      levels = c(2007, 2010, 2019, 2020, 2025),
      labels = c("2007", "2010", "2019", "2020", "2025")
    )
  )

status_2025 <- cps |>
  filter(year == 2025) |>
  group_by(education, labor_status) |>
  summarise(weighted_people = sum(weight), .groups = "drop") |>
  group_by(education) |>
  mutate(share = weighted_people / sum(weighted_people)) |>
  ungroup()

headline_results <- unemployment_trend |>
  filter(year %in% c(2007, 2010, 2019, 2020, 2025)) |>
  select(year, education, unemployment_rate) |>
  pivot_wider(names_from = year, values_from = unemployment_rate, names_prefix = "rate_") |>
  mutate(
    great_recession_change_pp = 100 * (rate_2010 - rate_2007),
    covid_change_pp = 100 * (rate_2020 - rate_2019)
  )

shock_changes <- headline_results |>
  select(education, great_recession_change_pp, covid_change_pp) |>
  pivot_longer(
    cols = ends_with("_pp"),
    names_to = "shock", values_to = "change_pp"
  ) |>
  mutate(shock = recode(
    shock,
    great_recession_change_pp = "Great Recession: 2007–2010",
    covid_change_pp = "COVID-19 shock: 2019–2020"
  ))

write_csv(unemployment_trend, "derived/unemployment_trend.csv")
write_csv(shock_years, "derived/shock_years.csv")
write_csv(status_2025, "derived/status_composition_2025.csv")
write_csv(headline_results, "derived/headline_results.csv")
write_csv(shock_changes, "derived/shock_changes.csv")

palette_education <- c(
  "Less than high school" = "#B54A3A",
  "High school" = "#DB8A34",
  "Some college / associate" = "#4B8E8D",
  "Bachelor's or higher" = "#315B7D"
)

p1 <- ggplot(unemployment_trend, aes(year, unemployment_rate, color = education)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.5) +
  scale_color_manual(values = palette_education) +
  scale_y_continuous(labels = label_percent(accuracy = 1), limits = c(0, NA)) +
  scale_x_continuous(breaks = seq(2000, 2025, 5)) +
  labs(
    title = "Unemployment rises in every downturn, but less for college graduates",
    subtitle = "Adults ages 25–64; May CPS basic monthly samples; weighted with WTFINL",
    x = NULL, y = "Unemployment rate", color = "Education",
    caption = "Source: IPUMS CPS. Rates use the civilian labor force denominator."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom", panel.grid.minor = element_blank(),
    axis.text.y = element_text(color = "#333333")
  )

p2 <- ggplot(shock_changes, aes(change_pp, education, fill = shock)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.62) +
  geom_text(
    aes(label = number(change_pp, accuracy = 0.1, suffix = " pp")),
    position = position_dodge(width = 0.72), hjust = -0.08, size = 3.6
  ) +
  scale_fill_manual(values = c(
    "Great Recession: 2007–2010" = "#4B8E8D",
    "COVID-19 shock: 2019–2020" = "#B54A3A"
  )) +
  scale_x_continuous(limits = c(0, 16), breaks = seq(0, 16, 4), expand = expansion(mult = c(0, .01))) +
  labs(
    title = "Joblessness rose most for workers with less education",
    subtitle = "Change in the weighted May unemployment rate during two shocks",
    x = "Increase in unemployment rate (percentage points)", y = NULL, fill = NULL,
    caption = "Source: IPUMS CPS; weighted with WTFINL."
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())

status_order <- c("Employed", "Unemployed", "Not in labor force")
status_2025$labor_status <- factor(status_2025$labor_status, levels = status_order)
p3 <- ggplot(status_2025, aes(education, share, fill = labor_status)) +
  geom_col(width = 0.72) +
  geom_text(
    aes(label = if_else(share >= .05, percent(share, accuracy = 1), "")),
    position = position_stack(vjust = 0.5), size = 3.4,
    color = ifelse(status_2025$labor_status == "Employed", "white", "#333333")
  ) +
  coord_flip() +
  scale_fill_manual(values = c(
    "Employed" = "#315B7D", "Unemployed" = "#B54A3A",
    "Not in labor force" = "#D8D3C8"
  )) +
  scale_y_continuous(labels = label_percent(accuracy = 1), expand = expansion(mult = c(0, .01))) +
  labs(
    title = "Education differences extend beyond unemployment",
    subtitle = "Weighted employment-status composition, May 2025, ages 25–64",
    x = NULL, y = "Share of the population", fill = NULL,
    caption = "Source: IPUMS CPS; weighted with WTFINL."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom", panel.grid.minor = element_blank(),
    axis.text.y = element_text(color = "#333333")
  )

ggsave("figures/01_unemployment_trend.png", p1, width = 9, height = 5.8, dpi = 300, bg = "white")
ggsave("figures/02_recession_comparison.png", p2, width = 9, height = 5.8, dpi = 300, bg = "white")
ggsave("figures/03_status_composition_2025.png", p3, width = 9, height = 5.8, dpi = 300, bg = "white")

message("Analysis complete: weighted tables and three figures written to derived/ and figures/.")
