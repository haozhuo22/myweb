suppressPackageStartupMessages({
  library(rvest)
  library(dplyr)
  library(stringr)
  library(readr)
  library(ggplot2)
})

out_dir <- "/Users/zhz/AEDS6400/Haozhuo-web/blog/posts/post2"
url <- "https://en.wikipedia.org/wiki/List_of_national_parks_of_the_United_States"

page <- read_html(url)
raw <- page |>
  html_element("table.wikitable") |>
  html_table(fill = TRUE)

area_col <- names(raw)[str_detect(names(raw), "^Area")][1]
visit_col <- names(raw)[str_detect(names(raw), "^Recreation visitors")][1]
stopifnot(!is.na(area_col), !is.na(visit_col))

parks <- raw |>
  transmute(
    park = Name |> str_remove_all("[†‡*]") |> str_squish(),
    location = Location |>
      str_remove("\\s*\\.mw-parser.*$") |>
      str_remove("\\s+\\d.*$") |>
      str_squish(),
    area_acres = parse_number(.data[[area_col]]),
    visits_2025 = parse_number(.data[[visit_col]])
  ) |>
  mutate(
    visits_per_1000_acres = visits_2025 / (area_acres / 1000),
    contiguous_us = !str_detect(location, "Alaska|Hawaii|American Samoa|Virgin Islands"),
    established_destination = visits_2025 >= 500000,
    analysis_candidate = contiguous_us & established_destination
  )

stopifnot(
  nrow(raw) == nrow(parks),
  nrow(parks) >= 60,
  all(!is.na(parks$area_acres)),
  all(!is.na(parks$visits_2025)),
  all(parks$area_acres > 0),
  all(parks$visits_2025 > 0),
  !anyDuplicated(parks$park)
)

candidates <- parks |>
  filter(analysis_candidate) |>
  arrange(visits_per_1000_acres) |>
  mutate(visitor_pressure_rank = row_number()) |>
  select(visitor_pressure_rank, everything())

top_eight <- candidates |>
  slice_head(n = 8) |>
  mutate(
    label_x = c(2400000, 1500000, 800000, 460000, 2200000, 335000, 1010000, 405000),
    label_y = c(1600000, 960000, 500000, 960000, 5800000, 650000, 3700000, 1650000)
  )
reference_density <- median(candidates$visits_per_1000_acres)

plot_object <- ggplot(candidates, aes(area_acres, visits_2025)) +
  geom_abline(
    slope = reference_density / 1000,
    intercept = 0,
    linetype = "dashed", color = "#8A8A8A"
  ) +
  geom_point(color = "#9CB9C8", size = 2.6, alpha = 0.8) +
  geom_point(data = top_eight, color = "#C4512D", size = 3) +
  geom_segment(
    data = top_eight,
    aes(x = area_acres, y = visits_2025, xend = label_x, yend = label_y),
    inherit.aes = FALSE, color = "#B88D7C", linewidth = 0.35
  ) +
  geom_text(
    data = top_eight,
    aes(x = label_x, y = label_y, label = park),
    inherit.aes = FALSE, size = 3.2, color = "#5B2B1E"
  ) +
  scale_x_log10(labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  scale_y_log10(labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  labs(
    x = "Park area (acres, log scale)",
    y = "2025 recreation visits (log scale)",
    title = "Large parks can absorb the same annual visitation differently",
    subtitle = "Contiguous-U.S. parks with at least 500,000 visits",
    caption = "Source: Wikipedia table citing National Park Service statistics; scraped 2026-09-21."
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), plot.title.position = "plot")

# CSV is easy to inspect; RDS preserves the exact R dataframe and column types.
write_csv(as.data.frame(raw), file.path(out_dir, "raw_scraped_dataframe.csv"))
saveRDS(raw, file.path(out_dir, "raw_scraped_dataframe.rds"))
write_csv(parks, file.path(out_dir, "cleaned_national_parks.csv"))
write_csv(candidates, file.path(out_dir, "analysis_candidates.csv"))
ggsave(
  file.path(out_dir, "national_park_visitor_pressure.png"),
  plot = plot_object, width = 9, height = 6, units = "in", dpi = 300,
  bg = "white"
)

cat("raw rows:", nrow(raw), "cleaned rows:", nrow(parks),
    "candidate rows:", nrow(candidates), "\n")
cat("top three:", paste(candidates$park[1:3], collapse = ", "), "\n")
