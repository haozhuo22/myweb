"""Create a reproducible parent-child panel and estimate intergenerational elasticity.

The data are synthetic and PSID-style. They are generated with a fixed random seed
so the tutorial can be shared without disclosing restricted longitudinal records.
"""

from pathlib import Path
import math
import sqlite3

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


SEED = 6400
N_FAMILIES = 2_000
TRUE_IGE = 0.40
ROOT = Path(__file__).resolve().parent
DATA_RAW = ROOT / "data" / "raw"
DATA_PROCESSED = ROOT / "data" / "processed"
FIGURES = ROOT / "figures"
DB_PATH = ROOT / "data" / "family_panel.sqlite"

for folder in (DATA_RAW, DATA_PROCESSED, FIGURES):
    folder.mkdir(parents=True, exist_ok=True)


def make_panel():
    """Generate people and annual income records with realistic measurement noise."""
    rng = np.random.default_rng(SEED)
    family_num = np.arange(1, N_FAMILIES + 1)
    family_ids = [f"F{x:05d}" for x in family_num]
    parent_ids = [f"P{x:05d}" for x in family_num]
    child_ids = [f"C{x:05d}" for x in family_num]

    parent_birth = rng.integers(1958, 1968, N_FAMILIES)
    child_birth = parent_birth + rng.integers(25, 34, N_FAMILIES)

    parent_log_perm = math.log(70_000) + rng.normal(0, 0.45, N_FAMILIES)
    child_log_perm = (
        math.log(58_000)
        + TRUE_IGE * (parent_log_perm - math.log(70_000))
        + rng.normal(0, 0.38, N_FAMILIES)
    )

    people = pd.DataFrame(
        {
            "person_id": parent_ids + child_ids,
            "family_id": family_ids + family_ids,
            "role": ["parent"] * N_FAMILIES + ["child"] * N_FAMILIES,
            "birth_year": np.concatenate([parent_birth, child_birth]),
        }
    )

    records = []
    for idx in range(N_FAMILIES):
        # Parent income is observed from age 35 through 55.
        for age in range(35, 56):
            lifecycle = 0.025 * (age - 45) - 0.0015 * (age - 45) ** 2
            shock = rng.normal(0, 0.25)
            income = math.exp(parent_log_perm[idx] + lifecycle + shock)
            records.append((parent_ids[idx], int(parent_birth[idx] + age), age, round(income, 2)))

        # High-lifetime-income children have steeper early-career growth.
        # At young ages, their current income therefore understates long-run rank.
        perm_gap = child_log_perm[idx] - math.log(58_000)
        for age in range(22, 41):
            lifecycle = 0.035 * (age - 35) - 0.0015 * (age - 35) ** 2
            heterogeneous_growth = 0.030 * (age - 35) * perm_gap
            shock = rng.normal(0, 0.28)
            income = math.exp(child_log_perm[idx] + lifecycle + heterogeneous_growth + shock)
            records.append((child_ids[idx], int(child_birth[idx] + age), age, round(income, 2)))

    income = pd.DataFrame(records, columns=["person_id", "year", "age", "income"])
    people.to_csv(DATA_RAW / "people.csv", index=False)
    income.to_csv(DATA_RAW / "income_panel.csv", index=False)
    return people, income


def build_database(people, income):
    """Load both tables into SQLite and index the join keys."""
    if DB_PATH.exists():
        DB_PATH.unlink()
    with sqlite3.connect(DB_PATH) as con:
        people.to_sql("people", con, index=False, if_exists="replace")
        income.to_sql("income", con, index=False, if_exists="replace")
        con.executescript(
            """
            CREATE UNIQUE INDEX idx_people_person ON people(person_id);
            CREATE INDEX idx_people_family_role ON people(family_id, role);
            CREATE INDEX idx_income_person_age ON income(person_id, age);

            CREATE VIEW parent_child_links AS
            SELECT
                c.family_id,
                c.person_id AS child_id,
                p.person_id AS parent_id
            FROM people AS c
            JOIN people AS p
              ON c.family_id = p.family_id
             AND c.role = 'child'
             AND p.role = 'parent';
            """
        )


MATCH_QUERY = """
WITH parent_income AS (
    SELECT
        person_id,
        MAX(CASE WHEN age = 45 THEN income END) AS parent_income_age45,
        AVG(CASE WHEN age BETWEEN 40 AND 50 THEN income END) AS parent_income_avg
    FROM income
    GROUP BY person_id
),
child_income AS (
    SELECT
        person_id,
        MAX(CASE WHEN age = 25 THEN income END) AS child_income_age25,
        MAX(CASE WHEN age = 35 THEN income END) AS child_income_age35,
        AVG(CASE WHEN age BETWEEN 30 AND 40 THEN income END) AS child_income_avg
    FROM income
    GROUP BY person_id
)
SELECT
    l.family_id,
    l.parent_id,
    l.child_id,
    p.parent_income_age45,
    p.parent_income_avg,
    c.child_income_age25,
    c.child_income_age35,
    c.child_income_avg
FROM parent_child_links AS l
JOIN parent_income AS p ON l.parent_id = p.person_id
JOIN child_income AS c ON l.child_id = c.person_id
WHERE p.parent_income_age45 > 0
  AND p.parent_income_avg > 0
  AND c.child_income_age25 > 0
  AND c.child_income_age35 > 0
  AND c.child_income_avg > 0;
"""


def ols_ige(parent_income, child_income):
    """Return the OLS slope and 95% confidence interval in a log-log regression."""
    x = np.log(np.asarray(parent_income, dtype=float))
    y = np.log(np.asarray(child_income, dtype=float))
    x_centered = x - x.mean()
    beta = np.sum(x_centered * (y - y.mean())) / np.sum(x_centered**2)
    intercept = y.mean() - beta * x.mean()
    residual = y - intercept - beta * x
    se = math.sqrt(np.sum(residual**2) / (len(x) - 2) / np.sum(x_centered**2))
    return beta, beta - 1.96 * se, beta + 1.96 * se


def estimate_models(matched):
    specs = [
        ("Single year: child age 25", "parent_income_age45", "child_income_age25"),
        ("Single year: child age 35", "parent_income_age45", "child_income_age35"),
        ("11-year averages", "parent_income_avg", "child_income_avg"),
    ]
    rows = []
    for label, parent_col, child_col in specs:
        beta, lower, upper = ols_ige(matched[parent_col], matched[child_col])
        rows.append((label, beta, lower, upper, len(matched)))
    estimates = pd.DataFrame(rows, columns=["specification", "ige", "ci_lower", "ci_upper", "n"])
    estimates.to_csv(DATA_PROCESSED / "ige_estimates.csv", index=False)
    return estimates


def estimates_by_child_age(con):
    parent_avg = pd.read_sql_query(
        """
        SELECT person_id, AVG(income) AS parent_income_avg
        FROM income
        WHERE age BETWEEN 40 AND 50
        GROUP BY person_id
        """,
        con,
    )
    links = pd.read_sql_query("SELECT * FROM parent_child_links", con)
    ages = []
    for age in range(22, 41):
        child = pd.read_sql_query(
            "SELECT person_id, income FROM income WHERE age = ?", con, params=(age,)
        )
        sample = (
            links.merge(parent_avg, left_on="parent_id", right_on="person_id")
            .merge(child, left_on="child_id", right_on="person_id", suffixes=("_parent", "_child"))
        )
        beta, lower, upper = ols_ige(sample["parent_income_avg"], sample["income"])
        ages.append((age, beta, lower, upper))
    result = pd.DataFrame(ages, columns=["child_age", "ige", "ci_lower", "ci_upper"])
    result.to_csv(DATA_PROCESSED / "ige_by_child_age.csv", index=False)
    return result


def estimates_by_window(con):
    links = pd.read_sql_query("SELECT * FROM parent_child_links", con)
    rows = []
    for years in (1, 3, 5, 7, 11):
        half = years // 2
        parent = pd.read_sql_query(
            """SELECT person_id, AVG(income) AS income
               FROM income WHERE age BETWEEN ? AND ? GROUP BY person_id""",
            con,
            params=(45 - half, 45 + half),
        )
        child = pd.read_sql_query(
            """SELECT person_id, AVG(income) AS income
               FROM income WHERE age BETWEEN ? AND ? GROUP BY person_id""",
            con,
            params=(35 - half, 35 + half),
        )
        sample = (
            links.merge(parent, left_on="parent_id", right_on="person_id")
            .merge(child, left_on="child_id", right_on="person_id", suffixes=("_parent", "_child"))
        )
        beta, lower, upper = ols_ige(sample["income_parent"], sample["income_child"])
        rows.append((years, beta, lower, upper))
    result = pd.DataFrame(rows, columns=["years_averaged", "ige", "ci_lower", "ci_upper"])
    result.to_csv(DATA_PROCESSED / "ige_by_averaging_window.csv", index=False)
    return result


def save_figures(estimates, by_age, by_window):
    plt.style.use("seaborn-v0_8-whitegrid")
    red = "#B2182B"
    blue = "#2166AC"
    navy = "#16324F"

    fig, ax = plt.subplots(figsize=(9, 5.5))
    order = estimates.iloc[::-1]
    xerr = np.vstack([order["ige"] - order["ci_lower"], order["ci_upper"] - order["ige"]])
    ax.errorbar(order["ige"], order["specification"], xerr=xerr, fmt="o", color=navy,
                ecolor="#6B7C8F", capsize=5, markersize=9, linewidth=2)
    ax.axvline(TRUE_IGE, color=red, linestyle="--", linewidth=1.8, label="Data-generating IGE = 0.40")
    for y, value in enumerate(order["ige"]):
        ax.text(value + 0.012, y, f"{value:.3f}", va="center", fontsize=10)
    ax.set(xlabel="Estimated intergenerational elasticity", ylabel="",
           title="One young-age income observation understates persistence")
    ax.legend(frameon=False, loc="lower left")
    ax.spines[["top", "right", "left"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(FIGURES / "figure1_ige_comparison.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5.5))
    ax.fill_between(by_age["child_age"], by_age["ci_lower"], by_age["ci_upper"], color=blue, alpha=0.16)
    ax.plot(by_age["child_age"], by_age["ige"], color=blue, marker="o", linewidth=2.5, markersize=4)
    ax.axhline(TRUE_IGE, color=red, linestyle="--", linewidth=1.8, label="Data-generating IGE = 0.40")
    ax.set(xlabel="Child age when annual income is measured", ylabel="Estimated IGE",
           title="The same families produce different IGE estimates over the life cycle")
    ax.set_xticks(range(22, 41, 2))
    ax.legend(frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(FIGURES / "figure2_lifecycle_bias.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5.5))
    ax.plot(by_window["years_averaged"], by_window["ige"], color=navy, marker="o",
            linewidth=2.5, markersize=7)
    ax.fill_between(by_window["years_averaged"], by_window["ci_lower"],
                    by_window["ci_upper"], color=navy, alpha=0.14)
    ax.axhline(TRUE_IGE, color=red, linestyle="--", linewidth=1.8, label="Data-generating IGE = 0.40")
    ax.set(xlabel="Number of income years averaged for each generation", ylabel="Estimated IGE",
           title="Averaging reduces transitory-income attenuation")
    ax.set_xticks(by_window["years_averaged"])
    ax.legend(frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    fig.savefig(FIGURES / "figure3_averaging_window.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def main():
    people, income = make_panel()
    build_database(people, income)
    with sqlite3.connect(DB_PATH) as con:
        matched = pd.read_sql_query(MATCH_QUERY, con)
        matched.to_csv(DATA_PROCESSED / "matched_parent_child.csv", index=False)
        estimates = estimate_models(matched)
        by_age = estimates_by_child_age(con)
        by_window = estimates_by_window(con)

    save_figures(estimates, by_age, by_window)
    print("Matched families:", f"{len(matched):,}")
    print(estimates.to_string(index=False, float_format=lambda x: f"{x:.3f}"))


if __name__ == "__main__":
    main()
