# C02 — Data Access Layer (mock-backed)

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M1 (parallel with CoCo's B02) |
| **Prerequisite** | C01 ✅ (references in `docs/references/`) |
| **Est. effort** | One session |
| **Writes** | `app/utils/*.py`, `tests/unit/test_data_layer.py`, `docs/CONTRACT.md` §11 (append only) |
| **Status** | ✅ **DONE** 2026-09-24. Gate passed (94 tests). |

---

## Goal

Build the one module that talks to Snowflake. Every UI tab and test calls it. It runs
fully on mock data now and switches to live Snowflake by flipping `USE_MOCK_DATA`.

---

## Why

- CoCo is still building Snowflake. A mock-backed data layer lets the app and tests be
  finished in parallel.
- One module means the UI never changes when going live, and one place handles failures:
  if a live query fails on stage, the app shows mock values with a warning instead of a
  stack trace.
- The contract (v1.1) fixes every identifier. Building SQL only from those allow-lists
  keeps user text out of SQL and stops the UI from asking for pairings Snowflake would
  reject.

---

## Steps

1. `app/utils/config.py`: copy contract constants verbatim (FQNs, persona roles and
   labels, metrics and ranges, dimensions, valid pairings, masking matrix, canonical
   questions, mock fixtures). `USE_MOCK_DATA = True`.
2. `app/utils/agent_response.py`: pure parser for the `DATA_AGENT_RUN` response
   (`docs/references/data_agent_run.md` §8). Skips unknown content types and tolerates a
   missing `rowType`.
3. `app/utils/mock_data.py`: deterministic fixtures inside the §3 ranges. Mock agent
   responses are built in the **real** response shape, so the parser is exercised in
   mock mode too.
4. `app/utils/source_catalog.py`: static source→governed column map from LLD §2/§4 for
   Tab 3, so no source-schema query is needed.
5. `app/utils/forge_data.py`: public API, where every function has a mock and a live
   branch:

   | Function | Live source |
   |----------|-------------|
   | `get_session()` | `get_active_session()`, else named local connection |
   | `get_metric(metric_key, dimension=None, role=None)` | contract §5.1 / §5.2 |
   | `get_all_metrics(role=None)` | one `SEMANTIC_VIEW` with all 4 metrics |
   | `compare_across_personas(metric_key=None)` | `SP_METRICS_AS_*` (**CR-002**) |
   | `get_masking_divergence(role)` | `SP_SAMPLE_AS_*` (§5.4) |
   | `ask_agent(question, role=None)` | §5.3 + parser |
   | `get_naive_otd()` / `get_governed_otd()` | §8 |
   | `get_source_schema_summary()` | static (both modes) |
   | `get_quality_results()` | `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` |
   | `pop_notices()` / `data_mode()` | fallback warnings for the UI |

6. Unit tests for the gate.
7. File change requests for any contract problems found.

---

## Decisions made during this card

| Decision | Why |
|----------|-----|
| **CR-002: persona metric procedures** (user approved) | Under v1.1, metrics are queried once as the app owner, so the consistency grid would show one number copied three times. Per-role procedures make it a real proof. |
| **CR-003: canonical Q8 has no valid pairing** | OTD × `suppliers.*` isn't in §4. Shipments have no path to suppliers. CoCo decides at B08/B09. |
| `.collect()` for all live queries | `to_pandas()` rejects non-SELECT statements (the `CALL`s). |
| Tab 3 source catalog is static | Keeps the "never query source schemas" rule; the only source query is §8. |
| `FRESHNESS` DMF shown as INFO, not PASS/FAIL | Demo data is loaded once, so freshness ages daily and would show a false red on stage. |
| No Streamlit import in the data layer | Testable on its own. The UI reads `pop_notices()` and `df.attrs["source"]`. |

---

## Gate ✅

Run: `.venv/Scripts/python -m pytest tests/unit -q` → **94 passed**

- `get_all_metrics()` returns one row with the 4 contract columns and the contract mock values
- every valid metric × dimension pairing returns rows inside the §3 ranges;
  `days_of_inventory × orders.*/shipments.*` raises
- consistency grid all `IDENTICAL`, and a 1e-5 difference is detected
- masking samples follow the §6 matrix for all three personas
- all 8 canonical questions answer, with SQL and the right `metric_used` (Q8 explains CR-003)
- the parser handles the official doc example and junk input
- SQL text equals contract §5.1, §5.2, §5.3, §5.4 and §8, **read from CONTRACT.md itself**
- in live mode with no Snowflake, functions return mock data plus a Notice and never raise

---

## On completion (done)

1. ✅ `.agents/NEXT.md`: C02 ticked, C03 set NEXT
2. ✅ `.agents/HANDOFF.md`: Latest from Claude Code (CR-002/003, 9-vs-10 tables,
   DMF name, DMF edition/role requirement)
3. ✅ `docs/SESSION_LOG.md`: Session 8
4. ✅ `docs/CONTRACT.md` §11: CR-002, CR-003 appended as PROPOSED
