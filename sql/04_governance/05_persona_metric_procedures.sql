-- ============================================================
-- 05_persona_metric_procedures.sql — Persona Metric Procedures (consistency proof)
-- Task: B08 (CR-002)
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.GOVERNED
-- Run as: ACCOUNTADMIN (creates, then hands ownership to each persona role)
-- ============================================================
-- Contract §5.4 / §6a. Same mechanism as 04_persona_procedures.sql: each
-- persona role OWNS an EXECUTE AS OWNER procedure, so inside it
-- CURRENT_ROLE() is that persona role and the real masking policies apply.
--
-- Each returns ONE row: the 4 canonical metrics, read through
-- SEMANTIC.SUPPLY_CHAIN_SV (never recomputed here). No metric references a
-- masked column (§6), so the three results must be identical to 6 dp while
-- SP_SAMPLE_AS_* show different visibility.
--
-- The three bodies are IDENTICAL; only the name and the owner differ.
-- PERSONA is derived from CURRENT_ROLE(), so the row proves which role ran.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. SP_METRICS_AS_PLANNER
CREATE OR REPLACE PROCEDURE SP_METRICS_AS_PLANNER()
RETURNS TABLE (
    PERSONA                VARCHAR,
    ON_TIME_DELIVERY_RATE  NUMBER(38,6),
    FILL_RATE              NUMBER(38,6),
    DAYS_OF_INVENTORY      NUMBER(38,6),
    AVG_LANDED_COST        NUMBER(38,6)
)
LANGUAGE SQL
COMMENT = 'Persona metrics (contract §5.4, CR-002): the 4 canonical metrics as PLANNER_ROLE computes them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               on_time_delivery_rate                AS ON_TIME_DELIVERY_RATE,
               fill_rate                            AS FILL_RATE,
               days_of_inventory                    AS DAYS_OF_INVENTORY,
               avg_landed_cost                      AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, order_lines.fill_rate,
                    inventory.days_of_inventory, shipments.avg_landed_cost
        )
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 2. SP_METRICS_AS_BUYER (identical body)
CREATE OR REPLACE PROCEDURE SP_METRICS_AS_BUYER()
RETURNS TABLE (
    PERSONA                VARCHAR,
    ON_TIME_DELIVERY_RATE  NUMBER(38,6),
    FILL_RATE              NUMBER(38,6),
    DAYS_OF_INVENTORY      NUMBER(38,6),
    AVG_LANDED_COST        NUMBER(38,6)
)
LANGUAGE SQL
COMMENT = 'Persona metrics (contract §5.4, CR-002): the 4 canonical metrics as BUYER_ROLE computes them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               on_time_delivery_rate                AS ON_TIME_DELIVERY_RATE,
               fill_rate                            AS FILL_RATE,
               days_of_inventory                    AS DAYS_OF_INVENTORY,
               avg_landed_cost                      AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, order_lines.fill_rate,
                    inventory.days_of_inventory, shipments.avg_landed_cost
        )
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 3. SP_METRICS_AS_LOGISTICS (identical body)
CREATE OR REPLACE PROCEDURE SP_METRICS_AS_LOGISTICS()
RETURNS TABLE (
    PERSONA                VARCHAR,
    ON_TIME_DELIVERY_RATE  NUMBER(38,6),
    FILL_RATE              NUMBER(38,6),
    DAYS_OF_INVENTORY      NUMBER(38,6),
    AVG_LANDED_COST        NUMBER(38,6)
)
LANGUAGE SQL
COMMENT = 'Persona metrics (contract §5.4, CR-002): the 4 canonical metrics as LOGISTICS_ROLE computes them'
EXECUTE AS OWNER
AS
$$
DECLARE
    rs RESULTSET DEFAULT (
        SELECT REPLACE(CURRENT_ROLE(), '_ROLE', '') AS PERSONA,
               on_time_delivery_rate                AS ON_TIME_DELIVERY_RATE,
               fill_rate                            AS FILL_RATE,
               days_of_inventory                    AS DAYS_OF_INVENTORY,
               avg_landed_cost                      AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, order_lines.fill_rate,
                    inventory.days_of_inventory, shipments.avg_landed_cost
        )
    );
BEGIN
    RETURN TABLE(rs);
END;
$$;

-- 4. Ownership: each persona role owns its own procedure (contract §6a).
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER()
    TO ROLE PLANNER_ROLE REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER()
    TO ROLE BUYER_ROLE REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS()
    TO ROLE LOGISTICS_ROLE REVOKE CURRENT GRANTS;

-- 5. The app owner calls all three.
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER()   TO ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER()     TO ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS() TO ROLE FORGE_ADMIN;
