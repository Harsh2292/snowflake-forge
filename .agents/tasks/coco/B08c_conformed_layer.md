# B08c — Load realistic data + `CONFORMED` cleansing layer

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M3 |
| **Prerequisite** | B08b gate passed (DATA_SPEC implementable, confirmed by Claude Code); C08 READY |
| **Account** | old account `tyduokn-gf25237` only (the new account waits for B08m) |
| **Writes** | `sql/01_setup/03_schemas_v2.sql`, `sql/02_tables/05_source_v2.sql`, `sql/04_governance/06_conformed_layer.sql`; edits `01_tags.sql`, `03_governed_views.sql`; `docs/artifacts/runs/C08_run.md`, `docs/artifacts/runs/B08c_run.md`; re-captures art 03 and art 04 |
| **Unblocks** | B09 (semantic view v2 on clean data), C10 (DMFs attach to `CONFORMED`), C11/C12 (real volumes) |
| **Status** | ✅ done 2026-09-29, gate 7/7 |

---

## Goal

Replace the v1 sample data with C08's 10-year realistic, messy data, and put a `CONFORMED`
layer of dynamic tables between `SOURCE` and `GOVERNED` that repairs every DATA_SPEC §4
defect and applies every edge-case rule. The 9 `GOVERNED` views keep their §7 names and
columns; they just read clean data now. The semantic view is not regenerated here (B09).

## Decisions

| Decision | Why |
|---|---|
| FX via a static `CALENDAR` table + `FX_RATE` DT (one rate per currency per day, carried forward with `LAST_VALUE … IGNORE NULLS`) | Facts join it on equality `(currency, date)`. A range join ("latest `GDATU ≤ date`") isn't incremental and fans out rows |
| Dedupe first (`QUALIFY ROW_NUMBER() … PARTITION BY UPPER(TRIM(key)) ORDER BY LOAD_TS DESC`), then filter | An M02 older version or an E12 row must be judged on its latest version only |
| Test masters by rule: ID starts `TEST`/`MAT9999`, or `UPPER(TRIM(name))` matches `^(TEST\|DUMMY)([^A-Z0-9_].*)?$`, or contains `DO NOT USE` | Snowflake regex has no `\b`; this is the same rule as §4 M04 |
| Scope by inner joins (lines → orders → customers; lines → parts; shipments → orders) | Drops orphans (E09), returns (E03), test dependents (M04) in one incremental-friendly construct |
| E11: an earlier primary overlapped by a later primary of the same part is demoted to secondary | §4 E11 "latest `VDATU` wins"; `LEAD()` with `PARTITION BY` is incremental |
| Shipment costs: E07c (freight NULL) first → all three NULL; else COALESCE duty/handling (E07a/b); then E08 if USD total > 25,000 → all three NULL | The order matters: a NULL freight must not become 0 |
| Types cast to the v1 governed types | The masking policies are typed (`NUMBER(12,2)`, `NUMBER(15,2)`, `VARCHAR`) |
| `TARGET_LAG = '1 day'`, incremental refresh | Static demo data; cheapest lag. Incremental is required so C12 can show refresh times at scale |
| `FORGE_ADMIN` gets `SELECT` on `CONFORMED`; persona roles get nothing | `SP_DATA_HEALTH` (owner FORGE_ADMIN) reads counts there; personas stay on the governed views |

## Steps

0. This card; HANDOFF answers (B08b gate passed, Claude Code's two deviations accepted,
   C09 part B go-ahead).
1. Schemas `CONFORMED`, `OPS`; v2 source DDL (DATA_SPEC §1, `CHANGE_TRACKING = TRUE`); tag
   `SEMANTIC_ROLE`; re-run the source tags.
2. Run C08 (dry run SF 0.01 ×2, inject, checks; then SF 1, inject, checks) → `C08_run.md`.
3. `06_conformed_layer.sql`: `CODE_MAP`, `CALENDAR`, `FX_RATE` + 9 DTs.
4. Re-point the governed views to `CONFORMED` (+ `SEMANTIC_ROLE` tag per column;
   `V_SOURCING` valid today); re-run the persona procedures and the semantic view as-is.
5. Re-capture art 03 and art 04.
6. Gate.

## Gate (all live)

1. §7: 65 columns, same names and order as the previous art 03; masking on exactly the 6 §6 columns.
2. Repairable defects present in `SOURCE` (C08 self-checks) and **zero** in `CONFORMED`.
3. Edge-case rules applied: `dq_flags` counts match `GEN_MESS_LOG`; no over-shipment or negative on-hand left; outlier costs NULL.
4. The 4 metrics in the §3a windows are inside the §5.4 ranges and identical across the 3 personas.
5. §8 naive OTD ≥ 8 points below governed.
6. Persona roles have no grants on `SOURCE` or `CONFORMED`.
7. Every DT refreshes incrementally, no refresh errors.

## Result

**Gate passed 7/7 (2026-09-29).** Full detail: `docs/artifacts/runs/B08c_run.md`, `docs/artifacts/runs/C08_run.md`.

- C08 at SF 1 on XS in 130 s after three small run-blocking fixes (COMMENT order, `SELECT … INTO`
  with a scalar subquery, an `OR` join that became a Cartesian join). The data is byte-identical
  before and after the fixes (checksums).
- 10 CONFORMED dynamic tables, all INCREMENTAL, 0 refresh errors. Every repairable defect is 0 in
  CONFORMED. `dq_flags` reconcile exactly with the injected rows that stay in scope.
- Windowed metrics, identical for all personas: OTD 0.8683 (0.8753 with the B09 E01 denominator) ·
  fill 0.9261 · DOI 36.44 · landed 604.84. Naive OTD 0.6817 (gap 18.7 pt).
- Art 03 re-captured (same 65 names, order and masking). Art 04 re-captured (same shape; the
  values are new, so Claude Code re-syncs 4 replay tests).
