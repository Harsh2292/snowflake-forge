# Gap Resolutions

> Open questions identified after the HLD/LLD were written, and how each was closed.
> Resolved: 2026-09-24

---

## GAP-1 — Persona switching inside Streamlit in Snowflake  ✅ RESOLVED

**Status**: Was a genuine blocker. Design changed.

### The problem

Snowflake documentation is explicit:

> "Streamlit in Snowflake apps run with owner's rights, so using `CURRENT_ROLE` inside a
> Streamlit app always returns the app owner role."
>
> "Warehouse-runtime apps using `CURRENT_ROLE()` in row access policies will always
> return the app owner's role, not the viewer's role."
>
> — <https://docs.snowflake.com/en/developer-guide/streamlit/features/row-access>

Our masking policies key off `CURRENT_ROLE()`. A persona dropdown in the app would have
had **no effect** — all three personas would return identical unmasked output while
appearing to work. The demo would have proven nothing, and we might not have noticed.

`USE ROLE` inside a warehouse-runtime SiS app is also restricted, because the app executes
as an owner's-rights stored procedure.

### Options considered and rejected

| Option | Why rejected |
|--------|-------------|
| Restricted Caller's Rights (RCR) | Container-runtime only, and it binds the app to *whoever is logged in* — we need one app where a dropdown simulates three personas |
| `USE ROLE` inside the app | Blocked by owner's-rights stored-procedure restrictions |
| Per-persona view sets (`V_PART_PLANNER`, …) | Simulates governance instead of using it; defeats the entire thesis |
| Session variable + `GETVARIABLE()` in the policy | Any user could set the variable to anything — weaker than role-based governance, and dishonest to present as governance |
| Pre-computed evidence table only | Real, auditable, but not live; acceptable as a fallback, weaker as a demo |

### The resolution

**Owner's-rights stored procedures, each owned by a different persona role.**

```sql
-- Owned by PLANNER_ROLE → runs as PLANNER_ROLE → real masking applies
CREATE OR REPLACE PROCEDURE GOVERNED.SP_SAMPLE_AS_PLANNER()
  RETURNS TABLE(...)
  LANGUAGE SQL
  EXECUTE AS OWNER
  AS $$ ... $$;

GRANT OWNERSHIP ON PROCEDURE GOVERNED.SP_SAMPLE_AS_PLANNER() TO ROLE PLANNER_ROLE;
GRANT USAGE ON PROCEDURE GOVERNED.SP_SAMPLE_AS_PLANNER() TO ROLE FORGE_ADMIN;
```

Three procedures, one per persona. Each executes with **its owner's** rights, so
`CURRENT_ROLE()` inside resolves to that persona role and the genuine masking policy
applies. The app calls all three from a single session as the app owner.

### Why this is correct, not a workaround

- The masking policies are real, role-based, production-grade — unchanged
- Each procedure genuinely executes as a different role
- No role switching is required of the app
- The divergence the app displays is produced by actual Snowflake governance

### Split of concerns

| Claim | Mechanism | Needs per-role execution? |
|-------|-----------|--------------------------|
| **Metrics are identical across personas** | Direct `SEMANTIC_VIEW()` query as app owner | **No** — they are identical by design; that is the point |
| **Data visibility differs across personas** | The three owner's-rights procedures | **Yes** |

### Consequences

- Add build step **B7b**: create the three persona sample procedures
- `GRANT READ SESSION ON ACCOUNT TO ROLE <app owner>` is required if any context
  function or row access policy is used in SiS
- Contract bumped to **v1.1** — the app calls procedures, not `USE ROLE`
- Use **warehouse runtime** for SiS (simpler; no compute pool needed). RCR is not used.

---

## GAP-2 — Derived time dimensions  ✅ RESOLVED

Exact expressions, defined on `GOVERNED.V_ORDER`:

```sql
order_date                                    AS order_date,
YEAR(order_date)                              AS order_year,
'Q' || QUARTER(order_date)                     AS order_quarter,
TO_CHAR(order_date, 'YYYY-MM')                AS order_month,
DATE_TRUNC('WEEK', order_date)                AS order_week
```

`order_quarter` renders as `Q1`…`Q4`, matching contract §4 valid values.
`order_month` renders as `2026-03` — sortable as a string, which charts need.

---

## GAP-3 — Custom DMF definitions  ✅ RESOLVED

```sql
-- Orphan order lines: lines whose order no longer exists
CREATE OR REPLACE DATA METRIC FUNCTION GOVERNED.DMF_ORPHAN_ORDER_LINES(
  arg_t TABLE(arg_order_id VARCHAR)
)
RETURNS NUMBER
AS $$
  SELECT COUNT(*) FROM arg_t
  WHERE arg_order_id NOT IN (SELECT order_id FROM GOVERNED.V_ORDER)
$$;

-- Overshipment: shipped more than ordered
CREATE OR REPLACE DATA METRIC FUNCTION GOVERNED.DMF_OVERSHIP_COUNT(
  arg_t TABLE(arg_ordered NUMBER, arg_shipped NUMBER)
)
RETURNS NUMBER
AS $$
  SELECT COUNT(*) FROM arg_t WHERE arg_shipped > arg_ordered
$$;
```

Both must return **0** on healthy data. Any non-zero value is a real defect in the
generated data and blocks the B4 gate.

Built-in DMFs used alongside these:
`SNOWFLAKE.CORE.NULL_COUNT`, `SNOWFLAKE.CORE.DUPLICATE_COUNT`, `SNOWFLAKE.CORE.FRESHNESS`

---

## GAP-4 — The fourth demo role (`LOGISTICS_APAC_ROLE`)  ✅ RESOLVED — DROPPED

**Decision**: cut it from MVP.

**Rationale**: it existed only to demonstrate a row access policy. Column masking already
proves governed access control, and it does so on the dimension that matters for this
problem statement — *who can see which fields*. A regional row filter adds a fourth role,
another policy, and another test axis while adding nothing to the core claim.

Row access policies move to **M6 as a stretch item**. If time allows, add
`LOGISTICS_APAC_ROLE` then. The row access policy is also the component most likely to
accidentally change metric aggregates across personas, which is the one thing that must
not happen.

Contract §2 stays at three personas.

---

## GAP-5 — Multilingual capability  ✅ VERIFIED

Tested against the live account:

| Prompt | Result |
|--------|--------|
| `What is 17 plus 25?` | `42` |
| `17 और 25 का योग क्या है?` | `42` |

Model: `claude-sonnet-4-5` via `SNOWFLAKE.CORTEX.COMPLETE`.

**Caveat**: this verifies the *model*, not the *Agent path* (which adds Cortex Analyst
text-to-SQL, where the semantic view's synonyms are English). Re-verify at **B10** with a
real Hindi question against the Agent before putting it in the demo. If Analyst struggles,
the fallback is to demo multilingual on the response side only.

---

## GAP-6 — Data generation approach  ✅ RESOLVED

Two files, strict FK order, `GENERATOR`-based.

**`01_generate_masters.sql`** — suppliers → parts → sourcing → plants → customers

**`02_generate_transactions.sql`** — orders → order_lines → shipments → inventory

### Pattern

```sql
INSERT INTO SRM_SOURCE.LFA1
SELECT
  'SUP' || LPAD(SEQ4(), 5, '0')                      AS LIFNR,
  ...
  CASE WHEN UNIFORM(1, 100, RANDOM()) <= 20 THEN 1
       WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 2
       ELSE 3 END                                    AS SUPP_TIER,
  ROUND(UNIFORM(0.70, 0.99, RANDOM()), 2)            AS RELIAB_SCR
FROM TABLE(GENERATOR(ROWCOUNT => 60));
```

### Distribution controls that must hold

| Target | Mechanism |
|--------|-----------|
| OTD ≈ 0.87 | `ACT_DLV_DT = PROM_DLV_DT + CASE WHEN UNIFORM(1,100,RANDOM()) <= 87 THEN -UNIFORM(0,3,…) ELSE UNIFORM(1,12,…) END` |
| Fill rate ≈ 0.93 | `QTY_SHIPPED = KWMENG * CASE WHEN UNIFORM(1,100,…) <= 85 THEN 1 ELSE UNIFORM(0.5,0.95,…) END` |
| DOI 15–45 | Generate `DAILY_USG` first, then `LABST = DAILY_USG * UNIFORM(15,45,…)` |
| ERP/TMS date conflict 15–25% | `ERDAT = PROM_DLV_DT + CASE WHEN UNIFORM(1,100,…) <= 20 THEN UNIFORM(-5,5,…) ELSE 0 END` |
| 8% still in transit | `ACT_DLV_DT = NULL` for that slice |
| Q4 seasonal uplift | Weight `AUDAT` generation toward Oct–Dec |

### Non-negotiable constraints

- FK values drawn only from already-inserted parents
- `QTY_SHIPPED <= KWMENG` always (DMF enforces)
- Exactly one `IS_PRIMARY = TRUE` per part in `SOURCING`
- `MARD.INV_KEY = WERKS || '-' || MATNR || '-' || SNAP_DT`
- Both custom DMFs return 0

Expect iteration. Distributions will not land on the first run; B5 exists precisely to
catch that before anything is built on top.

---

## Summary

| Gap | Status | Impact |
|-----|--------|--------|
| GAP-1 SiS persona switching | ✅ Resolved | **Design change** — added B7b, contract → v1.1 |
| GAP-2 Time dimensions | ✅ Resolved | Spec filled in |
| GAP-3 Custom DMFs | ✅ Resolved | Spec filled in |
| GAP-4 Fourth role | ✅ Dropped | Scope reduced; moved to M6 stretch |
| GAP-5 Multilingual | ✅ Verified | Re-verify on Agent path at B10 |
| GAP-6 Data generation | ✅ Resolved | Approach + distribution controls specified |
