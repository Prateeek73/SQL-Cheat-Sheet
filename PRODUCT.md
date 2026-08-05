# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Primary:** self-directed learners and the wider SQL community preparing for
data/analytics interviews. They arrive at the published Questions Index to study
real queries written against real data — picking a business question, reading the
SQL, and seeing the actual rows it returns.

**Secondary (maintainer):** the author, who uses the same environment locally to
build the databases and drill the 113 queries.

## Product Purpose

A public, interview-prep SQL learning resource. Five real Kaggle datasets are
loaded into five SQLite databases, with 113 progressively harder queries that
actually execute and return real results. Success = a learner can pick a business
question, see the SQL and the real rows behind it, understand the skill each
difficulty level teaches, and trust every result because it is verified and its
caveats are documented.

## Positioning

The meaningfully different mechanism is **radical data honesty**. Queries are
written against what the datasets actually contain, not what tutorials claim:

- 113/113 queries verified to execute with **zero errors and zero empty results**;
  every row and column of all 11 source CSVs is loaded — nothing sampled or dropped.
- Every measured caveat is documented rather than hidden — e.g. the fraud set has
  only PCA components (no merchants or customers), the churn set has no
  `churn_date`, and the food-delivery set is essentially randomly generated.
- **Null-result detection** is treated as a taught skill, not a bug.

A neighboring "SQL practice" site could copy the question list, but not the
verified-against-real-data rigor and the documented caveats that back every answer.

## Operating Context

- **Learning surface:** the published **Questions Index** (`docs/QUESTIONS.html`)
  on GitHub Pages — tabbed by the five projects, with per-level skills, a full
  schema map, and result previews; each card links into its SQL.
- **Local pipeline:** `fetch.py` (download 5 Kaggle datasets → `data/raw/`) →
  `build.py` (CSVs → 5 SQLite DBs → `db/`) → `run.py` (execute all 113 queries →
  `docs/RESULTS.md`). Queries live in `queries/*.sql`, one file per project, mapped
  to a database by its leading number (`01_ecommerce.sql` → `project_1_ecommerce.db`).
- **Difficulty tiers:** Beginner (1–6) → Intermediate (7–14) → Advanced (15–20)
  → Extended (21+).
- Datasets (~1.1 GB) and databases are gitignored and regenerable — not in the repo.
- **Known gotcha:** some queries use `sqrt()`/`power()`/`log()`, which SQLite ships
  only when compiled with `SQLITE_ENABLE_MATH_FUNCTIONS` (the `sqlPract` conda env
  has them).

## Capabilities and Constraints

**Binding constraints (user-confirmed):**

- **Pure static, no build step.** The site must keep working as plain files served
  by GitHub Pages — no bundler, no server-side rendering.
- **Vanilla only.** Hand-written HTML/CSS/JS — no React/Vue or other frameworks.

**Current implementation (not marked binding — may change):**

- Content is data-driven: the HTML shell holds no content and loads
  `docs/data/*.js` as `<script>` tags (not `fetch()`), so the page also opens
  straight from the folder over `file://`. Regenerating the data updates the site
  with no markup change.

**Content & data facts:**

- Five projects: ecommerce (128,975 sale lines, 26 Qs), churn (7,043 customers,
  20 Qs), HR (1,000 employees, 21 Qs), food delivery (20,000 orders, 21 Qs),
  fraud (284,807 transactions, 25 Qs).
- Python pipeline uses pandas + `sqlite3`; conda env `sqlPract`; Kaggle client 2.x
  auth (`kaggle auth login`, not `kaggle.json`).
- Each database keeps the untouched source as `raw_*` tables beside derived ones;
  derived tables are built only from columns that genuinely exist.

## Brand Commitments

- **Canonical product name: SQL Cheat Sheet.** The repo slug (`SQL-Cheat-Sheet`)
  and the live GitHub Pages URL already use it. Open item: the page `<title>` and
  README currently read "SQL Practice" — to be aligned to the canonical name in
  future work.
- **Voice (evident from existing copy; confirm before extending):** plain,
  exacting, anti-hype. Leads with measured truth and names its caveats
  ("The data is not what tutorials claim"). Never states a fabricated number.

## Evidence on Hand

- 113 verified queries (`queries/*.sql`) with real result previews
  (`docs/data/results.js`, `docs/RESULTS.md` — per-query pass/fail, row counts,
  timings).
- `docs/DATA_PROFILE.md` — per-CSV columns, types, null rates, cardinality.
- `docs/DATA_NOTES.md` — every measured caveat; the source of the honesty claims.
- Live: <https://prateeek73.github.io/SQL-Cheat-Sheet/docs/QUESTIONS.html>
- **Absence to preserve:** the source CSVs and built databases are not in the repo
  (gitignored, regenerable). Future work must not assume they are present or
  fabricate data values.

## Product Principles

1. **Truth over convention** — write and document against what the data actually
   contains, never what tutorials claim.
2. **Everything runs** — a query that doesn't execute and return real rows isn't
   shipped (113/113, 0 errors, 0 empty results).
3. **Caveats are first-class** — a documented null or artifact result is a teaching
   feature, not a failure to hide.
4. **Data-driven surface** — content lives in data, not markup; the page stays a
   thin, regenerable shell.
5. **Lightweight and portable** — pure static, vanilla, no build step; it must just
   open and work.

## Accessibility & Inclusion

No formal standard was mandated. As a public learning resource the page should stay
broadly readable: it already declares `color-scheme: light dark`, and future work
should keep it keyboard-navigable with legible contrast in both schemes.
