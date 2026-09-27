# NEXT — What To Do Right Now

> **Single source of truth for "what's next".** Read this, open the named card, execute it.
> Whichever agent finishes a card updates this file.

**Last updated**: 2026-09-27 · **Contract**: v1.4 · **Branch**: `development`

---

## CoCo → `B08` Semantic view

```
.agents/tasks/coco/B08_semantic_view.md   (to be written at planning time)
```

Build `SEMANTIC.SUPPLY_CHAIN_SV` incrementally over the governed views, capture art 05 and
art 06, then build the three `SP_METRICS_AS_*` procedures (CR-002). The B8 section of
`COCO_TASKS.md` lists what B07/B07b carried in: the CR-005 fill-rate filter, the §3 DOI
formula, the GAP-2 time dimensions, and persona `SELECT` on the semantic view.

---

## Claude Code → C6a Reconcile governed layer (card written, needs the user's go-ahead)

```
.agents/tasks/claude/C06a_reconcile_governed.md   (planned 2026-09-27, on hold)
```

**Paused 28–30 Sep** (the user is away). Resume on 30 Sep / 1 Oct in this order:
1. **C6a**: ask the user to approve the card, then build it. Art 03 and 04 already match
   the contract, with 0 mismatches found on the first check.
2. **C6b / C6c**: as soon as CoCo lands art 05/06 (B08) and art 07–09 (B10/B11).
3. **C05**: demo script and README, with the real numbers.
4. Last day: rehearsal, the user records the video, submission.

Already done: contract v1.4 (`fill_rate` string in `config.py`), C04 tests (`pytest -q`
188 passed; live variants skip without Snowflake; `pytest -m ui` 18 passed), C07 CI and
deploy script.

---

## How Parallelism Actually Works

Claude Code does **not** wait for CoCo, and needs **no Snowflake credentials**.

It builds the whole app against the frozen contract with a mock data layer. CoCo runs the
live queries and commits the **real output** to `docs/artifacts/`. Claude verifies against
those files. Three staged unlocks, not one handoff at the end.

```
CoCo                                     Claude Code
────                                     ───────────
B01  database, schemas          ║   C01  API references
B02  roles, grants   →art 01    ║   C02  data access layer (mock + live branches)
B03  source tables              ║   C03  Streamlit app, 5 tabs (mock-driven)
B04  data generation            ║   C04  test suite (written; artifacts become fixtures)
B05  verify          →art 02    ║   C05  demo script, README
B06  tags, masking              ║
B07  governed views  →art 03 ───╫──►  C6a  reconcile columns + masking
B07b persona procs   →art 04 ───╫──►       vs CONTRACT §6, §7
B08  semantic view   →art 05/06 ╫──►  C6b  reconcile metrics + dimensions
B09  verified queries           ║          real values replace mocks
B10  Cortex Agent    →art 07/08 ╫──►  C6c  write agent parser vs REAL JSON
B11  consistency     →art 09    ║          build Tab 2 proof grid
B12  DMFs            →art 10    ║
B13  contract audit  →art 11    ║
B14  MCP server (product feature, for judges)
B15  deploy app to SiS          ║
B16  differentiation            ║
B17  security review            ║
```

**First artifact unlock is at B07 — about 40% through CoCo's queue.**

### What CoCo does that Claude cannot

| Action | Why |
|--------|-----|
| Run any SQL | Claude has no Snowflake credentials |
| Capture artifacts | Requires live query execution |
| Deploy the Streamlit app | Requires Snowflake write access |

### What Claude does that CoCo does not

| Action | Why |
|--------|-----|
| Build the app, tests, docs | It is faster at application scaffolding |
| Parse the real agent JSON | It owns the response-handling code |

### Genuinely sequential residue

| Item | Why unavoidable |
|------|----------------|
| Artifact capture | Objects must exist before a query can run |
| SiS deployment | Needs semantic view + agent deployed |
| Final demo rehearsal | Needs the whole stack |

Everything else overlaps.

---

## Progress

### CoCo

| Card | Title | Status |
|------|-------|--------|
| B01 | Database, schemas, warehouse | ✅ |
| B02 | Roles and grants | ✅ |
| B03 | Source tables (9) | ✅ |
| B04 | Data generation | ✅ |
| B05 | Distribution verification | ✅ |
| B06 | Tags and masking policies | ✅ |
| B07 | Governed views (9) → art 03 | ✅ |
| B07b | Persona sample procedures (3) → art 04 | ✅ |
| B07c | MCP read-only — **DEFERRED**, not needed | ⏸ |
| B08 | Semantic view → art 05, 06 (+ `SP_METRICS_AS_*`) | ⬜ NEXT |
| B09 | Verified queries, AI instructions | ⬜ |
| B10 | Cortex Agent → art 07, 08 | ⬜ |
| B11 | Cross-persona consistency → art 09 | ⬜ |
| B12 | Data metric functions → art 10 | ⬜ |
| B13 | Contract conformance audit → art 11 | ⬜ |
| B14 | MCP server (product feature) | ⬜ |
| B15 | Deploy app to SiS | ⬜ |
| B16 | Differentiation artifacts | ⬜ |
| B17 | SQL and security review | ⬜ |

### Claude Code

| Card | Title | Status |
|------|-------|--------|
| C01 | API reference library | ✅ |
| C02 | Data access layer (mock-backed) | ✅ |
| C03 | Streamlit app (guided story + Explore), Revision 2 | ✅ |
| C04 | Test suite | ✅ |
| C05 | Demo script, README | ⬜ NEXT |
| C07 | CI tests on GitHub + one-command deploy script | ✅ |
| C6a | Reconcile governed layer | ⏸ card written, on hold by user (v1.4 config string done; first check: 0 mismatches) |
| C6b | Reconcile semantic layer | 🔒 needs art 05, 06 |
| C6c | Agent parser + proof grid | 🔒 needs art 07–09 |

Legend: ⬜ todo · 🔄 in progress · ✅ done · 🔒 waiting on artifact · ⏸ deferred

---

## Credentials — Resolved, Nothing Needed From You

**Decision: artifact handoff.** Claude Code needs no Snowflake credentials.

```
CoCo runs live query  →  commits real output to docs/artifacts/  →  Claude verifies
```

Why this was necessary:
- `connections.toml` uses `OAUTH_AUTHORIZATION_CODE` — browser-based, nothing reusable
  non-interactively
- `snow` CLI is not installed
- No secrets stored

**Nothing is required from the user.** If artifacts later prove insufficient, Claude Code
raises it in `.agents/HANDOFF.md` under `## Blocked`, and only then do we consider a
read-only PAT (CoCo's deferred B07c).

> The MCP server at **B14** is unaffected — it is a product feature demonstrated to judges,
> not a development dependency. Those two concerns are now separate.

---

## Rules

1. One card at a time. Finish it, pass its gate, then update this file.
2. A card is done when its **Gate** passes — not when the code runs.
3. **Task Planning & Card Rule**: Before implementing any task, enter plan mode, plan the task, author its markdown task card file (`.agents/tasks/coco/Bxx_...md` or `.agents/tasks/claude/Cxx_...md`), get user confirmation, and only then proceed with implementation.
4. `docs/CONTRACT.md` is binding. Deviations → Change Request in §11 + tell the user.
5. Append to `docs/SESSION_LOG.md` when you stop working.
6. Do not commit or push. The user does that.
