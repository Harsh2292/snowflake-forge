-- ============================================================
-- 04_persona_procedures.sql — Persona Sample Procedures (divergence proof)
-- Task: B07b
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.GOVERNED
-- Run as: ACCOUNTADMIN (creates, then hands ownership to each persona role)
-- ============================================================
-- Contract §5.4 / §6a. Streamlit in Snowflake runs with owner's rights, so
-- USE ROLE cannot drive masking. Instead each persona role OWNS an
-- EXECUTE AS OWNER procedure; inside it CURRENT_ROLE() is that persona role,
-- so the real B06 masking policies apply. The app calls all three as its
-- owner with only USAGE.
--
-- The three bodies are IDENTICAL. Same code, same rows: only the owning role
-- differs, and that alone changes what is visible.
--
-- PERSONA is derived from CURRENT_ROLE() rather than hard-coded, so the
-- result proves which role the procedure really ran as.
--
-- Sample: the first 3 primary sourcing rows by part_id (with their part and
-- supplier), paired by rank with the first 3 customers by customer_id.
-- Deterministic, so every persona gets the same IDs.
--
-- SP_METRICS_AS_* (CR-002) are built at the end of B08: they read
-- SEMANTIC.SUPPLY_CHAIN_SV, which does not exist yet.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. SP_SAMPLE_AS_PLANNER
CREATE OR REPLACE PROCEDURE SP_SAMPLE_AS_PLANNER()
RETURNS TABLE (
    PERSONA             VARCHAR,
    SAMPLE_PART_ID      VARCHAR,
    UNIT_COST           NUMBER(12,2),
    SAMPLE_SUPPLIER_ID  VARCHAR,
    PAYMENT_TERMS       VARCHAR,
    SAMPLE_CUSTOMER_ID  VARCHAR,
    CUSTOMER_NAME       VARCHAR,
    CREDIT_LIMIT        NUMBER(15,2),
    CONTRACT_PRICE      NUMBER(12,2),
    CUSTOMER_EMAIL      VARCHAR
)
LANGUAGE SQL
COMMENT = 'Persona sample (contract §5.4): governed rows as PLANNER_ROLE sees them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        WITH p AS (
            SELECT s.part_id, s.supplier_id, s.contract_price, pt.unit_cost,
                   ROW_NUMBER() OVER (ORDER BY s.part_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING s
            JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_PART pt ON pt.part_id = s.part_id
            WHERE s.is_primary
            QUALIFY rn <= 3
        ), c AS (
            SELECT customer_id, customer_name, email, credit_limit,
                   ROW_NUMBER() OVER (ORDER BY customer_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER
            QUALIFY rn <= 3
        )
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               p.part_id          AS SAMPLE_PART_ID,
               p.unit_cost        AS UNIT_COST,
               p.supplier_id      AS SAMPLE_SUPPLIER_ID,
               sup.payment_terms  AS PAYMENT_TERMS,
               c.customer_id      AS SAMPLE_CUSTOMER_ID,
               c.customer_name    AS CUSTOMER_NAME,
               c.credit_limit     AS CREDIT_LIMIT,
               p.contract_price   AS CONTRACT_PRICE,
               c.email            AS CUSTOMER_EMAIL
        FROM p
        JOIN c ON c.rn = p.rn
        JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER sup ON sup.supplier_id = p.supplier_id
        ORDER BY p.rn
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 2. SP_SAMPLE_AS_BUYER (identical body)
CREATE OR REPLACE PROCEDURE SP_SAMPLE_AS_BUYER()
RETURNS TABLE (
    PERSONA             VARCHAR,
    SAMPLE_PART_ID      VARCHAR,
    UNIT_COST           NUMBER(12,2),
    SAMPLE_SUPPLIER_ID  VARCHAR,
    PAYMENT_TERMS       VARCHAR,
    SAMPLE_CUSTOMER_ID  VARCHAR,
    CUSTOMER_NAME       VARCHAR,
    CREDIT_LIMIT        NUMBER(15,2),
    CONTRACT_PRICE      NUMBER(12,2),
    CUSTOMER_EMAIL      VARCHAR
)
LANGUAGE SQL
COMMENT = 'Persona sample (contract §5.4): governed rows as BUYER_ROLE sees them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        WITH p AS (
            SELECT s.part_id, s.supplier_id, s.contract_price, pt.unit_cost,
                   ROW_NUMBER() OVER (ORDER BY s.part_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING s
            JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_PART pt ON pt.part_id = s.part_id
            WHERE s.is_primary
            QUALIFY rn <= 3
        ), c AS (
            SELECT customer_id, customer_name, email, credit_limit,
                   ROW_NUMBER() OVER (ORDER BY customer_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER
            QUALIFY rn <= 3
        )
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               p.part_id          AS SAMPLE_PART_ID,
               p.unit_cost        AS UNIT_COST,
               p.supplier_id      AS SAMPLE_SUPPLIER_ID,
               sup.payment_terms  AS PAYMENT_TERMS,
               c.customer_id      AS SAMPLE_CUSTOMER_ID,
               c.customer_name    AS CUSTOMER_NAME,
               c.credit_limit     AS CREDIT_LIMIT,
               p.contract_price   AS CONTRACT_PRICE,
               c.email            AS CUSTOMER_EMAIL
        FROM p
        JOIN c ON c.rn = p.rn
        JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER sup ON sup.supplier_id = p.supplier_id
        ORDER BY p.rn
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 3. SP_SAMPLE_AS_LOGISTICS (identical body)
CREATE OR REPLACE PROCEDURE SP_SAMPLE_AS_LOGISTICS()
RETURNS TABLE (
    PERSONA             VARCHAR,
    SAMPLE_PART_ID      VARCHAR,
    UNIT_COST           NUMBER(12,2),
    SAMPLE_SUPPLIER_ID  VARCHAR,
    PAYMENT_TERMS       VARCHAR,
    SAMPLE_CUSTOMER_ID  VARCHAR,
    CUSTOMER_NAME       VARCHAR,
    CREDIT_LIMIT        NUMBER(15,2),
    CONTRACT_PRICE      NUMBER(12,2),
    CUSTOMER_EMAIL      VARCHAR
)
LANGUAGE SQL
COMMENT = 'Persona sample (contract §5.4): governed rows as LOGISTICS_ROLE sees them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        WITH p AS (
            SELECT s.part_id, s.supplier_id, s.contract_price, pt.unit_cost,
                   ROW_NUMBER() OVER (ORDER BY s.part_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING s
            JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_PART pt ON pt.part_id = s.part_id
            WHERE s.is_primary
            QUALIFY rn <= 3
        ), c AS (
            SELECT customer_id, customer_name, email, credit_limit,
                   ROW_NUMBER() OVER (ORDER BY customer_id) AS rn
            FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER
            QUALIFY rn <= 3
        )
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               p.part_id          AS SAMPLE_PART_ID,
               p.unit_cost        AS UNIT_COST,
               p.supplier_id      AS SAMPLE_SUPPLIER_ID,
               sup.payment_terms  AS PAYMENT_TERMS,
               c.customer_id      AS SAMPLE_CUSTOMER_ID,
               c.customer_name    AS CUSTOMER_NAME,
               c.credit_limit     AS CREDIT_LIMIT,
               p.contract_price   AS CONTRACT_PRICE,
               c.email            AS CUSTOMER_EMAIL
        FROM p
        JOIN c ON c.rn = p.rn
        JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER sup ON sup.supplier_id = p.supplier_id
        ORDER BY p.rn
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 4. Ownership: each persona role owns its own procedure (contract §6a).
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()
    TO ROLE PLANNER_ROLE REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER()
    TO ROLE BUYER_ROLE REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS()
    TO ROLE LOGISTICS_ROLE REVOKE CURRENT GRANTS;

-- 5. The app owner calls all three.
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()   TO ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER()     TO ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS() TO ROLE FORGE_ADMIN;
