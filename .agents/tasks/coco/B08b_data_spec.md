# B08b — Data spec v2 + context pack + CR-006

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M3 |
| **Prerequisite** | B08 gate passed; replan approved (ADR-008) |
| **Est. effort** | One session (Day 1, first: on the critical path) |
| **Writes** | `docs/DATA_SPEC.md`, CR-006 in `docs/CONTRACT.md` §11, 7 reference files in `docs/references/` (+ README index rows) |
| **Unblocks** | Claude Code C08 (generator), C10 (quality + `SP_DATA_HEALTH`), C11 (eval set), C12 (scale harness), C13 (after CR-006) |
| **Status** | 📝 delivered 2026-09-29; gate item 1 ✅ (CR-006 accepted, contract v1.5); item 2 pending (Claude Code's confirmation) |

---

## Goal

Fix every interface Claude Code's Snowflake SQL builds to, before any of it is written:
the v2 source tables, the volumes, the mess catalogue, the metric and time rules, the
generator's determinism rules, and the exact names, signatures and return shapes of every
new object. Then give Claude Code the Snowflake docs it needs, fetched and dated, plus how
CoCo actually runs its files. File CR-006 for the contract changes.

## Decisions

| Decision | Why |
|---|---|
| **Default window = trailing 12 months** for flow metrics (OTD, landed cost on `ship_date`; fill rate on `order_date`); **DOI = latest snapshot** | The user's choice (2026-09-29). One rule for the app and the agent, so one question gets one number |
| **Anchor = `CURRENT_DATE()`**; the as-of date shown = latest loaded business date | It's what Cortex Analyst does for "last quarter"; staleness is reported by `SP_DATA_HEALTH`, not hidden by a moving anchor |
| **Hash-based randomness, no `RANDOM()`** | Snowflake docs: `RANDOM(seed)` is not reproducible across executions (worker count, row order). `HASH(seed, id, attr)` is. 3M rows in 0.39 s on XS |
| **Generator = caller's-rights procedures in a new `OPS` schema, target DB as a parameter** | CoCo's SQL tool doesn't keep session variables or `USE ROLE` between calls (verified live). Procedures carry their parameters, run in one session, and B13 can point them at the clone |
| **Source columns become nullable except keys; IDs widened** | Every v1 column is `NOT NULL`, which blocks the edge cases; `VARCHAR(10)` IDs overflow at 100M+ lines |
| **`ERP_SOURCE.TCURR`** (SAP's FX table) becomes the 10th source table | Currency conversion needs rates; SAP naming keeps the four-system story |
| **Return orders (`AUART = 'RE'`) are out of scope of the ontology** | They're a different document type; including them would distort fill rate and revenue |
| **§7 governed columns don't change** | Core system rule 1. Extra flags live in `CONFORMED`; views filter |
| **Eval ground truth = `SEMANTIC_VIEW` SQL, pass = re-run the agent's SQL and compare** | Stays right when data changes; deterministic, not an LLM opinion. The native eval format is produced from it |

## Steps

1. Write `docs/DATA_SPEC.md` §1–§8 (source DDL v2, volumes, realism, mess catalogue,
   metric and time rules, determinism, interfaces, how CoCo runs files).
2. Verify: every SQL snippet compiles or runs read-only; the hash recipe gives identical
   checksums on two runs; the mess rates and metric targets are consistent with §3.
3. Context pack in `docs/references/`: `snowflake_data_generation.md`,
   `data_metric_functions.md`, `snowflake_scripting_procedures.md`,
   `agent_custom_tools.md`, `agent_evaluations.md`, `snowpark_async.md` (fetched by two
   subagents, reviewed by CoCo), `snowflake_execution_notes.md` (CoCo, live-verified).
4. Append CR-006 (PROPOSED) to `CONTRACT.md` §11.
5. Update NEXT, HANDOFF (CoCo section), SESSION_LOG, COCO_TASKS, tasks README, LLD pointer.

## Gate

1. **The user approves CR-006.**
2. **Claude Code confirms in HANDOFF** that the spec is implementable (or raises questions).
3. CoCo's own checks before handing over:
   - every SQL snippet in the spec and the references compiles
   - the determinism check passes
   - every defect has a table, a rate, a tolerance, a `CONFORMED` rule and a self-check
   - every interface has an exact signature and return shape

### Gate results (2026-09-29)

| # | Check | Result |
|---|---|---|
| 1 | User approves CR-006 | ✅ accepted 2026-09-29; applied in the `CONTRACT.md` body as v1.5 |
| 2 | Claude Code confirms the spec is implementable | ⏳ pending (asked in HANDOFF) |
| 3a | Every SQL snippet compiles / runs | ✅ the 3 §5.2 time-window patterns ran on the v1 view; the §6 determinism query ran; the CR-006 §8 naive query ran (0.783562 on v1); a custom DMF (`DMF_OVERSHIP_COUNT` shape) compiled; a `CREATE PROCEDURE` compiled |
| 3b | Determinism | ✅ `HASH_AGG` `5241903297775745443` on 5M rows, identical on `COMPUTE_WH` and `FORGE_WH`, result cache off |
| 3c | Every defect has a table, rate, tolerance, rule, self-check | ✅ M01–M07, E01–E12 in DATA_SPEC §4 (+ code map §4.3); self-checks listed in §7.1 |
| 3d | Every interface has an exact signature and shape | ✅ DATA_SPEC §7.1–§7.4 |

**Found while building the spec (live, read-only):**
- Enterprise edition, so DMFs and dynamic tables are available.
- Every v1 source column is `NOT NULL`, and IDs are `VARCHAR(10)`. Both are relaxed or
  widened in DDL v2.
- The SQL tool doesn't keep session variables or `USE ROLE` between calls. So the generator
  is procedures with arguments.
- Compile-only reports success on procedure bodies that reference missing tables. So every
  hand-over needs a small dry-run `CALL`.
- `INFORMATION_SCHEMA` query history has no partition counts; `GET_QUERY_OPERATOR_STATS`
  has them.
- The procedure-tool `identifier` needs the argument signature (`SP_DATA_HEALTH(VARCHAR)`),
  per the fetched docs.
- The v1 `DELAYED` status means "delivered late" (92/92 rows had a delivery date after the
  promise).

---

## On Completion

1. Tick B08b in `.agents/NEXT.md` (✅ once gate 1–2 pass; 📝 delivered until then).
2. HANDOFF (CoCo section): spec landed → C08, C10, C11, C12 unblocked.
3. Update `COCO_TASKS.md`, `docs/SESSION_LOG.md`, `.agents/tasks/README.md`.
