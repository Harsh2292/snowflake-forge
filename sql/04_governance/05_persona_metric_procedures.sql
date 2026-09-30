-- ============================================================
-- 05_persona_metric_procedures.sql — Persona Metric Procedures (consistency proof)
-- Task: B08 (CR-002); B09 applies the §3a time rule (CR-006)
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
--
-- §3a (CR-006, from B09): one SEMANTIC_VIEW call per default window, as in
-- contract §5.1: ship-date window for OTD and landed cost, order-date window
-- for fill rate, latest snapshot for DOI. The shape is unchanged.
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
               s.on_time_delivery_rate              AS ON_TIME_DELIVERY_RATE,
               o.fill_rate                          AS FILL_RATE,
               i.days_of_inventory                  AS DAYS_OF_INVENTORY,
               s.avg_landed_cost                    AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, shipments.avg_landed_cost
            WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
              AND shipments.ship_date <= CURRENT_DATE()
        ) s,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS order_lines.fill_rate
            WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
              AND orders.order_date <= CURRENT_DATE()
        ) o,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS inventory.days_of_inventory
            WHERE inventory.snapshot_date =
                  (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)
        ) i
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
               s.on_time_delivery_rate              AS ON_TIME_DELIVERY_RATE,
               o.fill_rate                          AS FILL_RATE,
               i.days_of_inventory                  AS DAYS_OF_INVENTORY,
               s.avg_landed_cost                    AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, shipments.avg_landed_cost
            WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
              AND shipments.ship_date <= CURRENT_DATE()
        ) s,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS order_lines.fill_rate
            WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
              AND orders.order_date <= CURRENT_DATE()
        ) o,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS inventory.days_of_inventory
            WHERE inventory.snapshot_date =
                  (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)
        ) i
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
               s.on_time_delivery_rate              AS ON_TIME_DELIVERY_RATE,
               o.fill_rate                          AS FILL_RATE,
               i.days_of_inventory                  AS DAYS_OF_INVENTORY,
               s.avg_landed_cost                    AS AVG_LANDED_COST
        FROM SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS shipments.on_time_delivery_rate, shipments.avg_landed_cost
            WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
              AND shipments.ship_date <= CURRENT_DATE()
        ) s,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS order_lines.fill_rate
            WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
              AND orders.order_date <= CURRENT_DATE()
        ) o,
        SEMANTIC_VIEW(
            SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
            METRICS inventory.days_of_inventory
            WHERE inventory.snapshot_date =
                  (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)
        ) i
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
