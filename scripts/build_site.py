"""
Phase G - regenerate the data behind docs/QUESTIONS.html.

    docs/data/meta.js      projects, difficulty levels, skills, question text
    docs/data/schema.js    tables, columns, PK/FK - read straight from the databases
    docs/data/results.js   per query: the SQL text, a row preview, and a timing

The page itself is a ~2 KB shell; docs/assets/app.js renders everything from these
three files at runtime. Nothing is baked into the markup, so regenerating here is
enough to update the published site.

They are written as `window.__X__ = {...};` assignments loaded via <script src>
rather than JSON fetched at runtime. Script tags are exempt from the file://
restriction that blocks fetch(), so the page renders identically opened from a
folder and served over HTTP - that was a real bug, not a hypothetical one.

Usage:  python scripts/build_site.py [--project project_2_churn]
Requires db/*.db, so run scripts/build.py first.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sqlutil import (  # noqa: E402
    DB_DIR, DOCS_DIR, PROJECTS, QUERY_DIR, Q_HEADER, connect, split_sql,
)

from run import PREVIEW_ROWS, project_for  # noqa: E402

# A preview cell wider than this is elided. Result tables sit beside the SQL in a
# two-up layout, and one long CASE label would otherwise set the column width for
# the whole table.
CELL_CHARS = 40

REPO, BRANCH = "Prateeek73/SQL-Cheat-Sheet", "main"

# id, query file, full title, tab label, db stem, kaggle id, size caption
META = [
    (1, "01_ecommerce.sql", "E-Commerce Sales", "E-Commerce", "project_1_ecommerce",
     "thedevastator/unlock-profits-with-e-commerce-sales-data", "128,975 sale lines"),
    (2, "02_churn.sql", "Telecom Churn", "Churn", "project_2_churn",
     "blastchar/telco-customer-churn", "7,043 customers"),
    (3, "03_hr.sql", "HR Performance", "HR", "project_3_hr",
     "nadeemajeedch/employee-performance-and-salary-dataset", "1,000 employees"),
    (4, "04_food_delivery.sql", "Food Delivery Ops", "Food Delivery", "project_4_food",
     "varshinipallerla/food-delivery", "20,000 orders"),
    (5, "05_fraud.sql", "Credit Card Fraud", "Fraud", "project_5_fraud",
     "mlg-ulb/creditcardfraud", "284,807 transactions"),
]

# 3-5 per level, unique within a project - repeating "Joins" at every level says
# nothing about what the harder queries actually exercise.
SKILLS = {
    1: {"Beginner": ["Aggregation & GROUP BY", "Filtering & HAVING", "Table Joins"],
        "Intermediate": ["Window Functions", "Ranking", "Subqueries", "CTEs"],
        "Advanced": ["Cohort Analysis", "RFM Segmentation", "Market Basket Analysis",
                     "Statistical Analysis"],
        "Extended": ["Margin Analysis", "Data Reconciliation", "Confounding Detection"]},
    2: {"Beginner": ["Aggregation & GROUP BY", "Conditional Logic", "Table Joins"],
        "Intermediate": ["Window Functions", "Quantile Bucketing", "CTEs",
                         "Pivoting with UNION"],
        "Advanced": ["Cohort Analysis", "Risk Scoring", "Customer Segmentation",
                     "Financial Modelling"]},
    3: {"Beginner": ["Aggregation & GROUP BY", "Descriptive Statistics", "Date Functions"],
        "Intermediate": ["Window Functions", "Ranking & Percentiles", "Outlier Detection",
                         "NULL Handling"],
        "Advanced": ["Pay Equity Analysis", "Data Quality Auditing", "Composite Scoring",
                     "Forecasting"],
        "Extended": ["Dimension Modelling"]},
    4: {"Beginner": ["Aggregation & GROUP BY", "Table Joins", "Conditional Logic"],
        "Intermediate": ["Window Functions", "Time Series Analysis", "Quantile Bucketing",
                         "CTEs"],
        "Advanced": ["Hypothesis Testing", "Effect Size Measurement", "Composite Scoring",
                     "Market Share Analysis"],
        "Extended": ["Segmentation Analysis"]},
    5: {"Beginner": ["Aggregation & GROUP BY", "Class Imbalance", "Filtering"],
        "Intermediate": ["Window Functions", "Anomaly Detection", "Percentile Analysis",
                         "Threshold Tuning"],
        "Advanced": ["Model Evaluation", "Confusion Matrix", "Cost-Benefit Analysis",
                     "Feature Engineering"],
        "Extended": ["Feature Selection", "Distribution Analysis"]},
}

# name, first Q, last Q, grid columns. The column count falls as the word budget
# rises: Beginner questions are 8-15 words, Extended up to 60.
LEVELS = [("Beginner", 1, 6, 6), ("Intermediate", 7, 14, 4),
          ("Advanced", 15, 20, 3), ("Extended", 21, 99, 3)]

# Question text. Word bands: Beginner 8-15, Intermediate 25-30, Advanced 40-45,
# Extended <=60. Caveat prose lives in docs/DATA_NOTES.md, not on the page.
Q: dict[str, dict[int, str]] = {
"01_ecommerce.sql": {
1: "What did the business sell in total — revenue, orders and units?",
2: "Which product categories earn most, and what share of revenue is each?",
3: "Which ten SKUs earn the most revenue, and what stock remains?",
4: "Which states generate the most revenue, and how does order value differ?",
5: "How does revenue move day by day across the whole period?",
6: "How do orders end up — fulfilled, cancelled, returned or in flight?",
7: "Is revenue growing month over month? Use LAG to compare each month against the one before it, then express the difference as a percentage growth rate.",
8: "Within each catalogue category, how do individual products rank by revenue? The ranking must partition by category rather than run across the whole table as one list.",
9: "What does cumulative revenue look like as a running total? Build it with a windowed SUM ordered by date, which is far cheaper than the self-join people reach for.",
10: "Which cities beat the site-wide average order value? Compare each city average against a scalar subquery, keeping only those with enough orders for the comparison to mean anything.",
11: "What are the three best-selling SKUs in every category? Rank inside a CTE first and filter one level up, because a window function cannot be evaluated in HAVING.",
12: "How are order values distributed? Assign each order a percentile and a quartile with window functions, so the value tiers come from the data rather than hardcoded thresholds.",
13: "Which products are low on stock relative to how fast they sell? Keep products that never sold — an inner join would hide exactly the ones you need to see.",
14: "Which international customers are worth the most, by lifetime value and product variety? This file is the only source in the whole dataset that carries named customers.",
15: "Do international customers acquired in a given month keep buying later? Group each customer by their first purchase month, then track how many remain active in every following month, which builds the retention matrix showing whether acquisition quality is improving.",
16: "How do customers segment by recency, frequency and spend? Score each dimension into quartiles with NTILE, combine them into an RFM cell, then label the result — champion, loyal, at risk or lapsed — so marketing can act on it straight away.",
17: "Which product categories get bought together in the same order? Self-join the order lines on order_id using a less-than comparison, so each pair is counted once and no category ever pairs with itself — the two mistakes that quietly wreck this analysis.",
18: "Which order lines are statistical outliers within their own category? Compute each category mean and standard deviation, then flag lines more than three deviations out. SQLite has no STDDEV, so it is derived from sums — pure SQL that runs in any client.",
19: "For every category pair, what are support, confidence and lift? Lift above one means the pair sells together more often than independence would predict, which is the metric that separates a genuine association from two items that are simply both popular.",
20: "Which segments suffer the worst cancellations and returns? Score every category, fulfilment and channel combination, weighting returns double because they cost more to process, then attach a recommended action to each risk tier so the output is something an operations team can use.",
21: "Do promotions cut cancellations? Promoted lines cancel 0.37% against 36.7% — a hundredfold gap that looks like a major finding. It is not. Break it out by status and the mechanism appears: promotion_ids is written at fulfilment, so cancelled orders never receive one. The arrow points backwards.",
22: "The same SKU is listed across up to nine marketplaces. How far apart do those prices drift? Compare the cheapest and dearest listing per SKU and flag anything varying by more than twenty percent — usually a margin leak or a stale listing rather than deliberate pricing.",
23: "Which marketplace earns the best gross margin on identical goods? Compare cost against list price for each channel, and count any SKU priced below cost. Note this is margin against list price only: the price list shares no key with the sales data.",
24: "How do cost, list price and margin compare across categories? The source carries two cost bases from different years, so both appear. Watch the dirty values — tp holds #VALUE! and the MRP columns hold Nill, both mapped to NULL rather than silently cast to zero.",
25: "What does every recorded field on a sale line look like? Twenty-five columns joined to the product catalogue and filtered to promoted, fulfilled lines — the wide detail extract you get asked for whenever somebody wants to check the underlying records themselves.",
26: "What do the remaining three tables hold? The geography dimension joins the sales data, but the warehouse rate card and the expense ledger carry no key to anything else, so they are reported alongside rather than joined — the honest treatment of orphan reference data.",
},
"02_churn.sql": {
1: "What share of customers churned, and how many stayed?",
2: "Which contract type loses customers fastest, and by how much?",
3: "How long do churned customers stay compared with those who remain?",
4: "Does internet service relate to churn, and what do those customers pay?",
5: "Which payment method carries the highest churn rate?",
6: "How does churn vary across tenure buckets, from new to long-standing?",
7: "How does churn differ across signup cohorts? The cohort month is back-calculated from tenure, since this dataset records no actual signup or churn date at all.",
8: "What share of customers survive to each tenure month? A reverse running total turns this single snapshot into an approximate survival curve, the closest this data allows.",
9: "Which demographic cell carries the highest risk? Group senior status, partner and dependents together, then rank the result — any single attribute on its own hides the interaction.",
10: "Is churn actually driven by price? Split customers into monthly-charge quartiles with NTILE, so the thresholds come from the real distribution rather than a number someone guessed.",
11: "Do customers who bundle more add-on services churn less? Count each customer active services, then compare churn across bundle sizes to test cross-sell as a retention lever.",
12: "How does churn climb as risk signals accumulate? Add one point per warning sign, then check the actual churn rate at each score — an explainable model before weights.",
13: "Which single add-on service is associated with the lowest churn? UNION ALL pivots six service columns into six comparable rows, the readable way to do this without UNPIVOT.",
14: "How do the three contract types compare on churn, tenure, billing and paperless adoption at once? A scorecard reads better than four separate single-metric queries run apart.",
15: "What is churn worth in money? Revenue booked, revenue projected twelve months forward, and revenue lost. Note the COALESCE: eleven customers have a NULL total_charges, and without it those rows vanish from the sum and quietly understate the total loss.",
16: "Which active customers should retention call first? Score six weighted signals into a 0-100 value, clamp it, then rank by annual revenue at risk. The p75 charge threshold comes from row position, since SQLite offers no PERCENTILE_CONT function at all.",
17: "How does each cohort thin out over time? Pivot the table so every row is a signup month and every column a horizon — six, twelve, twenty-four and forty-eight months — producing the classic retention waterfall that shows exactly where customers drop away.",
18: "How do charge distributions differ between churned and retained customers? Compare full percentile spreads rather than averages, because a mean hides a bimodal distribution where two genuinely distinct groups of customers sit either side of it, cancelling each other out.",
19: "Does a retention programme pay for itself? Model offer cost against recovered revenue and return the ROI multiple. Both assumptions live in their own CTE so a reviewer can challenge them directly, instead of hunting for magic numbers buried inside the arithmetic.",
20: "Which segments should retention target first? Cross lifecycle stage, value tier and contract type, rank by annual revenue lost, then attach a specific action to each — onboarding, a term-contract offer, or an account manager — so the analysis ends in a decision.",
},
"03_hr.sql": {
1: "What does pay look like per department — average, range and spread?",
2: "How many employees have a performance score, and how many are missing one?",
3: "Who joined most recently, measured against the latest hire date?",
4: "Does pay differ by office location or by shift session?",
5: "What share of each department has left, and did they earn less?",
6: "How is the workforce spread across age bands, and how does pay track?",
7: "Where does each employee rank on salary within their own department, and how far from that department average do they sit? One window query gives both.",
8: "Who are the three highest-rated performers per department? An inner join is correct here, since an employee with no score cannot be ranked — but make that choice deliberately.",
9: "Which salary percentile and quartile does each employee occupy? PERCENT_RANK and NTILE let pay bands come from the real distribution rather than from cutoffs someone simply picked.",
10: "How long has each employee been with the company? SQLite has no DATEDIFF, so days come from julianday and whole months from year and month arithmetic on strftime.",
11: "Does more experience actually translate into higher pay? Compare average salary across experience bands and measure the step up between each one, plus the gap against entry.",
12: "Which employees are paid unusually high or low against departmental peers? Flag anyone beyond one and a half standard deviations, derived from sums since SQLite lacks STDDEV.",
13: "At what tenure do people leave, and does that differ by department? Cross tenure band with department to locate the retention window actually worth investing in.",
14: "Do higher scores come with higher pay? Employees without a score are kept as their own row, so the missing half stays visible rather than silently disappearing.",
15: "Is there a pay gap by gender within each department? Compare every cell against its departmental baseline, reporting the gap in currency and percent. Cells under twenty people are excluded, because a gap computed on a handful of employees is noise rather than evidence.",
16: "What are the real salary bands per department? Build them from the actual distribution — minimum, quartiles, median, p90 and the interquartile range — using row position, since SQLite offers no PERCENTILE_CONT, and the approach ports to any database you might meet.",
17: "Is the missing half of the performance data missing at random? Compare the scored and unscored populations on salary, age, experience, attrition and department. If they differ systematically, then every conclusion drawn from that column is quietly biased from the start.",
18: "Which active employees are most likely to leave? Combine tenure, pay against the departmental average, performance and age into a weighted score, then attach a concrete action — a salary review, a development conversation, or simply booking the appraisal that was never done.",
19: "How do departments compare overall? Normalise performance, retention and review coverage onto a common 0-100 scale, so that salary measured in thousands and a score out of five can be blended into one index without either quietly dominating the result.",
20: "What will payroll cost in five years? Apply compound growth by performance band, with an explicit default rate for the half of the workforce carrying no score, then total the incremental cost per department so finance can budget for it properly.",
21: "Does the cached department dimension still agree with the live employee table? Joining a pre-aggregated dimension rather than recomputing the average is the pattern you meet in real warehouses, where that aggregate is a maintained table. The final column measures drift between cache and source, and should read zero.",
},
"04_food_delivery.sql": {
1: "What is the platform shape — orders, revenue, distance and delay?",
2: "Which restaurants generate the most revenue, and how fast are they?",
3: "Which menu items sell most often, and what revenue do they bring?",
4: "Which cities order most, and how far do those deliveries travel?",
5: "How many deliveries arrive early, on time or late? Negative means early.",
6: "Who are the customers — age, loyalty membership and ordering frequency?",
7: "Which days of the week are busiest? SQLite has no DAYOFWEEK, so strftime returns a weekday number that must be cast and mapped to a name, Sunday being zero.",
8: "How do orders and revenue trend month by month across the year, and what is the growth rate against the preceding month? LAG over an aggregate gives both.",
9: "How do restaurants rank on revenue, speed and satisfaction? Three separate rankings side by side, because they rarely agree — and the disagreement is the interesting part.",
10: "Does longer distance mean longer delay? Test the hypothesis rather than assume it — the answer here is not the one you expect, and saying so plainly is the skill.",
11: "How do weather and traffic combine to affect delivery? Build the full three-by-three conditions matrix and compare the average delay and late rate in every cell.",
12: "Do customers actually order the cuisine they claim to prefer? A stated-versus-revealed preference check, which is a genuinely useful pattern in any behavioural dataset you meet.",
13: "Do more efficient routes actually deliver faster? Bucket route efficiency into quartiles with NTILE, then compare the average delay within each delivery method, taken separately.",
14: "Does fresher food produce higher satisfaction? Compare average satisfaction at every freshness level and look for a monotonic climb across them — a flat line means nothing.",
15: "How do restaurants score overall? Blend punctuality, satisfaction and order value into one weighted index using percentile ranks, so measures on completely different scales can be combined without any single one dominating, then sort every restaurant into clear performance tiers.",
16: "Does any recorded factor explain delivery delay? Measure how far each factor group means actually move, divided by the overall spread. A real driver shifts the mean by minutes; everything here shifts it by a fraction of one, which is the signature of random data.",
17: "Which quality dimension drives satisfaction? Compare satisfaction at the worst and best level of each measure. A genuine driver climbs steadily across the levels; a flat line means those columns were generated independently, and no dashboard built on them would mean anything.",
18: "Is the loyalty programme worth anything? Compare members against non-members on order value, satisfaction and delay. A near-exact fifty-fifty split in membership is itself a clue about how this data was produced, and the gaps that follow confirm it plainly.",
19: "Which restaurants dominate each city? Compute market share against the city total with a window function, then rank within each city. This is a structural question that holds regardless of whether the underlying data contains any real correlations at all.",
20: "What does the weekly operations summary look like? Break every city down by weekday, then append a rollup row per city using UNION ALL, since SQLite offers no GROUPING SETS or ROLLUP syntax — the report an operations team reads each Monday.",
21: "Do short routes or bike-friendly routes deliver any faster? These two flags are the last unused columns in the dataset, and both split almost exactly fifty-fifty — already a hint they were assigned at random. This checks them the same way every other factor here is checked: by measuring the spread across groups rather than assuming an effect exists.",
},
"05_fraud.sql": {
1: "How rare is fraud here, and how much money does it move?",
2: "Which hours carry the highest fraud rate against the overall baseline?",
3: "Are the largest transactions actually the fraudulent ones?",
4: "How do fraudulent and legitimate transaction amounts compare overall?",
5: "Zero-value authorisations test a stolen card. How risky are they here?",
6: "Do the two days behave alike, before you pool them together?",
7: "Which amounts are extreme statistical outliers? Compute the mean and standard deviation once in a CTE, then cross join it against every transaction rather than recomputing per row.",
8: "Which amount bands carry the highest fraud rate, and what share of all fraud sits inside each one? The lift column compares each band against the overall base rate.",
9: "How far apart are the fraud and legitimate means for the best-known components? A first look at which features might carry real signal, before ranking all twenty-eight.",
10: "Which moments show bursts of transaction activity? A RANGE window frame counts everything inside a rolling sixty-second interval, the cloning signature without a card identifier.",
11: "How do amount distributions differ between the two classes? Percentiles survive skew where averages mislead, and fraud amounts turn out far more skewed than legitimate ones.",
12: "Which combinations of time block and amount band concentrate fraud? Two-dimensional grouping finds cells worth alerting on, rather than one blunt rule applied across the whole book.",
13: "Where should a V14 cut-off sit? Bucket the strongest feature and track how much of all fraud each band would capture, turning it into a candidate business rule.",
14: "If you reviewed only the riskiest one percent, how much fraud would you catch? The gains curve that fraud teams actually ask for when sizing a review queue.",
15: "How do candidate rules compare? Build a confusion matrix per rule and report precision, recall and F1. Accuracy is included deliberately so you can see why it is useless here: predicting never-fraud scores 99.83% and catches absolutely nothing at all.",
16: "How does a weighted score spread transactions across action tiers? Combine several signals, clamp the total to a hundred, then validate the resulting tiers against the known labels — which is the only honest way to tell whether the chosen weights are sane.",
17: "How does the precision-recall trade-off move across the threshold range? Cross join a list of candidate cut-offs against every transaction, so the whole curve comes from a single query and the operating point gets chosen deliberately rather than guessed at.",
18: "At the chosen operating point, what does the full confusion matrix look like? Counts and money side by side, including the false positive rate and the share of fraud value actually prevented — the single table a risk committee will sign off on.",
19: "Does running the rule pay for itself? Weigh recovered fraud against analyst review time and the cost of wrongly challenging good customers. All three assumptions sit in their own CTE so they can be argued with directly rather than quietly assumed.",
20: "What does a model-ready feature table look like? Standardised amounts, engineered time flags and the four best-known components, with every column derived only from information that would genuinely be available at scoring time rather than discovered only after the event has already happened.",
21: "Which of all twenty-eight components actually separate the classes? Rank every one by effect size — the gap between class means divided by the feature own spread. This is the query that should have chosen the features for the earlier rules rather than folklore, and it surfaces two strong components those rules missed entirely.",
22: "Which components separate cleanly, and which merely look different? A large gap between means flatters a feature whose distributions still overlap heavily. Comparing the fraud median against the legitimate first-to-ninety-ninth percentile band settles it: if that median falls inside the range, the feature cannot discriminate alone however impressive the averages appear.",
23: "Do rules built from the features the data chose beat the famous pair? The earlier rules used V14 and V17 because those are the well-known components. Testing combinations drawn from the full ranking shows a six-feature rule reaching a materially better F1 than the two-feature version everyone reaches for first.",
24: "What does every recorded value look like for all four hundred and ninety-two confirmed frauds? The complete wide extract — time, amount and all twenty-eight components — for the entire positive class, small enough to inspect by hand and worth reading once before trusting any model built on it.",
25: "What does the complete feature matrix look like using every component? All twenty-eight, plus standardised amount, engineered time flags and a count of how many strong features fire together. Contrast it with the earlier export, which carried only four components and would silently cap any model ceiling.",
},
}


def write_global(name: str, obj: object) -> Path:
    """Write docs/data/<name>.js as a `window.__NAME__ = {...};` assignment.

    Deliberately json.dumps defaults and no trailing newline: app.js does not care,
    but keeping the bytes stable means `git diff docs/data/` after a regeneration
    shows only what genuinely changed.
    """
    out = DOCS_DIR / "data" / f"{name}.js"
    out.write_text(f"window.__{name.upper()}__=" + json.dumps(obj) + ";", encoding="utf-8")
    return out


def build_schema(projects: list[tuple]) -> dict[int, dict]:
    """Read tables, columns and key roles straight out of each database.

    Reading PRAGMA rather than re-declaring the schema here means the page can
    never drift from what build.py actually created.
    """
    schema: dict[int, dict] = {}
    for pid, _f, _t, _s, dbstem, _k, _sz in projects:
        conn = connect(DB_DIR / f"{dbstem}.db")
        try:
            tabs: dict[str, dict] = {}
            names = [r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
            for t in names:
                if t.startswith("sqlite_"):
                    continue
                info = list(conn.execute(f'PRAGMA table_info("{t}")'))
                # column name -> [parent table, parent column]
                fks = {r[3]: [r[2], r[4]] for r in conn.execute(f'PRAGMA foreign_key_list("{t}")')}
                uq: list[str] = []
                for idx in conn.execute(f'PRAGMA index_list("{t}")'):
                    if idx[2]:  # unique
                        uq += [r[2] for r in conn.execute(f'PRAGMA index_info("{idx[1]}")')]
                tabs[t] = {
                    "rows": conn.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0],
                    "raw": t.startswith("raw_"),
                    # a column can be both PK and FK; app.js shows both badges
                    "cols": [{"name": r[1], "type": (r[2] or "").upper(),
                              "pk": bool(r[5]), "uq": r[1] in uq,
                              "fk": fks.get(r[1])} for r in info],
                }
            schema[pid] = tabs
        finally:
            conn.close()
    return schema


def discover(projects: list[tuple]) -> list[tuple[Path, tuple]]:
    """Pair each .sql file on disk with its META row, by glob - never by filename.

    Building a path from a project key is the defect that silently skipped two
    whole projects in the orchestrator this replaced, so files are always found by
    globbing and mapped through the leading ordinal (run.py's project_for).
    A META row with no file on disk is an error, not a silent omission.
    """
    keys = list(PROJECTS)
    by_pid = {m[0]: m for m in projects}
    found: list[tuple[Path, tuple]] = []
    for f in sorted(QUERY_DIR.glob("*.sql")):
        project = project_for(f)
        if project is None:
            print(f"    [skip] {f.name}: cannot map to a project")
            continue
        pid = keys.index(project) + 1
        if pid in by_pid:
            found.append((f, by_pid.pop(pid)))
    if by_pid:
        raise FileNotFoundError(
            "no .sql file found for: " + ", ".join(m[1] for m in by_pid.values()))
    return found


def cell(v: object) -> str:
    """Render one result value for the preview table.

    NULL is spelled the SQL way, not Python's None - the page is showing the
    output of a query, and `None` in a result cell reads as a rendering bug.
    """
    s = "NULL" if v is None else str(v)
    return s if len(s) <= CELL_CHARS else s[:CELL_CHARS - 1] + "..."


def header_lines(text: str) -> dict[int, int]:
    """Map each query number to the line its `-- Qn:` header sits on.

    Statement.line points at the start of the statement's span, which is just
    after the previous semicolon and therefore lands on the blank line above the
    header. The deep link in app.js is `<file>#L<line>`, and it should open on the
    comment that names the question, so the header position is what we want.
    Q_HEADER's leading \\s* can begin the match on an earlier blank line, so the
    offset is taken from the literal `--` rather than from the match start.
    """
    out: dict[int, int] = {}
    for m in Q_HEADER.finditer(text):
        pos = m.start() + m.group(0).index("--")
        out[int(m.group(1))] = text.count("\n", 0, pos) + 1
    return out


def build_results(projects: list[tuple]) -> tuple[dict[str, dict], dict[str, dict[int, int]]]:
    """Run every query and capture its SQL, a row preview and a timing.

    Also returns each query's `-- Qn:` header line, read from the same text that
    was split and executed, so the deep link cannot drift from the query it names.
    """
    results: dict[str, dict] = {}
    lines: dict[str, dict[int, int]] = {}
    for sql_file, (_pid, fname, _t, _s, dbstem, _k, _sz) in discover(projects):
        db_path = DB_DIR / f"{dbstem}.db"
        per: dict[int, dict] = {}
        text = sql_file.read_text(encoding="utf-8", errors="replace")
        per_line = header_lines(text)
        conn = connect(db_path)
        try:
            for st in split_sql(text):
                if st.number is None:
                    # an unlabelled statement cannot be addressed by a card
                    print(f"    [warn] {fname}: statement at line {st.line} has no -- Qn: header")
                    continue
                t0 = time.perf_counter()
                cur = conn.execute(st.sql)
                rows = cur.fetchall()
                ms = (time.perf_counter() - t0) * 1000
                per[st.number] = {
                    "n": len(rows),
                    "ms": round(ms, 1),
                    "cols": [d[0] for d in cur.description],
                    # stringified here rather than in app.js, so the page never has
                    # to decide how to render a float or a NULL
                    "rows": [[cell(v) for v in r] for r in rows[:PREVIEW_ROWS]],
                    "sql": st.sql,
                }
        finally:
            conn.close()
        results[fname] = per
        lines[fname] = per_line
        print(f"    {fname:22s} {len(per):3d} queries")
    return results, lines


def build_meta(projects: list[tuple], lines: dict[str, dict[int, int]]) -> dict:
    out, total = [], 0
    for pid, fname, title, short, dbstem, kaggle, size in projects:
        qs = Q[fname]
        levels = []
        for lname, lo, hi, cols in LEVELS:
            nums = sorted(n for n in qs if lo <= n <= hi)
            if not nums:
                continue
            total += len(nums)
            levels.append({
                "name": lname, "cols": cols, "skills": SKILLS[pid].get(lname, []),
                "queries": [{"n": n, "q": qs[n], "line": lines[fname].get(n, 1)} for n in nums],
            })
        out.append({"id": pid, "file": fname, "db": f"{dbstem}.db", "title": title,
                    "short": short, "kaggle": kaggle, "size": size,
                    "count": len(qs), "levels": levels})
    return {"repo": REPO, "branch": BRANCH, "generated": True,
            "totals": {"questions": total, "projects": len(projects), "levels": len(LEVELS),
                       "rows": "442k"},
            "projects": out}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="rebuild using only this project key")
    args = ap.parse_args()

    projects = META
    if args.project:
        keys = list(PROJECTS)
        if args.project not in keys:
            print(f"Unknown project '{args.project}'. Known: {', '.join(keys)}")
            return 1
        wanted = keys.index(args.project) + 1
        projects = [m for m in META if m[0] == wanted]

    missing = [f"{m[4]}.db" for m in projects if not (DB_DIR / f"{m[4]}.db").exists()]
    if missing:
        print(f"Missing {len(missing)} database(s) in {DB_DIR}: {', '.join(missing)}")
        print("Build them first:  python scripts/fetch.py && python scripts/build.py")
        return 1

    (DOCS_DIR / "data").mkdir(parents=True, exist_ok=True)

    print("=" * 78)
    print("PHASE G: SITE DATA")
    print("=" * 78)

    print("\n[schema]")
    schema = build_schema(projects)
    write_global("schema", schema)

    print("\n[results]")
    try:
        results, lines = build_results(projects)
    except sqlite3.Error as exc:
        print(f"\nA query failed: {type(exc).__name__}: {exc}")
        print("Run  python scripts/run.py  to see which one.")
        return 1
    write_global("results", results)

    print("\n[meta]")
    meta = build_meta(projects, lines)
    write_global("meta", meta)

    print()
    for name, extra in (("meta", f"{meta['totals']['questions']} questions"),
                        ("schema", f"{sum(len(t) for t in schema.values())} tables"),
                        ("results", f"{sum(len(v) for v in results.values())} queries")):
        kb = (DOCS_DIR / "data" / f"{name}.js").stat().st_size / 1024
        print(f"  data/{name}.js{'':<{10 - len(name)}} {kb:>7.0f} KB  {extra}")

    if args.project:
        print("\nNote: --project rewrote all three files with ONE project. "
              "Re-run without it before committing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
