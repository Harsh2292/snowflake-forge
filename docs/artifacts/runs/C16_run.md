# C16 run report — freshness fix 1 (`quality/30_sp_data_health.sql`, `quality/40_sp_dq_self_checks.sql`)

| | |
|---|---|
| **Date** | 2026-09-30 |
| **Account** | `tyduokn-gf25237` (DA53081) |
| **Role / warehouse** | `FORGE_ADMIN` / `FORGE_WH` (XS); `SP_DATA_HEALTH('ALL')` also as `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` |
| **Files run** | `quality/30_sp_data_health.sql`, then `quality/40_sp_dq_self_checks.sql` (both one `CREATE OR REPLACE PROCEDURE`). `00_setup.sql` not re-run (comment-only change). No DMF re-attach |
| **Status** | **DONE**: no fix needed from CoCo |

## How it was sent

The header comments were dropped before sending (they hold non-ASCII characters that the tool
bridge garbles), and the one `§` in `SP_DATA_HEALTH`'s `COMMENT` literal was sent as the
escape `\u00a7`. The procedure bodies were sent byte for byte. Both `CREATE` statements:
`Statement executed successfully.`

## 1. `CALL SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS('SUPPLY_CHAIN_FORGE')`

**93 rows, 93 TRUE** (B12: 91 rows, 90 TRUE). Query `01c76bd4-0002-23d2-000f-b48a00091062`.

| New / changed check | Expected | Actual | Passed |
|---|---|---|---|
| `HEALTH_REFERENCE_KINDS` | 5 | 5 | TRUE |
| `HEALTH_REFERENCE_NOT_AGED` | 0 | 0 | TRUE |
| `DQ_S_VBAP_E04` (now ≥ 0.95 × injected) | 19,589 injected | 19,390 (0.99×) | TRUE (was the B12 FALSE) |
| `HEALTH_SHAPE_ALL` | 0 missing keys | 9/9 entities, status OK, 2,441 bytes | TRUE |
| `HEALTH_AS_OF` | — | as_of_date 2026-09-29 | TRUE |
| `HEALTH_NO_FAILED_CHECKS` | 0 | 0 | TRUE |

## 2. `CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL')`

`status: OK`. Summary: *"Data is as of 2026-09-29. 9 of 9 entities OK. 5 reference tables
change rarely and are not judged on age. Only the checks that are not OK are listed; ask for
one entity to see all of its checks."*

| Entity | `freshness_status` | `status` | Age (h) |
|---|---|---|---|
| suppliers | REFERENCE | OK | 7,188.7 |
| parts | REFERENCE | OK | 87,636.4 |
| sourcing | REFERENCE | OK | 7,189.0 |
| plants | REFERENCE | OK | 87,636.8 |
| customers | REFERENCE | OK | 757.7 |
| inventory | OK | OK | 12.4 |
| orders | OK | OK | 12.4 |
| order_lines | OK | OK | 12.4 |
| shipments | OK | OK | 12.4 |

At B12 the 4 old reference tables read FAIL and ALL read FAIL. The answer is identical (apart
from `generated_at`) as all 4 roles. `'shipments'`: OK.

Note: the daily tables are 12.4 h old at the capture. Without C17's nightly day-append they
read WARN after 36 h (1 Oct ~17:00 UTC), as expected; that's B12a part 2.

## 3. Art 10 re-captured

`docs/artifacts/10_dmf_results.json`, same shape and queries as at B12:
- `self_checks`: 93 rows, 93 passed, none failed
- `payload.data_health_all` (4 roles) and `payload.data_health_shipments`: new
- `payload.dmf_results_latest`: 77 rows, **no value changed** since B12 (only the
  procedure changed, not the data)

Then `tests/tools/build_captured.py` → `app/utils/captured.json` (299 KB).

## 4. The eval re-run (lock row "Re-run (C16): `eval/10_questions.sql`, then `eval/99_run.sql`")

Run in the old account after B09a's changes (3 new verified queries, agent without
`data_to_chart`; card `.agents/tasks/coco/B09a_verified_queries_speed.md`). `FORGE_ADMIN`,
`FORGE_WH`.
- `eval/10_questions.sql`: its 3 statements were sent base64-encoded (Hindi and `§` in string
  literals) and decoded server-side. Step 1: **30 active questions, 0 unfilled**, Q28's Hindi
  text intact, Q30 present. Your run-time Q30 insert is no longer needed.
- `SP_RUN_EVAL('b10-v2', …)` × 4 batches (`Q0%`, `Q1%`, `Q2%`, `Q3%`), run concurrently:
  **30/30 passed** (b10-baseline 27/30). p50 18.9 s, p95 44.6 s (concurrent batches).
  - Q17 now passes with your all-12-plants ground truth.
  - Q15 and Q21 pass through the new verified queries.
- **Art 08 is not updated yet**: it will be written from the `b10-v2` run in the new account
  (B08m step 13, `.agents/tasks/coco/B08m_account_switch.md`).
- No fix was needed in `eval/`.

## Cost

A few seconds of XS (the self-checks call each `SP_DATA_HEALTH` entity once): < 0.01 credits.
The eval: 30 agent calls, $2.83 of `CORTEX_AGENTS` on 30 Sep in all.
