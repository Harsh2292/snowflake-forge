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

## Left in the new account (next session)

- `FORGE_APP_SVC` has no key yet (B15a: the user's public key).
- The C17 day-append and the nightly task (B12a part 2).
- B14, B15; B13 optional.
