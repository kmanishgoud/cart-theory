-- =====================================================================
-- 07_rfm.sql
-- Analytics layer, part 3: RFM customer segmentation.
-- Adapted to this data: 97% of customers have one order, so frequency
-- is used as "one-time vs repeat" instead of quintiles.
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/07_rfm.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- customer_rfm: one row per customer with R, F, M, scores and segment.
-- Recency is measured from the day after the last order in the data.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.customer_rfm AS
WITH ref AS (
    SELECT MAX(purchased_at)::date + 1 AS ref_date
    FROM analytics.order_facts
),
base AS (
    SELECT f.customer_unique_id,
           r.ref_date - MAX(f.purchased_at)::date  AS recency_days,
           COUNT(*)                                AS frequency,
           SUM(f.revenue)                          AS monetary
    FROM analytics.order_facts f
    CROSS JOIN ref r
    GROUP BY f.customer_unique_id, r.ref_date
),
scored AS (
    SELECT b.*,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- 5 = most recent
           NTILE(5) OVER (ORDER BY monetary)          AS m_score    -- 5 = highest spend
    FROM base b
)
SELECT s.*,
       CASE
           WHEN frequency >= 2 AND r_score >= 4 THEN 'Champions'
           WHEN frequency >= 2                  THEN 'Loyal, lapsing'
           WHEN r_score >= 4 AND m_score >= 4   THEN 'New big spenders'
           WHEN r_score >= 4                    THEN 'New, low spend'
           WHEN r_score = 3                     THEN 'Cooling off'
           WHEN m_score >= 4                    THEN 'Lost big spenders'
           ELSE                                      'Lost, low spend'
       END AS segment
FROM scored s;

-- ---------------------------------------------------------------------
-- rfm_segment_summary: what each segment is worth.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.rfm_segment_summary AS
SELECT segment,
       COUNT(*)                                                      AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS customers_pct,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)  AS revenue_pct,
       ROUND(AVG(recency_days))                                      AS avg_recency_days,
       ROUND(AVG(frequency), 2)                                      AS avg_orders,
       ROUND(AVG(monetary), 2)                                       AS avg_spend
FROM analytics.customer_rfm
GROUP BY segment;


-- =====================================================================
-- Results
-- =====================================================================

\echo '=== Why frequency quintiles fail on this data ==='
SELECT f_quintile,
       MIN(frequency) AS min_orders,
       MAX(frequency) AS max_orders,
       COUNT(*)       AS customers
FROM (SELECT frequency, NTILE(5) OVER (ORDER BY frequency) AS f_quintile
      FROM analytics.customer_rfm) x
GROUP BY f_quintile
ORDER BY f_quintile;

\echo '=== Score boundaries ==='
SELECT 'R' AS dimension, r_score AS score,
       MIN(recency_days) AS low, MAX(recency_days) AS high
FROM analytics.customer_rfm GROUP BY r_score
UNION ALL
SELECT 'M', m_score, ROUND(MIN(monetary)), ROUND(MAX(monetary))
FROM analytics.customer_rfm GROUP BY m_score
ORDER BY dimension, score;

\echo '=== Segments ==='
SELECT * FROM analytics.rfm_segment_summary
ORDER BY revenue_pct DESC;