-- =====================================================================
-- oracle/05_revenue.sql
-- Analytics layer, part 1: order facts and monthly revenue trends (Oracle 23ai).
-- Run as ANALYTICS from the project root:
--   sql analytics/CartTheory_1@localhost:1521/FREEPDB1 @oracle/05_revenue.sql
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';
SET LINESIZE 200 PAGESIZE 100 FEEDBACK ON

-- ---------------------------------------------------------------------
-- order_facts: one row per DELIVERED order with items.
-- Revenue = item prices + freight (what the customer paid, excl. instalment interest).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.order_facts AS
SELECT o.order_id,
       o.customer_unique_id,
       o.purchased_at,
       TRUNC(o.purchased_at, 'MM')                AS order_month,
       COUNT(*)                                   AS items,
       COUNT(DISTINCT i.seller_id)                AS sellers,
       SUM(i.price)                               AS product_value,
       SUM(i.freight)                             AS freight,
       SUM(i.price + i.freight)                   AS revenue
FROM core.orders o
JOIN core.order_items i ON i.order_id = o.order_id
WHERE o.status = 'delivered'
GROUP BY o.order_id, o.customer_unique_id, o.purchased_at;

-- ---------------------------------------------------------------------
-- monthly_revenue: trends for the reliable period (Jan 2017 - Aug 2018).
-- Audit: 2016 and Sep-Oct 2018 contain only a handful of orders.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.monthly_revenue AS
WITH monthly AS (
    SELECT order_month,
           COUNT(*)                            AS orders,
           COUNT(DISTINCT customer_unique_id)  AS customers,
           SUM(revenue)                        AS revenue
    FROM analytics.order_facts
    WHERE order_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
    GROUP BY order_month
)
SELECT order_month,
       orders,
       customers,
       ROUND(revenue, 0)                                              AS revenue,
       ROUND(revenue / orders, 2)                                     AS avg_order_value,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
                 / LAG(revenue) OVER (ORDER BY order_month), 1)       AS mom_growth_pct,
       ROUND(AVG(revenue) OVER (ORDER BY order_month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0)
                                                                      AS revenue_3m_avg,
       ROUND(SUM(revenue) OVER (ORDER BY order_month), 0)             AS running_revenue,
       ROUND(100 * (revenue - LAG(revenue, 12) OVER (ORDER BY order_month))
                 / LAG(revenue, 12) OVER (ORDER BY order_month), 1)   AS yoy_growth_pct
FROM monthly;


-- =====================================================================
-- Results
-- =====================================================================

PROMPT === Headline numbers (all delivered orders) ===
SELECT COUNT(*)                                       AS delivered_orders,
       COUNT(DISTINCT customer_unique_id)             AS customers,
       ROUND(SUM(revenue), 0)                         AS revenue_brl,
       ROUND(AVG(revenue), 2)                         AS avg_order_value,
       ROUND(100 * SUM(freight) / SUM(revenue), 1)    AS freight_share_pct
FROM analytics.order_facts;

PROMPT === Monthly revenue ===
SELECT * FROM analytics.monthly_revenue ORDER BY order_month;

PROMPT === Busiest days ===
SELECT TRUNC(purchased_at)                                        AS order_day,
       TO_CHAR(purchased_at, 'Dy', 'NLS_DATE_LANGUAGE=ENGLISH')   AS weekday,
       COUNT(*)                                                   AS orders,
       ROUND(SUM(revenue), 0)                                     AS revenue
FROM analytics.order_facts
GROUP BY TRUNC(purchased_at), TO_CHAR(purchased_at, 'Dy', 'NLS_DATE_LANGUAGE=ENGLISH')
ORDER BY orders DESC
FETCH FIRST 5 ROWS ONLY;

EXIT
