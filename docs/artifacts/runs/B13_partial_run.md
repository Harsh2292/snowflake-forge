# B13 run: scale proof, stopped by the user's decision (partial)

| | |
|---|---|
| **Date** | 2026-10-01, 10:47–11:42 PT |
| **Account** | `QURFOQP-XU04029` |
| **Status** | **Stopped** (the user: close out; art 12 doesn't affect the demo). Art 12 not written |
| **Credits** | **6.23** on the temporary warehouses (monitor `FORGE_SCALE_MONITOR`, cap 15), ~5 of them lost to the generator defect below before it was found |
| **Cleaned up** | `SUPPLY_CHAIN_FORGE_SCALE`, `FORGE_SCALE_LARGE`, `FORGE_SCALE_XS` and `FORGE_SCALE_MONITOR` dropped. Production untouched apart from the generator fix (identical output) |

## What ran

| Step | Result |
|---|---|
| `tests/scale/00`, `10`, `20` | OK: `SCALE_QUERIES` 75 rows (70 active), `SP_SCALE_RUN` created |
| `sf1-xs` (production, FORGE_WH XS) | **70 queries, 0 failed**, max 765 ms, total 21.6 s. In `OPS.SCALE_RESULTS` |
| Clone + DMF schedules unset on its 21 objects (so 77 DMFs don't run serverless over 100M rows) | OK; the clone's DTs, task and alert came over suspended |
| `SP_GENERATE_DATA` at SF 50, first attempt | **Cancelled** after ~33 min: ~10 min per history year on LARGE *and* on SMALL |
| Fixed `SP_GENERATE_DATA` at SF 50 (SMALL, Gen 1) | **6.5 min**: VBAK 32,500,000 · **VBAP 102,055,464** · VTTK 35,394,487 · MARD 2,156,400 |
| `SP_INJECT_MESS` at SF 50 | cancelled by the stop (logged 10 rows in `GEN_MESS_LOG` for `TARGET_DB = SUPPLY_CHAIN_FORGE_SCALE`; production checks filter on `TARGET_DB`) |
| `clone-xs`, `clone-large`, art 12 | not run |

## Defect found and fixed: a cartesian join in the generator's shipment step

`GET_QUERY_OPERATOR_STATS` on the slow statement (`CREATE … TMP_S`, 2018 chunk):
- **CartesianJoin**: 2,754,950 shipments × 42,820 carrier-days = **39,618,795,040 rows**
- the `(lane, date)` equality ran as a post-filter (78.8% + 15.3% of the time)

Cause: `dptbg` (the ship date) is computed inside the same query, so the optimizer couldn't use
`cd.d = l.dptbg` as a hash key. At SF 1 it is 2.3 billion rows a year (13 s), so it went
unnoticed. At SF 50, warehouse size made no difference.

Fix in `data_gen/10_sp_generate_data.sql` (Claude Code's file; the C08 precedent for
run-blocking fixes). The shipment rows are materialized first (`TMP_S_L`), then joined to
`TMP_CARRIER_DAY` in a second statement. The logic, the hashes and the ordering are unchanged.

**Proof:** SF 0.01 into the clone, old vs fixed procedure, `COUNT(*)` + `HASH_AGG(*)` on all 10
source tables. **Identical on all 10.** Deployed to `SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA`
(grants unchanged: owner only). Production data was not regenerated.

## Lessons (in `COCO.md`)

- Measure one chunk on XS before sizing up. A statement that is as slow on LARGE as on SMALL is
  serial, or a bad plan; a bigger warehouse only costs more.
- Resizing a warehouse in the middle of a running `CALL` didn't lower the billing rate. Billing
  stayed at the LARGE rate: 5.0 credits in ~33 min.
- New warehouses in this account default to **Gen 2 with query acceleration on**. For a test
  warehouse, set `GENERATION = '1'` and `ENABLE_QUERY_ACCELERATION = FALSE` to keep the cost
  predictable.
- `python_repl` calls stop after ~5 min, but the query keeps running in Snowflake; poll
  `GEN_LOG` / `QUERY_HISTORY` instead of waiting.

## To finish later (post-hackathon, ~2–3 credits)

1. Clone, unset the DMF schedules, run the fixed generator at SF 50 (SMALL Gen 1, ~7 min).
2. Run `SP_INJECT_MESS`.
3. Re-create the clone's CONFORMED with the 06 file pointed at the clone. Also its governed
   views, semantic view and persona procedures, since the cloned ones read production.
4. Run `clone-xs` and `clone-large`, then the art 12 queries in `tests/scale/99_run.sql`.
5. Drop everything.
