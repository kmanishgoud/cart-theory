-- =====================================================================
-- 03_audit.sql
-- Data-quality audit of the raw layer. Read-only: changes nothing.
--   psql -U postgres -d cart_theory -f sql/03_audit.sql
-- =====================================================================

\echo '=== AUDIT: one row per check ==='

-- ---------------------------------------------------------------- 1. KEYS
SELECT '1 Keys' AS area, 'orders: duplicate order_id' AS check_name,
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM raw.orders) AS result
UNION ALL
SELECT '1 Keys', 'customers: duplicate customer_id',
       (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM raw.customers)
UNION ALL
SELECT '1 Keys', 'customers: distinct customer_unique_id (real people)',
       (SELECT COUNT(DISTINCT customer_unique_id) FROM raw.customers)
UNION ALL
SELECT '1 Keys', 'customers: customer_ids with more than one order',
       (SELECT COUNT(*) FROM (SELECT customer_id FROM raw.orders GROUP BY customer_id HAVING COUNT(*) > 1) x)
UNION ALL
SELECT '1 Keys', 'order_items: duplicate (order_id, order_item_id)',
       (SELECT COUNT(*) FROM (SELECT order_id, order_item_id FROM raw.order_items
                              GROUP BY 1, 2 HAVING COUNT(*) > 1) x)
UNION ALL
SELECT '1 Keys', 'payments: duplicate (order_id, payment_sequential)',
       (SELECT COUNT(*) FROM (SELECT order_id, payment_sequential FROM raw.order_payments
                              GROUP BY 1, 2 HAVING COUNT(*) > 1) x)
UNION ALL
SELECT '1 Keys', 'reviews: duplicate review_id rows',
       (SELECT COUNT(*) - COUNT(DISTINCT review_id) FROM raw.order_reviews)
UNION ALL
SELECT '1 Keys', 'reviews: orders with more than one review',
       (SELECT COUNT(*) FROM (SELECT order_id FROM raw.order_reviews GROUP BY order_id HAVING COUNT(*) > 1) x)
UNION ALL
SELECT '1 Keys', 'products: duplicate product_id',
       (SELECT COUNT(*) - COUNT(DISTINCT product_id) FROM raw.products)
UNION ALL
SELECT '1 Keys', 'sellers: duplicate seller_id',
       (SELECT COUNT(*) - COUNT(DISTINCT seller_id) FROM raw.sellers)
UNION ALL
SELECT '1 Keys', 'geolocation: extra rows beyond one per zip prefix',
       (SELECT COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix) FROM raw.geolocation)

-- ---------------------------------------------------------------- 2. ORPHANS
UNION ALL
SELECT '2 Orphans', 'orders whose customer_id is not in customers',
       (SELECT COUNT(*) FROM raw.orders o
        WHERE NOT EXISTS (SELECT 1 FROM raw.customers c WHERE c.customer_id = o.customer_id))
UNION ALL
SELECT '2 Orphans', 'order_items whose order_id is not in orders',
       (SELECT COUNT(*) FROM raw.order_items i
        WHERE NOT EXISTS (SELECT 1 FROM raw.orders o WHERE o.order_id = i.order_id))
UNION ALL
SELECT '2 Orphans', 'order_items whose product_id is not in products',
       (SELECT COUNT(*) FROM raw.order_items i
        WHERE NOT EXISTS (SELECT 1 FROM raw.products p WHERE p.product_id = i.product_id))
UNION ALL
SELECT '2 Orphans', 'order_items whose seller_id is not in sellers',
       (SELECT COUNT(*) FROM raw.order_items i
        WHERE NOT EXISTS (SELECT 1 FROM raw.sellers s WHERE s.seller_id = i.seller_id))
UNION ALL
SELECT '2 Orphans', 'payments whose order_id is not in orders',
       (SELECT COUNT(*) FROM raw.order_payments p
        WHERE NOT EXISTS (SELECT 1 FROM raw.orders o WHERE o.order_id = p.order_id))
UNION ALL
SELECT '2 Orphans', 'reviews whose order_id is not in orders',
       (SELECT COUNT(*) FROM raw.order_reviews r
        WHERE NOT EXISTS (SELECT 1 FROM raw.orders o WHERE o.order_id = r.order_id))
UNION ALL
SELECT '2 Orphans', 'product categories with no English translation',
       (SELECT COUNT(DISTINCT p.product_category_name) FROM raw.products p
        WHERE p.product_category_name IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM raw.category_translation t
                          WHERE t.product_category_name = p.product_category_name))
UNION ALL
SELECT '2 Orphans', 'customers whose zip prefix is not in geolocation',
       (SELECT COUNT(*) FROM raw.customers c
        WHERE NOT EXISTS (SELECT 1 FROM raw.geolocation g
                          WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix))

-- ---------------------------------------------------------------- 3. COVERAGE
UNION ALL
SELECT '3 Coverage', 'orders with no items',
       (SELECT COUNT(*) FROM raw.orders o
        WHERE NOT EXISTS (SELECT 1 FROM raw.order_items i WHERE i.order_id = o.order_id))
UNION ALL
SELECT '3 Coverage', 'orders with no payment',
       (SELECT COUNT(*) FROM raw.orders o
        WHERE NOT EXISTS (SELECT 1 FROM raw.order_payments p WHERE p.order_id = o.order_id))
UNION ALL
SELECT '3 Coverage', 'orders with no review',
       (SELECT COUNT(*) FROM raw.orders o
        WHERE NOT EXISTS (SELECT 1 FROM raw.order_reviews r WHERE r.order_id = o.order_id))
UNION ALL
SELECT '3 Coverage', 'products with no category',
       (SELECT COUNT(*) FROM raw.products WHERE product_category_name IS NULL)

-- ---------------------------------------------------------------- 4. LOGIC
UNION ALL
SELECT '4 Logic', 'delivered orders with no delivery date',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL)
UNION ALL
SELECT '4 Logic', 'approved before purchase',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_approved_at::timestamp < order_purchase_timestamp::timestamp)
UNION ALL
SELECT '4 Logic', 'handed to carrier before purchase',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_delivered_carrier_date::timestamp < order_purchase_timestamp::timestamp)
UNION ALL
SELECT '4 Logic', 'delivered to customer before handed to carrier',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_delivered_customer_date::timestamp < order_delivered_carrier_date::timestamp)

-- ---------------------------------------------------------------- 5. VALUES
UNION ALL
SELECT '5 Values', 'items with price <= 0',
       (SELECT COUNT(*) FROM raw.order_items WHERE price::numeric <= 0)
UNION ALL
SELECT '5 Values', 'payments with value = 0',
       (SELECT COUNT(*) FROM raw.order_payments WHERE payment_value::numeric = 0)
UNION ALL
SELECT '5 Values', 'payments with type not_defined',
       (SELECT COUNT(*) FROM raw.order_payments WHERE payment_type = 'not_defined')
UNION ALL
SELECT '5 Values', 'payments with 0 instalments',
       (SELECT COUNT(*) FROM raw.order_payments WHERE payment_installments::int = 0)
UNION ALL
SELECT '5 Values', 'orders where payments differ from items + freight by > 1 BRL',
       (SELECT COUNT(*)
        FROM (SELECT order_id, SUM(price::numeric + freight_value::numeric) AS items_total
              FROM raw.order_items GROUP BY order_id) i
        JOIN (SELECT order_id, SUM(payment_value::numeric) AS paid
              FROM raw.order_payments GROUP BY order_id) p USING (order_id)
        WHERE ABS(p.paid - i.items_total) > 1)
ORDER BY area, check_name;


\echo '=== Order status ==='
SELECT order_status, COUNT(*) AS orders
FROM raw.orders
GROUP BY order_status
ORDER BY orders DESC;


\echo '=== Orders per month ==='
SELECT DATE_TRUNC('month', order_purchase_timestamp::timestamp)::date AS month,
       COUNT(*) AS orders
FROM raw.orders
GROUP BY 1
ORDER BY 1;