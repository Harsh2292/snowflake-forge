# C17b run report — the nightly day-append (`data_gen/40_sp_append_day.sql`, `99_run.sql` Step 3)

| | |
|---|---|
| **Date** | 2026-10-01 (~11:00 UTC) |
| **Account** | `QURFOQP-XU04029` (VC33954), the event account |
| **Role / warehouse** | `ACCOUNTADMIN` / `FORGE_WH` (XS) |
| **Status** | **DONE**: no fix needed in `data_gen/`. Production is caught up; the nightly task runs at 05:30 UTC |

## 1. Procedure

`data_gen/40_sp_append_day.sql` → `OPS.SP_APPEND_DAY` created (one statement, OK).

## 2. Clone proof (`SUPPLY_CHAIN_FORGE_C17B`, zero-copy; its 10 DTs suspended, judged on SOURCE)

| Step | Call | Result |
|---|---|---|
| 3a | `('…_C17B', 1, 20260929, '2026-10-01')` | `OK`, 2026-09-30 → 2026-10-01, `days_added 1`, 47 s. VBAK new 339 · VBAK versions 458 · VBAP new 1,072 · VBAP versions 633 · VTTK new 231 · VTTK versions 309 · MARD 3,600 · TCURR 9. max LOAD_TS 2026-10-01 05:00 |
| 3b | same again | `days_added 0`, nothing written, 4 s (idempotent) |
| 3c | `… '2026-10-04'` | `days_added 3`, 62 s. VBAK new 834 · VBAP new 2,627 · VTTK new 970 · MARD 10,800 · TCURR 18. max LOAD_TS 2026-10-04 05:00 |

**3d checks (clone):**
- Orders per business date: Thu 1 Oct 355, Fri 355, Sat 124. Generated history for the same weekdays: 337–339 and 119. About 5% above: inside the noise, but noted for you.
- Shipped per day: 231–348, inside the history range (217–382); the 231 is a Wednesday, like the 217–248 Wednesdays before it.
- Delivered per day: 279–311 (history 249–321).
- Max LOAD_TS ≤ 2026-10-04 05:00 in all 5 tables ✅.
- OPEN orders past their ship date: **0** ✅. Duplicate VTTK latest versions: **0** ✅.
- 12 orders dated Nov 2026 – Oct 2027 exist in production since the original load (deliberate mess); the append added none.
- `SP_GEN_SELF_CHECKS` on the clone: one row, `GENERATOR_RUN` FALSE ("No completed SP_GENERATE_DATA run found for this database"): `GEN_LOG` names the production database, so the clone can't match. Expected.

The clone was dropped afterwards.

## 3. Production

- `SP_APPEND_DAY('SUPPLY_CHAIN_FORGE', 1, 20260929, '2026-10-01')` (the UTC date): `OK`,
  `days_added 1`, 42 s, the **same row counts as 3a** (deterministic).
- The 10 `CONFORMED` DTs refreshed at once: INCREMENTAL where data changed, ~44 s in all.
- **`SP_DATA_HEALTH('ALL')`: OK; as-of date 2026-09-29 → 2026-09-30, freshness 6.4 h** (it was
  ~30 h old and would have turned WARN at ~17:00 UTC).
- `SP_DQ_SELF_CHECKS`: **93/93 TRUE** on the appended data.

**`SP_GEN_SELF_CHECKS` on production after the append: 7 FALSE, all explained, none a data
defect.** For Claude Code (the file is yours): the generator's self-checks don't know about
appended days yet.

| Check | Expected | Actual | Why |
|---|---|---|---|
| `LOAD_TS_CAP` VBAK / VBAP / VTTK / MARD | 0 | 797 / 1,705 / 540 / 3,600 | exactly the appended rows: the check assumes nothing loads after the generator's END_DATE |
| `DATA_DUPLICATE_KEYS` VBAP | 30,511 | 31,144 | +633 = the append's VBAP versions (shared keys by design) |
| `DATA_NON_CONTRACT_CODES` VTTK.CARRIER_CD | 45,565 | 46,898 | +1,300 known since C08, +33 = the append's M03 variants on new shipments (33 counted) |
| `CLEAN_FILL_YEAR_MIN` | 0.905–0.945 | 0.9007 | known since C08 (2021) |

Suggested change: cap `LOAD_TS_CAP` at the latest `SP_APPEND_DAY` end date (or skip rows from
appended loads), and add the append's versions and variants to the expectations.

## 4. The nightly task (CoCo, `sql/06_ops/05_nightly_append_task.sql`)

`OPS.FORGE_NIGHTLY_APPEND`:
- schedule `USING CRON 30 5 * * * UTC`, warehouse FORGE_WH
- 3 failures in a row suspend it; 30-min timeout
- passes `SYSDATE()::DATE` (UTC) to `SP_APPEND_DAY`, then refreshes the 10 DTs so the app sees
  the day within minutes (their target lag is 1 day)

Manual `EXECUTE TASK`: **SUCCEEDED** (0 days, as expected). First scheduled run:
**2026-10-02 05:30 UTC**. `OPS.FORGE_OPS_WATCH` e-mails if data health turns WARN anyway.

## Cost

Clone proof ~2 min + production ~1.5 min + the self-checks on XS: about 0.1 credits. Nightly: ~1.5 min of XS ≈ 0.03 credits.
