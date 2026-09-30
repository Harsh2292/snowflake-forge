# C17 — Nightly day-append: the data gains one real business day every night

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs it (handoff lock), first on a clone, then schedules it (B12a, 05:30 UTC) |
| **Milestone** | Replan Day 3. **In the handoff lock by the end of 1 Oct** (CoCo's ask, user-approved) |
| **Prerequisite** | C08 generator (DONE, run at B08c); `docs/DATA_SPEC.md` §7.1a (added 30 Sep), §3, §4, §6 |
| **Writes** | new `data_gen/40_sp_append_day.sql` (`OPS.SP_APPEND_DAY`), `data_gen/30_sp_gen_self_checks.sql` (an append check), `data_gen/99_run.sql` (a dry-run step), `data_gen/README.md`, `tests/unit/test_data_gen_sql.py` |
| **Status** | **Part A ✅ READY 2026-09-30** (the generator range-join fix, in the lock for the cutover). **Part B (the day-append) ⏸ deferred by the user until after the account switch.** CoCo chose A over the nightly reload (`runs/B12a_reload_test.md`) |

---

## Goal

Every night Snowflake receives one more business day, the way a real ERP, TMS and WMS feed
it:
- new orders and their lines
- orders that ship that day get shipments
- shipments that arrive get delivered
- the day's stock snapshot
- the day's exchange rates

The data stays fresh for the video (2 Oct) and for the judges (after 4 Oct), the 12-month
windows keep moving, and the numbers drift a little each day like real data.

## Why

The loaded data stops at 30 Sep 05:00 UTC. From 1 Oct ~17:00 the daily tables read WARN, and
from 3 Oct they read FAIL. C16 stops *reference* data being called stale, but for *daily* data
"stale" is simply true, unless new days arrive.

## Key design finding (30 Sep, from reading the generator)

- The full generator can't be re-run for "one more day". Its history is always the 10
  years ending on `END_DATE`, with a fixed total of 650,000 × SF orders spread over it, so
  moving the end one day shifts every row.
- But each order's life is fully determined by hashes of its own number: customer,
  priority, processing days, lines, plants, carrier, on-time draw and delay are all
  `HASH(SEED, 'VBAK' | 'VBAP' | 'VTTK', n, …)`. So:
  - **existing orders advance exactly as the generator would have.** The append re-derives
    each open or in-transit order's ship and delivery dates from the same hash expressions,
    and writes the new row version when day `D` reaches them.
  - **new orders on day `D`** use the §3.1 volume formula for `D` (growth, season, weekday),
    scaled to the original load's level, with IDs continuing after the current maximum and
    every attribute from the same hash recipe.
- Tell CoCo: DATA_SPEC §7.1a rule 3 says "as the full generator would have for
  `END_DATE = D + 1`". That's exact for lifecycle events, and not literally possible for new
  days' volume (the window moves). This is a one-line spec note, not a contract change.

## Design: `OPS.SP_APPEND_DAY(TARGET_DB, SCALE_FACTOR, SEED, NEW_END_DATE)` (§7.1a)

1. **Where we are:** `from_end_date = MAX(LOAD_TS)::DATE` over `VBAK`.
   - If `NEW_END_DATE <= from_end_date`: return `days_added: 0`, write nothing
     (idempotent).
   - Otherwise loop day by day to catch up (missed nights, or after the cutover).
2. **For each new day `D`:**
   - **New orders:**
     - count from §3.1
     - customers weighted by segment among those active on `D`
     - `PRIO`, `AUART`, cancels, lines, plants, parts, quantities and prices by the
       generator's hash expressions (copied verbatim, with a test that they stay identical)
     - status `OPEN`, or `CANCELLED` at the 4% rate
   - **Lifecycle (new row versions, never UPDATE):**
     - orders whose `DPTBG = D`: a new VBAK version (`SHIPPED`), lines with `QTY_SHIPPED`
       (short-ship rule §3.3), and VTTK shipments (carrier, SLA, promise, costs §3.4–3.6)
     - shipments whose `ACT_DLV_DT = D`: a new VTTK version (`ACT_DLV_DT`, `SHP_STATUS`)
     - orders now fully delivered: a VBAK version `DELIVERED`
   - **Inventory:** the MARD daily snapshot for `D`, with the §3.7 formula per stocked pair
     (the same hash keys as the generator's daily snapshots).
   - **FX:** one TCURR row per currency for `D` (business days), with the generator's
     formula.
   - **Mess on the new rows only, at the §4 rates:** M01 duplicates, M03 code variants, E01
     missing promise, E04 over-ship, E09 orphans. Each by hash, so a re-run is identical.
   - **`LOAD_TS`:** `D + 1` 02:00 + 0–180 hash minutes; the cap becomes `NEW_END_DATE`
     05:00.
3. **Logging:** `GEN_LOG` rows per stage. It returns
   `{target_db, from_end_date, new_end_date, days_added, rows: {…}, injected: {…}, elapsed_s}`.
4. **Runs as `ACCOUNTADMIN`** (the owner of the source tables), `EXECUTE AS CALLER`, schema
   qualified. One day at SF 1 is ~180 orders, so each day takes seconds on XS.
5. **Self-check (`SP_GEN_SELF_CHECKS` + an append check):**
   - row counts within ±1% of the expected growth
   - one primary sourcing row per part
   - no `LOAD_TS` above the cap
   - a second call with the same `NEW_END_DATE` adds nothing
   - no duplicate business keys beyond the M01 rate
6. **`99_run.sql`:** a dry run on a clone:
   - append 1 day, then check
   - append the same day again, and expect 0
   - append 3 days, and expect the catch-up

   CoCo then creates the nightly task in `sql/` (05:30 UTC, serverless) and adds it to the
   B08m cutover replay.

## Not changing
`10_sp_generate_data.sql` stays as it is: the cutover re-runs it in the new account, so it
must not move. The append copies the few hash expressions it needs, and a unit test fails if
the two ever drift.

## Part A, as built (30 Sep): the generator's range joins
- `data_gen/10_sp_generate_data.sql`: 5 range joins on number generators replaced by
  `LATERAL FLATTEN(ARRAY_GENERATE_RANGE(…))`:
  - `TMP_PLANT_MAP` (1..units)
  - `TMP_CUST_MAP` (1..weight)
  - sourcing segments (0..n_chg)
  - secondary sourcing (1..0–2)
  - `TMP_O` (1..cnt per day)
  - order lines (1..nlines)
- The same numbers, so the same rows. The unused `max_k` is removed.
- The supplier-eligibility join (`sp.eff_date <= s.vdatu`, two small tables) is kept.
- Tests:
  - `test_no_range_join_to_generate_numbers` (all `data_gen/` files, comments ignored; shown
    to catch the old forms)
  - `test_generator_uses_flatten_for_every_expansion` (6)
- `pytest -q` 516 passed, 0 failed.
- CoCo proves it with identical checksums on a scratch DB before the cutover.

## Steps
1. Tests first: the hash expressions match the generator's; idempotence guard; `LOAD_TS`
   cap; the return shape; schema-qualified names only; no `UPDATE`/`DELETE` on source
   tables.
2. `40_sp_append_day.sql`: new orders → lifecycle → inventory → FX → mess → log.
3. The self-check addition; the `99_run.sql` dry-run steps; the README.
4. `pytest -q` green, then the handoff lock row with expected results. CoCo runs it on a
   clone first.

## Gate
- [ ] `pytest -q` 0 failures (offline: the SQL's structure, the copied hashes, the guards)
- [ ] CoCo's clone run:
  - 1 day adds ~180 orders plus lifecycle versions
  - the same day again adds 0
  - 3 missed days catch up
  - the self-checks all TRUE
  - `CONFORMED` refreshes
  - `SP_DATA_HEALTH('ALL')` reads OK for the daily tables the next morning
- [ ] CoCo's nightly task runs once for real before the recording (2 Oct)

**Estimate:** 4–6 hours (the lifecycle logic is the bulk). It fits 1 Oct together with C13;
C05 and C14 follow on 2 Oct.
