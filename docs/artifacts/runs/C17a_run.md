# C17a run report — generator range-join fix (`data_gen/10_sp_generate_data.sql`)

| | |
|---|---|
| **Date** | 2026-09-30 |
| **Account** | `tyduokn-gf25237` (DA53081) |
| **Role / warehouse** | `ACCOUNTADMIN` / `FORGE_WH` (XS) |
| **Parameters** | seed `20260929`, END_DATE `'2026-09-30'`; SF 0.01 (the proof), then SF 1 (the timing) |
| **Where** | throwaway scratch clone `SUPPLY_CHAIN_FORGE_C17A` (DMF schedules off, DTs left suspended); the fixed procedure was first installed only as `SUPPLY_CHAIN_FORGE_C17A.OPS.SP_GENERATE_DATA`; the scratch DB was dropped afterwards |
| **Status** | **DONE**: no fix needed from CoCo. The fixed procedure is now deployed to `SUPPLY_CHAIN_FORGE.OPS` |

## Before

The deployed `SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA` was the pre-fix version: 4
`k.k <=` range joins and no `ARRAY_GENERATE_RANGE` (`GET_DDL`). The new file has 7
`ARRAY_GENERATE_RANGE` calls; its only `k.k <=` is inside the comment that explains the fix.

## 1. The proof: pre-fix and fixed, same parameters (SF 0.01)

Both procedures wrote into the scratch DB, one after the other (each truncates and rewrites).
Per-table `COUNT(*)` and `HASH_AGG(*)` after each run:

| Table | Rows | `HASH_AGG` (both runs) |
|---|---|---|
| `WMS_SOURCE.T001W` | 12 | -6836090621822336004 |
| `SRM_SOURCE.LFA1` | 150 | -7490876580963462968 |
| `SRM_SOURCE.MARA` | 1,200 | 4393063826881318349 |
| `ERP_SOURCE.KNA1` | 2,000 | 2029243716159076227 |
| `ERP_SOURCE.TCURR` | 23,310 | -9125865416576074700 |
| `SRM_SOURCE.SOURCING` | 2,489 | -6102828520590550907 |
| `ERP_SOURCE.VBAK` | 6,500 | 5936642801960486596 |
| `ERP_SOURCE.VBAP` | 20,598 | -4565850375553370739 |
| `TMS_SOURCE.VTTK` | 7,114 | 7968270691326684100 |
| `WMS_SOURCE.MARD` | 2,156,400 | -2129774281761543561 |

**All 10 tables are identical.** Time: pre-fix 123.6 s, fixed 114.3 s (at SF 0.01 the time
is mostly MARD, whose size doesn't scale).

## 2. SF 1 timing, plus a stronger check against production

- Fixed `SP_GENERATE_DATA(scratch, 1, 20260929, '2026-09-30')`: **132.8 s**, `status OK`
  (B08c: 130 s).
- `SP_INJECT_MESS(scratch, 20260929, '2026-09-30')`: 62.1 s.
- **The result is byte-identical to production**, which the pre-fix procedure generated at
  B08c on 29 Sep. All 10 tables have the same `COUNT(*)` and `HASH_AGG(*)`: VBAK 724,949 ·
  VBAP 2,074,071 · VTTK 780,439 · MARD 2,167,092 · KNA1 2,025 · LFA1 152 · MARA 1,204 ·
  SOURCING 2,503 · TCURR 23,310 · T001W 12.
- Slowest generator steps in this run (`QUERY_HISTORY`):
  - `TMP_S` max 2.9 s (27 runs, 35 s in all)
  - `TMP_L` max 1.9 s
  - `TMP_OS` 1.5 s
  - **`TMP_O` max 1.5 s per year (the B12a test saw ~9 min per year)**

  No step is near the Cartesian-join plan.

## 3. Deployed

`data_gen/10_sp_generate_data.sql` (its one statement) was run as `ACCOUNTADMIN`:
`SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA` is now the fixed version (`GET_DDL`: 7
`ARRAY_GENERATE_RANGE`). **No data was regenerated in production.** Production data is
already byte-identical to what the fixed procedure produces.

**For B08m:** the new account can replay C08 with this file as is.

## Cost

About 7 minutes of XS in all (SF 0.01 × 2, SF 1 + mess, checksums): ~0.12 credits. The clone
storage was zero-copy and has been dropped.
