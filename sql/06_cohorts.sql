-- =====================================================================
-- 06_cohorts.sql
-- Analytics layer, part 2: repeat purchases and cohort retention.
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/06_cohorts.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- customer_orders: every delivered order with its position in the
-- customer's history.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.customer_orders AS
SELECT f.customer_unique_id,
       f.order_id,
       f.purchased_at,
       f.order_month,
       f.revenue,
       ROW_NUMBER() OVER (PARTITION BY f.customer_unique_id
                          ORDER BY f.purchased_at, f.order_id)     AS order_number,
       MIN(f.order_month) OVER (PARTITION BY f.customer_unique_id) AS cohort_month,
       f.purchased_at::date - LAG(f.purchased_at::date) OVER (PARTITION BY f.customer_unique_id
                                                               ORDER BY f.purchased_at, f.order_id)
                                                                   AS days_since_previous
FROM analytics.order_facts f;

-- ---------------------------------------------------------------------
-- cohort_retention: long format, one row per cohort x months-since-first-order.
-- A full grid (generate_series) guarantees months with zero returning
-- customers appear as 0% instead of disappearing.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.cohort_retention AS
WITH activity AS (
    SELECT DISTINCT
           customer_unique_id,
           cohort_month,
           ((EXTRACT(YEAR  FROM order_month) - EXTRACT(YEAR  FROM cohort_month)) * 12
          +  EXTRACT(MONTH FROM order_month) - EXTRACT(MONTH FROM cohort_month))::int AS months_since
    FROM analytics.customer_orders
    WHERE order_month <= DATE '2018-08-01'
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM activity
    WHERE months_since = 0
      AND cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
    GROUP BY cohort_month
),
grid AS (
    SELECT s.cohort_month, s.cohort_size, k AS months_since
    FROM sizes s
    CROSS JOIN generate_series(0, 19) AS k
    WHERE s.cohort_month + MAKE_INTERVAL(months => k) <= DATE '2018-08-01'
)
SELECT g.cohort_month,
       g.cohort_size,
       g.months_since,
       COUNT(DISTINCT a.customer_unique_id)                                      AS active_customers,
       ROUND(100.0 * COUNT(DISTINCT a.customer_unique_id) / g.cohort_size, 2)    AS retention_pct
FROM grid g
LEFT JOIN activity a
       ON a.cohort_month = g.cohort_month
      AND a.months_since = g.months_since
GROUP BY g.cohort_month, g.cohort_size, g.months_since;

-- ---------------------------------------------------------------------
-- cohort_matrix: the classic triangle, pivoted with conditional aggregation.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.cohort_matrix AS
SELECT cohort_month,
       cohort_size,
       MAX(retention_pct) FILTER (WHERE months_since = 1)  AS m1,
       MAX(retention_pct) FILTER (WHERE months_since = 2)  AS m2,
       MAX(retention_pct) FILTER (WHERE months_since = 3)  AS m3,
       MAX(retention_pct) FILTER (WHERE months_since = 6)  AS m6,
       MAX(retention_pct) FILTER (WHERE months_since = 12) AS m12
FROM analytics.cohort_retention
GROUP BY cohort_month, cohort_size
ORDER BY cohort_month;


-- =====================================================================
-- Results
-- =====================================================================

\echo '=== Repeat purchase summary ==='
WITH per_customer AS (
    SELECT customer_unique_id,
           COUNT(*)                          AS orders,
           COUNT(DISTINCT purchased_at::date) AS order_days,
           SUM(revenue)                      AS revenue
    FROM analytics.customer_orders
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                                         AS customers,
       COUNT(*) FILTER (WHERE orders >= 2)                              AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2) / COUNT(*), 2) AS repeat_rate_pct,
       COUNT(*) FILTER (WHERE order_days >= 2)                          AS repeat_on_another_day,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_days >= 2) / COUNT(*), 2) AS true_repeat_rate_pct,
       ROUND(100.0 * SUM(revenue) FILTER (WHERE orders >= 2) / SUM(revenue), 1) AS repeat_revenue_share_pct
FROM per_customer;

\echo '=== Orders per customer ==='
SELECT CASE WHEN orders >= 4 THEN '4+' ELSE orders::text END AS orders_per_customer,
       COUNT(*)                                              AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)    AS share_pct
FROM (SELECT customer_unique_id, COUNT(*) AS orders
      FROM analytics.customer_orders GROUP BY 1) x
GROUP BY 1
ORDER BY 1;

\echo '=== Time to second order ==='
SELECT COUNT(*)                                                   AS second_orders,
       COUNT(*) FILTER (WHERE days_since_previous = 0)            AS same_day,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_since_previous = 0) / COUNT(*), 1) AS same_day_pct,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_since_previous)
           FILTER (WHERE days_since_previous > 0)                 AS median_days_excl_same_day
FROM analytics.customer_orders
WHERE order_number = 2;

\echo '=== Cohort matrix: % of each cohort buying again N months later ==='
SELECT * FROM analytics.cohort_matrix;

\echo '=== Average retention curve (weighted by cohort size) ==='
SELECT months_since,
       SUM(cohort_size)                                              AS customers_observed,
       ROUND(100.0 * SUM(active_customers) / SUM(cohort_size), 2)    AS retention_pct
FROM analytics.cohort_retention
WHERE months_since BETWEEN 1 AND 12
GROUP BY months_since
ORDER BY months_since;