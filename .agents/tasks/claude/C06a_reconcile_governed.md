# C6a — Reconcile the governed layer against real Snowflake output

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M2 → M3 (CoCo B07 + B07b done; Stage 1 artifacts DONE) |
| **Prerequisite** | C04 ✅; artifacts `03_governed_columns.json`, `04_persona_outputs.json` (CoCo, 2026-09-27) |
| **Est. effort** | Half a session |
| **Writes** | `tests/artifacts/` (new), `tests/conftest.py` (artifact helper), `app/utils/mock_data.py` (real sample rows), `app/utils/config.py` (§7 column list), `tests/unit/test_data_layer.py` |
| **Status** | ⏸ **PLANNED, ON HOLD** 2026-09-27: the user paused it (not approved yet; user away 28–30 Sep). Resume by getting approval for the Steps below. Done already: the v1.4 `fill_rate` string (CR-005) in `config.py`, plus a test that `config.py` matches the contract's own Python blocks (188 passed). |

---

## Goal

Prove, from CoCo's real captured output, that the governed views and the persona
procedures match the contract, and make that proof permanent: offline tests that replay
the real output through the app's own code. The practice data then shows the real sample rows.

---

## Why

- **First contact with real Snowflake output.** Until now every check ran on mock data
  I wrote to match the contract. The artifacts are what Snowflake actually returned.
- **A first pass already shows zero mismatches** (scripted comparison, 2026-09-27):
  - Art 03: 9 views, 65 columns; every name and position matches §7. Masking policies sit
    on exactly the six §6 columns (`MASK_SUPPLIER_COST`, `MASK_PAYMENT_TERMS`,
    `MASK_CUSTOMER_PII`, `MASK_CREDIT_LIMIT`).
  - Art 04: each procedure is owned by its persona role, returns the 10 §5.4 columns in
    order, `PERSONA` = its own role (read from `CURRENT_ROLE()`), and every masked value
    matches §6 on all rows. So no Change Request is needed.
- **Replay, not just compare.** Feeding the artifact rows through `forge_data`'s live
  branch (via a fake session) tests the exact code SiS will run: column order, Snowflake
  `NUMBER(12,2)` values arriving as `Decimal`, NULLs. A one-off comparison script would
  prove nothing about the app.
- **Real sample rows in the demo.** The "rows each team gets" drawer shows made-up
  `MOCK-PART-01` data today. Using the captured rows (`MAT000001`, `2/10 NET30`, …) makes
  the offline demo show what Snowflake really returns. `app/` can't read `docs/` once
  deployed, so the rows are copied into `mock_data.py`, and a test keeps them equal to the
  artifact.

---

## Steps

1. **`tests/conftest.py`**: an `artifact(name)` helper that loads
   `docs/artifacts/<name>` and skips cleanly if CoCo hasn't captured it yet (C6b/C6c
   reuse it).
2. **`app/utils/config.py`**: add `GOVERNED_COLUMNS` (§7, verbatim) next to the other
   contract constants, with a unit test that it matches the §7 table text.
3. **`tests/artifacts/test_stage1_governed.py`** (offline):
   - Art 03: the 9 views and every column name and position equal `GOVERNED_COLUMNS`; the
     masking policies cover exactly the §6 columns; `V_ORDER` has no ERP promised date.
   - Art 04: each procedure's owner is its persona role; `result_columns` equal the §5.4
     order; `PERSONA` equals the persona; the same sample IDs appear for all three personas
     (only masked values differ).
   - **Replay**: a fake session answers `CALL SP_SAMPLE_AS_*()` with the artifact rows
     (in `result_columns` order, numbers as `Decimal`). Then `get_masking_divergence()`
     in live mode returns the exact §5.4 frame, and the §6 checks from
     `tests/governance/test_masking.py` pass on it, for all six rows × three personas.
   - The Same screen's payload built from the replayed data marks the right chips visible
     and hidden per persona.
4. **`app/utils/mock_data.py`**: `masking_sample()` returns the real captured rows per
   persona. A test asserts mock == artifact 04, so they can't drift apart.
5. **Break-it check** (not committed): alter one masked value or one column in a copy of
   each artifact and confirm the matching test goes red.
6. **Browser check**: `pytest -m ui`, plus a look at the "rows each team gets" drawer with
   the real rows, light and dark.

Not in scope: metric values and dimensions (C6b, art 05/06), agent parsing (C6c, art 07+),
`compare_across_personas()` (needs `SP_METRICS_AS_*`, end of B08).

---

## Gate

- `pytest -q` green with the new artifact tests running (not skipped).
- Replaying art 04 through the live code path passes every §6 masking check.
- Mock sample rows equal art 04; `pytest -m ui` green.
- Zero unexplained mismatches; any real one becomes a Change Request, never a silent fix.

---

## On completion

1. This card
2. `.agents/NEXT.md` (C6a ✅)
3. `.agents/HANDOFF.md` ("Latest from Claude Code"): Stage 1 reconciled, result
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
