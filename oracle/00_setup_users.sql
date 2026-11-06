-- =====================================================================
-- oracle/00_setup_users.sql
-- One-time setup: CORE and ANALYTICS schemas inside FREEPDB1.
-- Run as SYSTEM:
--   sql system/<password>@localhost:1521/FREEPDB1 @oracle/00_setup_users.sql
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- core: holds the cleaned tables loaded from PostgreSQL
CREATE USER IF NOT EXISTS core IDENTIFIED BY "CartTheory_1"
    DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, DB_DEVELOPER_ROLE TO core;

-- analytics: owns the views and materialised views (files 05-09)
CREATE USER IF NOT EXISTS analytics IDENTIFIED BY "CartTheory_1"
    DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE VIEW, CREATE MATERIALIZED VIEW, CREATE TABLE TO analytics;

-- 23ai schema-level privilege: read every table in CORE, including ones added later.
-- Granted directly (not through a role), so views in ANALYTICS can use it.
GRANT SELECT ANY TABLE ON SCHEMA core TO analytics;

PROMPT Users CORE and ANALYTICS ready.
EXIT
