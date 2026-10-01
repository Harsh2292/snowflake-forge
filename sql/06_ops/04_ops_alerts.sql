-- ============================================================
-- 04_ops_alerts.sql — an hourly e-mail when something the public link depends on goes wrong
-- Task: B14/B15 (operations), user-approved 2026-10-01
-- Owner: CoCo
-- Run as: ACCOUNTADMIN (owns the alert; serverless alerts need EXECUTE MANAGED ALERT).
-- Re-runnable. Account-agnostic, and no e-mail address in the repo: the recipient is read from
-- the running user's own Snowflake profile at setup and kept in OPS.ALERT_RECIPIENT.
-- Needs: 03_ops_views.sql (V_AGENT_REQUESTS), quality/30 (SP_DATA_HEALTH), 05_app_access/.
-- ============================================================
-- What is checked (OPS.SP_OPS_PROBLEMS returns one row per problem, none when all is well):
--   data_health      SP_DATA_HEALTH('ALL') status is not OK (stale daily data, failing checks)
--   agent_failures   agent questions in the last hour that failed or had a failed tool call
--   ask_paused       FORGE_APP_ROLE has no USAGE on the agent (the Cortex budget stop revoked
--                    it, or an agent re-create dropped it: re-run sql/05_app_access/01)
--   warehouse_quota  FORGE_WH_MONITOR has used >= 75% of today's credits
-- The alert runs hourly, serverless; it e-mails only when a check fails, so a lasting problem
-- repeats hourly until fixed. Pause: ALTER ALERT SUPPLY_CHAIN_FORGE.OPS.FORGE_OPS_WATCH SUSPEND;

USE ROLE ACCOUNTADMIN;

-- E-mail integration. No ALLOWED_RECIPIENTS: it may send to any VERIFIED e-mail in the account.
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS FORGE_OPS_EMAIL
  TYPE = EMAIL
  ENABLED = TRUE
  COMMENT = 'B14: Supply Chain Forge operations alerts';

-- Recipients: the running user's own profile e-mail (must be verified in Snowsight).
CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.ALERT_RECIPIENT (
  email    VARCHAR NOT NULL,
  added_by VARCHAR,
  added_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

EXECUTE IMMEDIATE $$
DECLARE
  u VARCHAR DEFAULT CURRENT_USER();
BEGIN
  EXECUTE IMMEDIATE 'SHOW USERS LIKE ''' || REPLACE(u, '''', '''''') || '''';
  MERGE INTO SUPPLY_CHAIN_FORGE.OPS.ALERT_RECIPIENT t
  USING (SELECT "email" AS email FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
         WHERE "email" IS NOT NULL AND "email" <> '') s
  ON t.email = s.email
  WHEN NOT MATCHED THEN INSERT (email, added_by) VALUES (s.email, :u);
  RETURN 'recipient rows: ' || (SELECT COUNT(*) FROM SUPPLY_CHAIN_FORGE.OPS.ALERT_RECIPIENT);
END;
$$;

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_OPS_PROBLEMS()
RETURNS TABLE (check_name VARCHAR, severity VARCHAR, detail VARCHAR)
LANGUAGE SQL
COMMENT = 'B14: one row per operations problem for the public link; no rows when all is well'
EXECUTE AS CALLER
AS
$$
DECLARE
  health VARIANT;
  health_status VARCHAR;
  health_summary VARCHAR;
  agent_failures INTEGER;
  app_grants INTEGER;
  quota_pct NUMBER(10, 1);
  res RESULTSET;
BEGIN
  CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL');
  SELECT $1 INTO :health FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  health_status := COALESCE(health:status::VARCHAR, 'UNKNOWN');
  health_summary := COALESCE(health:summary::VARCHAR, '');

  -- Agent traces are in UTC (TIMESTAMP_NTZ); SYSDATE() is UTC too.
  SELECT COUNT(*) INTO :agent_failures
  FROM SUPPLY_CHAIN_FORGE.OPS.V_AGENT_REQUESTS
  WHERE started_at > DATEADD(hour, -1, SYSDATE())
    AND (status <> 'SUCCESS' OR COALESCE(failed_tool_calls, 0) > 0);

  SHOW GRANTS ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT;
  SELECT COUNT_IF("grantee_name" = 'FORGE_APP_ROLE' AND "privilege" = 'USAGE') INTO :app_grants
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

  SHOW RESOURCE MONITORS LIKE 'FORGE_WH_MONITOR';
  SELECT COALESCE(MAX(100 * "used_credits"::NUMBER(20, 4) / NULLIFZERO("credit_quota"::NUMBER(20, 4))), 0)
    INTO :quota_pct
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

  res := (
    SELECT 'data_health' AS check_name, IFF(:health_status = 'FAIL', 'ERROR', 'WARN') AS severity,
           'SP_DATA_HEALTH(ALL) status ' || :health_status || '. ' || :health_summary AS detail
    WHERE :health_status <> 'OK'
    UNION ALL
    SELECT 'agent_failures', 'ERROR',
           :agent_failures || ' agent question(s) failed in the last hour: see OPS.V_AGENT_REQUESTS'
    WHERE :agent_failures > 0
    UNION ALL
    SELECT 'ask_paused', 'ERROR',
           'FORGE_APP_ROLE has no USAGE on SUPPLY_CHAIN_AGENT: Ask is off on the public link (Cortex budget stop, or re-run sql/05_app_access/01_app_service_user.sql)'
    WHERE :app_grants = 0
    UNION ALL
    SELECT 'warehouse_quota', IFF(:quota_pct >= 100, 'ERROR', 'WARN'),
           'FORGE_WH_MONITOR has used ' || :quota_pct || '% of today''s credit quota'
    WHERE :quota_pct >= 75
  );
  RETURN TABLE(res);
END;
$$;

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_OPS_NOTIFY()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'B14: e-mails the current SP_OPS_PROBLEMS rows to OPS.ALERT_RECIPIENT'
EXECUTE AS CALLER
AS
$$
DECLARE
  n INTEGER;
  body VARCHAR;
  recipients ARRAY;
  config VARCHAR;
BEGIN
  CALL SUPPLY_CHAIN_FORGE.OPS.SP_OPS_PROBLEMS();
  SELECT COUNT(*), LISTAGG(severity || '  ' || check_name || ': ' || detail, '\n')
    INTO :n, :body
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  IF (n = 0) THEN
    RETURN 'no problems';
  END IF;
  SELECT ARRAY_AGG(email) INTO :recipients FROM SUPPLY_CHAIN_FORGE.OPS.ALERT_RECIPIENT;
  config := OBJECT_CONSTRUCT('FORGE_OPS_EMAIL',
              OBJECT_CONSTRUCT('subject', 'Supply Chain Forge: ' || n || ' operations problem(s)',
                               'toAddress', recipients))::VARCHAR;
  body := 'Supply Chain Forge operations check (' || TO_VARCHAR(SYSDATE(), 'YYYY-MM-DD HH24:MI') || ' UTC)\n\n'
          || body || '\n\nChecks: CALL SUPPLY_CHAIN_FORGE.OPS.SP_OPS_PROBLEMS();';
  CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(:body), :config);
  RETURN 'sent: ' || n || ' problem(s)';
END;
$$;

-- Serverless (no WAREHOUSE): billed only for the seconds it runs.
CREATE OR REPLACE ALERT SUPPLY_CHAIN_FORGE.OPS.FORGE_OPS_WATCH
  SCHEDULE = '60 MINUTE'
  COMMENT = 'B14: hourly operations check for the public link; e-mails only when a check fails'
  IF (EXISTS (CALL SUPPLY_CHAIN_FORGE.OPS.SP_OPS_PROBLEMS()))
  THEN CALL SUPPLY_CHAIN_FORGE.OPS.SP_OPS_NOTIFY();

ALTER ALERT SUPPLY_CHAIN_FORGE.OPS.FORGE_OPS_WATCH RESUME;

-- Check now:   CALL SUPPLY_CHAIN_FORGE.OPS.SP_OPS_PROBLEMS();
-- History:     SELECT * FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.ALERT_HISTORY(
--                SCHEDULED_TIME_RANGE_START => DATEADD(day, -1, CURRENT_TIMESTAMP()))) ORDER BY SCHEDULED_TIME DESC;
-- Delivery:    SELECT * FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.NOTIFICATION_HISTORY(
--                INTEGRATION_NAME => 'FORGE_OPS_EMAIL')) ORDER BY CREATED DESC;
