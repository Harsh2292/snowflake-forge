# B12a test report: nightly full reload (option B) vs day-append (option A)

| | |
|---|---|
| **Date** | 2026-09-30, 13:25–13:50 UTC |
| **Asked by** | Claude Code (HANDOFF, "Question for CoCo: freshness fix 2"), relayed by the user |
| **Where** | throwaway clone `SUPPLY_CHAIN_FORGE_RELOAD` of `SUPPLY_CHAIN_FORGE` (dropped afterwards; production untouched: `VTTK` 780,439, `CONFORMED.SHIPMENT` 693,241) |
| **Role / warehouse** | `ACCOUNTADMIN` / `FORGE_WH` (XS) |
| **Verdict** | **A (build C17).** B failed on run time and has two design risks. Details below |

## Setup

1. `CREATE DATABASE … CLONE SUPPLY_CHAIN_FORGE`: 45 s.
2. **Finding: a cloned dynamic table keeps reading the original database.** The clone's
   `CONFORMED.SHIPMENT` still read `SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK`, `…CONFORMED.SALES_ORDER`
   and so on, because every definition names the database in full. The clone's DTs arrive
   `SUSPENDED`.
   - Fix for the test: re-created the 10 DTs from `sql/04_governance/06_conformed_layer.sql`
     with the database name replaced.
   - **All 10 initial (full) builds took 42.7 s on XS in total** (ORDER_LINE 7.0 s, SHIPMENT
     5.4 s).
   - B13 and any clone-based test need the same step.
3. The clone's DMF schedules were switched off: `SP_ATTACH_DMFS(clone, '')` gave 21 SET
   SCHEDULE OK. Its 77 ADD rows returned ERROR because the clone has no copy of the catalogue's
   reference tables; not needed for this test.
4. **The baseline check is valid.** The four metrics computed directly on `CONFORMED` (the
   semantic view's formulas and §3a windows) equal the live semantic view exactly, on the clone
   and on production:
   - OTD 0.875272
   - fill 0.926086
   - DOI 36.436790
   - landed 604.81

## The test (Claude Code's steps)

1. `ALTER DYNAMIC TABLE … SUSPEND` on all 10 clone DTs.
2. At the same time, in two sessions:
   - **reload:** `SP_GENERATE_DATA(clone, 1, 20260929, '2026-10-01')`, then `SP_INJECT_MESS`
   - **probe:** every 20 s, `COUNT(*)` and `MAX(load_ts)` on `CONFORMED`, and `COUNT(*)` on
     `VTTK` / `VBAP`

## Results

| Check | Result |
|---|---|
| **No partial read from `CONFORMED` while its DTs are suspended** | ✅ **18 of 18 probes** (6 min) read the full old data (693,241 shipments, 2,000,369 lines, max `load_ts` 30 Sep 04:59), while the source tables were **empty** (`VTTK` 0, `VBAP` 0) from 20 s after the start |
| **Run time** | ❌ **the generator's `TMP_O` step (the orders of one history year) took ~9 min for 2016 and was just as slow for 2017.** At B08c the same statement took **1.2 s** per year. The operator profile of the 2016 run (`01c76aed-…a6fa`) shows a **`CartesianJoin`: 131,186,469 rows in, 12,034 out, 99.8% of the time**, from `TMP_DAYS d JOIN k ON k.k <= d.cnt` (a range join on the generator). Same code, same data, different plan. At ~9 min × 11 years that's ~1.5 h and ~1.5 credits a night, against a 5-credit/day monitor on `FORGE_WH`, which the app also uses. Stopped after 2017 (the run was cancelled; the answer was clear) |
| Resume → refresh order, the full CONFORMED refresh, self-checks, the §3 ranges after the reload | not reached (the run was stopped). The full rebuild cost is known from setup: 43 s XS |

## Why A, not B

1. **Run time isn't reliable.** A plan flip on the generator's range join turned 130 s into
   ~1.5 h. It's the same kind of failure as the `TMP_S` `OR` join I fixed at B08c. A
   nightly job that rewrites 10 years of data carries this risk every night; one that adds one
   day (~180 orders) does not.
2. **Suspending protects reads during the load (verified), but not while the DTs refresh.**
   Each DT refresh commits on its own. With B, the whole history is re-drawn and every
   `VBELN` / `TKNUM` means a different order the next day. For the window (at least ~40 s, the
   measured full-build time) while the 10 DTs
   refresh one by one, `SALES_ORDER` can be the new day and `ORDER_LINE` / `SHIPMENT` the old
   one, so joins pair unrelated rows and the metrics are wrong for that window. With A, old
   rows never change, so a half-finished refresh only means "today's rows aren't all in yet".
3. **B re-draws history every night.**
   - order IDs change meaning daily (the evaluation's lookup questions, demo lookups)
   - every DT does a full refresh, and all 77 DMFs re-run over ~10M rows
   - "incremental, clean once" (core rule 2) is lost

   A keeps all three.
4. Both fit the B08m cutover: the new account loads with `END_DATE = '2026-09-30'`, then the
   nightly job catches up day by day (A's rule 1).

## Two findings that apply either way

1. **The account timezone is `America/Los_Angeles`.** `CURRENT_DATE()` lags the UTC date by
   7–8 h. The nightly task must pass `CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::DATE`,
   never `CURRENT_DATE()`. (The §3a windows are unaffected: at 05:30 UTC the LA date is
   yesterday = the new last business date.)
2. **For Claude Code (`data_gen/10`, and in C17):** the `JOIN k ON k.k <= d.cnt` pattern (a
   generator joined by range) can plan as a Cartesian join. The B08m cutover regenerates the
   whole dataset with `SP_GENERATE_DATA`, so this can hit the cutover too. Suggested
   replacement, one generator per day without a range join:
   `FROM TMP_DAYS d, LATERAL FLATTEN(ARRAY_GENERATE_RANGE(1, d.cnt + 1)) f` with
   `n = d.cum_prev + f.value`. This is a small run-blocking fix: I can apply it at the cutover
   as a diff, or you can adopt it first.

## Cost of this test

- ~20 min of XS on `FORGE_WH` (≈ 0.35 credits; the monitor showed 0.06 used before the test)
- clone storage: zero-copy, dropped
