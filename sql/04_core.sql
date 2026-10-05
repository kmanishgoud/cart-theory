-- =====================================================================
-- 04_core.sql
-- Core layer: typed, keyed, cleaned tables built from raw.
-- Every rule here comes from a finding in 03_audit.sql.
-- Runs as one transaction: it either fully succeeds or changes nothing.
--   psql -U postgres -d cart_theory -v ON_ERROR_STOP=1 -f sql/04_core.sql
-- =====================================================================

BEGIN;

DROP SCHEMA IF EXISTS core CASCADE;
CREATE SCHEMA core;

-- ------------------------------------------------------------- geolocation
-- Audit: ~1M rows for ~19k zip prefixes -> one row per prefix, average coordinates.
-- Points outside Brazil's bounding box are ignored (bad GPS data).
CREATE TABLE core.geolocation (
    zip_prefix  CHAR(5) PRIMARY KEY,
    lat         NUMERIC(9,6) NOT NULL,
    lng         NUMERIC(9,6) NOT NULL,
    city        TEXT,
    state       CHAR(2)
);

INSERT INTO core.geolocation
SELECT LPAD(geolocation_zip_code_prefix, 5, '0'),
       AVG(geolocation_lat::numeric)::numeric(9,6),
       AVG(geolocation_lng::numeric)::numeric(9,6),
       MIN(geolocation_city),
       MIN(geolocation_state)
FROM raw.geolocation
WHERE geolocation_lat::numeric BETWEEN -34 AND 6
  AND geolocation_lng::numeric BETWEEN -74 AND -34
GROUP BY 1;

-- ------------------------------------------------------------- customers
-- Audit: customer_id is per ORDER. The real person is customer_unique_id.
-- One row per person, using the address from their most recent order.
CREATE TABLE core.customers (
    customer_unique_id  TEXT PRIMARY KEY,
    zip_prefix          CHAR(5),
    city                TEXT,
    state               CHAR(2)
);

INSERT INTO core.customers
SELECT DISTINCT ON (c.customer_unique_id)
       c.customer_unique_id,
       LPAD(c.customer_zip_code_prefix, 5, '0'),
       c.customer_city,
       c.customer_state
FROM raw.customers c
JOIN raw.orders o ON o.customer_id = c.customer_id
ORDER BY c.customer_unique_id, o.order_purchase_timestamp::timestamp DESC;

-- ------------------------------------------------------------- sellers
CREATE TABLE core.sellers (
    seller_id   TEXT PRIMARY KEY,
    zip_prefix  CHAR(5),
    city        TEXT,
    state       CHAR(2)
);

INSERT INTO core.sellers
SELECT seller_id, LPAD(seller_zip_code_prefix, 5, '0'), seller_city, seller_state
FROM raw.sellers;

-- ------------------------------------------------------------- products
-- Audit: 610 products without a category -> 'unknown';
--        2 categories missing from the translation table -> translated here.
-- Also fixes the source's misspelt 'lenght' columns.
CREATE TABLE core.products (
    product_id          TEXT PRIMARY KEY,
    category            TEXT NOT NULL,      -- English
    category_pt         TEXT,               -- original Portuguese
    name_length         INT,
    description_length  INT,
    photos_qty          INT,
    weight_g            INT,
    length_cm           INT,
    height_cm           INT,
    width_cm            INT
);

INSERT INTO core.products
SELECT p.product_id,
       COALESCE(
           t.product_category_name_english,
           CASE p.product_category_name
               WHEN 'pc_gamer' THEN 'pc_gamer'
               WHEN 'portateis_cozinha_e_preparadores_de_alimentos' THEN 'portable_kitchen_food_preparers'
           END,
           'unknown'),
       p.product_category_name,
       p.product_name_lenght::numeric::int,
       p.product_description_lenght::numeric::int,
       p.product_photos_qty::numeric::int,
       p.product_weight_g::numeric::int,
       p.product_length_cm::numeric::int,
       p.product_height_cm::numeric::int,
       p.product_width_cm::numeric::int
FROM raw.products p
LEFT JOIN raw.category_translation t USING (product_category_name);

-- ------------------------------------------------------------- orders
-- Audit: 775 orders without items -> has_items flag.
--        166 + 23 + 8 impossible/missing delivery timestamps -> has_timestamp_issue flag.
CREATE TABLE core.orders (
    order_id             TEXT PRIMARY KEY,
    customer_unique_id   TEXT NOT NULL REFERENCES core.customers,
    status               TEXT NOT NULL,
    purchased_at         TIMESTAMP NOT NULL,
    approved_at          TIMESTAMP,
    carrier_at           TIMESTAMP,
    delivered_at         TIMESTAMP,
    estimated_delivery   TIMESTAMP,
    has_items            BOOLEAN NOT NULL,
    has_timestamp_issue  BOOLEAN NOT NULL
);

INSERT INTO core.orders
WITH typed AS (
    SELECT o.order_id,
           c.customer_unique_id,
           o.order_status                                AS status,
           o.order_purchase_timestamp::timestamp         AS purchased_at,
           o.order_approved_at::timestamp                AS approved_at,
           o.order_delivered_carrier_date::timestamp     AS carrier_at,
           o.order_delivered_customer_date::timestamp    AS delivered_at,
           o.order_estimated_delivery_date::timestamp    AS estimated_delivery
    FROM raw.orders o
    JOIN raw.customers c USING (customer_id)
)
SELECT t.*,
       EXISTS (SELECT 1 FROM raw.order_items i WHERE i.order_id = t.order_id),
       COALESCE(t.carrier_at < t.purchased_at, FALSE)
         OR COALESCE(t.delivered_at < t.carrier_at, FALSE)
         OR (t.status = 'delivered' AND t.delivered_at IS NULL)
FROM typed t;

-- ------------------------------------------------------------- order_items
CREATE TABLE core.order_items (
    order_id          TEXT NOT NULL REFERENCES core.orders,
    item_seq          INT  NOT NULL,
    product_id        TEXT NOT NULL REFERENCES core.products,
    seller_id         TEXT NOT NULL REFERENCES core.sellers,
    shipping_limit_at TIMESTAMP,
    price             NUMERIC(10,2) NOT NULL CHECK (price > 0),
    freight           NUMERIC(10,2) NOT NULL CHECK (freight >= 0),
    PRIMARY KEY (order_id, item_seq)
);

INSERT INTO core.order_items
SELECT order_id, order_item_id::int, product_id, seller_id,
       shipping_limit_date::timestamp, price::numeric, freight_value::numeric
FROM raw.order_items;

-- ------------------------------------------------------------- order_payments
-- Audit: a few oddities (zero values, 'not_defined', 0 instalments): kept, documented.
CREATE TABLE core.order_payments (
    order_id      TEXT NOT NULL REFERENCES core.orders,
    payment_seq   INT  NOT NULL,
    payment_type  TEXT NOT NULL,
    installments  INT  NOT NULL,
    amount        NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (order_id, payment_seq)
);

INSERT INTO core.order_payments
SELECT order_id, payment_sequential::int, payment_type,
       payment_installments::int, payment_value::numeric
FROM raw.order_payments;

-- ------------------------------------------------------------- order_reviews
-- Audit: duplicate review_ids and 547 orders with several reviews
--        -> exactly one review per order (the most recently answered).
CREATE TABLE core.order_reviews (
    order_id         TEXT PRIMARY KEY REFERENCES core.orders,
    review_id        TEXT NOT NULL,
    score            SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment_title    TEXT,
    comment_message  TEXT,
    created_at       TIMESTAMP,
    answered_at      TIMESTAMP
);

INSERT INTO core.order_reviews
SELECT order_id, review_id, review_score::smallint, review_comment_title,
       review_comment_message, review_creation_date::timestamp, review_answer_timestamp::timestamp
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY r.order_id
               ORDER BY r.review_answer_timestamp::timestamp DESC NULLS LAST,
                        r.review_creation_date::timestamp DESC
           ) AS rn
    FROM raw.order_reviews r
) ranked
WHERE rn = 1;

-- ------------------------------------------------------------- indexes
-- Speed up the joins and date filters the analytics layer will use.
CREATE INDEX ON core.orders (customer_unique_id);
CREATE INDEX ON core.orders (purchased_at);
CREATE INDEX ON core.order_items (product_id);
CREATE INDEX ON core.order_items (seller_id);

COMMIT;

ANALYZE;    -- refresh the query planner's statistics

-- ------------------------------------------------------------- sanity check
\echo 'Core layer row counts:'
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM core.customers
UNION ALL SELECT 'geolocation',    COUNT(*) FROM core.geolocation
UNION ALL SELECT 'order_items',    COUNT(*) FROM core.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM core.order_payments
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM core.order_reviews
UNION ALL SELECT 'orders',         COUNT(*) FROM core.orders
UNION ALL SELECT 'products',       COUNT(*) FROM core.products
UNION ALL SELECT 'sellers',        COUNT(*) FROM core.sellers
ORDER BY table_name;

\echo 'Flags:'
SELECT COUNT(*) FILTER (WHERE NOT has_items)         AS orders_without_items,
       COUNT(*) FILTER (WHERE has_timestamp_issue)   AS orders_with_timestamp_issue,
       (SELECT COUNT(*) FROM core.products WHERE category = 'unknown') AS products_unknown_category
FROM core.orders;