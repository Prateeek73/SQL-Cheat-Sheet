"""
Derived tables, built strictly from columns that exist in the real CSVs.

Purpose: the raw Kaggle files are mostly wide flat tables. Splitting them into
properly typed fact/dimension tables restores real JOIN practice - the single
most-interviewed SQL skill - without inventing a single value. Every column here
traces back to a real source column; nothing is synthesised.

Where a dimension is NOT derivable from the data it is simply absent, and the
queries are designed around that rather than pointed at fabricated values.
Notable absences, confirmed by profiling:
  * project_4_food  - order_time/delivery_time are date-only, so there is no
    hour-of-day dimension; customer_id is unique per row, so there is no repeat
    -purchase or cohort dimension.
  * project_5_fraud - no merchant, customer, card or geography of any kind.
  * project_3_hr    - no promotions, attendance, manager or job-title data.
"""

from __future__ import annotations

import sqlite3

# Amazon report dates are MM-DD-YY strings; convert to ISO so SQLite date
# functions (julianday, strftime) work on them.
_ISO_DATE = (
    "CASE WHEN length(trim(date))=8 AND substr(date,3,1)='-' "
    "THEN '20'||substr(date,7,2)||'-'||substr(date,1,2)||'-'||substr(date,4,2) END"
)


def _exec(conn: sqlite3.Connection, sql: str) -> None:
    conn.executescript(sql)


def ecommerce(conn: sqlite3.Connection, tables: dict[str, list[str]]) -> list[str]:
    made: list[str] = []

    # Product dimension: a genuine catalogue table that joins to sales on SKU
    # (94% of sale lines match).
    _exec(conn, """
        DROP TABLE IF EXISTS products;
        CREATE TABLE products AS
        SELECT sku_code AS sku, design_no, category AS product_category,
               size AS product_size, color, stock
        FROM raw_sale_report
        WHERE sku_code IS NOT NULL AND trim(sku_code) <> ''
        GROUP BY sku_code;
        CREATE UNIQUE INDEX ix_products_sku ON products(sku);
    """)
    made.append("products")

    # Order lines: typed, ISO-dated fact table.
    _exec(conn, f"""
        DROP TABLE IF EXISTS order_lines;
        CREATE TABLE order_lines AS
        SELECT "index" AS line_id, order_id, {_ISO_DATE} AS order_date,
               status, fulfilment, sales_channel, ship_service_level,
               style, sku, category, size, asin, courier_status,
               CAST(qty AS INTEGER) AS qty, CAST(amount AS REAL) AS amount,
               currency, ship_city, ship_state, ship_postal_code, ship_country,
               b2b, fulfilled_by,
               promotion_ids,
               CASE WHEN promotion_ids IS NULL OR trim(promotion_ids) = ''
                    THEN 0 ELSE 1 END AS has_promotion,
               CASE WHEN promotion_ids IS NULL OR trim(promotion_ids) = '' THEN 0
                    ELSE length(promotion_ids) - length(replace(promotion_ids, ',', '')) + 1
               END AS promotion_count
        FROM raw_amazon_sale_report;
        CREATE INDEX ix_ol_order  ON order_lines(order_id);
        CREATE INDEX ix_ol_sku    ON order_lines(sku);
        CREATE INDEX ix_ol_date   ON order_lines(order_date);
        CREATE INDEX ix_ol_status ON order_lines(status);
        CREATE INDEX ix_ol_city   ON order_lines(ship_city);
    """)
    made.append("order_lines")

    # Order header, aggregated from its lines.
    _exec(conn, """
        DROP TABLE IF EXISTS orders;
        CREATE TABLE orders AS
        SELECT order_id, MIN(order_date) AS order_date, COUNT(*) AS line_count,
               SUM(qty) AS total_qty, ROUND(SUM(amount),2) AS order_amount,
               MAX(status) AS status, MAX(ship_city) AS ship_city,
               MAX(ship_state) AS ship_state, MAX(b2b) AS b2b,
               MAX(fulfilment) AS fulfilment
        FROM order_lines GROUP BY order_id;
        CREATE UNIQUE INDEX ix_orders_id ON orders(order_id);
        CREATE INDEX ix_orders_date ON orders(order_date);
    """)
    made.append("orders")

    # Geography dimension from real shipping columns.
    _exec(conn, """
        DROP TABLE IF EXISTS geography;
        CREATE TABLE geography AS
        SELECT ship_city AS city, ship_state AS state, COUNT(*) AS line_count
        FROM order_lines WHERE ship_city IS NOT NULL AND trim(ship_city) <> ''
        GROUP BY ship_city, ship_state;
        CREATE INDEX ix_geo_city ON geography(city);
    """)
    made.append("geography")

    # International sales: the only file with named customers (172 of them).
    _exec(conn, """
        DROP TABLE IF EXISTS intl_sales;
        CREATE TABLE intl_sales AS
        SELECT "index" AS sale_id, date AS raw_date, months, customer, style, sku,
               size, CAST(NULLIF(trim(pcs),'') AS REAL)  AS pcs,
               CAST(NULLIF(trim(rate),'') AS REAL)       AS rate,
               CAST(NULLIF(trim(gross_amt),'') AS REAL)  AS gross_amt
        FROM raw_international_sale_report
        WHERE customer IS NOT NULL AND trim(customer) <> '';
        CREATE INDEX ix_intl_cust ON intl_sales(customer);
        CREATE INDEX ix_intl_sku  ON intl_sales(sku);
    """)
    made.append("intl_sales")

    _exec(conn, """
        DROP TABLE IF EXISTS intl_customers;
        CREATE TABLE intl_customers AS
        SELECT customer AS customer_name, COUNT(*) AS sale_lines,
               ROUND(SUM(gross_amt),2) AS lifetime_value,
               MIN(raw_date) AS first_seen, MAX(raw_date) AS last_seen
        FROM intl_sales GROUP BY customer;
        CREATE UNIQUE INDEX ix_ic_name ON intl_customers(customer_name);
    """)
    made.append("intl_customers")

    # ---------------------------------------------------------------- pricing
    # The May-2022 and P&L-March-2021 files are a SKU-level price list covering
    # nine marketplaces plus a transfer (cost) price.
    #
    # IMPORTANT, measured: these SKUs do NOT join to the sales files. 0 of 1,330
    # match order_lines, products or intl_sales - it is a different catalogue
    # namespace ('Os206_3141_S' vs 'AN201-RED-M'). Cost-to-actual-revenue margin
    # analysis is therefore NOT possible without inventing a mapping, and is not
    # attempted. What IS real: per-SKU margin against list price, and price
    # dispersion across the nine channels.
    #
    # Dirty values are real too: tp contains '#VALUE!' and the MRP columns
    # contain 'Nill'. The GLOB test turns those into NULL instead of letting
    # CAST silently coerce them to 0 and drag every average down.
    def num(col: str) -> str:
        return f"CASE WHEN trim({col}) GLOB '[0-9]*' THEN CAST({col} AS REAL) END"

    channels = ["ajio_mrp", "amazon_mrp", "amazon_fba_mrp", "flipkart_mrp",
                "limeroad_mrp", "myntra_mrp", "paytm_mrp", "snapdeal_mrp"]
    # qualify with m. - both source tables carry these column names
    chan_sql = ",\n               ".join(f"{num('m.' + c)} AS {c}" for c in channels)
    _exec(conn, f"""
        DROP TABLE IF EXISTS pricing;
        CREATE TABLE pricing AS
        SELECT m.sku, m.style_id, m.catalog, m.category AS price_category,
               {num('m.weight')}        AS weight_kg,
               {num('m.tp')}            AS cost_price,
               {num('p.tp_1')}          AS cost_price_2021_a,
               {num('p.tp_2')}          AS cost_price_2021_b,
               {num('m.mrp_old')}       AS mrp_old,
               {num('m.final_mrp_old')} AS final_mrp_old,
               {chan_sql}
        FROM raw_may_2022 m
        LEFT JOIN raw_p_l_march_2021 p ON m.sku = p.sku;
        CREATE UNIQUE INDEX ix_pricing_sku ON pricing(sku);
        CREATE INDEX ix_pricing_cat ON pricing(price_category);
    """)
    made.append("pricing")

    # Long format: one row per SKU per marketplace. Turns "compare 8 price
    # columns" into a normal GROUP BY instead of eight repeated expressions.
    chan_union = " UNION ALL ".join(
        f"SELECT sku, style_id, catalog, price_category, cost_price, "
        f"'{c.replace('_mrp','')}' AS channel, {c} AS list_price FROM pricing"
        for c in channels
    )
    _exec(conn, f"""
        DROP TABLE IF EXISTS channel_prices;
        CREATE TABLE channel_prices AS {chan_union};
        CREATE INDEX ix_cp_sku     ON channel_prices(sku);
        CREATE INDEX ix_cp_channel ON channel_prices(channel);
    """)
    made.append("channel_prices")

    # The two remaining files are small operational ledgers whose headers are
    # embedded in the first data row rather than the header line. Filtered out
    # here so the numeric columns are usable.
    _exec(conn, """
        DROP TABLE IF EXISTS warehouse_rates;
        CREATE TABLE warehouse_rates AS
        SELECT shiprocket AS line_item,
               unnamed_1  AS shiprocket_rate,
               increff    AS increff_rate
        FROM raw_cloud_warehouse_compersion_chart
        WHERE shiprocket IS NOT NULL AND trim(shiprocket) <> ''
          AND lower(trim(shiprocket)) <> 'heads';
    """)
    made.append("warehouse_rates")

    _exec(conn, """
        DROP TABLE IF EXISTS expenses;
        CREATE TABLE expenses AS
        SELECT expance AS expense_item,
               CASE WHEN trim(unnamed_3) GLOB '[0-9]*'
                    THEN CAST(unnamed_3 AS REAL) END AS amount
        FROM raw_expense_iigf
        WHERE expance IS NOT NULL AND trim(expance) <> ''
          AND lower(trim(expance)) <> 'particular';
    """)
    made.append("expenses")
    return made


def churn(conn: sqlite3.Connection, tables: dict[str, list[str]]) -> list[str]:
    src = "raw_wa_fn_usec_telco_customer_churn"
    made: list[str] = []

    # Split the single wide table into the four entities the domain actually has.
    _exec(conn, f"""
        DROP TABLE IF EXISTS customers;
        CREATE TABLE customers AS
        SELECT customerid AS customer_id, gender, seniorcitizen AS senior_citizen,
               partner, dependents, tenure AS tenure_months, phoneservice AS phone_service,
               multiplelines AS multiple_lines, internetservice AS internet_service,
               contract AS contract_type, paperlessbilling AS paperless_billing,
               paymentmethod AS payment_method
        FROM {src};
        CREATE UNIQUE INDEX ix_cu_id ON customers(customer_id);
        CREATE INDEX ix_cu_contract ON customers(contract_type);
    """)
    made.append("customers")

    _exec(conn, f"""
        DROP TABLE IF EXISTS services;
        CREATE TABLE services AS
        SELECT customerid AS customer_id, onlinesecurity AS online_security,
               onlinebackup AS online_backup, deviceprotection AS device_protection,
               techsupport AS tech_support, streamingtv AS streaming_tv,
               streamingmovies AS streaming_movies
        FROM {src};
        CREATE UNIQUE INDEX ix_sv_id ON services(customer_id);
    """)
    made.append("services")

    # totalcharges ships as text and is blank for the 11 tenure=0 customers -
    # a classic real-data trap, preserved here rather than papered over.
    _exec(conn, f"""
        DROP TABLE IF EXISTS billing;
        CREATE TABLE billing AS
        SELECT customerid AS customer_id,
               CAST(monthlycharges AS REAL) AS monthly_charges,
               CAST(NULLIF(trim(totalcharges),'') AS REAL) AS total_charges
        FROM {src};
        CREATE UNIQUE INDEX ix_bl_id ON billing(customer_id);
    """)
    made.append("billing")

    # No churn_date exists in this dataset. tenure is the only time signal, so
    # cohorts are derived from it relative to the newest observation.
    _exec(conn, f"""
        DROP TABLE IF EXISTS churn;
        CREATE TABLE churn AS
        SELECT customerid AS customer_id, churn AS churn_status,
               date('2024-12-01','start of month',
                    '-'||tenure||' months') AS derived_signup_month
        FROM {src};
        CREATE UNIQUE INDEX ix_ch_id ON churn(customer_id);
        CREATE INDEX ix_ch_status ON churn(churn_status);
    """)
    made.append("churn")
    return made


def hr(conn: sqlite3.Connection, tables: dict[str, list[str]]) -> list[str]:
    src = "raw_employe_performance_dataset"
    made: list[str] = []

    _exec(conn, f"""
        DROP TABLE IF EXISTS employees;
        CREATE TABLE employees AS
        SELECT id AS employee_id, name AS employee_name, age, gender, department,
               CAST(salary AS REAL) AS salary, joining_date, location, session,
               CAST(experience AS INTEGER) AS experience_years, status
        FROM {src};
        CREATE UNIQUE INDEX ix_emp_id ON employees(employee_id);
        CREATE INDEX ix_emp_dept ON employees(department);
    """)
    made.append("employees")

    # Only 502 of 1000 employees have a score. Keeping this as its own table makes
    # the missing half an explicit LEFT JOIN rather than a hidden NULL.
    _exec(conn, f"""
        DROP TABLE IF EXISTS performance;
        CREATE TABLE performance AS
        SELECT id AS employee_id, CAST(performance_score AS REAL) AS performance_score
        FROM {src} WHERE performance_score IS NOT NULL;
        CREATE UNIQUE INDEX ix_perf_id ON performance(employee_id);
    """)
    made.append("performance")

    _exec(conn, """
        DROP TABLE IF EXISTS departments;
        CREATE TABLE departments AS
        SELECT department AS department_name, COUNT(*) AS headcount,
               ROUND(AVG(salary),2) AS avg_salary
        FROM employees GROUP BY department;
    """)
    made.append("departments")
    return made


def food(conn: sqlite3.Connection, tables: dict[str, list[str]]) -> list[str]:
    src = "raw_food_delivery_dataset"
    made: list[str] = []

    _exec(conn, f"""
        DROP TABLE IF EXISTS orders;
        CREATE TABLE orders AS
        SELECT order_id, restaurant_id, customer_id,
               date(order_time) AS order_date, date(delivery_time) AS delivery_date,
               food_item, CAST(delivery_distance AS REAL) AS delivery_distance_km,
               CAST(order_value AS REAL) AS order_value,
               CAST(delivery_delay AS REAL) AS delivery_delay_min,
               delivery_method, traffic_condition, weather_condition,
               route_taken, route_type, traffic_avoidance,
               CAST(route_efficiency AS REAL) AS route_efficiency,
               CAST(small_route AS INTEGER)         AS is_small_route,
               CAST(bike_friendly_route AS INTEGER) AS is_bike_friendly_route
        FROM {src};
        CREATE UNIQUE INDEX ix_fo_id   ON orders(order_id);
        CREATE INDEX ix_fo_rest ON orders(restaurant_id);
        CREATE INDEX ix_fo_cust ON orders(customer_id);
        CREATE INDEX ix_fo_date ON orders(order_date);
    """)
    made.append("orders")

    _exec(conn, f"""
        DROP TABLE IF EXISTS customers;
        CREATE TABLE customers AS
        SELECT customer_id, age, gender, location,
               CAST(order_history AS INTEGER) AS prior_order_count,
               preferred_cuisine, order_frequency, loyalty_program
        FROM {src};
        CREATE UNIQUE INDEX ix_fc_id ON customers(customer_id);
        CREATE INDEX ix_fc_loc ON customers(location);
    """)
    made.append("customers")

    _exec(conn, f"""
        DROP TABLE IF EXISTS order_quality;
        CREATE TABLE order_quality AS
        SELECT order_id, CAST(customer_rating AS INTEGER) AS customer_rating,
               food_temperature, CAST(food_freshness AS INTEGER) AS food_freshness,
               CAST(packaging_quality AS INTEGER) AS packaging_quality, food_condition,
               CAST(customer_satisfaction AS INTEGER) AS customer_satisfaction
        FROM {src};
        CREATE UNIQUE INDEX ix_oq_id ON order_quality(order_id);
    """)
    made.append("order_quality")

    # Restaurant dimension. The source has no restaurant attribute columns, so
    # this is an honest summary of that restaurant's real orders, not invented
    # metadata like a name or cuisine type.
    _exec(conn, """
        DROP TABLE IF EXISTS restaurants;
        CREATE TABLE restaurants AS
        SELECT o.restaurant_id, COUNT(*) AS total_orders,
               ROUND(AVG(o.order_value),2) AS avg_order_value,
               ROUND(AVG(o.delivery_delay_min),2) AS avg_delay_min,
               ROUND(AVG(q.customer_rating),2) AS avg_rating
        FROM orders o LEFT JOIN order_quality q ON o.order_id = q.order_id
        GROUP BY o.restaurant_id;
        CREATE UNIQUE INDEX ix_rest_id ON restaurants(restaurant_id);
    """)
    made.append("restaurants")
    return made


def fraud(conn: sqlite3.Connection, tables: dict[str, list[str]]) -> list[str]:
    made: list[str] = []

    # `time` is seconds since the first transaction and spans exactly 48 hours,
    # so hour-of-day and day-number are legitimately recoverable.
    # ALL 28 PCA components are carried through - every one is a usable feature
    # and restricting to a hand-picked few would pre-empt the feature-selection
    # work that Q9 and Q21 exist to do.
    v_cols = ", ".join(f"v{i}" for i in range(1, 29))
    _exec(conn, f"""
        DROP TABLE IF EXISTS transactions;
        CREATE TABLE transactions AS
        SELECT rowid AS transaction_id,
               CAST(time AS INTEGER) AS seconds_elapsed,
               CAST(time/3600 AS INTEGER) % 24 AS hour_of_day,
               CAST(time/86400 AS INTEGER) + 1 AS day_number,
               ROUND(CAST(amount AS REAL),2) AS amount,
               CAST(class AS INTEGER) AS is_fraud,
               {v_cols}
        FROM raw_creditcard;
        CREATE UNIQUE INDEX ix_tx_id    ON transactions(transaction_id);
        CREATE INDEX ix_tx_fraud ON transactions(is_fraud);
        CREATE INDEX ix_tx_hour  ON transactions(hour_of_day);
        CREATE INDEX ix_tx_amt   ON transactions(amount);
        CREATE INDEX ix_tx_v14   ON transactions(v14);
        CREATE INDEX ix_tx_v17   ON transactions(v17);
    """)
    made.append("transactions")

    # Long-format view of all 28 components. Wide tables are awkward to scan
    # feature-by-feature in SQL; unpivoting once here means a single GROUP BY
    # can rank every component's separation instead of 28 hand-written columns.
    union = " UNION ALL ".join(
        f"SELECT transaction_id, 'V{i}' AS feature, v{i} AS value, is_fraud FROM transactions"
        for i in range(1, 29)
    )
    _exec(conn, f"""
        DROP TABLE IF EXISTS transaction_features;
        CREATE TABLE transaction_features AS {union};
        CREATE INDEX ix_tf_feature ON transaction_features(feature);
        CREATE INDEX ix_tf_fraud   ON transaction_features(is_fraud);
    """)
    made.append("transaction_features")
    return made


RECIPES = {
    "project_1_ecommerce": ecommerce,
    "project_2_churn": churn,
    "project_3_hr": hr,
    "project_4_food": food,
    "project_5_fraud": fraud,
}
