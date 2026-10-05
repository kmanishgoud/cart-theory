-- =====================================================================
-- 02_load_raw.sql
-- Load the 9 CSVs into the raw schema.
-- Run from the project root (paths are relative to it):
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/02_load_raw.sql
-- =====================================================================

\echo 'Loading raw tables...'

\copy raw.customers            FROM 'data/raw/olist_customers_dataset.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.geolocation          FROM 'data/raw/olist_geolocation_dataset.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.orders               FROM 'data/raw/olist_orders_dataset.csv'             WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.order_items          FROM 'data/raw/olist_order_items_dataset.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.order_payments       FROM 'data/raw/olist_order_payments_dataset.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.order_reviews        FROM 'data/raw/olist_order_reviews_dataset.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.products             FROM 'data/raw/olist_products_dataset.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.sellers              FROM 'data/raw/olist_sellers_dataset.csv'            WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Row counts:'

SELECT 'customers'            AS table_name, COUNT(*) AS row_count FROM raw.customers
UNION ALL SELECT 'geolocation',          COUNT(*) FROM raw.geolocation
UNION ALL SELECT 'orders',               COUNT(*) FROM raw.orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM raw.order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM raw.order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM raw.order_reviews
UNION ALL SELECT 'products',             COUNT(*) FROM raw.products
UNION ALL SELECT 'sellers',              COUNT(*) FROM raw.sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM raw.category_translation
ORDER BY table_name;