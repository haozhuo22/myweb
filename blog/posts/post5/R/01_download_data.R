# Download the official source files used in Blog Post 5.
# The script is safe to rerun: existing files are not downloaded again.

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

sources <- c(
  B25070_2019 = "https://www2.census.gov/programs-surveys/acs/replicate_estimates/2019/data/5-year/050/B25070.csv.zip",
  B25070_2024 = "https://www2.census.gov/programs-surveys/acs/replicate_estimates/2024/data/5-year/050/B25070.csv.zip",
  county_boundaries = "https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_us_county_20m.zip",
  state_boundaries = "https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_us_state_20m.zip"
)

destinations <- c(
  "data/raw/B25070_2019.csv.zip",
  "data/raw/B25070_2024.csv.zip",
  "data/raw/cb_2024_us_county_20m.zip",
  "data/raw/cb_2024_us_state_20m.zip"
)

for (i in seq_along(sources)) {
  if (!file.exists(destinations[i])) {
    download.file(sources[i], destinations[i], mode = "wb", quiet = FALSE)
  }
}

metadata <- data.frame(
  file = basename(destinations),
  source_url = unname(sources),
  publisher = "U.S. Census Bureau",
  accessed = as.character(Sys.Date()),
  stringsAsFactors = FALSE
)

write.csv(metadata, "data/source_metadata.csv", row.names = FALSE)

