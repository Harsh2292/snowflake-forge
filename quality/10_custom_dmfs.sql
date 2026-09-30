-- ============================================================================
-- quality/10_custom_dmfs.sql — the 7 custom data metric functions
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Spec:       docs/DATA_SPEC.md §7.2 (DMF minimum set), §4 (the defects they count)
--             docs/references/data_metric_functions.md §5
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  2 of 6 (00 → 10 → 20 → 30 → 40 → 99).
--             Re-runnable: CREATE OR ALTER, so an existing function keeps its associations
--             (CREATE OR REPLACE would fail or detach them once they're attached).
-- Expected:   7 × "Function DMF_... successfully created/altered".
-- Rules:      each DMF RETURNS NUMBER, is SQL only and deterministic (reference §5).
--             Names are the ones the app labels (forge_data._QUALITY_EXPECT_ZERO).
--             They count rows only, nothing returns a value from a row.
-- ============================================================================

-- E04: shipped more than ordered. SOURCE VBAP (KWMENG, QTY_SHIPPED): ~1% of shipped lines
-- CONFORMED ORDER_LINE (quantity_ordered, quantity_shipped): 0 after the cap.
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_OVERSHIP_COUNT(
    ARG_T TABLE (ARG_QTY_ORDERED NUMBER, ARG_QTY_SHIPPED NUMBER))
RETURNS NUMBER
COMMENT = 'C10 E04: rows whose shipped quantity exceeds the ordered quantity'
AS
$$
    SELECT COUNT_IF(ARG_QTY_SHIPPED > ARG_QTY_ORDERED) FROM ARG_T
$$;

-- E05: negative on-hand stock. SOURCE MARD.LABST ~0.3%, CONFORMED INVENTORY 0 (zeroed).
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_NEGATIVE_ON_HAND_COUNT(
    ARG_T TABLE (ARG_QTY NUMBER))
RETURNS NUMBER
COMMENT = 'C10 E05: rows with a negative on-hand quantity'
AS
$$
    SELECT COUNT_IF(ARG_QTY < 0) FROM ARG_T
$$;

-- M04: test / dummy masters, by the CONFORMED rule in DATA_SPEC §4.1: the ID starts TEST or
-- MAT9999, or the upper-case name starts with the word TEST or DUMMY, or contains DO NOT USE.
-- (REGEXP_LIKE matches the whole string, "(TEST|DUMMY)([^A-Z0-9_].*)?" is "^(TEST|DUMMY)\b".)
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_TEST_RECORD_COUNT(
    ARG_T TABLE (ARG_ID VARCHAR, ARG_NAME VARCHAR))
RETURNS NUMBER
COMMENT = 'C10 M04: test or dummy master records (DATA_SPEC §4.1 rule)'
AS
$$
    SELECT COUNT_IF(
               UPPER(TRIM(ARG_ID)) LIKE 'TEST%'
            OR UPPER(TRIM(ARG_ID)) LIKE 'MAT9999%'
            OR REGEXP_LIKE(UPPER(TRIM(ARG_NAME)), '(TEST|DUMMY)([^A-Z0-9_].*)?')
            OR CONTAINS(UPPER(ARG_NAME), 'DO NOT USE'))
    FROM ARG_T
$$;

-- M03: values outside the contract set of one code domain. The domain comes from the
-- valid-code table it's attached with, e.g.
--   ON (REGIO, TABLE(SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_REGION(CODE)))
-- Exact, case-sensitive comparison: 'Apac' and 'apac ' are variants, 'APAC' is not.
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_NONCONTRACT_CODE_COUNT(
    ARG_T TABLE (ARG_CODE VARCHAR),
    ARG_VALID TABLE (ARG_VALID_CODE VARCHAR))
RETURNS NUMBER
COMMENT = 'C10 M03: non-NULL codes outside the contract values of the attached domain'
AS
$$
    SELECT COUNT(*) FROM ARG_T
    WHERE ARG_CODE IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM ARG_VALID WHERE ARG_VALID.ARG_VALID_CODE = ARG_T.ARG_CODE)
$$;

-- E09a: order lines whose order doesn't exist. Compared on UPPER(TRIM()), the CONFORMED
-- join rule (M07), so a lower-case order number isn't miscounted as an orphan. A NULL
-- order number counts as an orphan too.
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_ORPHAN_ORDER_LINES(
    ARG_T TABLE (ARG_ORDER_ID VARCHAR),
    ARG_ORDERS TABLE (ARG_KEY VARCHAR))
RETURNS NUMBER
COMMENT = 'C10 E09a: order lines with no matching order (IDs compared on UPPER(TRIM()))'
AS
$$
    SELECT COUNT(*) FROM ARG_T
    WHERE NOT EXISTS (SELECT 1 FROM ARG_ORDERS
                      WHERE UPPER(TRIM(ARG_ORDERS.ARG_KEY)) = UPPER(TRIM(ARG_T.ARG_ORDER_ID)))
$$;

-- E09b: shipments whose order doesn't exist. Same rule as E09a, a separate name because
-- the app and the catalogue label them separately.
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_ORPHAN_SHIPMENTS(
    ARG_T TABLE (ARG_ORDER_ID VARCHAR),
    ARG_ORDERS TABLE (ARG_KEY VARCHAR))
RETURNS NUMBER
COMMENT = 'C10 E09b: shipments with no matching order (IDs compared on UPPER(TRIM()))'
AS
$$
    SELECT COUNT(*) FROM ARG_T
    WHERE NOT EXISTS (SELECT 1 FROM ARG_ORDERS
                      WHERE UPPER(TRIM(ARG_ORDERS.ARG_KEY)) = UPPER(TRIM(ARG_T.ARG_ORDER_ID)))
$$;

-- E08: shipments whose cost was an outlier (> USD 25,000 in total), flagged COST_OUTLIER in
-- CONFORMED.SHIPMENT.dq_flags. There's no SOURCE version: the threshold needs FX (§7.2).
CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE.OPS.DMF_COST_OUTLIER_COUNT(
    ARG_T TABLE (ARG_FLAGS ARRAY))
RETURNS NUMBER
COMMENT = 'C10 E08: rows flagged COST_OUTLIER (costs set to unknown in CONFORMED)'
AS
$$
    SELECT COUNT_IF(ARRAY_CONTAINS('COST_OUTLIER'::VARIANT, ARG_FLAGS)) FROM ARG_T
$$;
