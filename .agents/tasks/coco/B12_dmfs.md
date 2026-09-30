# B12 — Data-quality checks (Day 2)

> **Owner**: CoCo · **Milestone**: M5 · **Contract**: v1.5 (CR-006: `SP_DATA_HEALTH`, §3a as-of date)
> **Spec**: `.agents/tasks/COCO_TASKS.md` § B12 · **Plan mode**: waived by the user (30 Sep)
> **Depends on**: B08c (v2 source loaded and messy, `CONFORMED` built), C10 (`quality/`, handoff lock)

## Goal

Run Claude Code's C10: system and custom DMFs on `SOURCE` and `CONFORMED`, on a schedule,
plus `SEMANTIC.SP_DATA_HEALTH` (the agent's `data_health` tool, wired in B10). Capture art 10.

## Build

1. Edition check: Enterprise (DMFs need it). ✅ `snowflake_execution_notes.md`.
2. Run C10 in order:
   - `00` (ACCOUNTADMIN): catalogue, valid-code tables, `V_CONFORMED_FACTS`, and the grants,
     incl. `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` to `FORGE_ADMIN`
   - `10` (ACCOUNTADMIN): 7 custom DMFs
   - `20` (ACCOUNTADMIN): `SP_ATTACH_DMFS`
   - `30` (FORGE_ADMIN): `SP_DATA_HEALTH`, with USAGE to the personas
   - `40` (ACCOUNTADMIN): `SP_DQ_SELF_CHECKS`
3. `99_run.sql`:
   1. attach `'5 MINUTE'`
   2. `SP_DATA_HEALTH('shipments')`
   3. after the warm-up, `SP_DQ_SELF_CHECKS`
   4. attach `'TRIGGER_ON_CHANGES'`
   5. `SP_DATA_HEALTH('ALL')` as FORGE_ADMIN and each persona
4. Capture art 10 `docs/artifacts/10_dmf_results.json`:
   - the latest `DATA_QUALITY_MONITORING_RESULTS` row per association
   - `SP_DATA_HEALTH('ALL')` per role
   - the shipments entity
5. Run report `docs/artifacts/runs/C10_run.md`.

## Gate

| # | Check | Result |
|---|---|---|
| 1 | Results land in `DATA_QUALITY_MONITORING_RESULTS` | ✅ all **77/77** associations (CONFORMED 40, ERP 17, SRM 7, TMS 7, WMS 6) |
| 2 | `SOURCE` shows the injected defects at the spec rates | ✅ E01, E05, E09a, E09b inside `[injected, 1.25 × injected + 5]`; E04 measured 19,390 against 19,589 injected (−1%, rate 0.93%): the self-check's strict lower bound, not a data defect |
| 3 | `CONFORMED` shows none of the repairable defects | ✅ every ZERO check is 0 (duplicates, code variants, test records, orphans, negative on-hand, over-shipment); E01 0.80% and E08 0.10% are excluded by rule, under threshold |
| 4 | `SP_DATA_HEALTH` returns the B8b shape for every entity | ✅ 9/9 entities; `ALL` 2,436–2,608 bytes ≤ 16 KB; `ERROR` for an unknown entity; identical for all four roles |
| 5 | Grants: `DATA_QUALITY_MONITORING_VIEWER` to FORGE_ADMIN; USAGE on `SP_DATA_HEALTH` for the agent's callers | ✅ |
| 6 | Steady schedule | ✅ `TRIGGER_ON_CHANGES` on all 21 tables (no CRON fallback needed) |

## Result: ✅ done 2026-09-30, gate 6/6

- **Run fix (10 catalogue rows in `quality/00_setup.sql`):** `SNOWFLAKE.CORE.FRESHNESS` has no
  `TIMESTAMP_NTZ` signature, and every `LOAD_TS` is NTZ; `CONFORMED.FX_RATE` has no `load_ts`.
  The 10 `*_FRESH` rows now use `ON ()` (time since the table last changed). Diff in
  `C10_run.md`.
- `SP_DQ_SELF_CHECKS`: **90/91 TRUE.** The FALSE is `DQ_S_VBAP_E04` (above); passed to
  Claude Code as a tolerance suggestion.
- **Finding for Claude Code:** `SP_DATA_HEALTH('ALL')` reads **FAIL** on freshness alone.
  Parts and plants were last loaded in 2016, suppliers and sourcing in Dec 2025, customers in
  Aug 2026. No check fails. The 36/72 h rule should apply to transactional entities only, or
  the agent will call master data stale on camera. Suggestion in `C10_run.md`.
- Cost: the warm-up ran ~35 min at 5-minute intervals (serverless); it's now event-driven.
