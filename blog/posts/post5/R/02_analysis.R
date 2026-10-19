if (dir.exists("R-lib")) .libPaths(c("R-lib", .libPaths()))

library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(scales)
library(sf)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("figures", recursive = TRUE, showWarnings = FALSE)
dir.create("data/raw/shapes", recursive = TRUE, showWarnings = FALSE)

unzip_if_needed <- function(zip_file, expected_shp) {
  if (!file.exists(expected_shp)) {
    unzip(zip_file, exdir = "data/raw/shapes")
  }
}

unzip_if_needed(
  "data/raw/cb_2024_us_county_20m.zip",
  "data/raw/shapes/cb_2024_us_county_20m.shp"
)
unzip_if_needed(
  "data/raw/cb_2024_us_state_20m.zip",
  "data/raw/shapes/cb_2024_us_state_20m.shp"
)

read_b25070 <- function(zip_file, member, year) {
  con <- unz(zip_file, member, encoding = "latin1")
  raw <- read.csv(con, check.names = FALSE, stringsAsFactors = FALSE)
  raw$NAME <- iconv(raw$NAME, from = "latin1", to = "UTF-8")

  raw |>
    filter(GEOID != "", ORDER %in% 1:11) |>
    transmute(
      geoid = substr(GEOID, nchar(GEOID) - 4, nchar(GEOID)),
      county = sub(", [^,]+$", "", NAME),
      state = sub("^.*, ", "", NAME),
      order = as.integer(ORDER),
      estimate = as.numeric(ESTIMATE)
    ) |>
    pivot_wider(names_from = order, values_from = estimate, names_prefix = "line_") |>
    transmute(
      geoid,
      county,
      state,
      year,
      renter_households = line_1,
      not_computed = line_11,
      computable_renter_households = line_1 - line_11,
      cost_burdened_households = line_7 + line_8 + line_9 + line_10,
      cost_burden_rate = 100 * cost_burdened_households / computable_renter_households
    )
}

county_2019 <- read_b25070(
  "data/raw/B25070_2019.csv.zip", "B25070.csv", 2019
)
county_2024 <- read_b25070(
  "data/raw/B25070_2024.csv.zip", "050/B25070.csv", 2024
)

county_panel <- bind_rows(county_2019, county_2024) |>
  mutate(state_fips = substr(geoid, 1, 2))

county_change <- county_2019 |>
  select(geoid, rate_2019 = cost_burden_rate) |>
  inner_join(
    county_2024 |>
      select(geoid, county, state, rate_2024 = cost_burden_rate,
             computable_renter_households),
    by = "geoid"
  ) |>
  mutate(change_pp = rate_2024 - rate_2019, state_fips = substr(geoid, 1, 2))

state_panel <- county_panel |>
  group_by(year, state_fips, state) |>
  summarise(
    computable_renter_households = sum(computable_renter_households, na.rm = TRUE),
    cost_burdened_households = sum(cost_burdened_households, na.rm = TRUE),
    cost_burden_rate = 100 * cost_burdened_households / computable_renter_households,
    .groups = "drop"
  )

state_change <- state_panel |>
  select(year, state_fips, state, cost_burden_rate) |>
  pivot_wider(names_from = year, values_from = cost_burden_rate, names_prefix = "rate_") |>
  mutate(change_pp = rate_2024 - rate_2019)

write_csv(county_panel, "data/processed/county_renter_cost_burden.csv")
write_csv(county_change, "data/processed/county_change_2019_2024.csv")
write_csv(state_panel, "data/processed/state_renter_cost_burden.csv")
write_csv(state_change, "data/processed/state_change_2019_2024.csv")

top_counties <- county_2024 |>
  filter(computable_renter_households >= 5000) |>
  arrange(desc(cost_burden_rate)) |>
  slice_head(n = 15)
write_csv(top_counties, "data/processed/top_counties_2024.csv")

counties <- st_read(
  "data/raw/shapes/cb_2024_us_county_20m.shp",
  quiet = TRUE
) |>
  st_transform(5070)

states <- st_read(
  "data/raw/shapes/cb_2024_us_state_20m.shp",
  quiet = TRUE
) |>
  st_transform(5070)

excluded_fips <- c("02", "15", "60", "66", "69", "72", "78")
county_map_base <- counties |>
  filter(!STATEFP %in% excluded_fips)
state_borders <- states |>
  filter(!STATEFP %in% excluded_fips)

map_2024 <- county_map_base |>
  left_join(county_2024, by = c("GEOID" = "geoid"))

figure1 <- ggplot(map_2024) +
  geom_sf(aes(fill = cost_burden_rate), color = NA) +
  geom_sf(data = state_borders, fill = NA, color = "white", linewidth = 0.25) +
  scale_fill_viridis_c(
    option = "magma", direction = -1,
    limits = c(30, 65), oob = squish,
    labels = label_percent(scale = 1),
    name = "Cost-burdened\nrenter households"
  ) +
  labs(
    title = "Renter cost burdens are widespread, but strongest in distinct regional clusters",
    subtitle = "Share of renter households spending at least 30% of income on gross rent, 2024",
    caption = "Source: U.S. Census Bureau, 2020–2024 ACS 5-year estimates, table B25070.\nAlaska, Hawaii, and territories omitted from the map for scale."
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 11, margin = margin(b = 8)),
    legend.position = "bottom",
    legend.key.width = unit(35, "mm"),
    plot.caption = element_text(hjust = 0, color = "grey35")
  )

ggsave("figures/figure1_2024_cost_burden_map.png", figure1,
       width = 10.5, height = 7, dpi = 300, bg = "white")

change_map <- county_map_base |>
  left_join(county_change, by = c("GEOID" = "geoid"))

figure2 <- ggplot(change_map) +
  geom_sf(aes(fill = change_pp), color = NA) +
  geom_sf(data = state_borders, fill = NA, color = "grey25", linewidth = 0.22) +
  scale_fill_gradient2(
    low = "#2166AC", mid = "#F7F7F7", high = "#B2182B", midpoint = 0,
    limits = c(-12, 12), oob = squish,
    breaks = c(-12, -6, 0, 6, 12),
    labels = function(x) paste0(ifelse(x > 0, "+", ""), x, " pp"),
    na.value = "grey85", name = "Change"
  ) +
  labs(
    title = "The national pattern hides sharply different local trajectories",
    subtitle = "Percentage-point change in renter cost-burden rate, 2019 to 2024",
    caption = "Source: U.S. Census Bureau ACS 5-year estimates, table B25070. Values outside ±12 pp are capped in the color scale.\nConnecticut is gray because the Census Bureau replaced counties with planning regions after 2019."
  ) +
  theme_void(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 11, margin = margin(b = 8)),
    legend.position = "bottom",
    legend.key.width = unit(35, "mm"),
    plot.caption = element_text(hjust = 0, color = "grey35")
  )

ggsave("figures/figure2_change_map.png", figure2,
       width = 10.5, height = 7, dpi = 300, bg = "white")

plot_states <- state_change |>
  filter(!state_fips %in% c("60", "66", "69", "72", "78"),
         !is.na(change_pp)) |>
  slice_max(order_by = abs(change_pp), n = 15, with_ties = FALSE) |>
  arrange(change_pp) |>
  mutate(state = factor(state, levels = state))

figure3 <- ggplot(plot_states, aes(y = state)) +
  geom_vline(xintercept = 0, color = "grey70", linewidth = 0.5) +
  geom_segment(aes(x = 0, xend = change_pp, yend = state, color = change_pp),
               linewidth = 2.8, lineend = "round") +
  geom_point(aes(x = change_pp, color = change_pp), size = 3.8) +
  scale_color_gradient2(low = "#2166AC", mid = "#999999", high = "#B2182B", midpoint = 0,
                        guide = "none") +
  scale_x_continuous(labels = function(x) paste0(ifelse(x > 0, "+", ""), x, " pp")) +
  labs(
    title = "The largest statewide shifts were measured in both directions",
    subtitle = "Fifteen states with the largest absolute change in renter cost burden, 2019–2024",
    x = "Percentage-point change", y = NULL,
    caption = "Rates are calculated from summed county counts, so larger counties receive appropriate population weight.\nSource: U.S. Census Bureau ACS 5-year estimates, table B25070."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 15),
    plot.caption = element_text(hjust = 0, color = "grey35")
  )

ggsave("figures/figure3_state_change.png", figure3,
       width = 9, height = 6.5, dpi = 300, bg = "white")

cat("National weighted rates:\n")
print(state_panel |>
        filter(!state_fips %in% c("60", "66", "69", "72", "78")) |>
        group_by(year) |>
        summarise(rate = 100 * sum(cost_burdened_households) /
                    sum(computable_renter_households)))
cat("\nLargest state changes:\n")
print(state_change |> arrange(desc(change_pp)) |> select(state, rate_2019, rate_2024, change_pp) |> head(10))
cat("\nLargest state declines:\n")
print(state_change |> arrange(change_pp) |> select(state, rate_2019, rate_2024, change_pp) |> head(10))
cat("\nTop large counties, 2024:\n")
print(top_counties |> select(county, state, cost_burden_rate) |> head(10))
