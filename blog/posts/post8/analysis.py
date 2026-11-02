"""Reproduce the simulations and interactive Plotly figures for Blog Post 8."""

from pathlib import Path
import numpy as np
import pandas as pd
import plotly.graph_objects as go

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
FIGURES = ROOT / "figures"
DATA.mkdir(exist_ok=True)
FIGURES.mkdir(exist_ok=True)

SEED = 6400
TRUE_MEAN = 1.0
POP_SHAPE = 4.0
POP_SCALE = TRUE_MEAN / POP_SHAPE
BOOT_REPS = 2_000
COVERAGE_EXPERIMENTS = 500
DISPLAY_INTERVALS = 80


def bootstrap_means(rng, sample, reps=BOOT_REPS):
    indices = rng.integers(0, len(sample), size=(reps, len(sample)))
    return sample[indices].mean(axis=1)


def make_bootstrap_figure(rng):
    sample = rng.gamma(POP_SHAPE, POP_SCALE, size=50)
    boot = bootstrap_means(rng, sample, 5_000)
    low, high = np.quantile(boot, [0.025, 0.975])
    sample_mean = sample.mean()

    pd.DataFrame({"value": sample}).to_csv(DATA / "bootstrap_sample.csv", index=False)
    pd.DataFrame({"bootstrap_mean": boot}).to_csv(DATA / "bootstrap_distribution.csv", index=False)

    fig = go.Figure()
    fig.add_histogram(
        x=boot, nbinsx=48, name="Bootstrap means",
        marker_color="#4C78A8", opacity=0.82,
        hovertemplate="Bootstrap mean: %{x:.3f}<br>Count: %{y}<extra></extra>",
    )
    ymax = np.histogram(boot, bins=48)[0].max()
    for x, color, dash, label in [
        (TRUE_MEAN, "#222222", "dash", "True population mean"),
        (sample_mean, "#2A9D8F", "solid", "Sample mean"),
        (low, "#E45756", "dot", "95% percentile limits"),
        (high, "#E45756", "dot", None),
    ]:
        fig.add_trace(go.Scatter(
            x=[x, x], y=[0, ymax * 1.05], mode="lines", name=label,
            showlegend=label is not None,
            line=dict(color=color, width=2.4, dash=dash),
            hovertemplate=f"{label or 'Upper 95% limit'}: {x:.3f}<extra></extra>",
        ))
    fig.update_layout(
        template="plotly_white", height=540,
        margin=dict(l=58, r=18, t=72, b=65),
        xaxis_title="Mean of a bootstrap resample",
        yaxis_title="Number of resamples",
        legend=dict(orientation="h", yanchor="bottom", y=1.01, x=0, font=dict(size=10)),
        bargap=0.03, font=dict(size=11), hoverlabel=dict(namelength=-1),
    )
    write_figure(fig, "figure1_bootstrap_distribution.html")
    return sample_mean, low, high


def interval_segments(frame, covered):
    subset = frame.head(DISPLAY_INTERVALS)
    subset = subset[subset["covered"] == covered]
    xs, ys = [], []
    for row in subset.itertuples():
        xs.extend([row.low, row.high, None])
        ys.extend([row.display_order, row.display_order, None])
    return xs, ys


def coverage_annotation(n, level, coverage):
    return dict(
        x=1, y=1.18, xref="paper", yref="paper", xanchor="right", showarrow=False,
        text=f"n={n}; nominal={level:.0%}; observed coverage={coverage:.1%}",
        font=dict(size=12, color="#333333"),
    )


def make_coverage_figure(rng):
    sample_sizes = [20, 50, 100]
    levels = [0.90, 0.95, 0.99]
    combos, summaries = [], []

    for n in sample_sizes:
        for level in levels:
            alpha = 1 - level
            rows = []
            for experiment in range(COVERAGE_EXPERIMENTS):
                sample = rng.gamma(POP_SHAPE, POP_SCALE, size=n)
                boot = bootstrap_means(rng, sample)
                low, high = np.quantile(boot, [alpha / 2, 1 - alpha / 2])
                rows.append((experiment + 1, low, high, low <= TRUE_MEAN <= high))
            frame = pd.DataFrame(rows, columns=["experiment", "low", "high", "covered"])
            frame = pd.concat([frame[~frame.covered], frame[frame.covered]], ignore_index=True)
            frame["display_order"] = np.arange(1, len(frame) + 1)
            coverage = frame.covered.mean()
            combos.append((n, level, coverage, frame))
            summaries.append({"sample_size": n, "confidence_level": level,
                              "empirical_coverage": coverage,
                              "experiments": COVERAGE_EXPERIMENTS,
                              "bootstrap_resamples": BOOT_REPS})

    pd.DataFrame(summaries).to_csv(DATA / "coverage_results.csv", index=False)

    fig = go.Figure()
    for n, level, coverage, frame in combos:
        for covered, name, color in [
            (True, "Interval contains the true mean", "#2A9D8F"),
            (False, "Interval misses the true mean", "#E45756"),
        ]:
            xs, ys = interval_segments(frame, covered)
            fig.add_trace(go.Scatter(
                x=xs, y=ys, mode="lines", name=name,
                line=dict(color=color, width=2.2),
                visible=(n == 50 and level == 0.95),
                hoverinfo="skip", showlegend=True,
            ))

    buttons = []
    for i, (n, level, coverage, _) in enumerate(combos):
        visible = [False] * (2 * len(combos))
        visible[2 * i:2 * i + 2] = [True, True]
        buttons.append(dict(
            label=f"n={n}, {int(level*100)}% CI", method="update",
            args=[{"visible": visible},
                  {"annotations": [coverage_annotation(n, level, coverage)]}],
        ))

    default = next(x for x in combos if x[0] == 50 and x[1] == 0.95)
    fig.update_layout(
        template="plotly_white", height=650,
        margin=dict(l=58, r=18, t=115, b=62),
        xaxis_title="Bootstrap confidence interval for the population mean",
        yaxis_title="Simulated experiment (misses shown first)",
        yaxis=dict(range=[DISPLAY_INTERVALS + 2, 0]),
        legend=dict(orientation="h", yanchor="bottom", y=1.01, x=0, font=dict(size=10)),
        updatemenus=[dict(
            buttons=buttons, direction="down", x=0, xanchor="left",
            y=1.19, yanchor="top", showactive=True, active=4,
        )],
        shapes=[dict(type="line", x0=TRUE_MEAN, x1=TRUE_MEAN, y0=0, y1=1,
                     yref="paper", line=dict(color="#222222", width=2, dash="dash"))],
        annotations=[coverage_annotation(*default[:3])],
        font=dict(size=11),
    )
    write_figure(fig, "figure2_coverage_explorer.html")
    return pd.DataFrame(summaries)


def test_annotation(result):
    decision = "reject H₀" if result["reject_at_5_percent"] else "do not reject H₀"
    return dict(
        x=1, y=1.18, xref="paper", yref="paper", xanchor="right", showarrow=False,
        text=f"two-sided p={result['p_value']:.3f}; {decision} at 5%",
        font=dict(size=12, color="#333333"),
    )


def make_hypothesis_figure(rng):
    n = 40
    sims = 20_000
    group_a = rng.gamma(POP_SHAPE, POP_SCALE, size=(sims, n))
    group_b = rng.gamma(POP_SHAPE, POP_SCALE, size=(sims, n))
    null_stats = group_b.mean(axis=1) - group_a.mean(axis=1)
    critical = np.quantile(np.abs(null_stats), 0.95)
    effects = [0.15, 0.25, 0.35]
    pd.DataFrame({"null_difference_in_means": null_stats}).to_csv(
        DATA / "null_distribution.csv", index=False
    )

    fig = go.Figure()
    results = []
    ymax = np.histogram(null_stats, bins=65)[0].max()
    for observed in effects:
        p_value = (np.count_nonzero(np.abs(null_stats) >= abs(observed)) + 1) / (sims + 1)
        reject = bool(abs(observed) >= critical)
        result = {"observed_difference": observed, "p_value": p_value,
                  "critical_absolute_difference": critical,
                  "reject_at_5_percent": reject,
                  "null_simulations": sims, "group_sample_size": n}
        results.append(result)
        visible = observed == 0.25
        fig.add_histogram(
            x=null_stats, nbinsx=65, name="Null distribution", visible=visible,
            marker_color="#9EC1D9", opacity=0.82,
            hovertemplate="Difference: %{x:.3f}<br>Count: %{y}<extra></extra>",
        )
        tails = null_stats[np.abs(null_stats) >= abs(observed)]
        fig.add_histogram(
            x=tails, nbinsx=65, name="Outcomes at least as extreme", visible=visible,
            marker_color="#F4A261", opacity=0.92,
            hovertemplate="Tail outcome: %{x:.3f}<br>Count: %{y}<extra></extra>",
        )
        fig.add_trace(go.Scatter(
            x=[observed, observed], y=[0, ymax * 1.04], mode="lines",
            name="Observed statistic", visible=visible,
            line=dict(color="#9D174D", width=3),
            hovertemplate=f"Observed difference: {observed:.2f}<extra></extra>",
        ))

    buttons = []
    for i, result in enumerate(results):
        visible = [False] * (3 * len(results))
        visible[3 * i:3 * i + 3] = [True, True, True]
        buttons.append(dict(
            label=f"Observed difference = {result['observed_difference']:.2f}",
            method="update",
            args=[{"visible": visible}, {"annotations": [test_annotation(result)]}],
        ))
    default = results[1]
    fig.update_layout(
        template="plotly_white", height=590, barmode="overlay", bargap=0.03,
        margin=dict(l=58, r=18, t=112, b=65),
        xaxis_title="Difference in sample means under H₀",
        yaxis_title="Number of null simulations",
        legend=dict(orientation="h", yanchor="bottom", y=1.01, x=0, font=dict(size=10)),
        updatemenus=[dict(buttons=buttons, direction="down", x=0, xanchor="left",
                          y=1.19, yanchor="top", showactive=True, active=1)],
        shapes=[
            dict(type="line", x0=-critical, x1=-critical, y0=0, y1=1, yref="paper",
                 line=dict(color="#E45756", width=2, dash="dash")),
            dict(type="line", x0=critical, x1=critical, y0=0, y1=1, yref="paper",
                 line=dict(color="#E45756", width=2, dash="dash")),
        ],
        annotations=[test_annotation(default)], font=dict(size=11),
    )
    pd.DataFrame(results).to_csv(DATA / "hypothesis_test_results.csv", index=False)
    write_figure(fig, "figure3_null_distribution.html")
    return pd.DataFrame(results)


def write_figure(fig, filename):
    fig.write_html(
        FIGURES / filename, include_plotlyjs=True, full_html=True,
        config={"displaylogo": False, "responsive": True, "scrollZoom": False},
    )


def main():
    rng = np.random.default_rng(SEED)
    sample_mean, low, high = make_bootstrap_figure(rng)
    coverage = make_coverage_figure(rng)
    tests = make_hypothesis_figure(rng)
    default_coverage = coverage.query("sample_size == 50 and confidence_level == 0.95").iloc[0]
    default_test = tests.query("observed_difference == 0.25").iloc[0]
    print(f"Sample mean: {sample_mean:.3f}; 95% percentile CI: [{low:.3f}, {high:.3f}]")
    print(f"Default empirical coverage: {default_coverage.empirical_coverage:.1%}")
    print(f"Default hypothesis-test p-value: {default_test.p_value:.4f}")


if __name__ == "__main__":
    main()
