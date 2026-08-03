/* PROJECT 2: TELECOM CHURN | db/project_2_churn.db | 20 queries
   Kaggle: blastchar/telco-customer-churn (7,043 customers, 26.54% churned)
   customers 7,043x12 | services 7,043x7 | billing 7,043x3 | churn 7,043x3
   raw_wa_fn_usec_telco_customer_churn = untouched source (21 cols).
   Caveats - no churn_date/churn_reason exist, derived_signup_month is
   back-calculated, total_charges is blank for 11 rows: docs/DATA_NOTES.md */

-- ===== BEGINNER =====
-- Q1: Overall churn rate
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    SUM(CASE WHEN churn_status = 'No' THEN 1 ELSE 0 END) AS retained,
    ROUND(100.0 * SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM churn;

-- Q2: Churn by contract type
SELECT
    c.contract_type, COUNT(*) AS customers,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
GROUP BY c.contract_type
ORDER BY churn_rate_pct DESC;

-- Q3: Tenure of churned vs retained customers
SELECT
    ch.churn_status, COUNT(*) AS customers,
    ROUND(AVG(c.tenure_months), 1) AS avg_tenure_months,
    MIN(c.tenure_months) AS min_tenure, MAX(c.tenure_months) AS max_tenure,
    ROUND(AVG(b.monthly_charges), 2) AS avg_monthly_charges
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
JOIN billing b ON c.customer_id = b.customer_id
GROUP BY ch.churn_status;

-- Q4: Churn by internet service type
SELECT
    c.internet_service, COUNT(*) AS customers,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(b.monthly_charges), 2) AS avg_monthly_charges
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
JOIN billing b ON c.customer_id = b.customer_id
GROUP BY c.internet_service
ORDER BY churn_rate_pct DESC;

-- Q5: Churn by payment method
SELECT
    c.payment_method, COUNT(*) AS customers,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(c.tenure_months), 1) AS avg_tenure
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
GROUP BY c.payment_method
ORDER BY churn_rate_pct DESC;

-- Q6: Churn by tenure bucket
SELECT
    CASE
        WHEN c.tenure_months <= 6 THEN '0-6 months'
        WHEN c.tenure_months <= 12 THEN '7-12 months'
        WHEN c.tenure_months <= 24 THEN '1-2 years'
        WHEN c.tenure_months <= 48 THEN '2-4 years'
        ELSE '4+ years'
    END AS tenure_bucket,
    COUNT(*) AS customers,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
GROUP BY tenure_bucket
ORDER BY MIN(c.tenure_months);

-- ===== INTERMEDIATE =====
-- Q7: Churn by derived signup cohort
SELECT
    ch.derived_signup_month AS signup_cohort, COUNT(*) AS cohort_size,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(b.monthly_charges), 2) AS avg_monthly_charges
FROM churn ch
JOIN billing b ON ch.customer_id = b.customer_id
GROUP BY ch.derived_signup_month
HAVING COUNT(*) >= 20
ORDER BY signup_cohort;

-- Q8: Retention curve by tenure month
WITH by_tenure AS (
    SELECT c.tenure_months,
           COUNT(*) AS customers,
           SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned
    FROM customers c
    JOIN churn ch ON c.customer_id = ch.customer_id
    GROUP BY c.tenure_months
)
SELECT
    tenure_months, customers, churned,
    ROUND(100.0 * churned / customers, 2) AS churn_rate_pct,
    SUM(customers) OVER (ORDER BY tenure_months DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS still_active_at_or_beyond,
    ROUND(100.0 * SUM(customers) OVER (ORDER BY tenure_months DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / (SELECT COUNT(*) FROM customers), 2) AS pct_reaching_tenure
FROM by_tenure
ORDER BY tenure_months;

-- Q9: Highest-risk demographic combinations
SELECT
    CASE WHEN c.senior_citizen = 1 THEN 'Senior' ELSE 'Non-senior' END AS age_group,
    c.partner AS has_partner, c.dependents AS has_dependents, COUNT(*) AS group_size,
    SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
    RANK() OVER (ORDER BY 1.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END)
                          / COUNT(*) DESC) AS risk_rank
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
GROUP BY age_group, c.partner, c.dependents
HAVING COUNT(*) >= 100
ORDER BY risk_rank;

-- Q10: Price sensitivity - churn by monthly-charge quartile
WITH tiers AS (
    SELECT b.customer_id, b.monthly_charges, ch.churn_status,
           NTILE(4) OVER (ORDER BY b.monthly_charges) AS charge_quartile
    FROM billing b
    JOIN churn ch ON b.customer_id = ch.customer_id
)
SELECT
    charge_quartile, COUNT(*) AS customers, ROUND(MIN(monthly_charges), 2) AS min_charge,
    ROUND(MAX(monthly_charges), 2) AS max_charge, ROUND(AVG(monthly_charges), 2) AS avg_charge,
    SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM tiers
GROUP BY charge_quartile
ORDER BY charge_quartile;

-- Q11: Does bundling more services reduce churn?
WITH bundles AS (
    SELECT
        s.customer_id, ch.churn_status,
        (CASE WHEN s.online_security = 'Yes' THEN 1 ELSE 0 END) +
        (CASE WHEN s.online_backup = 'Yes' THEN 1 ELSE 0 END) +
        (CASE WHEN s.device_protection = 'Yes' THEN 1 ELSE 0 END) +
        (CASE WHEN s.tech_support = 'Yes' THEN 1 ELSE 0 END) +
        (CASE WHEN s.streaming_tv = 'Yes' THEN 1 ELSE 0 END) +
        (CASE WHEN s.streaming_movies = 'Yes' THEN 1 ELSE 0 END) AS service_count
    FROM services s
    JOIN churn ch ON s.customer_id = ch.customer_id
)
SELECT
    service_count, COUNT(*) AS customers,
    SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM bundles
GROUP BY service_count
ORDER BY service_count;

-- Q12: Early-warning signal count
WITH signals AS (
    SELECT
        c.customer_id, c.tenure_months, c.contract_type, b.monthly_charges,
        ch.churn_status,
        CASE WHEN c.contract_type = 'Month-to-month' THEN 1 ELSE 0 END AS f_mtm,
        CASE WHEN c.tenure_months < 12 THEN 1 ELSE 0 END AS f_new,
        CASE WHEN b.monthly_charges > 75 THEN 1 ELSE 0 END AS f_expensive,
        CASE WHEN c.partner = 'No' THEN 1 ELSE 0 END AS f_no_partner,
        CASE WHEN c.payment_method = 'Electronic check' THEN 1 ELSE 0 END AS f_echeck,
        CASE WHEN s.tech_support = 'No' THEN 1 ELSE 0 END AS f_no_support
    FROM customers c
    JOIN billing b ON c.customer_id = b.customer_id
    JOIN services s ON c.customer_id = s.customer_id
    JOIN churn ch ON c.customer_id = ch.customer_id
)
SELECT
    (f_mtm + f_new + f_expensive + f_no_partner + f_echeck + f_no_support) AS signal_count,
    COUNT(*) AS customers,
    SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS actual_churn_rate_pct
FROM signals
GROUP BY signal_count
ORDER BY signal_count;

-- Q13: Which individual service most reduces churn?
WITH sa AS (
    SELECT s.*, ch.churn_status
    FROM services s JOIN churn ch ON s.customer_id = ch.customer_id
)
SELECT 'Online security' AS service,
       SUM(CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END) AS subscribers,
       ROUND(100.0 * SUM(CASE WHEN online_security = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN online_security = 'Yes' THEN 1 ELSE 0 END), 0), 2) AS churn_rate_pct
FROM sa
UNION ALL
SELECT 'Online backup',
       SUM(CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN online_backup = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN online_backup = 'Yes' THEN 1 ELSE 0 END), 0), 2)
FROM sa
UNION ALL
SELECT 'Device protection',
       SUM(CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN device_protection = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN device_protection = 'Yes' THEN 1 ELSE 0 END), 0), 2)
FROM sa
UNION ALL
SELECT 'Tech support',
       SUM(CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN tech_support = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN tech_support = 'Yes' THEN 1 ELSE 0 END), 0), 2)
FROM sa
UNION ALL
SELECT 'Streaming TV',
       SUM(CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN streaming_tv = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN streaming_tv = 'Yes' THEN 1 ELSE 0 END), 0), 2)
FROM sa
UNION ALL
SELECT 'Streaming movies',
       SUM(CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN streaming_movies = 'Yes' AND churn_status = 'Yes' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN streaming_movies = 'Yes' THEN 1 ELSE 0 END), 0), 2)
FROM sa
ORDER BY churn_rate_pct;

-- Q14: Contract effectiveness scorecard
SELECT
    c.contract_type, COUNT(*) AS customers,
    ROUND(100.0 * SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(c.tenure_months), 1) AS avg_tenure,
    ROUND(AVG(b.monthly_charges), 2) AS avg_monthly,
    ROUND(AVG(b.total_charges), 2) AS avg_total_billed,
    ROUND(100.0 * AVG(CASE WHEN c.paperless_billing = 'Yes' THEN 1.0 ELSE 0.0 END), 1) AS paperless_pct
FROM customers c
JOIN churn ch ON c.customer_id = ch.customer_id
JOIN billing b ON c.customer_id = b.customer_id
GROUP BY c.contract_type
ORDER BY churn_rate_pct;

-- ===== ADVANCED =====
-- Q15: Revenue impact of churn
WITH base AS (
    SELECT
        c.customer_id, c.contract_type, c.tenure_months,
        b.monthly_charges,
        COALESCE(b.total_charges, 0) AS total_charges,
        ch.churn_status
    FROM customers c
    JOIN billing b ON c.customer_id = b.customer_id
    JOIN churn ch ON c.customer_id = ch.customer_id
),
valued AS (
    SELECT *,
        CASE WHEN churn_status = 'No'
             THEN total_charges + monthly_charges * 12
             ELSE total_charges
        END AS projected_12m_value,
        CASE WHEN churn_status = 'Yes'
             THEN monthly_charges * 12 ELSE 0 END AS annualised_revenue_lost
    FROM base
)
SELECT
    churn_status, COUNT(*) AS customers,
    ROUND(AVG(monthly_charges), 2) AS avg_monthly,
    ROUND(SUM(total_charges), 2) AS revenue_booked_to_date,
    ROUND(SUM(projected_12m_value), 2) AS projected_value_next_12m,
    ROUND(SUM(annualised_revenue_lost), 2) AS annualised_loss,
    ROUND(100.0 * SUM(projected_12m_value)
          / SUM(SUM(projected_12m_value)) OVER (), 2) AS pct_of_total_value
FROM valued
GROUP BY churn_status
ORDER BY churn_status;

-- Q16: Weighted churn risk score (0-100) for still-active customers
WITH p75 AS (
    SELECT monthly_charges AS threshold
    FROM (
        SELECT monthly_charges,
               ROW_NUMBER() OVER (ORDER BY monthly_charges) AS rn,
               COUNT(*) OVER () AS n
        FROM billing
    )
    WHERE rn = CAST(0.75 * (n - 1) + 1 AS INTEGER)
),
scored AS (
    SELECT
        c.customer_id, c.tenure_months, c.contract_type,
        b.monthly_charges, ch.churn_status,
        (CASE WHEN c.contract_type = 'Month-to-month' THEN 25 ELSE 0 END) +
        (CASE WHEN c.tenure_months < 6 THEN 20 ELSE 0 END) +
        (CASE WHEN b.monthly_charges > (SELECT threshold FROM p75) THEN 20 ELSE 0 END) +
        (CASE WHEN c.partner = 'No' THEN 15 ELSE 0 END) +
        (CASE WHEN c.payment_method = 'Electronic check' THEN 10 ELSE 0 END) +
        (CASE WHEN c.internet_service = 'Fiber optic' THEN 10 ELSE 0 END) AS raw_score
    FROM customers c
    JOIN billing b ON c.customer_id = b.customer_id
    JOIN churn ch ON c.customer_id = ch.customer_id
)
SELECT
    customer_id, tenure_months, contract_type, ROUND(monthly_charges, 2) AS monthly_charges,
    MIN(raw_score, 100) AS risk_score,
    CASE
        WHEN raw_score >= 75 THEN 'Critical'
        WHEN raw_score >= 50 THEN 'High'
        WHEN raw_score >= 25 THEN 'Medium'
        ELSE 'Low'
    END AS risk_tier,
    ROUND(monthly_charges * 12, 2) AS annual_revenue_at_risk
FROM scored
WHERE churn_status = 'No'
ORDER BY raw_score DESC, annual_revenue_at_risk DESC
LIMIT 250;

-- Q17: Cohort retention waterfall
WITH cohort AS (
    SELECT
        ch.derived_signup_month AS cohort_month, c.tenure_months,
        CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END AS churned
    FROM customers c
    JOIN churn ch ON c.customer_id = ch.customer_id
)
SELECT
    cohort_month, COUNT(*) AS cohort_size, SUM(churned) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churned = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS retained_pct,
    SUM(CASE WHEN tenure_months >= 6 THEN 1 ELSE 0 END) AS reached_6m,
    SUM(CASE WHEN tenure_months >= 12 THEN 1 ELSE 0 END) AS reached_12m,
    SUM(CASE WHEN tenure_months >= 24 THEN 1 ELSE 0 END) AS reached_24m,
    SUM(CASE WHEN tenure_months >= 48 THEN 1 ELSE 0 END) AS reached_48m
FROM cohort
GROUP BY cohort_month
HAVING COUNT(*) >= 20
ORDER BY cohort_month;

-- Q18: Charge distribution percentiles, churned vs retained
WITH ranked AS (
    SELECT
        ch.churn_status, b.monthly_charges,
        ROW_NUMBER() OVER (PARTITION BY ch.churn_status ORDER BY b.monthly_charges) AS rn,
        COUNT(*) OVER (PARTITION BY ch.churn_status) AS n
    FROM billing b
    JOIN churn ch ON b.customer_id = ch.customer_id
)
SELECT
    churn_status, n AS customers,
    ROUND(MAX(CASE WHEN rn = 1 THEN monthly_charges END), 2) AS min_charge,
    ROUND(MAX(CASE WHEN rn = CAST(0.25*(n-1)+1 AS INTEGER) THEN monthly_charges END), 2) AS p25,
    ROUND(MAX(CASE WHEN rn = CAST(0.50*(n-1)+1 AS INTEGER) THEN monthly_charges END), 2) AS median,
    ROUND(MAX(CASE WHEN rn = CAST(0.75*(n-1)+1 AS INTEGER) THEN monthly_charges END), 2) AS p75,
    ROUND(MAX(CASE WHEN rn = CAST(0.90*(n-1)+1 AS INTEGER) THEN monthly_charges END), 2) AS p90,
    ROUND(MAX(CASE WHEN rn = n THEN monthly_charges END), 2) AS max_charge
FROM ranked
GROUP BY churn_status, n
ORDER BY churn_status;

-- Q19: Retention programme ROI
WITH facts AS (
    SELECT
        SUM(CASE WHEN ch.churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
        ROUND(AVG(CASE WHEN ch.churn_status = 'Yes' THEN b.monthly_charges END), 2) AS avg_monthly_of_churned,
        COUNT(*) AS total_customers
    FROM billing b JOIN churn ch ON b.customer_id = ch.customer_id
),
assumptions AS (SELECT 5.0 AS offer_cost, 0.30 AS save_rate),
model AS (
    SELECT f.*, a.offer_cost, a.save_rate,
           f.churned * f.avg_monthly_of_churned * 12 AS annual_revenue_lost,
           f.churned * a.offer_cost AS programme_cost,
           f.churned * a.save_rate AS customers_saved,
           f.churned * a.save_rate * f.avg_monthly_of_churned * 12 AS revenue_recovered
    FROM facts f CROSS JOIN assumptions a
)
SELECT
    total_customers, churned, avg_monthly_of_churned,
    ROUND(annual_revenue_lost, 2) AS annual_revenue_lost,
    ROUND(offer_cost, 2) AS offer_cost_per_customer,
    ROUND(100.0 * save_rate, 0) AS assumed_save_rate_pct,
    ROUND(customers_saved, 0) AS customers_saved, ROUND(programme_cost, 2) AS programme_cost,
    ROUND(revenue_recovered, 2) AS revenue_recovered,
    ROUND(revenue_recovered - programme_cost, 2) AS net_benefit,
    ROUND((revenue_recovered - programme_cost) / NULLIF(programme_cost, 0), 1) AS roi_multiple
FROM model;

-- Q20: Segmented retention strategy
WITH segmented AS (
    SELECT
        CASE
            WHEN c.tenure_months < 6 THEN 'New'
            WHEN c.tenure_months < 24 THEN 'Growing'
            ELSE 'Established'
        END AS lifecycle,
        CASE
            WHEN b.monthly_charges < 45 THEN 'Economy'
            WHEN b.monthly_charges < 75 THEN 'Standard'
            ELSE 'Premium'
        END AS value_tier,
        c.contract_type, b.monthly_charges,
        ch.churn_status
    FROM customers c
    JOIN billing b ON c.customer_id = b.customer_id
    JOIN churn ch ON c.customer_id = ch.customer_id
),
rolled AS (
    SELECT
        lifecycle, value_tier, contract_type, COUNT(*) AS segment_size,
        SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) AS churned,
        ROUND(100.0 * SUM(CASE WHEN churn_status = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct,
        ROUND(SUM(CASE WHEN churn_status = 'Yes' THEN monthly_charges * 12 ELSE 0 END), 2) AS annual_revenue_lost
    FROM segmented
    GROUP BY lifecycle, value_tier, contract_type
)
SELECT
    lifecycle, value_tier, contract_type,
    segment_size, churned, churn_rate_pct, annual_revenue_lost,
    RANK() OVER (ORDER BY annual_revenue_lost DESC) AS loss_rank,
    CASE
        WHEN churn_rate_pct > 40 THEN 'Critical'
        WHEN churn_rate_pct > 25 THEN 'High'
        WHEN churn_rate_pct > 12 THEN 'Watch'
        ELSE 'Stable'
    END AS priority,
    CASE
        WHEN lifecycle = 'New' AND contract_type = 'Month-to-month'
             THEN 'Onboarding sequence + 12-month contract incentive'
        WHEN value_tier = 'Premium' AND churn_rate_pct > 25
             THEN 'Assign account manager; service-quality review'
        WHEN contract_type = 'Month-to-month'
             THEN 'Term-contract offer with loyalty discount'
        WHEN churn_rate_pct > 25
             THEN 'Targeted win-back campaign'
        ELSE 'Business as usual'
    END AS recommended_action
FROM rolled
WHERE segment_size >= 50
ORDER BY annual_revenue_lost DESC;
