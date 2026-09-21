# Personal website and blog — Haozhuo

Source repository for my Quarto website and blog, published at
<https://haozhuo22.github.io/myweb/>.

Begin with Blog Post 2, each blog post is submitted together with this repository,
which contains the Quarto source, the code, and the data snapshot needed to
reproduce the analysis.

## Repository layout

```
.
├── _quarto.yml                  # site configuration (output-dir: docs)
├── index.qmd                    # home page
├── about.qmd, bio.qmd, resume.qmd
├── styles.css, images/
├── blog/
│   ├── index.qmd                # blog listing page (listing: contents: posts)
│   └── posts/
│       ├── post1/               # Blog Post 1 — Simpson's paradox
│       │   ├── index.qmd        # source + executable R code
│       │   └── figure1.png
│       └── post2/               # Blog Post 2 — national parks space per visitor
│           ├── index.qmd        # source + executable R code
│           └── data/
│               └── parks_clean.csv   # archived data snapshot
├── docs/                        # rendered site (GitHub Pages serves this folder)
└── README.md
```

Each post lives in its own folder and is named `index.qmd`; the blog listing page
collects every folder under `blog/posts/` automatically.

## Requirements

- R (developed and tested with R 4.x)
- [Quarto](https://quarto.org/) CLI — the version bundled with RStudio also works
- R packages:

  ```r
  install.packages(c("rvest", "dplyr", "stringr", "readr",
                     "ggplot2", "scales", "knitr"))
  ```

## Reproducing Blog Post 2

The post *"Finding Room to Roam: Which National Parks Offer More Space per
Visitor?"* is fully reproducible from `blog/posts/post2/index.qmd`.

**Option A — render the post (recommended).** From the repository root:

```bash
quarto render blog/posts/post2/index.qmd
```

This executes every R chunk in order and writes the HTML output next to the
source. Quarto sets the working directory to the document's folder, so the
scrape chunk writes its data snapshot to `blog/posts/post2/data/parks_clean.csv`.

**Option B — render the whole site** (same thing, plus all other pages):

```bash
quarto render
```

The rendered site is written to `docs/`.

### What the code does

1. `scrape-and-clean` — sends **one** HTTP request to the
   [Wikipedia list of U.S. national parks](https://en.wikipedia.org/wiki/List_of_national_parks_of_the_United_States),
   extracts the first `table.wikitable` with `rvest::html_table()`, locates the
   area and visitation columns by name prefix (so footnote markers do not break
   it), parses the numbers, and computes annual visits per 1,000 acres. It calls
   `stopifnot()` on the parsed data so the analysis fails loudly instead of
   silently producing wrong results, then archives the snapshot with
   `write_csv()`.
2. `shortlist` — filters to contiguous-U.S. parks with at least 500,000 annual
   visits and keeps the eight with the lowest visitor pressure.
3. `fig-space` — scatterplot of park area against 2025 visitation on log axes,
   with the shortlisted parks labelled.

### Data

| File | Description |
| --- | --- |
| `blog/posts/post2/data/parks_clean.csv` | Snapshot of the analysis dataset as used on 2026-09-20: 63 parks with `park`, `location`, `area_acres` (2023), `visits_2025`, and the derived `visits_per_1000_acres`. |

The chunk writes this file on every run. Reporting the results against the
archived copy is what keeps the numbers in the post stable, because Wikipedia
can be edited after publication. Figures referenced in the post (Death Valley
1,320,134; Everglades 778,198; Big Bend 568,104 visits) match the snapshot and
the official [NPS visitation statistics](https://irma.nps.gov/Stats/).

**Source and license.** The park table is taken from Wikipedia, available under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); the post links
and attributes the source rather than reproducing its prose or images. The
scrape sends one ordinary request, accesses no login or restricted page, and
does not crawl individual park pages.

## Deployment

The site is published with GitHub Pages from the `docs/` folder of `main`.

```bash
quarto render                              # renders blog and site into docs/
git add -A
git commit -m "post update"
git push origin main                       # GitHub Pages rebuilds automatically
```

## Notes

- `.gitignore` excludes `.Rproj.user`, `.Rhistory`, `.RData`, `.Ruserdata` and
  the `.quarto/` cache.
- Binary assets kept in the repository (`figure1.png`) are the original images
  used by Blog Post 1.
