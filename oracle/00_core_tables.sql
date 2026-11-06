-- =====================================================================
-- oracle/00_core_tables.sql
-- Recreates the PostgreSQL core tables in the CORE schema and loads the CSVs.
-- The cleaning logic stays in PostgreSQL (04_core.sql); this only copies the result.
-- Run as CORE from the project root, after export_core_from_postgres.sql:
--   sql core/CartTheory_1@localhost:1521/FREEPDB1 @oracle/00_core_tables.sql
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';

-- children first so the foreign keys don't block the drops
DROP TABLE IF EXISTS order_reviews PURGE;
DROP TABLE IF EXISTS order_items   PURGE;
DROP TABLE IF EXISTS orders        PURGE;
DROP TABLE IF EXISTS products      PURGE;
DROP TABLE IF EXISTS sellers       PURGE;
DROP TABLE IF EXISTS customers     PURGE;

CREATE TABLE customers (
    customer_unique_id  VARCHAR2(50) PRIMARY KEY,
    zip_prefix          CHAR(5),
    city                VARCHAR2(100),
    state               CHAR(2)
);

CREATE TABLE sellers (
    seller_id   VARCHAR2(50) PRIMARY KEY,
    zip_prefix  CHAR(5),
    city        VARCHAR2(100),
    state       CHAR(2)
);

CREATE TABLE products (
    product_id          VARCHAR2(50) PRIMARY KEY,
    category            VARCHAR2(100) NOT NULL,
    category_pt         VARCHAR2(100),
    name_length         NUMBER(10),
    description_length  NUMBER(10),
    photos_qty          NUMBER(10),
    weight_g            NUMBER(10),
    length_cm           NUMBER(10),
    height_cm           NUMBER(10),
    width_cm            NUMBER(10)
);

-- DATE in Oracle stores date + time to the second, matching the source timestamps,
-- and DATE - DATE gives days as a number (used by 09_delivery_reviews).
CREATE TABLE orders (
    order_id             VARCHAR2(50) PRIMARY KEY,
    customer_unique_id   VARCHAR2(50) NOT NULL REFERENCES customers,
    status               VARCHAR2(20) NOT NULL,
    purchased_at         DATE NOT NULL,
    approved_at          DATE,
    carrier_at           DATE,
    delivered_at         DATE,
    estimated_delivery   DATE,
    has_items            BOOLEAN NOT NULL,      -- native BOOLEAN, new in 23ai
    has_timestamp_issue  BOOLEAN NOT NULL
);

CREATE TABLE order_items (
    order_id          VARCHAR2(50) NOT NULL REFERENCES orders,
    item_seq          NUMBER(10)   NOT NULL,
    product_id        VARCHAR2(50) NOT NULL REFERENCES products,
    seller_id         VARCHAR2(50) NOT NULL REFERENCES sellers,
    shipping_limit_at DATE,
    price             NUMBER(10,2) NOT NULL CHECK (price > 0),
    freight           NUMBER(10,2) NOT NULL CHECK (freight >= 0),
    PRIMARY KEY (order_id, item_seq)
);

CREATE TABLE order_reviews (
    order_id         VARCHAR2(50) PRIMARY KEY REFERENCES orders,
    review_id        VARCHAR2(50) NOT NULL,
    score            NUMBER(1) NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment_title    VARCHAR2(400),
    comment_message  VARCHAR2(4000),
    created_at       DATE,
    answered_at      DATE
);

-- SQLcl LOAD matches CSV header names to column names.
LOAD customers     oracle/export/customers.csv
LOAD sellers       oracle/export/sellers.csv
LOAD products      oracle/export/products.csv
LOAD orders        oracle/export/orders.csv
LOAD order_items   oracle/export/order_items.csv
LOAD order_reviews oracle/export/order_reviews.csv
COMMIT;

CREATE INDEX orders_customer_ix  ON orders (customer_unique_id);
CREATE INDEX orders_purchased_ix ON orders (purchased_at);
CREATE INDEX items_product_ix    ON order_items (product_id);
CREATE INDEX items_seller_ix     ON order_items (seller_id);

EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER)

PROMPT Core row counts (should match docs/run_all_output.txt):
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'order_items',   COUNT(*) FROM order_items
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'orders',        COUNT(*) FROM orders
UNION ALL SELECT 'products',      COUNT(*) FROM products
UNION ALL SELECT 'sellers',       COUNT(*) FROM sellers
ORDER BY table_name;
EXIT
