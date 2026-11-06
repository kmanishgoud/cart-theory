-- =====================================================================
-- oracle/export_core_from_postgres.sql
-- Dumps the six core tables the analytics layer needs to CSV.
-- Run against PostgreSQL from the project root (creates oracle/export/ first):
--   mkdir -p oracle/export
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f oracle/export_core_from_postgres.sql
-- Not exported: geolocation, order_payments (no analytics file uses them).
-- =====================================================================
\copy core.customers TO 'oracle/export/customers.csv' WITH (FORMAT csv, HEADER)
\copy core.sellers   TO 'oracle/export/sellers.csv'   WITH (FORMAT csv, HEADER)
\copy core.products  TO 'oracle/export/products.csv'  WITH (FORMAT csv, HEADER)

-- Booleans as 'true'/'false' text; Oracle 23ai converts these into BOOLEAN.
\copy (SELECT order_id, customer_unique_id, status, purchased_at, approved_at, carrier_at, delivered_at, estimated_delivery, has_items::text AS has_items, has_timestamp_issue::text AS has_timestamp_issue FROM core.orders) TO 'oracle/export/orders.csv' WITH (FORMAT csv, HEADER)

\copy core.order_items TO 'oracle/export/order_items.csv' WITH (FORMAT csv, HEADER)

-- Review text can contain line breaks; flattened to spaces so the CSV loads row-per-line.
\copy (SELECT order_id, review_id, score, regexp_replace(comment_title, E'[\\r\\n]+', ' ', 'g') AS comment_title, regexp_replace(comment_message, E'[\\r\\n]+', ' ', 'g') AS comment_message, created_at, answered_at FROM core.order_reviews) TO 'oracle/export/order_reviews.csv' WITH (FORMAT csv, HEADER)
