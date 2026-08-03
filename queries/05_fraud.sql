/* PROJECT 5: CREDIT CARD FRAUD | db/project_5_fraud.db | 25 queries
   Kaggle: mlg-ulb/creditcardfraud (284,807 rows, 492 frauds = 0.1727%)
   transactions 284,807x34 (all 28 PCA components v1..v28)
   transaction_features 7,974,596x4 (long format, one row per component)
   raw_creditcard = untouched source (31 cols).
   V1-V28 are PCA components with NO business meaning - there is no merchant,
   customer, card or city in this data. At a 0.17% base rate accuracy is
   useless, so these queries report precision/recall only.
   Feature rankings and rule performance: docs/DATA_NOTES.md */

-- ===== BEGINNER =====
-- Q1: Fraud overview and class imbalance
SELECT
    COUNT(*) AS total_transactions, SUM(is_fraud) AS fraud_count, COUNT(*) - SUM(is_fraud) AS legitimate_count,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct,
    ROUND(1.0 * COUNT(*) / NULLIF(SUM(is_fraud), 0), 0) AS one_fraud_every_n_txns,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS total_fraud_amount,
    ROUND(SUM(amount), 2) AS total_volume
FROM transactions;

-- Q2: Fraud rate by hour of day
SELECT
    hour_of_day, COUNT(*) AS transactions, SUM(is_fraud) AS frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct,
    ROUND( (100.0 * SUM(is_fraud) / COUNT(*)) /
           (SELECT 100.0 * SUM(is_fraud) / COUNT(*) FROM transactions), 2) AS times_base_rate,
    ROUND(AVG(amount), 2) AS avg_amount
FROM transactions
GROUP BY hour_of_day
ORDER BY fraud_rate_pct DESC;

-- Q3: Largest transactions
SELECT
    transaction_id, ROUND(amount, 2) AS amount, hour_of_day, day_number, is_fraud,
    CASE WHEN is_fraud = 1 THEN 'FRAUD' ELSE 'legitimate' END AS label
FROM transactions
ORDER BY amount DESC
LIMIT 50;

-- Q4: Amount profile of fraud vs legitimate
SELECT
    CASE WHEN is_fraud = 1 THEN 'Fraud' ELSE 'Legitimate' END AS class,
    COUNT(*) AS transactions, ROUND(AVG(amount), 2) AS avg_amount,
    ROUND(MIN(amount), 2) AS min_amount, ROUND(MAX(amount), 2) AS max_amount,
    ROUND(SUM(amount), 2) AS total_amount,
    SUM(CASE WHEN amount = 0 THEN 1 ELSE 0 END) AS zero_value_txns
FROM transactions
GROUP BY is_fraud;

-- Q5: Zero-amount transactions (card testing)
SELECT
    COUNT(*) AS zero_amount_txns, SUM(is_fraud) AS frauds_among_them,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct,
    (SELECT ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) FROM transactions) AS overall_fraud_rate_pct,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM transactions), 3) AS pct_of_all_txns
FROM transactions
WHERE amount = 0;

-- Q6: Volume and fraud by day
SELECT
    day_number, COUNT(*) AS transactions, SUM(is_fraud) AS frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct, ROUND(SUM(amount), 2) AS volume,
    ROUND(AVG(amount), 2) AS avg_amount
FROM transactions
GROUP BY day_number;

-- ===== INTERMEDIATE =====
-- Q7: Amount outliers by z-score
WITH stats AS (
    SELECT AVG(amount) AS mean_amt,
           sqrt( (SUM(amount*amount) - SUM(amount)*SUM(amount)/COUNT(*)) / NULLIF(COUNT(*)-1,0) ) AS sd_amt
    FROM transactions
)
SELECT
    t.transaction_id, ROUND(t.amount, 2) AS amount, t.hour_of_day, ROUND(s.mean_amt, 2) AS overall_mean,
    ROUND((t.amount - s.mean_amt) / NULLIF(s.sd_amt, 0), 2) AS z_score, t.is_fraud
FROM transactions t CROSS JOIN stats s
WHERE ABS((t.amount - s.mean_amt) / NULLIF(s.sd_amt, 0)) > 5
ORDER BY z_score DESC
LIMIT 100;

-- Q8: Fraud rate by amount band
SELECT
    CASE WHEN amount = 0 THEN 'a. Zero'
        WHEN amount < 10 THEN 'b. Under 10'
        WHEN amount < 50 THEN 'c. 10-50'
        WHEN amount < 100 THEN 'd. 50-100'
        WHEN amount < 500 THEN 'e. 100-500'
        WHEN amount < 1000 THEN 'f. 500-1000'
        ELSE 'g. 1000+' END AS amount_band,
    COUNT(*) AS transactions, SUM(is_fraud) AS frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct,
    ROUND( (1.0 * SUM(is_fraud) / COUNT(*)) /
           (SELECT 1.0 * SUM(is_fraud) / COUNT(*) FROM transactions), 2) AS lift_vs_base,
    ROUND(100.0 * SUM(is_fraud) / (SELECT SUM(is_fraud) FROM transactions), 2) AS pct_of_all_fraud
FROM transactions
GROUP BY amount_band
ORDER BY amount_band;

-- Q9: How well do the PCA features separate the classes?
WITH s AS (
    SELECT
        AVG(CASE WHEN is_fraud = 0 THEN v14 END) AS v14_legit, AVG(CASE WHEN is_fraud = 1 THEN v14 END) AS v14_fraud,
        AVG(CASE WHEN is_fraud = 0 THEN v17 END) AS v17_legit, AVG(CASE WHEN is_fraud = 1 THEN v17 END) AS v17_fraud,
        AVG(CASE WHEN is_fraud = 0 THEN v12 END) AS v12_legit, AVG(CASE WHEN is_fraud = 1 THEN v12 END) AS v12_fraud,
        AVG(CASE WHEN is_fraud = 0 THEN v10 END) AS v10_legit, AVG(CASE WHEN is_fraud = 1 THEN v10 END) AS v10_fraud,
        AVG(CASE WHEN is_fraud = 0 THEN amount END) AS amt_legit, AVG(CASE WHEN is_fraud = 1 THEN amount END) AS amt_fraud
    FROM transactions
)
SELECT 'V14' AS feature, ROUND(v14_legit,4) AS legit_mean, ROUND(v14_fraud,4) AS fraud_mean,
       ROUND(ABS(v14_fraud - v14_legit),4) AS separation FROM s
UNION ALL SELECT 'V17', ROUND(v17_legit,4), ROUND(v17_fraud,4), ROUND(ABS(v17_fraud - v17_legit),4) FROM s
UNION ALL SELECT 'V12', ROUND(v12_legit,4), ROUND(v12_fraud,4), ROUND(ABS(v12_fraud - v12_legit),4) FROM s
UNION ALL SELECT 'V10', ROUND(v10_legit,4), ROUND(v10_fraud,4), ROUND(ABS(v10_fraud - v10_legit),4) FROM s
UNION ALL SELECT 'Amount', ROUND(amt_legit,4), ROUND(amt_fraud,4), ROUND(ABS(amt_fraud - amt_legit),4) FROM s
ORDER BY separation DESC;

-- Q10: Transaction velocity in a rolling window
WITH seq AS (
    SELECT
        transaction_id, seconds_elapsed, amount, is_fraud, hour_of_day,
        LAG(seconds_elapsed) OVER (ORDER BY seconds_elapsed) AS prev_seconds,
        COUNT(*) OVER (ORDER BY seconds_elapsed RANGE BETWEEN 60 PRECEDING AND CURRENT ROW) AS txns_last_60s
    FROM transactions
)
SELECT
    transaction_id, seconds_elapsed, seconds_elapsed - prev_seconds AS gap_seconds,
    txns_last_60s, ROUND(amount, 2) AS amount, is_fraud
FROM seq
WHERE txns_last_60s > 20
ORDER BY txns_last_60s DESC
LIMIT 100;

-- Q11: Amount percentiles by class
WITH ranked AS (
    SELECT
        is_fraud, amount, ROW_NUMBER() OVER (PARTITION BY is_fraud ORDER BY amount) AS rn,
        COUNT(*) OVER (PARTITION BY is_fraud) AS n
    FROM transactions
)
SELECT
    CASE WHEN is_fraud = 1 THEN 'Fraud' ELSE 'Legitimate' END AS class,
    n AS transactions, ROUND(MAX(CASE WHEN rn = CAST(0.10*(n-1)+1 AS INTEGER) THEN amount END), 2) AS p10,
    ROUND(MAX(CASE WHEN rn = CAST(0.25*(n-1)+1 AS INTEGER) THEN amount END), 2) AS p25,
    ROUND(MAX(CASE WHEN rn = CAST(0.50*(n-1)+1 AS INTEGER) THEN amount END), 2) AS median,
    ROUND(MAX(CASE WHEN rn = CAST(0.75*(n-1)+1 AS INTEGER) THEN amount END), 2) AS p75,
    ROUND(MAX(CASE WHEN rn = CAST(0.95*(n-1)+1 AS INTEGER) THEN amount END), 2) AS p95,
    ROUND(MAX(CASE WHEN rn = CAST(0.99*(n-1)+1 AS INTEGER) THEN amount END), 2) AS p99,
    ROUND(MAX(CASE WHEN rn = n THEN amount END), 2) AS max
FROM ranked
GROUP BY is_fraud, n
ORDER BY is_fraud;

-- Q12: Fraud concentration matrix - hour against amount band
SELECT
    CASE WHEN hour_of_day BETWEEN 0 AND 5 THEN '00-05 (overnight)'
         WHEN hour_of_day BETWEEN 6 AND 11 THEN '06-11 (morning)'
         WHEN hour_of_day BETWEEN 12 AND 17 THEN '12-17 (afternoon)'
         ELSE '18-23 (evening)' END AS time_block,
    CASE WHEN amount < 50 THEN 'small (<50)'
         WHEN amount < 500 THEN 'medium (50-500)'
         ELSE 'large (500+)' END AS amount_band,
    COUNT(*) AS transactions, SUM(is_fraud) AS frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct,
    ROUND( (1.0 * SUM(is_fraud) / COUNT(*)) /
           (SELECT 1.0 * SUM(is_fraud) / COUNT(*) FROM transactions), 2) AS lift
FROM transactions
GROUP BY time_block, amount_band
HAVING COUNT(*) >= 100
ORDER BY lift DESC;

-- Q13: Where should the V14 cut-off go?
SELECT
    CASE WHEN v14 < -10 THEN 'a. below -10'
        WHEN v14 < -8 THEN 'b. -10 to -8'
        WHEN v14 < -6 THEN 'c. -8 to -6'
        WHEN v14 < -4 THEN 'd. -6 to -4'
        WHEN v14 < -2 THEN 'e. -4 to -2'
        WHEN v14 < 0 THEN 'f. -2 to 0'
        ELSE 'g. 0 or above' END AS v14_band,
    COUNT(*) AS transactions, SUM(is_fraud) AS frauds,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3) AS fraud_rate_pct,
    ROUND(100.0 * SUM(is_fraud) / (SELECT SUM(is_fraud) FROM transactions), 2) AS pct_of_all_fraud_caught
FROM transactions
GROUP BY v14_band
ORDER BY v14_band;

-- Q14: Cumulative fraud capture by risk ranking
WITH ranked AS (
    SELECT is_fraud, amount, v14,
           NTILE(100) OVER (ORDER BY v14) AS risk_percentile
    FROM transactions
),
per_bucket AS (
    SELECT risk_percentile,
           COUNT(*) AS txns,
           SUM(is_fraud) AS frauds
    FROM ranked GROUP BY risk_percentile
)
SELECT
    risk_percentile, txns, frauds,
    SUM(frauds) OVER (ORDER BY risk_percentile
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_frauds,
    ROUND(100.0 * SUM(frauds) OVER (ORDER BY risk_percentile
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / (SELECT SUM(is_fraud) FROM transactions), 2) AS pct_of_fraud_captured,
    ROUND(100.0 * SUM(txns) OVER (ORDER BY risk_percentile
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / (SELECT COUNT(*) FROM transactions), 2) AS pct_of_volume_reviewed
FROM per_bucket
ORDER BY risk_percentile
LIMIT 20;

-- ===== ADVANCED =====
-- Q15: Precision, recall and F1 for candidate rules
WITH rules AS (
    SELECT 'amount > 1000' AS rule, CASE WHEN amount > 1000 THEN 1 ELSE 0 END AS flag, is_fraud FROM transactions
    UNION ALL SELECT 'amount > 200', CASE WHEN amount > 200 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'overnight (0-5h)', CASE WHEN hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V14 < -4', CASE WHEN v14 < -4 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V14 < -8', CASE WHEN v14 < -8 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V14 < -4 AND V17 < -4', CASE WHEN v14 < -4 AND v17 < -4 THEN 1 ELSE 0 END, is_fraud FROM transactions
),
matrix AS (
    SELECT rule,
        SUM(CASE WHEN flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END) AS true_positives,
        SUM(CASE WHEN flag = 1 AND is_fraud = 0 THEN 1 ELSE 0 END) AS false_positives,
        SUM(CASE WHEN flag = 0 AND is_fraud = 1 THEN 1 ELSE 0 END) AS false_negatives,
        SUM(CASE WHEN flag = 0 AND is_fraud = 0 THEN 1 ELSE 0 END) AS true_negatives
    FROM rules GROUP BY rule
)
SELECT
    rule, true_positives, false_positives, false_negatives,
    ROUND(100.0 * true_positives / NULLIF(true_positives + false_positives, 0), 2) AS precision_pct,
    ROUND(100.0 * true_positives / NULLIF(true_positives + false_negatives, 0), 2) AS recall_pct,
    ROUND(2.0 * true_positives
          / NULLIF(2.0 * true_positives + false_positives + false_negatives, 0), 4) AS f1_score,
    ROUND(100.0 * (true_positives + true_negatives) / NULLIF(true_positives + false_positives + false_negatives + true_negatives, 0), 3) AS accuracy_pct_ignore_this
FROM matrix
ORDER BY f1_score DESC;

-- Q16: Composite risk score
WITH scored AS (
    SELECT
        transaction_id, amount, hour_of_day, v14, v17, v12, is_fraud,
        (CASE WHEN v14 < -8 THEN 40 WHEN v14 < -4 THEN 25 WHEN v14 < -2 THEN 10 ELSE 0 END)
      + (CASE WHEN v17 < -8 THEN 25 WHEN v17 < -4 THEN 15 ELSE 0 END)
      + (CASE WHEN v12 < -4 THEN 15 ELSE 0 END)
      + (CASE WHEN hour_of_day BETWEEN 0 AND 5 THEN 10 ELSE 0 END)
      + (CASE WHEN amount = 0 THEN 10 WHEN amount > 500 THEN 5 ELSE 0 END) AS raw_score
    FROM transactions
),
tiered AS (
    SELECT *, MIN(raw_score, 100) AS risk_score,
        CASE WHEN raw_score >= 70 THEN '1 Critical - block'
             WHEN raw_score >= 45 THEN '2 High - challenge'
             WHEN raw_score >= 20 THEN '3 Medium - monitor'
             ELSE '4 Low - allow' END AS risk_tier
    FROM scored
)
SELECT
    risk_tier, COUNT(*) AS transactions,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM transactions), 3) AS pct_of_volume,
    SUM(is_fraud) AS frauds_in_tier, ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3) AS fraud_rate_in_tier_pct,
    ROUND(100.0 * SUM(is_fraud) / (SELECT SUM(is_fraud) FROM transactions), 2) AS pct_of_all_fraud_caught,
    ROUND(AVG(risk_score), 1) AS avg_score,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END), 2) AS fraud_value_in_tier
FROM tiered
GROUP BY risk_tier
ORDER BY risk_tier;

-- Q17: Threshold sweep (a gains / ROC-style curve)
WITH thresholds(cut) AS (
    VALUES (-12.0), (-10.0), (-8.0), (-6.0), (-5.0), (-4.0), (-3.0), (-2.0), (-1.0), (0.0)
),
swept AS (
    SELECT
        th.cut, SUM(CASE WHEN t.v14 < th.cut AND t.is_fraud = 1 THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN t.v14 < th.cut AND t.is_fraud = 0 THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN t.v14 >= th.cut AND t.is_fraud = 1 THEN 1 ELSE 0 END) AS fn
    FROM thresholds th CROSS JOIN transactions t
    GROUP BY th.cut
)
SELECT
    cut AS v14_threshold, tp + fp AS transactions_flagged, tp AS frauds_caught,
    fp AS false_alarms, fn AS frauds_missed, ROUND(100.0 * tp / NULLIF(tp + fp, 0), 2) AS precision_pct,
    ROUND(100.0 * tp / NULLIF(tp + fn, 0), 2) AS recall_pct,
    ROUND(2.0 * tp / NULLIF(2.0 * tp + fp + fn, 0), 4) AS f1_score,
    ROUND(1.0 * fp / NULLIF(tp, 0), 1) AS false_alarms_per_catch
FROM swept
ORDER BY cut;

-- Q18: Confusion matrix at the chosen operating point
WITH applied AS (
    SELECT
        CASE WHEN v14 < -4 AND v17 < -3 THEN 1 ELSE 0 END AS predicted_fraud,
        is_fraud AS actual_fraud,
        amount
    FROM transactions
),
cm AS (
    SELECT
        SUM(CASE WHEN predicted_fraud = 1 AND actual_fraud = 1 THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN predicted_fraud = 1 AND actual_fraud = 0 THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN predicted_fraud = 0 AND actual_fraud = 1 THEN 1 ELSE 0 END) AS fn,
        SUM(CASE WHEN predicted_fraud = 0 AND actual_fraud = 0 THEN 1 ELSE 0 END) AS tn,
        SUM(CASE WHEN predicted_fraud = 1 AND actual_fraud = 1 THEN amount ELSE 0 END) AS value_caught,
        SUM(CASE WHEN predicted_fraud = 0 AND actual_fraud = 1 THEN amount ELSE 0 END) AS value_missed
    FROM applied
)
SELECT
    tp AS true_positives, fp AS false_positives, fn AS false_negatives, tn AS true_negatives,
    ROUND(100.0 * tp / NULLIF(tp + fp, 0), 2) AS precision_pct,
    ROUND(100.0 * tp / NULLIF(tp + fn, 0), 2) AS recall_pct,
    ROUND(100.0 * fp / NULLIF(fp + tn, 0), 4) AS false_positive_rate_pct,
    ROUND(2.0 * tp / NULLIF(2.0 * tp + fp + fn, 0), 4) AS f1_score,
    ROUND(value_caught, 2) AS fraud_value_prevented, ROUND(value_missed, 2) AS fraud_value_missed,
    ROUND(100.0 * value_caught / NULLIF(value_caught + value_missed, 0), 2) AS pct_value_prevented
FROM cm;

-- Q19: Cost-benefit of running the rule
WITH assumptions AS (
    SELECT 25.0 AS review_cost_per_alert, -- analyst time per flagged txn
           0.85 AS recovery_rate, -- share of caught fraud actually recovered
           15.0 AS customer_friction_cost -- cost of wrongly challenging a good customer
),
outcome AS (
    SELECT
        SUM(CASE WHEN v14 < -4 AND is_fraud = 1 THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN v14 < -4 AND is_fraud = 0 THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN v14 < -4 AND is_fraud = 1 THEN amount ELSE 0 END) AS caught_value,
        SUM(CASE WHEN v14 >= -4 AND is_fraud = 1 THEN amount ELSE 0 END) AS missed_value
    FROM transactions
)
SELECT
    o.tp AS frauds_caught, o.fp AS false_alarms, ROUND(o.caught_value, 2) AS fraud_value_caught,
    ROUND(o.missed_value, 2) AS fraud_value_missed,
    ROUND(o.caught_value * a.recovery_rate, 2) AS value_recovered,
    ROUND((o.tp + o.fp) * a.review_cost_per_alert, 2) AS review_cost,
    ROUND(o.fp * a.customer_friction_cost, 2) AS friction_cost,
    ROUND(o.caught_value * a.recovery_rate - (o.tp + o.fp) * a.review_cost_per_alert
          - o.fp * a.customer_friction_cost, 2) AS net_benefit,
    ROUND( (o.caught_value * a.recovery_rate)
           / NULLIF((o.tp + o.fp) * a.review_cost_per_alert + o.fp * a.customer_friction_cost, 0), 2) AS benefit_cost_ratio,
    CASE WHEN o.caught_value * a.recovery_rate
              > (o.tp + o.fp) * a.review_cost_per_alert + o.fp * a.customer_friction_cost
         THEN 'Deploy - positive return' ELSE 'Do not deploy - costs exceed recovery' END AS recommendation
FROM outcome o CROSS JOIN assumptions a;

-- Q20: ML-ready feature export
WITH stats AS (
    SELECT AVG(amount) AS mean_amt,
           sqrt( (SUM(amount*amount) - SUM(amount)*SUM(amount)/COUNT(*)) / NULLIF(COUNT(*)-1,0) ) AS sd_amt
    FROM transactions
)
SELECT
    t.transaction_id, ROUND(t.amount, 2) AS amount,
    ROUND((t.amount - s.mean_amt) / NULLIF(s.sd_amt, 0), 4) AS amount_zscore,
    ROUND(LOG(1 + t.amount), 4) AS log_amount, t.hour_of_day,
    CASE WHEN t.hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END AS is_overnight,
    CASE WHEN t.amount = 0 THEN 1 ELSE 0 END AS is_zero_amount,
    ROUND(t.v14, 4) AS v14, ROUND(t.v17, 4) AS v17, ROUND(t.v12, 4) AS v12, ROUND(t.v10, 4) AS v10,
    CASE WHEN t.v14 < -4 THEN 1 ELSE 0 END AS v14_flag,
    CASE WHEN t.v17 < -4 THEN 1 ELSE 0 END AS v17_flag,
    (CASE WHEN t.v14 < -4 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v17 < -4 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v12 < -4 THEN 1 ELSE 0 END)
      + (CASE WHEN t.hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END) AS risk_flag_count,
    t.is_fraud AS target_label
FROM transactions t CROSS JOIN stats s
WHERE t.is_fraud = 1
   OR (CASE WHEN t.v14 < -4 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v17 < -4 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v12 < -4 THEN 1 ELSE 0 END) >= 2
ORDER BY t.is_fraud DESC, risk_flag_count DESC
LIMIT 5000;

-- ===== EXTENDED =====
-- Q21: Rank ALL 28 components by class separation
WITH stats AS (
    SELECT
        feature, AVG(CASE WHEN is_fraud = 0 THEN value END) AS legit_mean,
        AVG(CASE WHEN is_fraud = 1 THEN value END) AS fraud_mean, COUNT(*) AS observations,
        sqrt( (SUM(value*value) - SUM(value)*SUM(value)/COUNT(*)) / NULLIF(COUNT(*)-1,0) ) AS sd_all
    FROM transaction_features
    GROUP BY feature
)
SELECT
    feature, ROUND(legit_mean, 4) AS legit_mean, ROUND(fraud_mean, 4) AS fraud_mean,
    ROUND(ABS(fraud_mean - legit_mean), 4) AS separation, ROUND(sd_all, 4) AS overall_sd,
    ROUND(ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0), 4) AS effect_size,
    RANK() OVER (ORDER BY ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0) DESC) AS rank_by_effect,
    CASE WHEN ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0) > 2.0 THEN 'Very strong'
         WHEN ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0) > 1.0 THEN 'Strong'
         WHEN ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0) > 0.5 THEN 'Moderate'
         WHEN ABS(fraud_mean - legit_mean) / NULLIF(sd_all, 0) > 0.2 THEN 'Weak'
         ELSE 'Negligible - drop from the model' END AS usefulness
FROM stats
ORDER BY effect_size DESC;

-- Q22: Which components separate cleanly, and which merely look different?
WITH ranked AS (
    SELECT feature, value, is_fraud,
           ROW_NUMBER() OVER (PARTITION BY feature, is_fraud ORDER BY value) AS rn,
           COUNT(*) OVER (PARTITION BY feature, is_fraud) AS n
    FROM transaction_features
),
pct AS (
    SELECT feature, is_fraud, n,
           MAX(CASE WHEN rn = CAST(0.01*(n-1)+1 AS INTEGER) THEN value END) AS p01,
           MAX(CASE WHEN rn = CAST(0.50*(n-1)+1 AS INTEGER) THEN value END) AS median,
           MAX(CASE WHEN rn = CAST(0.99*(n-1)+1 AS INTEGER) THEN value END) AS p99
    FROM ranked GROUP BY feature, is_fraud, n
)
SELECT
    l.feature, ROUND(l.p01, 3) AS legit_p01, ROUND(l.median, 3) AS legit_median,
    ROUND(l.p99, 3) AS legit_p99, ROUND(f.median, 3) AS fraud_median,
    ROUND(ABS(f.median - l.median), 3) AS median_gap,
    CASE WHEN f.median BETWEEN l.p01 AND l.p99
         THEN 'Overlaps - weak on its own'
         ELSE 'Separates cleanly' END AS discrimination
FROM pct l
JOIN pct f ON l.feature = f.feature AND l.is_fraud = 0 AND f.is_fraud = 1
ORDER BY median_gap DESC;

-- Q23: Rules built from the features the data chose, not the famous ones
WITH rules AS (
    SELECT 'V14<-4 AND V17<-4' AS rule, CASE WHEN v14 < -4 AND v17 < -4 THEN 1 ELSE 0 END AS flag, is_fraud FROM transactions
    UNION ALL SELECT 'V3<-4 AND V14<-4', CASE WHEN v3 < -4 AND v14 < -4 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V3<-4 AND V17<-4', CASE WHEN v3 < -4 AND v17 < -4 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V10<-4 AND V12<-4', CASE WHEN v10 < -4 AND v12 < -4 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'V3,V14,V17 all <-3', CASE WHEN v3 < -3 AND v14 < -3 AND v17 < -3 THEN 1 ELSE 0 END, is_fraud FROM transactions
    UNION ALL SELECT 'any 3 of 6 strong features < -3',
        CASE WHEN (CASE WHEN v3 < -3 THEN 1 ELSE 0 END)
                + (CASE WHEN v10 < -3 THEN 1 ELSE 0 END)
                + (CASE WHEN v12 < -3 THEN 1 ELSE 0 END)
                + (CASE WHEN v14 < -3 THEN 1 ELSE 0 END)
                + (CASE WHEN v16 < -3 THEN 1 ELSE 0 END)
                + (CASE WHEN v17 < -3 THEN 1 ELSE 0 END) >= 3
             THEN 1 ELSE 0 END, is_fraud FROM transactions
),
m AS (
    SELECT rule,
        SUM(CASE WHEN flag = 1 AND is_fraud = 1 THEN 1 ELSE 0 END) AS tp,
        SUM(CASE WHEN flag = 1 AND is_fraud = 0 THEN 1 ELSE 0 END) AS fp,
        SUM(CASE WHEN flag = 0 AND is_fraud = 1 THEN 1 ELSE 0 END) AS fn
    FROM rules GROUP BY rule
)
SELECT
    rule, tp AS frauds_caught, fp AS false_alarms, fn AS frauds_missed,
    ROUND(100.0 * tp / NULLIF(tp + fp, 0), 2) AS precision_pct,
    ROUND(100.0 * tp / NULLIF(tp + fn, 0), 2) AS recall_pct,
    ROUND(2.0 * tp / NULLIF(2.0 * tp + fp + fn, 0), 4) AS f1_score,
    RANK() OVER (ORDER BY 2.0 * tp / NULLIF(2.0 * tp + fp + fn, 0) DESC) AS rank_by_f1
FROM m
ORDER BY f1_score DESC;

-- Q24: Full-width profile of every confirmed fraud
SELECT
    transaction_id, seconds_elapsed, hour_of_day, day_number, amount,
    ROUND(v1,3) AS v1, ROUND(v2,3) AS v2, ROUND(v3,3) AS v3, ROUND(v4,3) AS v4, ROUND(v5,3) AS v5,
    ROUND(v6,3) AS v6, ROUND(v7,3) AS v7, ROUND(v8,3) AS v8, ROUND(v9,3) AS v9, ROUND(v10,3) AS v10,
    ROUND(v11,3) AS v11, ROUND(v12,3) AS v12, ROUND(v13,3) AS v13, ROUND(v14,3) AS v14,
    ROUND(v15,3) AS v15, ROUND(v16,3) AS v16, ROUND(v17,3) AS v17, ROUND(v18,3) AS v18,
    ROUND(v19,3) AS v19, ROUND(v20,3) AS v20, ROUND(v21,3) AS v21, ROUND(v22,3) AS v22,
    ROUND(v23,3) AS v23, ROUND(v24,3) AS v24, ROUND(v25,3) AS v25, ROUND(v26,3) AS v26,
    ROUND(v27,3) AS v27, ROUND(v28,3) AS v28
FROM transactions
WHERE is_fraud = 1
ORDER BY amount DESC;

-- Q25: ML export using every component
WITH s AS (
    SELECT AVG(amount) AS mean_amt,
           sqrt( (SUM(amount*amount) - SUM(amount)*SUM(amount)/COUNT(*)) / NULLIF(COUNT(*)-1,0) ) AS sd_amt
    FROM transactions
),
flagged AS (
    SELECT t.*,
        (CASE WHEN t.v3 < -3 THEN 1 ELSE 0 END) + (CASE WHEN t.v10 < -3 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v12 < -3 THEN 1 ELSE 0 END) + (CASE WHEN t.v14 < -3 THEN 1 ELSE 0 END)
      + (CASE WHEN t.v16 < -3 THEN 1 ELSE 0 END) + (CASE WHEN t.v17 < -3 THEN 1 ELSE 0 END)
        AS strong_feature_flags
    FROM transactions t
)
SELECT
    f.transaction_id, f.amount, ROUND((f.amount - s.mean_amt) / NULLIF(s.sd_amt, 0), 4) AS amount_zscore,
    f.hour_of_day, f.day_number,
    CASE WHEN f.hour_of_day BETWEEN 0 AND 5 THEN 1 ELSE 0 END AS is_overnight,
    CASE WHEN f.amount = 0 THEN 1 ELSE 0 END AS is_zero_amount,
    f.v1, f.v2, f.v3, f.v4, f.v5, f.v6, f.v7, f.v8, f.v9, f.v10, f.v11, f.v12, f.v13, f.v14,
    f.v15, f.v16, f.v17, f.v18, f.v19, f.v20, f.v21, f.v22, f.v23, f.v24, f.v25, f.v26, f.v27, f.v28,
    f.strong_feature_flags,
    f.is_fraud AS target_label
FROM flagged f CROSS JOIN s
WHERE f.is_fraud = 1 OR f.strong_feature_flags >= 2
ORDER BY f.is_fraud DESC, f.strong_feature_flags DESC
LIMIT 5000;
