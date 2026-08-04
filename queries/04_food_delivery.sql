-- Q1: Platform overview ==> Beginner-friendly
SELECT
    COUNT(*) AS total_orders, COUNT(DISTINCT restaurant_id) AS restaurants,
    COUNT(DISTINCT customer_id) AS customers, ROUND(SUM(order_value), 2) AS total_revenue,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(AVG(delivery_distance_km), 2) AS avg_distance_km,
    ROUND(AVG(delivery_delay_min), 2) AS avg_delay_min,
    MIN(order_date) AS first_order,
    MAX(order_date) AS last_order
FROM orders;

-- Q2: Top restaurants by revenue ==> Beginner-friendly
SELECT
    o.restaurant_id, COUNT(*) AS orders, ROUND(SUM(o.order_value), 2) AS revenue,
    ROUND(AVG(o.order_value), 2) AS avg_order_value,
    ROUND(AVG(o.delivery_delay_min), 2) AS avg_delay_min,
    r.avg_rating
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
GROUP BY o.restaurant_id, r.avg_rating
ORDER BY revenue DESC
LIMIT 20;

-- Q3: Most popular menu items ==> Beginner-friendly
SELECT
    food_item, COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 2) AS pct_of_orders,
    ROUND(SUM(order_value), 2) AS revenue,
    ROUND(AVG(order_value), 2) AS avg_value
FROM orders
GROUP BY food_item
ORDER BY orders DESC;

-- Q4: Demand by city ==> Beginner-friendly
SELECT
    c.location AS city, COUNT(*) AS orders, ROUND(SUM(o.order_value), 2) AS revenue,
    ROUND(AVG(o.order_value), 2) AS avg_order_value,
    ROUND(AVG(o.delivery_distance_km), 2) AS avg_distance_km,
    ROUND(AVG(o.delivery_delay_min), 2) AS avg_delay_min
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.location
ORDER BY revenue DESC;

-- Q5: Early, on-time and late deliveries ==> Beginner-friendly
SELECT
    CASE
        WHEN delivery_delay_min < 0 THEN 'Early'
        WHEN delivery_delay_min = 0 THEN 'Exactly on time'
        WHEN delivery_delay_min <= 5 THEN 'Late by up to 5 min'
        WHEN delivery_delay_min <= 10 THEN 'Late by 5-10 min'
        ELSE 'Late by over 10 min'
    END AS delivery_outcome,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 2) AS pct_of_orders,
    ROUND(AVG(delivery_delay_min), 2) AS avg_delay_in_bucket,
    ROUND(AVG(delivery_distance_km), 2) AS avg_distance
FROM orders
GROUP BY delivery_outcome
ORDER BY MIN(delivery_delay_min);

-- Q6: Customer base profile ==> Beginner-friendly
SELECT
    loyalty_program, order_frequency, COUNT(*) AS customers, ROUND(AVG(age), 1) AS avg_age,
    ROUND(AVG(prior_order_count), 1) AS avg_prior_orders
FROM customers
GROUP BY loyalty_program, order_frequency
ORDER BY customers DESC;

-- Q7: Day-of-week ordering pattern ==> Intermediate-friendly
SELECT
    CAST(strftime('%w', order_date) AS INTEGER) AS dow_number,
    CASE CAST(strftime('%w', order_date) AS INTEGER)
        WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
        ELSE 'Saturday'
    END AS day_name,
    COUNT(*) AS orders, ROUND(SUM(order_value), 2) AS revenue,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(AVG(delivery_delay_min), 2) AS avg_delay_min
FROM orders
GROUP BY dow_number
ORDER BY dow_number;

-- Q8: Monthly trend with month-over-month growth ==> Intermediate-friendly
SELECT
    strftime('%Y-%m', order_date) AS month, COUNT(*) AS orders,
    ROUND(SUM(order_value), 2) AS revenue,
    ROUND(LAG(SUM(order_value)) OVER (ORDER BY strftime('%Y-%m', order_date)), 2) AS prev_month_revenue,
    ROUND(100.0 * (SUM(order_value) - LAG(SUM(order_value)) OVER (ORDER BY strftime('%Y-%m', order_date)))
          / NULLIF(LAG(SUM(order_value)) OVER (ORDER BY strftime('%Y-%m', order_date)), 0), 2) AS growth_pct
FROM orders
GROUP BY month
ORDER BY month;

-- Q9: Restaurant league table ==> Intermediate-friendly
WITH stats AS (
    SELECT
        o.restaurant_id, COUNT(*) AS orders, ROUND(SUM(o.order_value), 2) AS revenue,
        ROUND(AVG(o.delivery_delay_min), 2) AS avg_delay,
        ROUND(AVG(q.customer_satisfaction), 3) AS avg_satisfaction
    FROM orders o
    JOIN order_quality q ON o.order_id = q.order_id
    GROUP BY o.restaurant_id
)
SELECT
    restaurant_id, orders, revenue, avg_delay, avg_satisfaction,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
    RANK() OVER (ORDER BY avg_delay ASC) AS speed_rank,
    RANK() OVER (ORDER BY avg_satisfaction DESC) AS satisfaction_rank
FROM stats
ORDER BY revenue_rank
LIMIT 30;

-- Q10: Does distance predict delay? ==> Intermediate-friendly
SELECT
    CASE
        WHEN delivery_distance_km < 5 THEN '2-5 km'
        WHEN delivery_distance_km < 10 THEN '5-10 km'
        ELSE '10-15 km'
    END AS distance_band,
    COUNT(*) AS orders,
    ROUND(AVG(delivery_distance_km), 2) AS avg_distance,
    ROUND(AVG(delivery_delay_min), 3) AS avg_delay_min,
    ROUND(MIN(delivery_delay_min), 1) AS min_delay,
    ROUND(MAX(delivery_delay_min), 1) AS max_delay,
    ROUND(sqrt( (SUM(delivery_delay_min * delivery_delay_min)
                 - SUM(delivery_delay_min) * SUM(delivery_delay_min) / COUNT(*))
                / NULLIF(COUNT(*) - 1, 0) ), 3) AS delay_stddev
FROM orders
GROUP BY distance_band
ORDER BY MIN(delivery_distance_km);

-- Q11: Weather and traffic interaction ==> Intermediate-friendly
SELECT
    weather_condition, traffic_condition, COUNT(*) AS orders,
    ROUND(AVG(delivery_delay_min), 3) AS avg_delay_min,
    ROUND(100.0 * SUM(CASE WHEN delivery_delay_min > 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_over_10min_late,
    ROUND(AVG(order_value), 2) AS avg_order_value
FROM orders
GROUP BY weather_condition, traffic_condition
ORDER BY avg_delay_min DESC;

-- Q12: Do customers order the cuisine they say they prefer? ==> Intermediate-friendly
SELECT
    c.preferred_cuisine, COUNT(*) AS orders,
    COUNT(DISTINCT o.food_item) AS distinct_items_ordered,
    ROUND(AVG(o.order_value), 2) AS avg_order_value,
    ROUND(AVG(q.customer_satisfaction), 3) AS avg_satisfaction
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_quality q ON o.order_id = q.order_id
GROUP BY c.preferred_cuisine
ORDER BY orders DESC;

-- Q13: Route efficiency and delivery method ==> Intermediate-friendly
WITH bucketed AS (
    SELECT
        delivery_method, route_type, traffic_avoidance, delivery_delay_min, route_efficiency,
        NTILE(4) OVER (ORDER BY route_efficiency) AS efficiency_quartile
    FROM orders
)
SELECT
    efficiency_quartile, delivery_method, COUNT(*) AS orders,
    ROUND(AVG(route_efficiency), 3) AS avg_route_efficiency,
    ROUND(AVG(delivery_delay_min), 3) AS avg_delay_min
FROM bucketed
GROUP BY efficiency_quartile, delivery_method
ORDER BY efficiency_quartile, delivery_method;

-- Q14: Quality scores versus satisfaction ==> Intermediate-friendly
SELECT
    q.food_freshness, COUNT(*) AS orders,
    ROUND(AVG(q.customer_satisfaction), 3) AS avg_satisfaction,
    ROUND(AVG(q.customer_rating), 3) AS avg_rating,
    ROUND(AVG(q.packaging_quality), 3) AS avg_packaging,
    ROUND(AVG(o.order_value), 2) AS avg_order_value
FROM order_quality q
JOIN orders o ON q.order_id = o.order_id
GROUP BY q.food_freshness
ORDER BY q.food_freshness;

-- Q15: Restaurant performance scorecard ==> Advanced-friendly
WITH base AS (
    SELECT
        o.restaurant_id, COUNT(*) AS orders, AVG(o.order_value) AS avg_value,
        AVG(o.delivery_delay_min) AS avg_delay,
        AVG(q.customer_satisfaction) AS avg_satisfaction,
        SUM(CASE WHEN o.delivery_delay_min <= 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS on_time_rate
    FROM orders o
    JOIN order_quality q ON o.order_id = q.order_id
    GROUP BY o.restaurant_id
),
scored AS (
    SELECT *,
        PERCENT_RANK() OVER (ORDER BY avg_value) AS value_pct,
        PERCENT_RANK() OVER (ORDER BY on_time_rate) AS punctuality_pct,
        PERCENT_RANK() OVER (ORDER BY avg_satisfaction) AS satisfaction_pct
    FROM base
)
SELECT
    restaurant_id, orders, ROUND(avg_value, 2) AS avg_order_value,
    ROUND(avg_delay, 2) AS avg_delay_min,
    ROUND(100.0 * on_time_rate, 1) AS on_time_pct,
    ROUND(avg_satisfaction, 3) AS avg_satisfaction,
    ROUND(100 * value_pct, 1) AS value_percentile,
    ROUND(100 * punctuality_pct, 1) AS punctuality_percentile,
    ROUND(100 * satisfaction_pct, 1) AS satisfaction_percentile,
    ROUND(100 * (0.4 * punctuality_pct + 0.4 * satisfaction_pct + 0.2 * value_pct), 1) AS composite_score,
    CASE
        WHEN 0.4*punctuality_pct + 0.4*satisfaction_pct + 0.2*value_pct >= 0.75 THEN 'Tier 1'
        WHEN 0.4*punctuality_pct + 0.4*satisfaction_pct + 0.2*value_pct >= 0.50 THEN 'Tier 2'
        WHEN 0.4*punctuality_pct + 0.4*satisfaction_pct + 0.2*value_pct >= 0.25 THEN 'Tier 3'
        ELSE 'Tier 4 - review'
    END AS tier
FROM scored
ORDER BY composite_score DESC;

-- Q16: SIGNAL TEST - does any factor explain delivery delay? ==> Advanced-friendly
WITH overall AS (
    SELECT sqrt( (SUM(delivery_delay_min*delivery_delay_min)
                  - SUM(delivery_delay_min)*SUM(delivery_delay_min)/COUNT(*))
                 / NULLIF(COUNT(*)-1, 0) ) AS sd_all
    FROM orders
),
factor AS (
    SELECT 'traffic_condition' AS factor, traffic_condition AS level,
           COUNT(*) AS n, AVG(delivery_delay_min) AS mean_delay FROM orders GROUP BY traffic_condition
    UNION ALL
    SELECT 'weather_condition', weather_condition, COUNT(*), AVG(delivery_delay_min) FROM orders GROUP BY weather_condition
    UNION ALL
    SELECT 'delivery_method', delivery_method, COUNT(*), AVG(delivery_delay_min) FROM orders GROUP BY delivery_method
    UNION ALL
    SELECT 'route_type', route_type, COUNT(*), AVG(delivery_delay_min) FROM orders GROUP BY route_type
    UNION ALL
    SELECT 'traffic_avoidance', traffic_avoidance, COUNT(*), AVG(delivery_delay_min) FROM orders GROUP BY traffic_avoidance
)
SELECT
    f.factor, COUNT(*) AS levels,
    ROUND(MIN(f.mean_delay), 3) AS lowest_group_mean,
    ROUND(MAX(f.mean_delay), 3) AS highest_group_mean,
    ROUND(MAX(f.mean_delay) - MIN(f.mean_delay), 3) AS spread_minutes,
    ROUND(o.sd_all, 3) AS overall_stddev,
    ROUND((MAX(f.mean_delay) - MIN(f.mean_delay)) / o.sd_all, 4) AS effect_size,
    CASE
        WHEN (MAX(f.mean_delay) - MIN(f.mean_delay)) / o.sd_all > 0.20 THEN 'Meaningful effect'
        WHEN (MAX(f.mean_delay) - MIN(f.mean_delay)) / o.sd_all > 0.05 THEN 'Weak effect'
        ELSE 'NO DETECTABLE EFFECT - consistent with random data'
    END AS verdict
FROM factor f CROSS JOIN overall o
GROUP BY f.factor, o.sd_all
ORDER BY effect_size DESC;

-- Q17: SIGNAL TEST - what drives customer satisfaction? ==> Advanced-friendly
WITH levels AS (
    SELECT 'customer_rating' AS dimension, customer_rating AS level, AVG(customer_satisfaction) AS mean_sat, COUNT(*) AS n FROM order_quality GROUP BY customer_rating
    UNION ALL
    SELECT 'food_freshness', food_freshness, AVG(customer_satisfaction), COUNT(*) FROM order_quality GROUP BY food_freshness
    UNION ALL
    SELECT 'packaging_quality', packaging_quality, AVG(customer_satisfaction), COUNT(*) FROM order_quality GROUP BY packaging_quality
)
SELECT
    dimension, COUNT(*) AS levels_observed,
    ROUND(MIN(mean_sat), 3) AS satisfaction_at_worst_level,
    ROUND(MAX(mean_sat), 3) AS satisfaction_at_best_level,
    ROUND(MAX(mean_sat) - MIN(mean_sat), 3) AS total_lift,
    CASE
        WHEN MAX(mean_sat) - MIN(mean_sat) > 0.5 THEN 'Clear driver'
        WHEN MAX(mean_sat) - MIN(mean_sat) > 0.2 THEN 'Possible driver'
        ELSE 'NOT A DRIVER - flat across all levels'
    END AS verdict
FROM levels
GROUP BY dimension
ORDER BY total_lift DESC;

-- Q18: SIGNAL TEST - is the loyalty programme worth anything? ==> Advanced-friendly
WITH grp AS (
    SELECT
        c.loyalty_program, COUNT(*) AS customers, AVG(o.order_value) AS mean_value,
        AVG(q.customer_satisfaction) AS mean_satisfaction,
        AVG(c.prior_order_count) AS mean_prior_orders,
        AVG(o.delivery_delay_min) AS mean_delay
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_quality q ON o.order_id = q.order_id
    GROUP BY c.loyalty_program
)
SELECT
    loyalty_program, customers, ROUND(mean_value, 3) AS avg_order_value,
    ROUND(mean_satisfaction, 3) AS avg_satisfaction,
    ROUND(mean_prior_orders, 2) AS avg_prior_orders,
    ROUND(mean_delay, 3) AS avg_delay_min,
    ROUND(mean_value - MIN(mean_value) OVER (), 3) AS value_gap_vs_other_group,
    ROUND(mean_satisfaction - MIN(mean_satisfaction) OVER (), 3) AS satisfaction_gap_vs_other_group
FROM grp
ORDER BY loyalty_program;

-- Q19: Market share by city ==> Advanced-friendly
WITH city_rest AS (
    SELECT
        c.location AS city, o.restaurant_id, COUNT(*) AS orders,
        SUM(o.order_value) AS revenue
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.location, o.restaurant_id
),
ranked AS (
    SELECT
        city, restaurant_id, orders, revenue,
        SUM(revenue) OVER (PARTITION BY city) AS city_revenue,
        RANK() OVER (PARTITION BY city ORDER BY revenue DESC) AS rank_in_city,
        COUNT(*) OVER (PARTITION BY city) AS restaurants_in_city
    FROM city_rest
)
SELECT
    city, restaurant_id, orders, ROUND(revenue, 2) AS revenue,
    ROUND(city_revenue, 2) AS city_revenue,
    ROUND(100.0 * revenue / city_revenue, 2) AS market_share_pct,
    rank_in_city,
    restaurants_in_city
FROM ranked
WHERE rank_in_city <= 5
ORDER BY city, rank_in_city;

-- Q20: Operational summary by city and weekday ==> Advanced-friendly
WITH detail AS (
    SELECT
        c.location AS city,
        CASE CAST(strftime('%w', o.order_date) AS INTEGER)
            WHEN 0 THEN 'Sunday' WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
            ELSE 'Saturday'
        END AS day_name,
        o.order_value, o.delivery_delay_min, q.customer_satisfaction
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_quality q ON o.order_id = q.order_id
),
combined AS (
    SELECT city, day_name, 0 AS sort_key,
           COUNT(*) AS orders, ROUND(SUM(order_value), 2) AS revenue,
           ROUND(AVG(delivery_delay_min), 2) AS avg_delay,
           ROUND(AVG(customer_satisfaction), 3) AS avg_satisfaction
    FROM detail
    GROUP BY city, day_name
    UNION ALL
    SELECT city, 'ALL DAYS', 1, COUNT(*), ROUND(SUM(order_value), 2),
           ROUND(AVG(delivery_delay_min), 2), ROUND(AVG(customer_satisfaction), 3)
    FROM detail
    GROUP BY city
)
SELECT city, day_name, orders, revenue, avg_delay, avg_satisfaction
FROM combined
ORDER BY city, sort_key, day_name;

-- Q21: Route shape versus delivery outcome ==> Extended-friendly
SELECT
    CASE WHEN is_small_route = 1 THEN 'Short route' ELSE 'Long route' END AS route_length,
    CASE WHEN is_bike_friendly_route = 1 THEN 'Bike friendly' ELSE 'Not bike friendly' END AS bike_access,
    delivery_method, COUNT(*) AS orders,
    ROUND(AVG(delivery_distance_km), 2) AS avg_distance_km,
    ROUND(AVG(delivery_delay_min), 3) AS avg_delay_min,
    ROUND(AVG(route_efficiency), 3) AS avg_route_efficiency,
    ROUND(100.0 * SUM(CASE WHEN delivery_delay_min <= 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_early_or_on_time,
    ROUND(MAX(AVG(delivery_delay_min)) OVER () - MIN(AVG(delivery_delay_min)) OVER (), 3) AS spread_across_all_groups
FROM orders
GROUP BY is_small_route, is_bike_friendly_route, delivery_method
ORDER BY avg_delay_min DESC;
