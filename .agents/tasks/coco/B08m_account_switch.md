# B08m — Move to the event account (cutover), then finish there

| | |
|---|---|
| **Owner** | CoCo |
| **Status** | ✅ **DONE 2026-09-30 (evening)**: replayed with no hand fix, data byte-identical, every compared number matches, 93/93 self-checks, eval 28/30. Report `docs/artifacts/runs/B08m_run.md`. The "After the gate" list below is what's left |
| **Why now** | The old account `DA53081` (connection `tyduokn-gf25237`) had **$135.91** left on 30 Sep, and CoCo's own tokens are ~80% of the spend and bill to the account the session is connected to. The event account has **$399.68**. User decision 30 Sep: switch now, not at the end of 1 Oct |
| **New account** | connection **`QURFOQP-XU04029`** · locator `VC33954` · user **`LAZYBOY2`** · role `ACCOUNTADMIN` · `AZURE_CENTRALINDIA` · **Enterprise** · `CORTEX_ENABLED_CROSS_REGION = ANY_REGION` · timezone `America/Los_Angeles` (same as old) · empty on 30 Sep (no `SUPPLY_CHAIN_FORGE`, no Forge roles) |
| **Old account** | read-only from now on: only for the side-by-side number check (step 9). Never drop anything there |
| **Writes** | `docs/artifacts/runs/B08m_run.md` (every step, verbatim errors, fixes as diffs), art 08 (b10-v2), updated docs |
| **Contract** | no change: every FQN, role and metric is identical. No CR needed |

## Pre-flight done on 30 Sep (no need to repeat)

1. **Inventory.** All 289 objects of the old account were listed and matched to repo scripts:
   45 tables/views/DTs, 15 procedures, 7 functions, 10 schemas, 7 tags, 4 masking policies, our
   5 roles (`FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`, `FORGE_APP_ROLE`),
   `FORGE_APP_SVC`, `FORGE_WH`, `FORGE_WH_MONITOR`, `OPS.FORGE_APP_CORTEX_BUDGET`, the agent and
   the semantic view. **Nothing was built by hand.** (The ~165 unmatched names are Snowflake's
   own roles, e.g. `CORTEX-MODEL-ROLE-*`, `APP_*`.) No tasks, alerts, integrations, network
   policies or Streamlit apps exist in the old account.
2. **Run-time fixes are in the files:** C08's 3 fixes (COMMENT order, `SELECT … INTO`, the
   range joins, proven byte-identical at C17a), C10's `FRESHNESS ON ()`, C11's CR-007 bind. C16
   and B09a ran straight from the files on 30 Sep.
3. **Two replay blockers found and fixed** (both in `sql/01_setup/`):
   - `02_roles_grants.sql` granted the 4 roles `TO USER LAZYBOY`; the new user is `LAZYBOY2`.
     Now an anonymous block grants them to `CURRENT_USER()` (tested: idempotent, "granted to
     LAZYBOY" in the old account).
   - `01_database.sql` now also sets `COMPUTE_WH` auto-suspend to 60 s (it was 94% of the old
     account's warehouse credits and wasn't scripted).
4. **The runner:** `sql/replay_helper.py` (tested live 30 Sep). It splits files safely (`$$`
   bodies, strings), drops comment lines, base64-wraps any statement with non-ASCII (the tool
   bridge garbles it), sends a DDL file as one call, and fetches JSON base64-encoded.

## How to run (in CoCo's Python REPL)

```python
exec(open(r'e:\DevStuff\snowflake-forge\sql\replay_helper.py', encoding='utf-8').read())
CONN = 'QURFOQP-XU04029'
run_file('sql/01_setup/01_database.sql', 'ACCOUNTADMIN', CONN)   # one call per DDL file
q("CALL ...", 'FORGE_ADMIN', CONN)                                 # one step
fetch_json("CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL')", 'FORGE_ADMIN', CONN)
```

- `q()` raises on a SQL error: record the verbatim message in `B08m_run.md`, fix the smallest
  thing, commit the fix to the file (CoCo files) or record it as a diff (Claude Code files:
  `data_gen/`, `quality/`, `eval/`, `tests/`).
- The REPL may restart and lose its state: re-run the `exec(...)` line.
- A long call can time out in the REPL while the query keeps running: poll
  `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` / `INFORMATION_SCHEMA.QUERY_HISTORY()`.
- Always pass `connection='QURFOQP-XU04029'` (the helper does). The VS Code active connection
  may still be the old one.

## The replay (in this order)

The v1 tables and v1 sample data (`sql/02_tables/01–04`, `sql/03_sample_data/`) are **skipped**:
`05_source_v2.sql` drops and re-creates every source table, so v1 would only be thrown away.

| # | File(s) | Role | Expected |
|---|---|---|---|
| 1 | `sql/01_setup/01_database.sql` | ACCOUNTADMIN | DB, the 4 source schemas + `GOVERNED`, `SEMANTIC`, `APP`; `FORGE_WH` XS 60 s; `COMPUTE_WH` 60 s |
| 2 | `sql/01_setup/02_roles_grants.sql` | ACCOUNTADMIN | 4 roles, granted to `LAZYBOY2`, Cortex database roles |
| 3 | `sql/01_setup/03_schemas_v2.sql` | ACCOUNTADMIN | `CONFORMED`, `OPS`, tag `SEMANTIC_ROLE` |
| 4 | `sql/02_tables/05_source_v2.sql` | ACCOUNTADMIN | 10 v2 source tables, `CHANGE_TRACKING = TRUE` |
| 5 | `data_gen/00_setup.sql`, `10_…`, `20_…`, `30_…` (`run_file` each), then `data_gen/99_run.sql` with `run_each` | ACCOUNTADMIN | seed `20260929`, END_DATE **`'2026-09-30'`** (fixed, as in the old account). SF 1 generate ~133 s + mess ~62 s. Counts = old production: VBAK 724,949 · VBAP 2,074,071 · VTTK 780,439 · MARD 2,167,092 · KNA1 2,025 · LFA1 152 · MARA 1,204 · SOURCING 2,503 · TCURR 23,310 · T001W 12. Self-checks: TRUE or NULL (the 2 known non-blocking FALSEs of `C08_run.md` may recur) |
| 6 | `sql/04_governance/01_tags.sql` → `02_masking_policies.sql` → `06_conformed_layer.sql` → `03_governed_views.sql` → `04_persona_procedures.sql` → `05_persona_metric_procedures.sql` | ACCOUNTADMIN | tags on source, 4 masking policies, `CODE_MAP`, `CALENDAR` + the 10 `CONFORMED` DTs (as in the old account: CUSTOMER, FX_RATE, INVENTORY, ORDER_LINE, PART, PLANT, SALES_ORDER, SHIPMENT, SOURCING, SUPPLIER), refreshed, 9 governed views with masking on exactly the 6 contract §6 columns, the persona procedures |
| 7 | `semantic/01_semantic_view.sql` | FORGE_ADMIN | `SUPPLY_CHAIN_SV`, **15 verified queries** (B09a added 3) |
| 8 | `quality/00_setup.sql`, `10_custom_dmfs.sql`, `20_sp_attach_dmfs.sql` (ACCOUNTADMIN) → `30_sp_data_health.sql` (FORGE_ADMIN) → `40_sp_dq_self_checks.sql` (ACCOUNTADMIN) | as noted | `DQ_CHECKS` 77 rows, 7 DMFs, the procedures |
| 9 | `agent/01_agent.sql` | FORGE_ADMIN | the agent (no `data_to_chart`, no SQL-block rule: B09a) + 3 persona grants |
| 10 | `quality/99_run.sql`, **step by step with `q()`** (not `run_each`: roles differ and there's a wait): attach `'5 MINUTE'` (ACCOUNTADMIN) → `SP_DATA_HEALTH('shipments')` → **wait 10–15 min** → `SP_DQ_SELF_CHECKS` (FORGE_ADMIN) → attach `'TRIGGER_ON_CHANGES'` (ACCOUNTADMIN) | as noted | attach 98 rows, no ERROR; self-checks **93 rows, all TRUE** ("no DMF result yet" = wait and re-call) |
| 11 | `eval/00_setup.sql` (ACCOUNTADMIN) → `10_questions.sql`, `20_sp_run_eval.sql`, `30_sp_build_eval_dataset.sql` (FORGE_ADMIN) | as noted | 30 active questions, 0 unfilled `{{ORDER_ID}}` |
| 12 | `sql/05_app_access/01_app_service_user.sql` → `02_cost_controls.sql` | ACCOUNTADMIN | `FORGE_APP_ROLE`, `FORGE_APP_SVC` (no key yet), the agent grant to `FORGE_APP_ROLE`, `FORGE_WH_MONITOR` (5 credits/day), `OPS.FORGE_APP_CORTEX_BUDGET` (25 credits/month, auto-revoke of Ask) |
| 13 | `SP_RUN_EVAL('b10-v2', 'Q0%' / 'Q1%' / 'Q2%' / 'Q3%')`: 4 separate `sql_execute` calls **in parallel** (each < 15 min), FORGE_ADMIN | FORGE_ADMIN | **30/30** as in the old account on 30 Sep. Watch Q02, Q05, Q14, Q19: in the old account they still called a built-in chart skill (+15–20 s); the no-chart instruction added after that run is untested |

## Checks (the gate)

Do these **on the same day in both accounts** (live vs live), because every "last 12 months"
metric is anchored on `CURRENT_DATE()` and drifts a little each day. Don't compare against the
saved artifacts' exact numbers.

1. **Source data identical:** per table, `COUNT(*)` and `HASH_AGG(*)` for the 10 source tables in
   both accounts: all equal.
2. **Governed layer:** row counts of the 9 governed views equal; masking as each persona (e-mail
   `*** MASKED ***`, credit limit NULL for the personas that must not see it) as in art 03/04.
3. **Metrics:** the 8 canonical verified-query SQLs (the `SELECT * FROM SEMANTIC_VIEW(...)` in
   `semantic/01_semantic_view.sql`) return the same values in both accounts. Persona equality
   (art 09 query) holds.
4. `SP_DQ_SELF_CHECKS`: 93/93 TRUE. `SP_DATA_HEALTH('ALL')`: OK, 5 × `REFERENCE`. Re-capture
   art 10 from the new account (same code as C16: `fetch_json` for the 4 roles + shipments,
   DMF results base64), then run `.venv/Scripts/python tests/tools/build_captured.py`.
5. Eval `b10-v2`: 30/30 (or explain each miss). Update art 08 from `b10-v2` (fetch base64: the
   Hindi answer), and compare with `b10-baseline` from the old account (27/30, p50 17.7 s,
   p95 48.8 s).
6. The replay needed no hand fix, or every fix is committed back to its file.

## After the gate (user actions + the rest of the day)

- **Tell the user the new secrets values** for Streamlit Community Cloud (`deploy/RUNBOOK.md`):
  account `QURFOQP-XU04029`, user `FORGE_APP_SVC`, role `FORGE_APP_ROLE`, warehouse `FORGE_WH`,
  database `SUPPLY_CHAIN_FORGE`, schema `SEMANTIC`.
- **B15a:** when the user pastes the *public* key: `ALTER USER FORGE_APP_SVC SET RSA_PUBLIC_KEY
  = '…'` (ACCOUNTADMIN), check `DESC USER FORGE_APP_SVC` → `RSA_PUBLIC_KEY_FP`. Then RUNBOOK §4
  checks (Ask included) and `pytest -m live` with a `FORGE_APP_ROLE` connection.
- **B12a part 2:** Claude Code's C17 day-append, when it's in the handoff lock (the user
  deferred C17 until after the switch), plus the nightly task with the UTC date passed
  explicitly (the account timezone is America/Los_Angeles).
- **B14:** `pytest -m live` as FORGE_ADMIN + the security review → art 11.
- **B13** (optional): the C12 scale harness on a clone of the new account. A cloned DT keeps
  reading the original database: re-create the clone's DTs.
- **B15:** cost check, the final checks on the public link.
- **Docs:** `COCO.md` connection section; a HANDOFF note to Claude Code (account changed, no
  FQN changes, new identifier for the secrets; `snowflake_execution_notes.md` is Claude Code's
  file, so ask them to update its header).

## Risks and what to do

| Risk | What to do |
|---|---|
| `02_cost_controls.sql`: a resource-monitor notification needs a verified e-mail for the admin user | Record the error; ask the user to verify the e-mail in Snowsight (Profile), then re-run the file |
| A Cortex model named in the agent (`claude-sonnet-4-5`) isn't offered | Cross-region is `ANY_REGION`, so it should be. If not, record the error and ask the user before changing the model |
| DMFs show "no result yet" | Serverless DMFs take a few minutes after attach: wait and re-call the self-checks |
| A DT refresh fails right after creation | Run `ALTER DYNAMIC TABLE … REFRESH` once and record it |
| A Claude Code SQL file fails | Smallest run-blocking fix only, recorded as a diff in `B08m_run.md`; anything bigger goes back to Claude Code via the handoff lock |
