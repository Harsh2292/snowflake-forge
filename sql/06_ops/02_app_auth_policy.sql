-- ============================================================
-- 02_app_auth_policy.sql — the public app's service user may only log in with its key pair
-- Task: B14 (security review), user-approved 2026-10-01
-- Owner: CoCo
-- Run as: ACCOUNTADMIN, after sql/05_app_access/01_app_service_user.sql. Re-runnable.
-- Account-agnostic: names no account.
-- ============================================================
-- Scope: USER level on FORGE_APP_SVC only. It never touches the account-level policy, so human
-- users (browser OAuth, Snowsight) are unaffected. A user-level policy takes precedence over
-- any account-level one.
--   AUTHENTICATION_METHODS = KEYPAIR  the app's JWT login (Community Cloud secrets); no password,
--                                      PAT, OAuth or SAML path exists for this user
--   CLIENT_TYPES = DRIVERS             the Python connector / Snowpark only; no Snowsight, CLI
-- Revert: ALTER USER FORGE_APP_SVC UNSET AUTHENTICATION POLICY;

USE ROLE ACCOUNTADMIN;

CREATE AUTHENTICATION POLICY IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_SVC_AUTH
  AUTHENTICATION_METHODS = ('KEYPAIR')
  CLIENT_TYPES = ('DRIVERS')
  COMMENT = 'B14: the public app service user logs in with its key pair through a driver only';

-- Keep a re-run in step with the definition above (CREATE ... IF NOT EXISTS doesn't update).
ALTER AUTHENTICATION POLICY SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_SVC_AUTH SET
  AUTHENTICATION_METHODS = ('KEYPAIR')
  CLIENT_TYPES = ('DRIVERS');

-- Attach (re-runnable: detach first; UNSET is a no-op when nothing is attached).
ALTER USER FORGE_APP_SVC UNSET AUTHENTICATION POLICY;
ALTER USER FORGE_APP_SVC SET AUTHENTICATION POLICY SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_SVC_AUTH;

-- Check: one reference, on the user FORGE_APP_SVC.
SELECT policy_name, ref_entity_name, ref_entity_domain
FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.POLICY_REFERENCES(
  POLICY_NAME => 'SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_SVC_AUTH'));
