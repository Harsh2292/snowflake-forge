-- ============================================================================
-- data_gen/00_setup.sql — log tables for the data generator
-- Card:       C08 (.agents/tasks/claude/C08_data_generator.md)
-- Spec:       docs/DATA_SPEC.md §7.1
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  1 of 5 (00 → 10 → 20 → 30 → 99). Re-runnable: IF NOT EXISTS only.
-- Needs:      database SUPPLY_CHAIN_FORGE and role FORGE_ADMIN (CoCo's sql/01_setup).
--             OPS is normally created by CoCo at B08c; created here too if missing,
--             so the file runs on an empty account in the documented order.
-- Expected:   7 statements succeed; the three tables exist (empty on a new account).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS
  COMMENT = 'Private operations schema: data generator, evaluation, scale harness (FORGE_ADMIN only)';

-- One row per generator stage (and per year chunk), so a long run can be followed from
-- another session: SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG ORDER BY STARTED_AT DESC;
CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (
    RUN_ID        VARCHAR       NOT NULL COMMENT 'One id per procedure call',
    TARGET_DB     VARCHAR       NOT NULL COMMENT 'Database written (SUPPLY_CHAIN_FORGE, or a clone at B13)',
    STAGE         VARCHAR       NOT NULL COMMENT 'start, masters, fx, sourcing, orders, inventory, stats, mess, done, error',
    TABLE_NAME    VARCHAR                COMMENT 'Source table written, e.g. VBAK',
    CHUNK         VARCHAR                COMMENT 'History year for chunked stages',
    ROWS_WRITTEN  NUMBER(38,0),
    STARTED_AT    TIMESTAMP_NTZ,
    ENDED_AT      TIMESTAMP_NTZ,
    PARAMS        VARIANT                COMMENT 'Procedure arguments (on the start row) or error detail'
);

-- Facts about each load: row counts, distinct keys, HASH_AGG checksums and the metrics
-- computed on the clean load. SP_GEN_SELF_CHECKS reads these.
CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.GEN_STATS (
    RUN_ID        VARCHAR       NOT NULL,
    TARGET_DB     VARCHAR       NOT NULL,
    PHASE         VARCHAR       NOT NULL COMMENT 'CLEAN (after SP_GENERATE_DATA) or MESSY (after SP_INJECT_MESS)',
    NAME          VARCHAR       NOT NULL COMMENT 'ROWS, DISTINCT_KEYS, CHECKSUM, or a metric name',
    TABLE_NAME    VARCHAR,
    VALUE         FLOAT,
    DETAIL        VARCHAR                COMMENT 'Checksums as text (64-bit), notes',
    PARAMS        VARIANT                COMMENT 'scale_factor, seed, end_date of the run',
    LOGGED_AT     TIMESTAMP_NTZ
);

-- One row per injected defect and table: the base population and how many rows changed.
CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.GEN_MESS_LOG (
    RUN_ID        VARCHAR       NOT NULL,
    TARGET_DB     VARCHAR       NOT NULL,
    CODE          VARCHAR       NOT NULL COMMENT 'DATA_SPEC §4 code, e.g. M01, E07a',
    TABLE_NAME    VARCHAR       NOT NULL,
    BASE_ROWS     NUMBER(38,0)           COMMENT 'The §4 base population before injection',
    TARGET_RATE   FLOAT                  COMMENT 'The §4 rate',
    AFFECTED_ROWS NUMBER(38,0)           COMMENT 'Rows changed or added',
    LOGGED_AT     TIMESTAMP_NTZ
);

GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.GEN_LOG TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.GEN_STATS TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.GEN_MESS_LOG TO ROLE FORGE_ADMIN;
