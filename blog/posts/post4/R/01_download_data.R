# Download the five public FRED series used in Blog Post 4.
# No API key or login is required for FRED's graph CSV endpoint.

series <- c("MSPUS", "MORTGAGE30US", "MEHOINUSA646N",
            "CPIAUCSL", "USRECQ")
base_url <- "https://fred.stlouisfed.org/graph/fredgraph.csv?id="

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

for (id in series) {
  destination <- file.path("data", "raw", paste0(id, ".csv"))
  download.file(paste0(base_url, id), destination,
                mode = "wb", quiet = FALSE)
}

source_metadata <- data.frame(
  series_id = series,
  description = c(
    "Median sales price of new houses sold in the United States",
    "30-year fixed-rate mortgage average in the United States",
    "Median household income in the United States",
    "Consumer Price Index for All Urban Consumers: All Items",
    "NBER-based recession indicator, peak-following period through trough"
  ),
  source_agency = c(
    "U.S. Census Bureau and U.S. Department of Housing and Urban Development",
    "Freddie Mac",
    "U.S. Census Bureau",
    "U.S. Bureau of Labor Statistics",
    "Federal Reserve Bank of St. Louis, based on NBER dates"
  ),
  original_frequency = c("Quarterly", "Weekly", "Annual", "Monthly", "Quarterly"),
  units = c("Current dollars", "Percent", "Current dollars",
            "Index, 1982-1984=100", "1=recession, 0=expansion"),
  fred_url = paste0("https://fred.stlouisfed.org/series/", series),
  retrieved_on = as.character(Sys.Date())
)

write.csv(source_metadata, "data/source_metadata.csv", row.names = FALSE)
