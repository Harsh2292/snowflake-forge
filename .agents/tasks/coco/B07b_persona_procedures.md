# B07b — Persona Sample Procedures → artifact 04

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M2 |
| **Prerequisite** | B07 gate passed (9 governed views, masking attached, persona `SELECT` granted) |
| **Est. effort** | One session |
| **Writes** | `sql/04_governance/04_persona_procedures.sql`, `docs/artifacts/04_persona_outputs.json` |
| **Status** | ✅ done 2026-09-27, gate passed |

---

## Goal

Build the three owner's-rights sample procedures of contract §1, §5.4 and §6a, so the app,
running as its owner in Streamlit in Snowflake, can show real per-persona masking. Capture
`04_persona_outputs.json`, which together with art 03 unlocks Claude Code's C6a.

## Scope decision (planning, 2026-09-27, approved by the user)

| In B07b | Moved |
|---|---|
| `SP_SAMPLE_AS_PLANNER()`, `SP_SAMPLE_AS_BUYER()`, `SP_SAMPLE_AS_LOGISTICS()` | `SP_METRICS_AS_*` go to the **end of B08**. CR-002 says they run the metrics through `SEMANTIC_VIEW`, and `SUPPLY_CHAIN_SV` doesn't exist until B08. Art 09 (B11) calls them. |

CR-005 was **accepted** (contract v1.4): fill rate excludes OPEN and CANCELLED orders.
That is B08's concern; nothing in B07b depends on it.

---

## Design

| Decision | Why |
|---|---|
| **Identical body** in all three procedures; only the name and the owner differ | The demo claim in its purest form: same code, same rows, different visibility, because of the role alone. |
| **`PERSONA` = `REPLACE(CURRENT_ROLE(), '_ROLE', '')`**, not a literal | Self-proving: inside an owner's-rights procedure `CURRENT_ROLE()` is the owner. If ownership or rights were wrong, it would read `ACCOUNTADMIN` and `test_sample_has_contract_shape` would fail. |
| **Deterministic sample, 3 rows**: the first 3 primary sourcing rows by `part_id` (with their part and supplier), paired by rank with the first 3 customers by `customer_id` | All personas return the **same IDs**, so only masked values differ. 3 rows matches the mock. |
| `LANGUAGE SQL`, `EXECUTE AS OWNER`, `RETURNS TABLE(...)` with explicit types | The §5.4 shape is fixed at creation. Types: `UNIT_COST`/`CONTRACT_PRICE` `NUMBER(12,2)`, `CREDIT_LIMIT` `NUMBER(15,2)`, the rest `VARCHAR`. |
| Created by `ACCOUNTADMIN`, then `GRANT OWNERSHIP … TO ROLE <persona> REVOKE CURRENT GRANTS` | Contract §6a: each persona role owns its own procedure. |
| `GRANT USAGE` on each procedure to `FORGE_ADMIN` | The app owner calls all three (it inherits the persona roles anyway; the explicit grant documents intent). |
| Reads governed views only | Persona roles have no `SELECT` on source tables. |

Shape, in exact order (§5.4, CR-004): `PERSONA`, `SAMPLE_PART_ID`, `UNIT_COST`,
`SAMPLE_SUPPLIER_ID`, `PAYMENT_TERMS`, `SAMPLE_CUSTOMER_ID`, `CUSTOMER_NAME`, `CREDIT_LIMIT`,
`CONTRACT_PRICE`, `CUSTOMER_EMAIL`.

---

## Steps

1. Write `sql/04_governance/04_persona_procedures.sql`: 3 procedures, ownership transfers, `USAGE` grants.
2. Execute as `ACCOUNTADMIN`.
3. Run the gate.
4. Capture art 04: call all three as `FORGE_ADMIN` and `TO_JSON` the stored results. Write it verbatim; SHA-256 must match.

---

## Gate

1. `SHOW PROCEDURES IN SCHEMA GOVERNED`: each `SP_SAMPLE_AS_*` owned by its persona role.
2. As `FORGE_ADMIN`, each `CALL` returns 3 rows, the 10 §5.4 columns in order, and `PERSONA` equal to its owner.
3. Sample IDs identical across the three procedures.
4. All 6 masked columns match §6 exactly per persona.
5. Persona roles still cannot read source tables directly.
6. Art 04 exists, parses, and matches Snowflake's hash of the captured result.

Not run: Claude Code's `pytest -m live`, because the project venv has no Snowpark. SQL checks 2–4 cover the same assertions as `tests/governance/test_masking.py`.

### Gate results (2026-09-27, live)

| # | Check | Result |
|---|---|---|
| 1 | Ownership | `SP_SAMPLE_AS_PLANNER` → `PLANNER_ROLE`, `_BUYER` → `BUYER_ROLE`, `_LOGISTICS` → `LOGISTICS_ROLE` ✅ |
| 2 | Shape as `FORGE_ADMIN` | 3 rows each; `DESCRIBE RESULT` gives the 10 §5.4 columns in order; `PERSONA` = PLANNER / BUYER / LOGISTICS, derived from `CURRENT_ROLE()` inside the procedure ✅ |
| 3 | Same IDs | `MAT000001-3`, `SUP00001-3`, `CUST00001-3` for all three ✅ |
| 4 | §6 masking (3 rows each) | PLANNER and LOGISTICS: unit_cost and contract_price NULL, payment_terms RESTRICTED, customer name and email visible, credit_limit NULL. BUYER: unit_cost, contract_price and payment_terms visible; name and email MASKED; credit_limit NULL ✅ |
| 5 | No source bypass | `PLANNER_ROLE` alone: `LFA1` "does not exist or not authorized" ✅ |
| 6 | Artifact | written verbatim; SHA-256 `0a0c9164…95bc4bd46` matches Snowflake; parses ✅ |

**Found while running the gate (tooling, not the design):**
- `USE ROLE` no longer carried over between separate statements in this session, so each role-switched check ran inside a single `EXECUTE IMMEDIATE` block.
- The user's session has **secondary roles = ALL**, including `ACCOUNTADMIN`. With them on, a `PLANNER_ROLE` session could read `LFA1`. With them off, it is denied.
  - **Masking is unaffected:** `CURRENT_ROLE()` checks only the primary role.
  - B07's "every role reads every view" check was re-run with secondary roles off, and it passes (13,842 rows per persona).
  - Art 04 was captured with secondary roles off, which matches how SiS calls the procedures (owner's rights, no secondary roles).

---

## On Completion

1. Tick B07b ✅ in `.agents/NEXT.md`; set B08 as NEXT.
2. Update `.agents/HANDOFF.md`: art 04 DONE, so Stage 1 is complete and C6a can start.
3. Update `.agents/tasks/COCO_TASKS.md`, `docs/SESSION_LOG.md`, `.agents/tasks/README.md`.
