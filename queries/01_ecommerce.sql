/* PROJECT 1: E-COMMERCE | db/project_1_ecommerce.db | 26 queries
   Kaggle: thedevastator/unlock-profits-with-e-commerce-sales-data
   order_lines 128,975x25 | orders 120,378 | products 9,170 | geography 9,148
   pricing 1,330x18 | channel_prices 10,640 | intl_sales 36,392
   intl_customers 172 | warehouse_rates 20 | expenses 14
   raw_* = untouched source CSVs (all 7 files loaded).
   Caveats - NULL amounts, cancellations, the promotion artifact, and the
   price list that does not join: docs/DATA_NOTES.md */

-- ===== BEGINNER =====
-- Q1: Headline sales figures
SELECT
    COUNT(*) AS sale_lines, COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(amount), 2) AS total_revenue, ROUND(AVG(amount), 2) AS avg_line_value,
    SUM(qty) AS units_sold
FROM order_lines
WHERE status <> 'Cancelled'
  AND amount IS NOT NULL;

-- Q2: Revenue by product category
SELECT
    category, COUNT(*) AS sale_lines, SUM(qty) AS units, ROUND(SUM(amount), 2) AS revenue,
    ROUND(AVG(amount), 2) AS avg_line_value,
    ROUND(100.0 * SUM(amount) / (
        SELECT SUM(amount) FROM order_lines
        WHERE status <> 'Cancelled' AND amount IS NOT NULL), 2) AS pct_of_revenue
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY category
ORDER BY revenue DESC;

-- Q3: Top 10 SKUs by revenue, enriched from the catalogue
SELECT
    ol.sku, p.design_no, p.product_category, p.color, SUM(ol.qty) AS units_sold,
    ROUND(SUM(ol.amount), 2) AS revenue,
    p.stock AS stock_on_hand
FROM order_lines ol
INNER JOIN products p ON ol.sku = p.sku
WHERE ol.status <> 'Cancelled' AND ol.amount IS NOT NULL
GROUP BY ol.sku, p.design_no, p.product_category, p.color, p.stock
ORDER BY revenue DESC
LIMIT 10;

-- Q4: Where the orders ship to
SELECT
    ship_state, COUNT(DISTINCT order_id) AS orders, ROUND(SUM(amount), 2) AS revenue,
    ROUND(AVG(amount), 2) AS avg_line_value
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY ship_state
HAVING COUNT(DISTINCT order_id) >= 100
ORDER BY revenue DESC;

-- Q5: Daily revenue trend
SELECT
    order_date, strftime('%Y-%m', order_date) AS month, COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(amount), 2) AS revenue
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY order_date
ORDER BY order_date;

-- Q6: Order status breakdown
SELECT
    status, COUNT(*) AS lines,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_lines), 2) AS pct_of_lines,
    CASE
        WHEN status = 'Cancelled' THEN 'Lost'
        WHEN status LIKE '%Returned%'
          OR status LIKE '%Returning%'
          OR status LIKE '%Rejected%' THEN 'Returned'
        WHEN status LIKE 'Pending%'
          OR status = 'Shipping' THEN 'In flight'
        ELSE 'Fulfilled'
    END AS outcome
FROM order_lines
GROUP BY status
ORDER BY lines DESC;

-- ===== INTERMEDIATE =====
-- Q7: Month-over-month revenue growth
SELECT
    strftime('%Y-%m', order_date) AS month, ROUND(SUM(amount), 2) AS revenue,
    ROUND(LAG(SUM(amount)) OVER (ORDER BY strftime('%Y-%m', order_date)), 2) AS prev_month,
    ROUND(100.0 * (SUM(amount) - LAG(SUM(amount)) OVER (ORDER BY strftime('%Y-%m', order_date)))
          / NULLIF(LAG(SUM(amount)) OVER (ORDER BY strftime('%Y-%m', order_date)), 0), 2) AS growth_pct
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY strftime('%Y-%m', order_date)
ORDER BY month;

-- Q8: Rank products within their catalogue category
SELECT
    p.product_category, ol.sku, p.color, ROUND(SUM(ol.amount), 2) AS revenue,
    DENSE_RANK() OVER (PARTITION BY p.product_category
                       ORDER BY SUM(ol.amount) DESC) AS rank_in_category
FROM order_lines ol
INNER JOIN products p ON ol.sku = p.sku
WHERE ol.status <> 'Cancelled' AND ol.amount IS NOT NULL
GROUP BY p.product_category, ol.sku, p.color
ORDER BY p.product_category, rank_in_category;

-- Q9: Cumulative revenue (running total)
SELECT
    order_date, ROUND(SUM(amount), 2) AS daily_revenue,
    ROUND(SUM(SUM(amount)) OVER (ORDER BY order_date
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY order_date
ORDER BY order_date;

-- Q10: Cities whose average order beats the site-wide average
SELECT
    ship_city, COUNT(DISTINCT order_id) AS orders, ROUND(AVG(amount), 2) AS avg_line_value,
    ROUND(SUM(amount), 2) AS revenue
FROM order_lines
WHERE status <> 'Cancelled' AND amount IS NOT NULL
GROUP BY ship_city
HAVING COUNT(DISTINCT order_id) >= 50
   AND AVG(amount) > (SELECT AVG(amount) FROM order_lines
                      WHERE status <> 'Cancelled' AND amount IS NOT NULL)
ORDER BY avg_line_value DESC;

-- Q11: Top 3 SKUs in every category
WITH ranked AS (
    SELECT
        p.product_category, ol.sku, ROUND(SUM(ol.amount), 2) AS revenue,
        ROW_NUMBER() OVER (PARTITION BY p.product_category
                           ORDER BY SUM(ol.amount) DESC) AS rn
    FROM order_lines ol
    INNER JOIN products p ON ol.sku = p.sku
    WHERE ol.status <> 'Cancelled' AND ol.amount IS NOT NULL
    GROUP BY p.product_category, ol.sku
)
SELECT product_category, sku, revenue, rn AS rank_in_category
FROM ranked
WHERE rn <= 3
ORDER BY product_category, rn;

-- Q12: Order-value distribution
SELECT
    order_id, order_amount,
    ROUND(100 * PERCENT_RANK() OVER (ORDER BY order_amount), 2) AS percentile,
    NTILE(4) OVER (ORDER BY order_amount) AS quartile,
    CASE NTILE(4) OVER (ORDER BY order_amount)
        WHEN 4 THEN 'Top 25%'
        WHEN 3 THEN 'Upper mid'
        WHEN 2 THEN 'Lower mid'
        ELSE 'Bottom 25%'
    END AS value_tier
FROM orders
WHERE order_amount IS NOT NULL AND status <> 'Cancelled'
ORDER BY order_amount DESC
LIMIT 200;

-- Q13: Low stock against recent demand
SELECT
    p.sku, p.product_category, p.color, p.stock,
    COALESCE(SUM(ol.qty), 0) AS units_sold_in_window,
    ROUND(p.stock * 1.0 / NULLIF(SUM(ol.qty), 0), 1) AS windows_of_cover
FROM products p
LEFT JOIN order_lines ol
       ON p.sku = ol.sku AND ol.status <> 'Cancelled'
WHERE p.stock IS NOT NULL AND p.stock < 20
GROUP BY p.sku, p.product_category, p.color, p.stock
ORDER BY windows_of_cover IS NULL, windows_of_cover
LIMIT 100;

-- Q14: International customer value
SELECT
    ic.customer_name, ic.sale_lines, ic.lifetime_value,
    ROUND(ic.lifetime_value / NULLIF(ic.sale_lines, 0), 2) AS avg_line_value,
    COUNT(DISTINCT s.sku) AS distinct_skus,
    ROUND(SUM(s.pcs), 0) AS total_pieces
FROM intl_customers ic
JOIN intl_sales s ON s.customer = ic.customer_name
GROUP BY ic.customer_name, ic.sale_lines, ic.lifetime_value
ORDER BY ic.lifetime_value DESC
LIMIT 25;

-- ===== ADVANCED =====
-- Q15: Monthly cohorts of international customers
WITH sales AS (
    SELECT customer,
           '20' || substr(raw_date, 7, 2) || '-' || substr(raw_date, 1, 2) AS ym,
           gross_amt
    FROM intl_sales
    WHERE length(trim(raw_date)) = 8 AND gross_amt IS NOT NULL
),
first_month AS (
    SELECT customer, MIN(ym) AS cohort_month
    FROM sales GROUP BY customer
),
activity AS (
    SELECT f.cohort_month, s.ym AS active_month, s.customer, s.gross_amt
    FROM sales s JOIN first_month f ON s.customer = f.customer
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer) AS cohort_customers
    FROM first_month GROUP BY cohort_month
)
SELECT
    a.cohort_month, a.active_month,
    (CAST(substr(a.active_month,1,4) AS INTEGER) - CAST(substr(a.cohort_month,1,4) AS INTEGER)) * 12
      + (CAST(substr(a.active_month,6,2) AS INTEGER) - CAST(substr(a.cohort_month,6,2) AS INTEGER))
 AS months_since_first, cs.cohort_customers,
    COUNT(DISTINCT a.customer) AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT a.customer) / cs.cohort_customers, 1) AS retention_pct,
    ROUND(SUM(a.gross_amt), 2) AS revenue
FROM activity a
JOIN cohort_size cs ON a.cohort_month = cs.cohort_month
GROUP BY a.cohort_month, a.active_month, cs.cohort_customers
ORDER BY a.cohort_month, a.active_month;

-- Q16: RFM segmentation of international customers
WITH base AS (
    SELECT customer,
           MAX('20'||substr(raw_date,7,2)||'-'||substr(raw_date,1,2)||'-'||substr(raw_date,4,2)) AS last_purchase,
           COUNT(*) AS frequency,
           SUM(gross_amt) AS monetary
    FROM intl_sales
    WHERE length(trim(raw_date)) = 8 AND gross_amt IS NOT NULL
    GROUP BY customer
),
scored AS (
    SELECT customer, last_purchase, frequency, monetary,
           CAST(julianday((SELECT MAX(last_purchase) FROM base)) - julianday(last_purchase) AS INTEGER) AS recency_days,
           NTILE(4) OVER (ORDER BY julianday(last_purchase)) AS r_score,
           NTILE(4) OVER (ORDER BY frequency) AS f_score,
           NTILE(4) OVER (ORDER BY monetary) AS m_score
    FROM base
)
SELECT
    customer, recency_days, frequency, ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    (r_score || f_score || m_score) AS rfm_cell,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champion'
        WHEN r_score >= 3 AND f_score >= 2 THEN 'Loyal'
        WHEN r_score >= 3 THEN 'Promising'
        WHEN f_score >= 3 OR m_score >= 3 THEN 'At risk - valuable'
        ELSE 'Lapsed'
    END AS segment
FROM scored
ORDER BY monetary DESC;

-- Q17: Categories bought together in the same order
SELECT
    a.category AS category_a, b.category AS category_b,
    COUNT(DISTINCT a.order_id) AS orders_with_both,
    ROUND(100.0 * COUNT(DISTINCT a.order_id) /
          (SELECT COUNT(*) FROM orders WHERE line_count > 1), 2) AS pct_of_multiline_orders
FROM order_lines a
JOIN order_lines b
  ON a.order_id = b.order_id
 AND a.category < b.category
WHERE a.status <> 'Cancelled' AND b.status <> 'Cancelled'
GROUP BY a.category, b.category
HAVING COUNT(DISTINCT a.order_id) >= 5
ORDER BY orders_with_both DESC;

-- Q18: Outlier order values by category (z-score)
WITH stats AS (
    SELECT category,
           COUNT(*) AS n, AVG(amount) AS mean_amount,
           sqrt( (SUM(amount * amount) - SUM(amount) * SUM(amount) / COUNT(*))
                 / NULLIF(COUNT(*) - 1, 0) ) AS sd_amount
    FROM order_lines
    WHERE status <> 'Cancelled' AND amount IS NOT NULL
    GROUP BY category
)
SELECT
    ol.order_id, ol.order_date, ol.category, ol.sku, ROUND(ol.amount, 2) AS amount,
    ROUND(s.mean_amount, 2) AS category_mean, ROUND(s.sd_amount, 2) AS category_sd,
    ROUND((ol.amount - s.mean_amount) / NULLIF(s.sd_amount, 0), 2) AS z_score,
    CASE
        WHEN ABS((ol.amount - s.mean_amount) / NULLIF(s.sd_amount, 0)) > 4 THEN 'Extreme'
        WHEN ABS((ol.amount - s.mean_amount) / NULLIF(s.sd_amount, 0)) > 3 THEN 'Significant'
        ELSE 'Moderate'
    END AS outlier_class
FROM order_lines ol
JOIN stats s ON ol.category = s.category
WHERE ol.status <> 'Cancelled' AND ol.amount IS NOT NULL
  AND ABS((ol.amount - s.mean_amount) / NULLIF(s.sd_amount, 0)) > 3
ORDER BY ABS((ol.amount - s.mean_amount) / NULLIF(s.sd_amount, 0)) DESC
LIMIT 100;

-- Q19: Market basket rules - support, confidence, lift
WITH multi AS (
    SELECT order_id FROM orders WHERE line_count > 1
),
basket AS (
    SELECT DISTINCT ol.order_id, ol.category
    FROM order_lines ol
    JOIN multi m ON ol.order_id = m.order_id
    WHERE ol.status <> 'Cancelled'
),
total AS (SELECT COUNT(*) AS n_orders FROM multi),
item AS (
    SELECT category, COUNT(*) AS cnt FROM basket GROUP BY category
),
pair AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS both_cnt
    FROM basket a
    JOIN basket b ON a.order_id = b.order_id AND a.category < b.category
    GROUP BY a.category, b.category
)
SELECT
    p.cat_a, p.cat_b, p.both_cnt,
    ROUND(100.0 * p.both_cnt / t.n_orders, 3) AS support_pct,
    ROUND(100.0 * p.both_cnt / ia.cnt, 2) AS confidence_a_to_b,
    ROUND(100.0 * p.both_cnt / ib.cnt, 2) AS confidence_b_to_a,
    ROUND( (1.0 * p.both_cnt / t.n_orders) /
           NULLIF((1.0 * ia.cnt / t.n_orders) * (1.0 * ib.cnt / t.n_orders), 0), 2) AS lift
FROM pair p
JOIN item ia ON p.cat_a = ia.category
JOIN item ib ON p.cat_b = ib.category
CROSS JOIN total t
WHERE p.both_cnt >= 5
ORDER BY lift DESC;

-- Q20: Cancellation risk scorecard by segment
WITH segment AS (
    SELECT
        category, fulfilment,
        CASE WHEN b2b = 1 THEN 'B2B' ELSE 'B2C' END AS channel,
        COUNT(*) AS lines,
        SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
        SUM(CASE WHEN status LIKE '%Returned%'
                   OR status LIKE '%Returning%'
                   OR status LIKE '%Rejected%' THEN 1 ELSE 0 END) AS returned,
        ROUND(AVG(CASE WHEN amount IS NOT NULL THEN amount END), 2) AS avg_value
    FROM order_lines
    GROUP BY category, fulfilment, channel
),
scored AS (
    SELECT *,
        ROUND(100.0 * cancelled / NULLIF(lines, 0), 2) AS cancel_rate,
        ROUND(100.0 * returned / NULLIF(lines, 0), 2) AS return_rate,
        ROUND(100.0 * cancelled / NULLIF(lines, 0)
            + 2 * 100.0 * returned / NULLIF(lines, 0), 2) AS risk_score
    FROM segment
    WHERE lines >= 100
)
SELECT
    category, fulfilment, channel, lines, avg_value,
    cancel_rate, return_rate, risk_score,
    CASE
        WHEN risk_score >= 30 THEN 'Critical'
        WHEN risk_score >= 20 THEN 'High'
        WHEN risk_score >= 12 THEN 'Watch'
        ELSE 'Healthy'
    END AS risk_tier,
    CASE
        WHEN return_rate > 3 THEN 'Investigate sizing / product photos'
        WHEN cancel_rate > 25 THEN 'Review stock accuracy and lead time'
        WHEN cancel_rate > 15 THEN 'Monitor fulfilment SLA'
        ELSE 'No action'
    END AS recommended_action
FROM scored
ORDER BY risk_score DESC;

-- ===== EXTENDED =====
-- Q21: Promotions - and a lesson in not trusting the obvious read
SELECT
    status, COUNT(*) AS lines, SUM(has_promotion) AS promoted_lines,
    ROUND(100.0 * SUM(has_promotion) / COUNT(*), 1) AS pct_carrying_promo_id,
    ROUND(AVG(promotion_count), 2) AS avg_promos_applied,
    ROUND(AVG(CASE WHEN has_promotion = 1 THEN amount END), 2) AS avg_value_promoted,
    ROUND(AVG(CASE WHEN has_promotion = 0 THEN amount END), 2) AS avg_value_unpromoted,
    ROUND(100.0 * SUM(CASE WHEN b2b = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS b2b_pct
FROM order_lines
GROUP BY status
ORDER BY lines DESC;

-- Q22: Price dispersion across the nine marketplaces
WITH per_sku AS (
    SELECT sku, price_category, cost_price,
           COUNT(list_price) AS channels_listed, MIN(list_price) AS cheapest,
           MAX(list_price) AS dearest,
           ROUND(AVG(list_price), 2) AS avg_price
    FROM channel_prices
    WHERE list_price IS NOT NULL
    GROUP BY sku, price_category, cost_price
)
SELECT
    sku, price_category, channels_listed, cost_price, cheapest, dearest, avg_price,
    ROUND(dearest - cheapest, 2) AS price_spread,
    ROUND(100.0 * (dearest - cheapest) / NULLIF(cheapest, 0), 1) AS spread_pct,
    CASE
        WHEN 100.0 * (dearest - cheapest) / NULLIF(cheapest, 0) > 20 THEN 'Inconsistent - review'
        WHEN 100.0 * (dearest - cheapest) / NULLIF(cheapest, 0) > 5 THEN 'Minor variance'
        ELSE 'Aligned'
    END AS pricing_status
FROM per_sku
WHERE channels_listed >= 2
ORDER BY spread_pct DESC
LIMIT 100;

-- Q23: Gross margin against list price, by channel
SELECT
    channel, COUNT(*) AS skus_listed, ROUND(AVG(cost_price), 2) AS avg_cost,
    ROUND(AVG(list_price), 2) AS avg_list_price,
    ROUND(AVG(list_price - cost_price), 2) AS avg_gross_margin,
    ROUND(100.0 * AVG((list_price - cost_price) / NULLIF(list_price, 0)), 2) AS avg_margin_pct,
    ROUND(MIN((list_price - cost_price) / NULLIF(list_price, 0)) * 100, 1) AS worst_margin_pct,
    SUM(CASE WHEN list_price < cost_price THEN 1 ELSE 0 END) AS skus_priced_below_cost
FROM channel_prices
WHERE list_price IS NOT NULL AND cost_price IS NOT NULL
GROUP BY channel
ORDER BY avg_margin_pct DESC;

-- Q24: Catalogue margin profile by category
WITH m AS (
    SELECT price_category, catalog, sku, weight_kg,
           cost_price, cost_price_2021_a, cost_price_2021_b,
           final_mrp_old, amazon_mrp, amazon_mrp - cost_price AS margin_value,
           100.0 * (amazon_mrp - cost_price) / NULLIF(amazon_mrp, 0) AS margin_pct
    FROM pricing
    WHERE cost_price IS NOT NULL AND amazon_mrp IS NOT NULL
)
SELECT
    price_category, COUNT(*) AS skus, COUNT(DISTINCT catalog) AS catalogs,
    ROUND(AVG(weight_kg), 3) AS avg_weight_kg, ROUND(AVG(cost_price), 2) AS avg_cost_2022,
    ROUND(AVG(cost_price_2021_a), 2) AS avg_cost_2021_base,
    ROUND(AVG(cost_price_2021_b), 2) AS avg_cost_2021_alt,
    ROUND(AVG(amazon_mrp), 2) AS avg_amazon_price,
    ROUND(AVG(margin_value), 2) AS avg_margin_value,
    ROUND(AVG(margin_pct), 2) AS avg_margin_pct, ROUND(MIN(margin_pct), 1) AS min_margin_pct,
    ROUND(MAX(margin_pct), 1) AS max_margin_pct
FROM m
GROUP BY price_category
ORDER BY avg_margin_pct DESC;

-- Q25: Full-width order line detail
SELECT
    ol.line_id, ol.order_id, ol.order_date, ol.status, ol.courier_status,
    ol.fulfilment, ol.sales_channel, ol.ship_service_level,
    ol.style, ol.sku, ol.asin, ol.category, ol.size,
    ol.qty, ol.amount, ol.currency,
    ol.ship_city, ol.ship_state, ol.ship_postal_code, ol.ship_country,
    ol.b2b, ol.has_promotion, ol.promotion_count, p.design_no, p.color, p.stock,
    ROUND(ol.amount / NULLIF(ol.qty, 0), 2) AS unit_price
FROM order_lines ol
LEFT JOIN products p ON ol.sku = p.sku
WHERE ol.amount IS NOT NULL
  AND ol.status <> 'Cancelled'
  AND ol.has_promotion = 1
ORDER BY ol.amount DESC
LIMIT 200;

-- Q26: Geography, warehouse rates and the expense ledger
WITH top_geo AS (
    SELECT g.state,
           COUNT(DISTINCT g.city) AS cities_served, SUM(g.line_count) AS lines_from_geo_dim,
           ROUND(SUM(ol.amount), 2) AS revenue
    FROM geography g
    JOIN order_lines ol
      ON ol.ship_city = g.city AND ol.ship_state = g.state
    WHERE ol.status <> 'Cancelled' AND ol.amount IS NOT NULL
    GROUP BY g.state
)
SELECT 'geography' AS source,
       state AS item, cities_served AS metric_a,
       revenue AS metric_b
FROM top_geo
WHERE revenue IS NOT NULL
UNION ALL
SELECT 'warehouse_rates', line_item, NULL,
       CASE WHEN trim(increff_rate) GLOB '[0-9]*' THEN CAST(increff_rate AS REAL) END
FROM warehouse_rates
UNION ALL
SELECT 'expenses', expense_item, NULL, amount
FROM expenses
ORDER BY source, metric_b DESC NULLS LAST;
