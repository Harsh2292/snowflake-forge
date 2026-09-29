# C08 — Realistic data generator (`data_gen/`)

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs (handoff lock) |
| **Milestone** | M3, replan Day 1 (29 Sep): **critical path**, READY by the end of the day |
| **Prerequisite** | `docs/DATA_SPEC.md` (B08b ✅), CR-006 ✅ (contract v1.5). CoCo's B08c creates the v2 source tables and schema `OPS` before running this |
| **Writes** | `data_gen/00_setup.sql`, `10_sp_generate_data.sql`, `20_sp_inject_mess.sql`, `30_sp_gen_self_checks.sql`, `99_run.sql`, `README.md`; `tests/unit/test_data_gen_sql.py` |
| **Status** | ✅ **READY** 2026-09-29: handed to CoCo (HANDOFF "Ready for CoCo to run"). Offline gate green (`tests/unit/test_data_gen_sql.py`, 23 checks). The live gate is CoCo's run report `docs/artifacts/runs/C08_run.md` |

---

## Goal

Three procedures in `SUPPLY_CHAIN_FORGE.OPS` that fill the 10 v2 source tables with 10
years of realistic data ending yesterday, then damage it exactly as DATA_SPEC §4 lists, then
prove both with self-checks. They are deterministic: the same seed, scale factor and end
date give the same bytes.

## Why

- The core system has to be proven on data that looks like a real business: 650K orders,
  seasonality and growth, carrier churn, currencies, duplicates and edge cases. The v1
  sample is 12K clean rows.
- It must also run at 100M+ order lines on a clone (B13) with the same code, and re-run
  cleanly on a new, empty account (the account switch, 1 Oct).

## Steps

1. **`00_setup.sql`**: `OPS` if missing; the log tables `GEN_LOG`, `GEN_STATS`,
   `GEN_MESS_LOG` (`IF NOT EXISTS`); `SELECT` on them to `FORGE_ADMIN`.
2. **`10_sp_generate_data.sql`**: `OPS.SP_GENERATE_DATA(TARGET_DB, SCALE_FACTOR, SEED,
   END_DATE)`, caller's rights, `USE SCHEMA <TARGET_DB>.OPS`, schema-qualified table names.
   - The stages follow §2.3: masters, `TCURR`, `SOURCING`, then per history year
     `VBAK` → `VBAP` → `VTTK`, then `MARD` per year.
   - Hash-only randomness (§6), gap-free numbering, and exact `NUMBER` sums wherever a sum
     feeds the data (floating-point sums can differ between runs).
   - Writes only clean rows, then records the clean stats in `GEN_STATS`: row counts,
     distinct keys, `HASH_AGG` checksums, and the four metrics per §5.3/§5.4 computed on
     the clean load. So a badly tuned distribution shows up now, not at B08c.
3. **`20_sp_inject_mess.sql`**: `OPS.SP_INJECT_MESS(TARGET_DB, SEED, END_DATE)`.
   - Every §4 defect is injected with **exact counts** (round(rate × base), picked by hash
     rank), so the rates hold even at SF 0.01.
   - The order is fixed so copies stay identical and no `LOAD_TS` passes the cap:
     M04 → E-codes → M06 → M02 → M03 → M07 → M01.
   - The base and affected counts go to `GEN_MESS_LOG`.
4. **`30_sp_gen_self_checks.sql`**: `OPS.SP_GEN_SELF_CHECKS(TARGET_DB)` returns the §7.1
   table:
   - row counts
   - uniqueness of the clean load
   - checksum repeat, compared with the previous run that used the same parameters
   - the E10 conflict rate
   - plant × year coverage
   - the metric targets from §5.4
   - M05 rates (reported) and FX coverage (gated)
   - every §4 rate against its target, plus cross-checks on the data
5. **`99_run.sql`**: the driver CoCo runs.
   - Setup.
   - Dry run at SF 0.01, **twice**, with the checks. This proves determinism cheaply and
     surfaces errors inside procedure bodies, which compile-only mode doesn't check.
   - Then SF 1: generate, inject, check.
6. **`tests/unit/test_data_gen_sql.py`** (offline) checks every `data_gen/` file:
   - no `RANDOM()` / `UNIFORM(…RANDOM…)`, and no `CURRENT_DATE` in the data
   - no account name or locator
   - a header with card, role, warehouse and run order
   - `CREATE OR REPLACE` / `IF NOT EXISTS` only; balanced `$$`
   - every §4 code present in the injector, with its rate
7. Hand over: a row in HANDOFF "Ready for CoCo to run", with the run order and expected
   results; confirm in HANDOFF that the spec is implementable, and list the decisions below.

## Decisions where the spec leaves room (listed for CoCo in HANDOFF)

- **VTTK.VBELN trailing space (M07)**: `VARCHAR(12)` can't hold `ORD000000001 `. The
  injector uses lower case instead (`ord000000001`); `UPPER(TRIM())` repairs both.
- **Row-count tolerance**: ±1% where §2 gives an exact formula (VBAK) or a fixed count
  (masters); ±10% where §2 says "~" (VBAP, VTTK, MARD, SOURCING, TCURR).
- **M04 test customers carry 0.3% of orders**: existing orders are reassigned to
  `TEST0001`–`TEST0005` (their lines and shipments follow). Test parts are put on 0.1% of
  existing lines. The test suppliers get one secondary sourcing row each.
- **TCURR** starts one week before the history, so every date has a rate on or before it
  (the M05 gate). The rate path is a bounded, mean-reverting curve (two slow waves plus
  small daily noise, in log space), with a daily step well under 0.6%.
- **APAC share 20% → 32%**: with 25% of customers in APAC and equal weights that's not
  reachable, so customers onboarded after the history start in APAC get a 1.5× order
  weight (≈ 20% → ≈ 30%). Reported, not gated.
- **Stocked parts per plant**: a uniform hash pick of 300 of the 1,200 parts ("weighted to
  the categories the plant ships" isn't defined).
- **Split shipments**: the second part ships 1–2 days after the first; if that's after
  `L`, it doesn't exist yet.
- **Fuel index**: linear 1.00 (2021-07-01) → 1.35 (2022-12-31) → 1.10 (2023-12-31), then
  flat. Carrier freight bases are fixed per carrier, within 150–450.
- **Supplier countries** use the §2.1 customer country lists per region.
- **Returns (E03)**: 1.5% of orders; shipments are removed from some of them, so 60% of
  returns have one.

## Gate (from CoCo's run report)

- Every statement runs; the SF 0.01 dry run twice gives identical checksums.
- At SF 1: every self-check passes (M05 rows are report-only). The clean-load metrics are
  inside the §5.4 targets. The whole run fits the runtime budget (≤ 20 min on XS).

## On completion

1. This card
2. `.agents/NEXT.md` (C08 row)
3. `.agents/HANDOFF.md` ("Latest from Claude Code" + the "Ready for CoCo to run" row)
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
