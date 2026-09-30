# C08 run report — data generator (run by CoCo at B08c)

| | |
|---|---|
| **Date** | 2026-09-29 |
| **Account** | `tyduokn-gf25237` (DA53081, AZURE_CENTRALINDIA) |
| **Role / warehouse** | `ACCOUNTADMIN` / `FORGE_WH` (XS; briefly MEDIUM during the aborted first SF 1 attempt, see fix 3) |
| **Parameters** | seed `20260929`, END_DATE `'2026-09-30'`, SF 0.01 (dry run), SF 1 |
| **Prerequisite run first** | `sql/01_setup/03_schemas_v2.sql`, `sql/02_tables/05_source_v2.sql`, `sql/04_governance/01_tags.sql` |
| **Status** | **DONE** (three small run-blocking fixes, below) |

## Fixes CoCo applied (run-blocking, a few lines each)

**1. `COMMENT` must come before `EXECUTE AS`** in `CREATE PROCEDURE` (10, 20, 30). Error:
`syntax error line 6 at position 0 unexpected 'COMMENT'`.

```diff
 LANGUAGE SQL
-EXECUTE AS CALLER
 COMMENT = 'C08: ...'
+EXECUTE AS CALLER
 AS
```

**2. `SELECT … INTO :var` isn't allowed when the select list has a scalar subquery and
there's no `FROM`** (10 line ~845, 20 line ~629). Error: `INTO clause is not allowed in this
context`. Reproduced in an anonymous block; the assignment form works.

```diff
-    SELECT OBJECT_CONSTRUCT( ... (SELECT OBJECT_AGG(...) FROM ...) ... )
-      INTO :result;
+    result := (SELECT OBJECT_CONSTRUCT( ... (SELECT OBJECT_AGG(...) FROM ...) ... ));
```

**3. Performance: the `OR` join in `TMP_S` became a Cartesian join** (10, the shipments
CTE). At SF 1 each year chunk took 107–160 s (the operator profile showed
`CartesianJoin`: 641M rows in → 60K out, 84% of the time, because the planner merged the
`OR` condition with the carrier-day join), so the run would have taken ~22 min and hit the
tool's 20-min timeout. Rewritten as an equivalent `UNION ALL`:

```diff
-        parts AS (SELECT 1 AS part_no UNION ALL SELECT 2),
-        sp AS (
-            SELECT g.n, g.werks, parts.part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num
-            FROM g JOIN parts
-              ON parts.part_no = 1
-              OR BITAND(HASH(:SEED, 'VTTK', g.n, SUBSTR(g.werks, 3)::NUMBER, 'split'), 4294967295) / 4294967295.0 < 0.05),
+        sp AS (   -- part 1 always; part 2 on the 5% split (UNION ALL, not an OR join: see C08_run.md)
+            SELECT g.n, g.werks, 1 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
+            UNION ALL
+            SELECT g.n, g.werks, 2 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
+            WHERE BITAND(HASH(:SEED, 'VTTK', g.n, SUBSTR(g.werks, 3)::NUMBER, 'split'), 4294967295) / 4294967295.0 < 0.05),
```

**Proof it's identical**: the SF 0.01 clean-load `HASH_AGG` checksums of all 10 tables are
the same before and after the fix (runs `437e87e8…` vs `a576ba0a…`). SF 1 then took
**130 s** in total on XS. The first SF 1 attempt (`60fbf34f…`) was cancelled mid-run; the
successful run truncates and rewrites everything (idempotent).

## Calls and results

| # | Call | Elapsed | Result |
|---|---|---|---|
| 0 | `00_setup.sql` | 1.4 s | OK |
| 0 | `10` / `20` / `30` (after fixes 1–3) | < 2 s each | `CREATE PROCEDURE` OK |
| 1 | `SP_GENERATE_DATA(…, 0.01, …)` | 105 s | `status OK`; VBAK 6,500 · VBAP 20,598 · VTTK 7,114 · MARD 2,156,400 |
| 2 | `SP_GENERATE_DATA(…, 0.01, …)` | 110 s | same counts |
| 3 | `SP_INJECT_MESS` (dry run) | 46 s | `status OK` |
| 4 | `SP_GEN_SELF_CHECKS` (dry run) | 7 s | **`CHECKSUM_REPEAT` TRUE on all 10 tables**; 2 FALSE (below) |
| 5 | `SP_GENERATE_DATA(…, 1, …)` | **130 s** | `status OK` (run `1d4a2805…`) |
| 6 | `SP_INJECT_MESS` (SF 1) | 61 s | `status OK` (run `8e34d317…`) |
| 7 | `SP_GEN_SELF_CHECKS` (SF 1) | < 30 s | 118 rows: 104 TRUE, 12 NULL (report-only or no repeat run), **2 FALSE** (below) |

**Clean rows at SF 1**: T001W 12 · LFA1 150 · MARA 1,200 · KNA1 2,000 · TCURR 23,310 ·
SOURCING 2,489 · VBAK 650,000 · VBAP 2,043,560 · VTTK 707,236 · MARD 2,156,400. Every
`ROWS_CLEAN` and `UNIQUE_KEYS_CLEAN` check is TRUE.

**Injected at SF 1** (`GEN_MESS_LOG`): M01 KNA1 20 / VBAK 12,940 / VBAP 30,511 / VTTK 21,023 /
MARD 10,692 · M02 VBAK 62,009 / VTTK 56,137 · M03 GBSTK 21,360, PRIO 14,240, CARRIER 45,565,
SHP_STATUS 22,782, KNA1.REGIO 160, KTOKD 60, LFA1.REGIO 12, MATKL 60, REGION_CD 2 · M04 5
customers, 2 vendors, 4 parts, 1,950 orders, 2,044 lines · M06 VBAP 20,122 / VTTK 6,933 ·
M07 VBAP.MATNR 10,218, VBAP.VBELN 4,087, VTTK.VBELN 2,278 · E01 5,614 · E02 3,062 · E03 9,750
(5,850 with a shipment) · E04 19,589 · E05 6,469 · E06 72 pairs · E07a 120,614 · E07b 7,033 ·
E07c 1,407 · E08 703 · E09a 4,087 · E09b 1,407 · E11 12 · E12 130. Every `RATE_*` check TRUE.

**Clean metrics (self-check, on SOURCE before mess)**: OTD T12M 0.8752, 10-year 0.8718,
yearly 0.8575–0.8767 · fill T12M 0.9254, 10-year 0.9239 · DOI latest 36.4 · landed cost T12M
605.6, 10-year 588.8 · E10 conflict rate 0.1997 · naive gap T12M **0.194** (governed 0.8752
vs naive 0.6809).

## Self-checks that returned FALSE (not blocking; for Claude Code)

| Run | Check | Expected | Actual | Why | Suggested change |
|---|---|---|---|---|---|
| SF 0.01 | `CLEAN_OTD_YEAR_MIN` | 0.845–0.895 | 0.8427 | ~500 orders per year: sampling noise | none (passes at SF 1: 0.8575) |
| SF 0.01 and SF 1 | `DATA_NON_CONTRACT_CODES` VTTK.CARRIER_CD | 45,565 ±2% | 46,865 | M01 runs after M03, so M01's duplicate copies of rows that already carry a variant add ~21,023 × 6% ≈ 1,260 more variants. The data is right; the check's expectation is off (GBSTK shows the same, +385, inside tolerance) | count distinct keys with a variant, or add the M01 copies to the expectation |
| SF 1 | `CLEAN_FILL_YEAR_MIN` | 0.905–0.945 | 0.9007 | 2021 (supply crisis, `p_short` 0.27 × factor): 0.4 pt under the per-year band; the spec's own estimate was ~0.912 | optional: 0.25 × factor in 2021. Still inside the contract §3 range 0.90–0.95; T12M and 10-year pass |

`CHECKSUM_REPEAT` at SF 1 is NULL because `99_run.sql` runs SF 1 once; determinism is
shown by the dry run (all TRUE) and by the fix-3 comparison.
