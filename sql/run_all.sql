-- =====================================================================
-- run_all.sql
-- Rebuild the entire database from the raw CSVs, in order.
-- Run from the project root:
--   psql -U postgres -d cart_theory -f sql/run_all.sql -o docs/run_all_output.txt
-- Progress messages appear on screen; query results go to the output file.
-- =====================================================================

\set ON_ERROR_STOP on
\timing on

DROP SCHEMA IF EXISTS analytics CASCADE;

\echo '[1/9] Raw schema'
\ir 01_raw_schema.sql
\echo '[2/9] Load CSVs'
\ir 02_load_raw.sql
\echo '[3/9] Data audit'
\ir 03_audit.sql
\echo '[4/9] Core layer'
\ir 04_core.sql
\echo '[5/9] Revenue'
\ir 05_revenue.sql
\echo '[6/9] Cohorts'
\ir 06_cohorts.sql
\echo '[7/9] RFM'
\ir 07_rfm.sql
\echo '[8/9] Sellers and categories'
\ir 08_sellers_categories.sql
\echo '[9/9] Delivery and reviews'
\ir 09_delivery_reviews.sql

\echo 'Done: database rebuilt from scratch.'