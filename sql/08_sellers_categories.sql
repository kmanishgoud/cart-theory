-- =====================================================================
-- 08_sellers_categories.sql
-- Analytics layer, part 4: category and seller performance.
-- Sales = item prices (excl. freight), delivered orders only.
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/08_sellers_categories.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- item_facts: one row per delivered item, with product, seller and review.
-- Note: reviews are per ORDER; multi-seller orders share one review.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.item_facts AS
SELECT i.order_id,
       i.item_seq,
       i.product_id,
       p.category,
       i.seller_id,
       s.state                                   AS seller_state,
       o.customer_unique_id,
       o.purchased_at,
       DATE_TRUNC('month', o.purchased_at)::date AS order_month,
       i.price,
       i.freight,
       r.score                                   AS review_score
FROM core.order_items i
JOIN core.orders   o USING (order_id)
JOIN core.products p USING (product_id)
JOIN core.sellers  s USING (seller_id)
LEFT JOIN core.order_reviews r USING (order_id)
WHERE o.status = 'delivered';

-- ---------------------------------------------------------------------
-- category_performance: ranking + Pareto (cumulative share of sales).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.category_performance AS
WITH cat AS (
    SELECT category,
           COUNT(DISTINCT order_id)  AS orders,
           COUNT(*)                  AS items,
           SUM(price)                AS sales,
           AVG(price)                AS avg_price,
           AVG(review_score)         AS avg_review
    FROM analytics.item_facts
    GROUP BY category
)
SELECT RANK() OVER (ORDER BY sales DESC)                       AS sales_rank,
       category,
       orders,
       items,
       ROUND(sales, 0)                                         AS sales,
       ROUND(avg_price, 2)                                     AS avg_price,
       ROUND(avg_review, 2)                                    AS avg_review,
       ROUND(100.0 * sales / SUM(sales) OVER (), 2)            AS share_pct,
       ROUND(100.0 * SUM(sales) OVER (ORDER BY sales DESC
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / SUM(sales) OVER (), 1)                    AS cumulative_share_pct
FROM cat;

-- ---------------------------------------------------------------------
-- seller_performance: national rank, rank within state, sales decile.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.seller_performance AS
WITH s AS (
    SELECT seller_id,
           seller_state,
           COUNT(DISTINCT order_id)  AS orders,
           SUM(price)                AS sales,
           AVG(review_score)         AS avg_review,
           COUNT(DISTINCT category)  AS categories
    FROM analytics.item_facts
    GROUP BY seller_id, seller_state
)
SELECT seller_id,
       seller_state,
       orders,
       ROUND(sales, 0)                                              AS sales,
       ROUND(avg_review, 2)                                         AS avg_review,
       categories,
       RANK()   OVER (ORDER BY sales DESC)                          AS national_rank,
       RANK()   OVER (PARTITION BY seller_state ORDER BY sales DESC) AS state_rank,
       NTILE(10) OVER (ORDER BY sales DESC)                         AS sales_decile,
       ROUND(100.0 * sales / SUM(sales) OVER (), 3)                 AS share_pct
FROM s;


-- =====================================================================
-- Results
-- =====================================================================

\echo '=== Top 15 categories by sales ==='
SELECT sales_rank, category, orders, sales, avg_price, avg_review, share_pct, cumulative_share_pct
FROM analytics.category_performance
ORDER BY sales_rank
LIMIT 15;

\echo '=== Pareto: how many categories make 80% of sales? ==='
SELECT MIN(sales_rank) FILTER (WHERE cumulative_share_pct >= 80) AS categories_for_80pct,
       COUNT(*)                                                  AS total_categories
FROM analytics.category_performance;

\echo '=== Fastest-growing categories: Jan-Aug 2018 vs Jan-Aug 2017 (min R$50k in 2017) ==='
SELECT category,
       ROUND(sales_2017, 0)                                  AS sales_2017,
       ROUND(sales_2018, 0)                                  AS sales_2018,
       ROUND(100.0 * (sales_2018 - sales_2017) / sales_2017, 1) AS growth_pct
FROM (
    SELECT category,
           SUM(price) FILTER (WHERE order_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS sales_2017,
           SUM(price) FILTER (WHERE order_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01') AS sales_2018
    FROM analytics.item_facts
    GROUP BY category
) x
WHERE sales_2017 >= 50000
ORDER BY growth_pct DESC
LIMIT 10;

\echo '=== Seller concentration by sales decile ==='
SELECT sales_decile,
       COUNT(*)                          AS sellers,
       ROUND(SUM(share_pct), 1)          AS sales_share_pct,
       ROUND(AVG(orders))                AS avg_orders,
       ROUND(AVG(avg_review), 2)         AS avg_review
FROM analytics.seller_performance
GROUP BY sales_decile
ORDER BY sales_decile;

\echo '=== Sellers by state (top 8) ==='
SELECT seller_state,
       COUNT(*)                     AS sellers,
       ROUND(SUM(share_pct), 1)     AS sales_share_pct
FROM analytics.seller_performance
GROUP BY seller_state
ORDER BY sales_share_pct DESC
LIMIT 8;

\echo '=== Top 10 sellers ==='
SELECT national_rank,
       LEFT(seller_id, 8) || '…'   AS seller,
       seller_state,
       orders,
       sales,
       avg_review,
       categories
FROM analytics.seller_performance
WHERE national_rank <= 10
ORDER BY national_rank;

\echo '=== Lowest-rated high-volume sellers (100+ orders) ==='
SELECT LEFT(seller_id, 8) || '…'   AS seller,
       seller_state,
       orders,
       sales,
       avg_review
FROM analytics.seller_performance
WHERE orders >= 100
ORDER BY avg_review
LIMIT 5;