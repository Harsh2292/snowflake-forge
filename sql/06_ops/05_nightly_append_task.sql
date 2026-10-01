-- ============================================================
-- 05_nightly_append_task.sql — the nightly day-append (B12a part 2; Claude Code's C17)
-- Task: B12a, user-approved 2026-09-30; built 2026-10-01
-- Owner: CoCo (the task). OPS.SP_APPEND_DAY is Claude Code's (data_gen/40_sp_append_day.sql).
-- Run as: ACCOUNTADMIN (owns the source tables). Re-runnable. Account-agnostic.
-- Needs: data_gen/00, 10, 20, 40 (the generator + SP_APPEND_DAY), sql/04_governance/06 (the DTs).
-- ============================================================
-- Every night at 05:30 UTC:
--   1. SP_APPEND_DAY adds the business days since the last load, up to the UTC date (the load
--      date; it carries the previous business day). The UTC date is passed explicitly
--      (SYSDATE() is UTC; the account timezone is America/Los_Angeles). Idempotent: a re-run on
--      the same date adds nothing; missed nights catch up (<= 60 days).
--   2. Refresh the 10 CONFORMED DTs at once, so the app and the agent see the new day within
--      minutes (their TARGET_LAG is 1 day). The DMFs run by themselves on the change
--      (TRIGGER_ON_CHANGES).
-- Cost (1 Oct, XS): ~45 s append + ~45 s refresh, about 0.03 credits a night.
-- Failure: the task suspends after 3 failed nights in a row; FORGE_OPS_WATCH e-mails when data
-- health turns WARN. Pause: ALTER TASK SUPPLY_CHAIN_FORGE.OPS.FORGE_NIGHTLY_APPEND SUSPEND;

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE TASK SUPPLY_CHAIN_FORGE.OPS.FORGE_NIGHTLY_APPEND
  WAREHOUSE = FORGE_WH
  SCHEDULE = 'USING CRON 30 5 * * * UTC'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  USER_TASK_TIMEOUT_MS = 1800000
  COMMENT = 'B12a: nightly day-append (SP_APPEND_DAY, UTC date) + CONFORMED refresh'
AS
EXECUTE IMMEDIATE $$
DECLARE
  utc_date DATE DEFAULT SYSDATE()::DATE;
  result VARIANT;
  append_failed EXCEPTION (-20001, 'SP_APPEND_DAY did not return status OK');
BEGIN
  CALL SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY('SUPPLY_CHAIN_FORGE', 1, 20260929, :utc_date);
  SELECT $1 INTO :result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  IF (result:status::VARCHAR IS DISTINCT FROM 'OK') THEN
    RAISE append_failed;
  END IF;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SUPPLIER REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.PART REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SOURCING REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.PLANT REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.CUSTOMER REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.ORDER_LINE REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SHIPMENT REFRESH;
  ALTER DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.INVENTORY REFRESH;
  RETURN TO_JSON(result);
END;
$$;

ALTER TASK SUPPLY_CHAIN_FORGE.OPS.FORGE_NIGHTLY_APPEND RESUME;

-- Run it now (safe: idempotent):  EXECUTE TASK SUPPLY_CHAIN_FORGE.OPS.FORGE_NIGHTLY_APPEND;
-- History: SELECT name, state, scheduled_time, completed_time, return_value, error_message
--   FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'FORGE_NIGHTLY_APPEND'))
--   ORDER BY scheduled_time DESC;
