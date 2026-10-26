"""Download World Bank data and build two self-contained Plotly visualizations."""

from datetime import date
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import requests


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "data" / "raw"
PROCESSED = ROOT / "data" / "processed"
FIGURES = ROOT / "figures"
for folder in (RAW, PROCESSED, FIGURES):
    folder.mkdir(parents=True, exist_ok=True)

START_YEAR = 1990
END_YEAR = 2023
INDICATORS = {
    "gdp_per_capita": "NY.GDP.PCAP.PP.KD",
    "life_expectancy": "SP.DYN.LE00.IN",
    "population": "SP.POP.TOTL",
}


def get_json(url):
    response = requests.get(url, timeout=90, headers={"User-Agent": "AEDS6400-student-project"})
    response.raise_for_status()
    return response.json()


def fetch_country_metadata():
    url = "https://api.worldbank.org/v2/country?format=json&per_page=400"
    payload = get_json(url)
    (RAW / "country_metadata.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    rows = []
    for item in payload[1]:
        if item["region"]["value"] == "Aggregates":
            continue
        rows.append(
            {
                "iso3": item["id"],
                "iso2": item["iso2Code"],
                "country": item["name"],
                "region": item["region"]["value"],
                "income_group": item["incomeLevel"]["value"],
            }
        )
    return pd.DataFrame(rows), url


def fetch_indicator(label, indicator):
    url = (
        f"https://api.worldbank.org/v2/country/all/indicator/{indicator}"
        f"?format=json&date={START_YEAR}:{END_YEAR}&per_page=20000"
    )
    payload = get_json(url)
    (RAW / f"{indicator}.json").write_text(json.dumps(payload), encoding="utf-8")
    rows = [
        {"iso3": x["countryiso3code"], "year": int(x["date"]), label: x["value"]}
        for x in payload[1]
        if x["countryiso3code"] and x["value"] is not None
    ]
    return pd.DataFrame(rows), url


def download_and_clean():
    countries, metadata_url = fetch_country_metadata()
    panel = None
    source_rows = []
    for label, indicator in INDICATORS.items():
        frame, url = fetch_indicator(label, indicator)
        panel = frame if panel is None else panel.merge(frame, on=["iso3", "year"], how="outer")
        source_rows.append(
            {"variable": label, "indicator": indicator, "source_url": url, "accessed": str(date.today())}
        )
    source_rows.append(
        {"variable": "country_metadata", "indicator": "country", "source_url": metadata_url,
         "accessed": str(date.today())}
    )
    pd.DataFrame(source_rows).to_csv(ROOT / "data" / "source_metadata.csv", index=False)

    panel = panel.merge(countries, on="iso3", how="inner")
    panel = panel.dropna(subset=["gdp_per_capita", "life_expectancy", "population"])
    panel = panel.query("gdp_per_capita > 0 and population > 0").copy()
    panel["year"] = panel["year"].astype(int)
    panel = panel.sort_values(["year", "region", "country"])
    panel.to_csv(PROCESSED / "world_income_health_panel.csv", index=False)
    return panel


def weighted_summary(panel):
    rows = []
    for (year, region), group in panel.groupby(["year", "region"]):
        weights = group["population"].to_numpy()
        rows.append(
            {
                "year": year,
                "region": region,
                "countries": len(group),
                "population": weights.sum(),
                "life_expectancy": np.average(group["life_expectancy"], weights=weights),
                "gdp_per_capita": np.average(group["gdp_per_capita"], weights=weights),
            }
        )
    regional = pd.DataFrame(rows)
    regional.to_csv(PROCESSED / "regional_weighted_trends.csv", index=False)
    return regional


def regression_summaries(panel):
    summaries = []
    for year, group in panel.groupby("year"):
        x = np.log2(group["gdp_per_capita"].to_numpy())
        y = group["life_expectancy"].to_numpy()
        slope, intercept = np.polyfit(x, y, 1)
        corr = np.corrcoef(x, y)[0, 1]
        pop = group["population"].to_numpy()
        summaries.append(
            {
                "year": year,
                "countries": len(group),
                "years_per_gdp_doubling": slope,
                "correlation": corr,
                "population_weighted_life_expectancy": np.average(y, weights=pop),
                "population_weighted_gdp_per_capita": np.average(group["gdp_per_capita"], weights=pop),
            }
        )
    result = pd.DataFrame(summaries)
    result.to_csv(PROCESSED / "annual_summary.csv", index=False)

    latest = panel[panel["year"] == END_YEAR].copy()
    x = np.log2(latest["gdp_per_capita"])
    slope, intercept = np.polyfit(x, latest["life_expectancy"], 1)
    latest["life_expectancy_residual"] = latest["life_expectancy"] - (intercept + slope * x)
    latest.sort_values("life_expectancy_residual").to_csv(
        PROCESSED / "latest_year_income_health_residuals.csv", index=False
    )
    return result, latest


def make_animation(panel):
    region_order = [
        "East Asia & Pacific", "Europe & Central Asia", "Latin America & Caribbean",
        "Middle East, North Africa, Afghanistan & Pakistan", "North America",
        "South Asia", "Sub-Saharan Africa",
    ]
    region_labels = {
        "East Asia & Pacific": "E. Asia & Pacific",
        "Europe & Central Asia": "Europe & C. Asia",
        "Latin America & Caribbean": "Latin America & Caribbean",
        "Middle East, North Africa, Afghanistan & Pakistan": "Middle East & N. Africa",
        "North America": "North America",
        "South Asia": "South Asia",
        "Sub-Saharan Africa": "Sub-Saharan Africa",
    }
    chart_data = panel.copy()
    chart_data["region"] = chart_data["region"].str.strip()
    chart_data["region_short"] = chart_data["region"].map(region_labels)
    palette = px.colors.qualitative.Safe
    fig = px.scatter(
        chart_data,
        x="gdp_per_capita",
        y="life_expectancy",
        animation_frame="year",
        animation_group="iso3",
        size="population",
        color="region_short",
        category_orders={"region_short": [region_labels[x] for x in region_order]},
        color_discrete_sequence=palette,
        hover_name="country",
        hover_data={
            "iso3": False,
            "region": True,
            "region_short": False,
            "income_group": True,
            "gdp_per_capita": ":$,.0f",
            "life_expectancy": ":.1f",
            "population": ":,.0f",
            "year": True,
        },
        log_x=True,
        size_max=55,
        range_x=[450, 180_000],
        range_y=[38, 88],
        labels={
            "gdp_per_capita": "GDP per capita, PPP (constant 2021 international $)",
            "life_expectancy": "Life expectancy at birth (years)",
            "region_short": "World Bank region",
        },
    )
    fig.update_layout(
        template="plotly_white", height=720,
        margin=dict(l=64, r=18, t=105, b=145),
        legend=dict(
            orientation="h", yanchor="bottom", y=1.02, xanchor="left", x=0,
            title_text="Region", font=dict(size=9),
            bgcolor="rgba(255,255,255,0.88)",
        ),
        font=dict(size=11),
        hoverlabel=dict(namelength=-1),
    )
    if fig.layout.sliders:
        fig.layout.sliders[0].update(
            x=0.16, len=0.82, y=-0.14, pad=dict(t=0),
            currentvalue=dict(prefix="Year: ", font=dict(size=12)),
        )
    if fig.layout.updatemenus:
        fig.layout.updatemenus[0].update(x=0.01, y=-0.14, pad=dict(t=0, r=8))
    fig.update_xaxes(gridcolor="#E8E8E8")
    fig.update_yaxes(gridcolor="#E8E8E8")
    fig.write_html(
        FIGURES / "figure1_income_health_animation.html",
        include_plotlyjs=True,
        full_html=True,
        config={"displaylogo": False, "responsive": True},
    )


def make_regional_selector(regional):
    regional = regional.copy()
    regional["region"] = regional["region"].str.strip()
    regions = sorted(regional["region"].unique())
    region_labels = {
        "East Asia & Pacific": "E. Asia & Pacific",
        "Europe & Central Asia": "Europe & C. Asia",
        "Latin America & Caribbean": "Latin America & Caribbean",
        "Middle East, North Africa, Afghanistan & Pakistan": "Middle East & N. Africa",
        "North America": "North America",
        "South Asia": "South Asia",
        "Sub-Saharan Africa": "Sub-Saharan Africa",
    }
    colors = dict(zip(regions, px.colors.qualitative.Safe * 2))
    fig = go.Figure()
    for region in regions:
        d = regional[regional["region"] == region]
        fig.add_trace(
            go.Scatter(
                x=d["year"], y=d["life_expectancy"], mode="lines+markers",
                name=region_labels[region], legendgroup=region,
                line=dict(color=colors[region], width=2.5),
                hovertemplate=f"<b>{region}</b><br>%{{x}}<br>Life expectancy: %{{y:.1f}} years<extra></extra>",
                visible=True,
            )
        )
    for region in regions:
        d = regional[regional["region"] == region]
        fig.add_trace(
            go.Scatter(
                x=d["year"], y=d["gdp_per_capita"], mode="lines+markers",
                name=region_labels[region], legendgroup=region, showlegend=False,
                line=dict(color=colors[region], width=2.5),
                hovertemplate=f"<b>{region}</b><br>%{{x}}<br>GDP per capita: $%{{y:,.0f}}<extra></extra>",
                visible=False,
            )
        )
    n = len(regions)
    fig.update_layout(
        template="plotly_white", height=650,
        yaxis_title="Population-weighted life expectancy (years)",
        xaxis_title="Year",
        legend=dict(
            orientation="h", yanchor="bottom", y=1.01, xanchor="left", x=0,
            font=dict(size=9), bgcolor="rgba(255,255,255,0.88)",
        ),
        updatemenus=[
            dict(
                type="buttons", direction="right", x=0, y=1.20,
                buttons=[
                    dict(label="Life expectancy", method="update",
                         args=[{"visible": [True] * n + [False] * n, "showlegend": [True] * n + [False] * n},
                               {"yaxis": {"title": "Population-weighted life expectancy (years)", "type": "linear"}}]),
                    dict(label="GDP per capita", method="update",
                         args=[{"visible": [False] * n + [True] * n, "showlegend": [False] * n + [True] * n},
                               {"yaxis": {"title": "Population-weighted GDP per capita (constant PPP $)", "type": "log"}}]),
                ],
            )
        ],
        margin=dict(l=70, r=18, t=125, b=70),
        font=dict(size=11),
    )
    fig.write_html(
        FIGURES / "figure2_regional_selector.html",
        include_plotlyjs=True,
        full_html=True,
        config={"displaylogo": False, "responsive": True},
    )


def main():
    panel = download_and_clean()
    regional = weighted_summary(panel)
    annual, latest = regression_summaries(panel)
    make_animation(panel)
    make_regional_selector(regional)

    print(f"Complete country-year observations: {len(panel):,}")
    for year in (START_YEAR, END_YEAR):
        row = annual.loc[annual.year == year].iloc[0]
        print(
            f"{year}: {int(row.countries)} countries; weighted life expectancy "
            f"{row.population_weighted_life_expectancy:.1f}; weighted GDP per capita "
            f"${row.population_weighted_gdp_per_capita:,.0f}; "
            f"{row.years_per_gdp_doubling:.2f} life-years per GDP doubling"
        )
    eligible = latest[latest.population >= 1_000_000]
    print("Largest positive residuals:")
    print(eligible.nlargest(5, "life_expectancy_residual")[["country", "life_expectancy_residual"]].to_string(index=False))
    print("Largest negative residuals:")
    print(eligible.nsmallest(5, "life_expectancy_residual")[["country", "life_expectancy_residual"]].to_string(index=False))


if __name__ == "__main__":
    main()

