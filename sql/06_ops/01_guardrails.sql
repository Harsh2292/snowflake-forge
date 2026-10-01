-- ============================================================
-- 01_guardrails.sql — Cortex AI Guardrails (prompt injection / jailbreak protection)
-- Task: B14 (security review), user-approved 2026-10-01
-- Owner: CoCo
-- Run as: ACCOUNTADMIN. Re-runnable. Account-agnostic: names no account.
-- Docs: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-guardrails
-- ============================================================
-- What it does: account-level run-time scanning of tool outputs for indirect prompt injection,
-- plus jailbreak detection, for Cortex Agents (our SUPPLY_CHAIN_AGENT behind the public Ask
-- screen), Snowflake CoWork and CoCo.
-- Needs: Enterprise edition, and CORTEX_ENABLED_CROSS_REGION set (ANY_REGION here).
-- Cost: credits per token scanned. Check it in ACCOUNT_USAGE.CORTEX_AI_GUARDRAILS_USAGE_HISTORY
-- (query at the bottom). It covers CoCo sessions in this account too.
-- Turn off: ALTER ACCOUNT UNSET AI_SETTINGS;

USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET AI_SETTINGS = $$
  guardrails:
    advanced_prompt_injection:
      - enabled: true
$$;

SHOW PARAMETERS LIKE 'AI_SETTINGS' IN ACCOUNT;

-- Flagged requests and cost (ACCOUNT_USAGE latency applies):
-- SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_GUARDRAILS_USAGE_HISTORY
--  WHERE USAGE_TIME >= DATEADD('hour', -72, CURRENT_TIMESTAMP()) ORDER BY USAGE_TIME DESC;
