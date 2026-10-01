# B08m run report — the move to the event account (cutover)

| | |
|---|---|
| **Date** | 2026-09-30 (evening) |
| **From → to** | `tyduokn-gf25237` (DA53081, read-only now) → **`QURFOQP-XU04029`** (VC33954, user `LAZYBOY2`, Enterprise, `AZURE_CENTRALINDIA`) |
| **How** | `sql/replay_helper.py` from CoCo's Python REPL, every call with `connection='QURFOQP-XU04029'`. This session itself ran on the old account's connection (its CoCo tokens billed there) |
| **Status** | **DONE**: the whole build replayed from the repo with **no hand fix**; the data is byte-identical; every compared number matches |

## Replay (card steps 1–13)

| # | Step | Result |
|---|---|---|
| 1 | `sql/01_setup/01_database.sql` | OK. First attempt failed only because the helper's `USE WAREHOUSE FORGE_WH` ran before the file created `FORGE_WH`: re-run with `wh='COMPUTE_WH'` (a runner detail, not a file fix) |
| 2 | `02_roles_grants.sql` | OK: the 4 roles granted to `LAZYBOY2` (the `CURRENT_USER()` fix) |
| 3–4 | `03_schemas_v2.sql`, `02_tables/05_source_v2.sql` | OK: 9 schemas, 10 source tables |
| 5 | `data_gen/00`, `10`, `20`, `30`; then `SP_GENERATE_DATA(…, 1, 20260929, '2026-09-30')` + `SP_INJECT_MESS` | OK. The SF 0.01 dry run and `SP_GEN_SELF_CHECKS` were skipped: the data is proven byte-identical (below), which is stronger. Generate: **894 s** (old account 133 s), although its own stages sum to ~50 s and no query took over 9 s: per-statement overhead on a new account, not a plan problem. Mess: 64 s, the same injected counts as the old run |
| 6 | `sql/04_governance/01`, `02`, `06`, `03`, `04`, `05` | OK: tags, 4 masking policies, `CONFORMED` (10 DTs), 9 governed views, persona procedures |
| 7 | `semantic/01_semantic_view.sql` | OK (then re-created once more after the Q18 fix below: 14 verified queries) |
| 8 | `quality/00`, `10`, `20`, `30`, `40` | OK |
| 9 | `agent/01_agent.sql` | OK |
| 10 | `SP_ATTACH_DMFS('5 MINUTE')` → self-checks → `SP_ATTACH_DMFS('TRIGGER_ON_CHANGES')` | 98 rows each time (77 ADDED/EXISTS + 21 schedule OK), no ERROR |
| 11 | `eval/00`, `10`, `20`, `30` | OK: 30 active questions, 0 unfilled, Hindi intact |
| 12 | `sql/05_app_access/01`, `02` | OK: `FORGE_APP_ROLE`, `FORGE_APP_SVC` (no key yet), monitor, Cortex budget (its usage refresh initiated). No e-mail verification problem |
| 13 | `SP_RUN_EVAL('b10-v2', …)` × 4 in parallel | 28/30 (below) |

## The gate: old vs new, live, same evening

| Check | Result |
|---|---|
| 10 source tables, `COUNT(*)` + `HASH_AGG(*)` | **all 10 identical** (VBAK 724,949 · VBAP 2,074,071 · VTTK 780,439 · MARD 2,167,092 · KNA1 2,025 · LFA1 152 · MARA 1,204 · SOURCING 2,503 · TCURR 23,310 · T001W 12) |
| 9 governed views, row counts | identical |
| All 15 verified-query SQLs (before the Q18 change) | 14 identical; `vq_below_reorder_by_plant` has the same numbers, only a different order among ties |
| Masking as PLANNER / BUYER / LOGISTICS | identical (BUYER sees `*** MASKED ***`; credit limit NULL); `V_CUSTOMER` has the same 3 policy references |
| `SP_METRICS_AS_*` × 3, `SP_SAMPLE_AS_*` × 3 | identical |
| `SP_DQ_SELF_CHECKS` | **93/93 TRUE** |
| `SP_DATA_HEALTH('ALL')` | **OK**, 5 × REFERENCE, identical as the 4 roles |
| DMF results (77) | 67 identical; the 10 FRESHNESS values are lower (seconds since the last change: the tables were just loaded) |

**Art 10 re-captured** from the new account; `build_captured.py` → `captured.json`.

## Eval `b10-v2` (art 08 re-written)

**28/30 passed. p50 12.3 s, p95 36.5 s** (baseline 27/30, p50 17.7 s, p95 48.8 s).
- The no-chart instruction works: Q02 11.1 s, Q05 10.3 s, Q19 8.4 s (no chart skill any more).
- **Q18 fixed during the run.** The first answer gave landed cost ($604.81) for "average freight
  cost per shipment": Analyst matched it to the new `vq_landed_cost_overall`. That verified
  query was removed (`semantic/01_semantic_view.sql`, now 14); re-run: PASS, $468.29.
- **Q22 FAIL, a real agent miss:** fill rate stated as 88.1%, the governed value is 92.6%
  (Analyst's own CTE in a two-part question). The app's C14 router answers this question from
  the semantic view instead.
- **Q23 FAIL is a runner limitation:** the answer ($604.81, 95,707 shipments) is right; the
  runner can't re-run multi-statement SQL.

`pytest -q`: 725 passed with the new art 08 and art 10.

## Extra verification (same night, after the user asked "is everything really shifted?")

**1. Full object diff, old vs new** (`INFORMATION_SCHEMA` + `SHOW`):
- **122 database objects identical**: tables, views, DTs, procedures, functions (with argument
  signatures), schemas, and per table a checksum of every column's name, type and position.
- Account level identical: warehouses (FORGE_WH XS, 60 s, on `FORGE_WH_MONITOR`), the monitor
  (5 credits/day, 75/100/110%), the budget, agent, semantic view, the 10 DTs, the 7 tags, the 4
  masking policies, roles, `FORGE_APP_SVC` (SERVICE, no key yet), cross-region Cortex.
- 77 DMF associations report in both.

**2. Grants, all 5 roles:** PLANNER/BUYER/LOGISTICS identical (24 each). FORGE_ADMIN 828 vs 827.
The only differences are expected, or are drift in the OLD account:
- account-level grants name the account (`DA53081` / `VC33954`)
- 6 DT grants on Snowflake-generated internal (UUID) names
- the old account's `SP_DQ_SELF_CHECKS` became FORGE_ADMIN-owned when C16 re-created it; the
  new one follows the script (owned by ACCOUNTADMIN)
- **the old account's `FORGE_APP_ROLE` had lost USAGE on `SP_DATA_HEALTH`**: C16's
  `CREATE OR REPLACE` dropped a grant made by `sql/05_app_access/01`. The new account has it.
  Rule added to `COCO.md` (gotchas): after re-creating any object the app uses, re-run
  `sql/05_app_access/01_app_service_user.sql` (idempotent; keeps the key).

**3. The public app's own queries, as `FORGE_APP_ROLE` (secondary roles off), new account.** The
SQL was generated by the app's own code (`forge_data.build_metric_sql` over every
`config.VALID_PAIRINGS` pairing, `build_call_sql`, `NAIVE_OTD_SQL`, `QUALITY_SQL`,
`build_agent_sql` + `agent_request`):
- **71/71 queries succeeded**: 62 metric × dimension queries, the 6 persona procedures,
  `SP_DATA_HEALTH('ALL')`, the §8 naive-OTD query (0.6818), the quality results (77 rows).
- **All 62 metric results equal FORGE_ADMIN's** (governed numbers don't depend on the role).
- Masking applies to the app: e-mail `*** MASKED ***`, credit limit NULL. A source table the app
  must not read (`ERP_SOURCE.KNA1`) is refused.
- **Ask:** one agent call as the app role: `completed` in 12.8 s, "87.5% for the last 12 months".

**4. `pytest -m live` (C13): 148 passed, 0 failed** (1 Oct, 05:18–05:22 UTC, 225.9 s, new
account, user `LAZYBOY2`, the connection's default role ACCOUNTADMIN). Per contract section: §3
ranges / §5.1 / §8 11 · §4 pairings / §5.2 68 · §1/§3/§4 objects 2 · §6 one number per persona
8 · §5.3/§9 agent 10 · data health + DMFs 15. The only warnings are a connector-library
deprecation notice. **The first live run of the suite ever.**
- Why the first two attempts skipped everything: the connection uses browser OAuth, and CoCo's
  shell is sandboxed, so the browser's redirect to the local listener on `127.0.0.1` never
  reached the test process ("Unable to receive the OAuth message within a given timeout"). The
  user's approvals went nowhere. **Fix: run it with the sandbox disabled** (the bash tool's
  `dangerously_disable_sandbox`), and the user approves the browser sign-in within ~2 min.
- **Run 2, as the public app (B15a), 1 Oct: 148 passed, 0 failed** (229.8 s). User
  `FORGE_APP_SVC`, role `FORGE_APP_ROLE`, no secondary roles, key-pair JWT (no browser). The
  connection came from a throwaway `connections.toml` in `%TEMP%\forge_svc_home` via
  `SNOWFLAKE_HOME`, so the user's own `~\.snowflake\connections.toml` is untouched.
- **B15a key:** `ALTER USER FORGE_APP_SVC SET RSA_PUBLIC_KEY` (the user's `rsa_key.pub`) →
  `RSA_PUBLIC_KEY_FP = SHA256:iiLw9woPFOJe6lO+YZOeHaMmfXqkZg0PM2iBq7WFyv0=`; the fingerprint
  computed from the user's private key file is identical. The private key is unencrypted and
  lives outside the repo (`.gitignore` also blocks `rsa_key*`).

## Left in the new account (next session)

- ~~`FORGE_APP_SVC` has no key yet~~ done 1 Oct (above). Left for B15a: the Community Cloud app
  + RUNBOOK §4 checks on the public link.
- The C17 day-append and the nightly task (B12a part 2).
- B14, B15; B13 optional.
