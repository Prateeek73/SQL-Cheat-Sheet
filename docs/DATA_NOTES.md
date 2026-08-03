# Data Notes

Measured caveats for all five datasets. Every figure here was computed from the
downloaded CSVs, not taken from the dataset description.

Read the section for a project before quoting any result from it. None of these
facts is recoverable from the SQL alone, which is why they live here rather than
in the query files.

---

## Global — SQLite math functions

Several queries use `sqrt()`, and a few use `power()` / `log()`. SQLite has
shipped these since 3.35 **but only in builds compiled with
`SQLITE_ENABLE_MATH_FUNCTIONS`**. Test your client:

```sql
SELECT sqrt(4);      -- 2.0 if supported, else "no such function"
```

Measured on this machine: the `sqlPract` conda env (3.53.4) **has** them;
Anaconda's bundled `sqlite3.exe` (3.51.0) does **not**. It is a compile flag, not
a version — the lower version number is the one that works.

Affected: P1 Q18, P3 Q1/Q12/Q20, P4 Q10, P5 Q7/Q20/Q21. All percentile logic is
pure SQL and portable anywhere.

Queries anchor date filters to the **latest date in the data**, never
`CURRENT_DATE` — these are historical datasets, so "last 12 months" against
today's clock returns nothing.

### SQLite translations used throughout

The original queries were written in a mix of PostgreSQL, MySQL and SQL Server
dialects. These are the substitutions applied:

| Other dialects | Here |
|---|---|
| `STDDEV(x)` | `sqrt((sum(x*x) - sum(x)*sum(x)/count(*)) / (count(*)-1))` |
| `DATEDIFF(day,a,b)` | `julianday(b) - julianday(a)` |
| `YEAR(x)` / `HOUR(x)` | `strftime('%Y',x)` / `strftime('%H',x)` |
| `DAYOFWEEK(d)` | `strftime('%w',d)` (0 = Sunday) |
| `DATE_TRUNC('month',d)` | `date(d,'start of month')` |
| `CURRENT_DATE - INTERVAL '30 days'` | `date('now','-30 days')` |
| `PERCENTILE_CONT(p) WITHIN GROUP` | `ROW_NUMBER()` + `COUNT() OVER ()` by position |
| `QUALIFY` | rank in a CTE, filter in the next |

Two constructs in the original set were invalid in **every** SQL dialect and were
genuine bugs, not dialect issues: an aggregate in a `WHERE` clause, and a window
function in `HAVING`. Both are fixed, each with a comment at the query explaining
the correct pattern.

---

## P1 — E-commerce

- **Date coverage is 2022-03-31 to 2022-06-29** (~3 months). Month-over-month
  works; year-over-year is impossible.
- **`amount` is NULL on 7,795 of 128,975 lines (6%)**, overwhelmingly cancelled
  orders. Revenue queries must exclude them or `SUM` silently under-reports.
- **18,332 lines (14%) are cancelled.** "Revenue" everywhere excludes them.
- 6,846 orders have more than one line — that is what makes the market-basket
  queries (Q17, Q19) possible at all.
- 121,269 of 128,975 lines (94%) join the `products` catalogue on SKU.

### Q21 — the promotion result is reverse causation, not an effect

Compared naively, promoted lines cancel **0.37%** of the time against **36.7%**
for the rest — a 100× "effect". It is an artifact:

| status | lines | carry a promotion_id |
|---|---|---|
| Shipped - Delivered to Buyer | 28,769 | 99.9% |
| Shipped - Returned to Seller | 1,953 | 99.8% |
| Cancelled | 18,332 | **1.6%** |

`promotion_ids` is written at **fulfilment**, not at order time. Cancelled orders
never reach that step, so they never get one. Not-cancelling causes the field to
be populated, not the reverse. Q21 is written to expose this rather than report
the false finding.

### Q22–Q24 — the price list does not join the sales data

The May-2022 / P&L price-list SKUs match `order_lines`, `products` and
`intl_sales` **0 times out of 1,330** — different catalogue namespaces
(`Os206_3141_S` vs `AN201-RED-M`). Margin against **list price** is real. Margin
against **actual revenue** is not computable and is not attempted anywhere.

Dirty values are real: `tp` contains `#VALUE!` and the MRP columns contain
`Nill`. `derive.py` maps those to NULL rather than letting `CAST` coerce them to
0, which would drag every average down. `products` also carries one `#REF!` SKU,
an Excel error that leaked into the source.

---

## P2 — Telco churn

- Ground truth: **1,869 of 7,043 churned = 26.54%.**
- **There is no `churn_date` and no `churn_reason`.** Any tutorial query using
  them is fiction. `derived_signup_month` is **back-calculated** as
  (2024-12-01 − tenure_months) so cohort analysis is possible; it is a derived
  axis, not an observed event date.
- Churn here means "left within the last month" — a single snapshot, not a time
  series. Cohorts are therefore built on tenure, not on calendar churn dates.
- **`total_charges` is TEXT in the source and blank for exactly 11 customers**,
  all of them `tenure_months = 0`. It poisons `AVG`/`SUM` in most engines.
  `derive.py` casts it to REAL with blanks becoming NULL; Q15 and Q19 handle the
  NULLs explicitly.
- Churn by contract: month-to-month 42.71%, one year 11.27%, two year 2.83%.

---

## P3 — HR

- **`performance_score` exists for only 502 of 1,000 employees (49.8% missing).**
  That is why it is a separate table — every performance query is a LEFT JOIN and
  must decide what to do about the missing half. An INNER JOIN silently halves
  the population. Q17 tests whether the missing half differs systematically from
  the scored half; if it does, every performance conclusion is biased.
- Only 3 departments (HR / IT / Sales), 3 locations, 3 shift sessions. No
  job-title column.
- `joining_date` spans 2014-12-11 to 2024-12-07. Queries anchor to
  `MAX(joining_date)`, not `CURRENT_DATE`.
- **Not present, despite what the original query file claimed:** promotions,
  attendance/hours, manager_id, job_title, bonus, education level. Those queries
  were re-aimed at tenure, experience and pay equity.
- Salary range 2,015–9,993, mean 5,917.

---

## P4 — Food delivery: this dataset is randomly generated

Do not quote any "driver" or "impact" finding from this data as fact. Measured:

```
delay by traffic     High 4.98 | Medium 4.82 | Low 5.05   minutes
delay by distance    0-5km 5.18 | 5-10km 5.02 | 10-15km 4.75
satisfaction         1* 2.998  2* 2.985  3* 2.976  4* 2.945  5* 2.978
loyalty members      50.1% / 49.9%
traffic/weather/method   all split into near-exact thirds
restaurants          158-244 orders each, ratings all clustered at ~3.0
```

Heavy traffic is associated with **faster** delivery, long distances are
**faster** than short ones, and a 1-star order produces the same satisfaction as
a 5-star one. These relationships are not weak — they are **absent**. The columns
were drawn independently of one another. Measured effect sizes for delay:
0.019–0.059 against a standard deviation of 8.62.

That does not make the project useless, it changes what it is for. The SQL is
real. And Q16/Q17/Q18 are built to **test whether a relationship exists rather
than assume one**, and correctly conclude that it does not. Recognising a null
result — and not shipping a dashboard built on noise — is the lesson.

Other hard constraints:

- **`order_date` and `delivery_date` are date-only.** There is no clock time, so
  peak-hour analysis is impossible. Day-of-week and month seasonality are fine.
- All 20,000 orders are same-day.
- **`customer_id` is unique per row** — 20,000 customers, 20,000 orders. No
  repeat customers, so cohort retention, LTV and repeat-purchase analysis are
  impossible. `prior_order_count` is a static attribute, not a history.
- **`delivery_delay_min` ranges −10 to +20: negative means EARLY.** Treating it
  as "minutes late" without handling the sign is the trap in Q5; `AVG` alone
  hides that early and late cancel out.
- The source has no restaurant names or cuisines. `restaurants` is an honest
  summary of each restaurant's real orders, not invented metadata.

---

## P5 — Credit card fraud

**V1–V28 are principal components.** The bank published this data only after a
PCA transform, deliberately destroying the original business meaning. There is
**no merchant, no customer, no card number, no city, country, category or card
type** anywhere in the file — it has exactly 31 columns: `Time`, `V1–V28`,
`Amount`, `Class`. Every "fraud by merchant category" or "impossible travel"
query written against this dataset is fiction.

What is genuinely recoverable:

- `time` is seconds since the first transaction, spanning exactly 172,792s =
  **48 hours**, so `hour_of_day` and `day_number` are real. Both days are
  consecutive and unlabelled, so weekday analysis is not possible.
- **Strong, real signal**, unlike P4. Effect sizes (mean gap ÷ overall SD):

  ```
  V17 7.86 | V14 7.29 | V12 6.28 | V10 5.22 | V16 4.73 | V3 4.65 | V7 4.51
  ... down to V25 0.08, V23 0.07, V22 0.02   (noise - drop from any model)
  ```

  V16 and V7 are strong and are invisible if you only look at the four features
  usually quoted for this dataset.
- **Effect size, not raw mean gap.** Ranking by raw gap puts V3 first (7.045 vs
  V14's 6.984); ranking by effect size puts V3 **sixth**. The second is correct —
  a wide feature can post a big raw gap while its distributions still overlap.
  Q21 computes both; Q22 settles it with distribution overlap.
- **1,825 transactions have `amount = 0.00`** — the classic card-testing
  signature, where a stolen card is validated with a zero-value authorisation.
- Amount means: 88.29 legitimate vs 122.21 fraud. Hour 02 runs a 1.71% fraud rate
  against the 0.173% baseline (~10×).

### Class imbalance — why accuracy is never reported

492 frauds in 284,807 rows = **0.1727%**. A model predicting "never fraud" is
**99.83% accurate and completely useless**. Q15–Q18 use precision and recall
only. Measured rule performance:

| rule | precision | recall | F1 |
|---|---|---|---|
| any 3 of 6 strong features < −3 | 82.23% | 78.05% | **0.801** |
| `V14 < -4 AND V17 < -4` | 86.73% | 54.47% | 0.669 |
| `V14 < -4` | 43.74% | 76.63% | 0.557 |
| overnight (0–5h) | 0.52% | 25.20% | 0.010 |
| `amount > 1000` | 0.31% | 1.83% | 0.005 |

The intuitive "flag big transactions" rule is worthless. Using six features
instead of two lifts F1 from 0.669 to 0.801.

### Performance note

P5 Q22 scans `transaction_features` (7,974,596 rows) with partitioned window
functions and takes ~19 seconds. That is expected, not a hang.
