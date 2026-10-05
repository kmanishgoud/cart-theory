-- =====================================================================
-- 09_delivery_reviews.sql
-- Analytics layer, part 5: delivery performance, reviews, and whether
-- the first experience predicts a customer coming back.
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/09_delivery_reviews.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- delivery_facts: delivered orders with reliable timestamps.
-- days_late > 0 means delivered after the date promised at checkout.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.delivery_facts AS
SELECT o.order_id,
       o.customer_unique_id,
       c.state                                                      AS customer_state,
       o.purchased_at,
       DATE_TRUNC('month', o.purchased_at)::date                    AS order_month,
       ROUND(EXTRACT(EPOCH FROM (o.delivered_at - o.purchased_at)) / 86400.0, 1) AS delivery_days,
       o.delivered_at::date - o.estimated_delivery::date            AS days_late,
       o.delivered_at::date > o.estimated_delivery::date            AS is_late,
       r.score                                                      AS review_score
FROM core.orders o
JOIN core.customers c USING (customer_unique_id)
LEFT JOIN core.order_reviews r USING (order_id)
WHERE o.status = 'delivered'
  AND o.delivered_at IS NOT NULL
  AND NOT o.has_timestamp_issue;

-- ---------------------------------------------------------------------
-- review_by_delivery: review scores by how early/late the order arrived.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.review_by_delivery AS
SELECT CASE
           WHEN days_late <= -8 THEN '1. 8+ days early'
           WHEN days_late <= -1 THEN '2. 1-7 days early'
           WHEN days_late =   0 THEN '3. on the promised day'
           WHEN days_late <=  3 THEN '4. 1-3 days late'
           WHEN days_late <=  7 THEN '5. 4-7 days late'
           WHEN days_late <= 14 THEN '6. 8-14 days late'
           ELSE                      '7. 15+ days late'
       END                                                       AS delivery_vs_promise,
       COUNT(*)                                                  AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS orders_pct,
       ROUND(AVG(review_score), 2)                               AS avg_review,
       ROUND(100.0 * AVG((review_score = 1)::int), 1)            AS one_star_pct,
       ROUND(100.0 * AVG((review_score = 5)::int), 1)            AS five_star_pct
FROM analytics.delivery_facts
WHERE review_score IS NOT NULL
GROUP BY 1;


-- =====================================================================
-- Results
-- =====================================================================

\echo '=== Delivery headline ==='
SELECT COUNT(*)                                                           AS orders,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)         AS median_delivery_days,
       ROUND(100.0 * AVG(is_late::int), 1)                                AS late_pct,
       ROUND(AVG(review_score) FILTER (WHERE NOT is_late), 2)             AS avg_review_on_time,
       ROUND(AVG(review_score) FILTER (WHERE is_late), 2)                 AS avg_review_late,
       ROUND(-AVG(days_late) FILTER (WHERE NOT is_late), 1)               AS avg_days_early_when_on_time
FROM analytics.delivery_facts;

\echo '=== Review score by delivery vs promise ==='
SELECT * FROM analytics.review_by_delivery ORDER BY delivery_vs_promise;

\echo '=== Delivery by customer state (500+ orders), slowest first ==='
SELECT customer_state,
       COUNT(*)                                                    AS orders,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)  AS median_days,
       ROUND(100.0 * AVG(is_late::int), 1)                         AS late_pct,
       ROUND(AVG(review_score), 2)                                 AS avg_review
FROM analytics.delivery_facts
GROUP BY customer_state
HAVING COUNT(*) >= 500
ORDER BY median_days DESC;

\echo '=== Late rate by month ==='
SELECT order_month,
       COUNT(*)                               AS orders,
       ROUND(100.0 * AVG(is_late::int), 1)    AS late_pct,
       ROUND(AVG(review_score), 2)            AS avg_review
FROM analytics.delivery_facts
WHERE order_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY order_month
ORDER BY order_month;

\echo '=== Does the FIRST order experience predict coming back? ==='
WITH firsts AS (
    SELECT co.customer_unique_id, d.is_late, d.review_score
    FROM analytics.customer_orders co
    JOIN analytics.delivery_facts d USING (order_id)
    WHERE co.order_number = 1
),
returners AS (              -- bought again on a later day (same-day orders excluded)
    SELECT DISTINCT customer_unique_id
    FROM analytics.customer_orders
    WHERE order_number >= 2 AND days_since_previous > 0
)
SELECT 'Review: ' || CASE
           WHEN f.review_score IS NULL THEN 'none'
           WHEN f.review_score >= 4    THEN '4-5 stars'
           WHEN f.review_score = 3     THEN '3 stars'
           ELSE                             '1-2 stars'
       END                                                         AS first_order,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * AVG((r.customer_unique_id IS NOT NULL)::int), 2) AS came_back_pct
FROM firsts f
LEFT JOIN returners r USING (customer_unique_id)
GROUP BY 1
UNION ALL
SELECT 'Delivery: ' || CASE WHEN f.is_late THEN 'late' ELSE 'on time' END,
       COUNT(*),
       ROUND(100.0 * AVG((r.customer_unique_id IS NOT NULL)::int), 2)
FROM firsts f
LEFT JOIN returners r USING (customer_unique_id)
GROUP BY 1
ORDER BY 1;