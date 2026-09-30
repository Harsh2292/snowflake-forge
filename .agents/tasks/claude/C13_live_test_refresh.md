# C13 — Live-test refresh: CoCo's contract audit (B14) gets a clear pass/fail per section

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs `pytest -m live` at B14 (and can at B15a, as `FORGE_APP_ROLE`) |
| **Milestone** | Replan Day 3 (1 Oct) |
| **Prerequisite** | contract v1.5 (+ CR-007), C6b/C6c/C16 done; art 05–10 captured |
| **Writes** | `tests/conftest.py` (per-section summary), new live tests in `tests/semantic/`, `tests/governance/`, `tests/quality/`, `tests/agent/`; `tests/README.md` |
| **Status** | ✅ **READY** 2026-09-30: built; offline `pytest -q` 510 passed, 0 failed (the new live tests skip cleanly); in the handoff lock for CoCo's B14 (and B15a as `FORGE_APP_ROLE`) |

---

## Goal
One command against real Snowflake:

```
SNOWFLAKE_CONNECTION_NAME=<conn> pytest -m live -q
```

It says, **contract section by section**, what passes and what fails, and every failure
names the Snowflake object at fault. That's CoCo's audit at B14, and the proof in the
submission that the governed layer does what the contract says.

## Why
The 116 live tests were written before CR-006/CR-007, the data-health tool, the DMFs and
semantic view v2. They cover metrics, pairings, masking, personas and the agent, but not:
- `SP_DATA_HEALTH` (shape, the REFERENCE rule, as-of date)
- the DMF results (cleaned data at zero)
- the semantic view's own metric and dimension lists
- the governed views' columns (§7)
- the agent's refusal of a cross-grain question, and its data-health tool

There's also no per-section summary, and no written run guide.

## Design
1. **Per-section summary** (`pytest_terminal_summary` in `conftest.py`, only when live tests
   ran): a table of contract section → passed / failed / skipped, then one line per
   failure: the test and its first message line, which names the object.
2. **New live tests** (live-only where mock can't answer; ~25 tests, ~3 agent calls):
   - §1/§3/§4 `SHOW SEMANTIC METRICS/DIMENSIONS IN SUPPLY_CHAIN_SV`: every contract metric
     and dimension exists (extra v2 content is fine), and for each metric every §4 pairing
     is legal (`… FOR METRIC`).
   - §7 `INFORMATION_SCHEMA.COLUMNS`: each governed view has the contract's columns in the
     contract's order (extra columns allowed).
   - DATA_SPEC §7.2 `SP_DATA_HEALTH`:
     - `ALL` and each entity have the spec shape
     - the 5 reference entities read `REFERENCE` (C16)
     - `ALL` isn't FAIL
     - `as_of_date` ≤ today
     - `ALL` ≤ 16 KB
   - DMF results: every CONFORMED zero-check passes; results exist for all 77
     associations.
   - Agent (CR-007 path):
     - "What is on-time delivery rate by part category?" → no SQL grouping shipments by
       `parts.category` (a refusal or a clarifying question)
     - "Is the shipment data up to date?" → uses the data-health tool
3. **`tests/README.md`:**
   - how to run (mock, live, ui)
   - what live needs: only `SNOWFLAKE_CONNECTION_NAME` + `app/requirements.txt`
   - its cost (~11 agent calls, a few cents)
   - how to run it as `FORGE_APP_ROLE` for B15a: a connection whose role is the app role
   - how to read the summary
4. **Hand over:** a row in the HANDOFF "Ready for CoCo to run" table for B14.

## As built (30 Sep)

**New live-only test files** (`live_only` = the `forge` fixture parametrised to `live`
alone):
- `semantic/test_semantic_objects.py` (6)
- `governance/test_governed_columns.py` (9)
- `agent/test_agent_behaviour.py` (2)

**`quality/test_data_health_live.py`** (15): the shape and CONFORMED zero-checks run on mock
and live; REFERENCE, ALL status/as-of, the 16 KB budget and "77 associations" are live
only.

**Live total:** 148 (was 116), one row per contract section:
- §3/§5.1/§8: 11
- §4/§5.2: 68
- view objects: 6
- §6 masking: 21
- §7: 9
- persona invariant: 8
- agent: 10
- data health: 15

**Summary:** `conftest.live_summary()` is a pure function, plus a `pytest_terminal_summary`
hook that prints only when a live test really ran. It is unit-tested on fake reports in
`unit/test_live_summary.py` (4):
- nothing printed without a live run
- the counts per section
- the failing object's message
- a failed teardown counts
- every live test file maps to a section

**`tests/README.md`:** the three commands, what live needs, roles (B14 `FORGE_ADMIN`, B15a
`FORGE_APP_ROLE`), cost (10 agent calls), how to read the table, and the expected C16-pending
failures.

## Gate
- [ ] offline `pytest -q` 0 failures; the new live tests skip cleanly without Snowflake
- [ ] the summary prints per section when live tests run (checked with the replay
      session, and with a forced failure)
- [ ] CoCo's B14 run: the per-section table, every failure naming its object
