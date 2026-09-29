# C6a — Reconcile the governed layer against real Snowflake output

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M2 → M3 (CoCo B07 + B07b done; Stage 1 artifacts DONE) |
| **Prerequisite** | C04 ✅; artifacts `03_governed_columns.json`, `04_persona_outputs.json` (CoCo, 2026-09-27) |
| **Est. effort** | Half a session |
| **Writes** | `tests/artifacts/` (new), `tests/conftest.py` (artifact helper, replay), `tests/governance/test_masking.py`, `app/utils/mock_data.py` (real sample rows), `app/utils/config.py` (§5.4 and §7 column lists), `tests/unit/test_data_layer.py`, plus the Same screen drawer (`app/ui/payloads.py`, `views/same.html`, `views/base.css`, `tests/ui/test_browser.py`) |
| **Status** | ✅ **DONE** 2026-09-28. Approved by the user on 2026-09-28. 0 mismatches, no Change Request. `pytest -q` 227 passed, `pytest -m ui` 18 passed. See **Result**. |

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

## Result (2026-09-28)

**Gate: passed.** Every item below is checked by a test that runs offline on every push.

| Check | Result |
|---|---|
| Art 03: 9 views, 65 columns, names and order = §7 (`config.GOVERNED_COLUMNS`) | ✅ |
| Art 03: masking policies on exactly the six §6 columns; promised date only on `V_SHIPMENT` | ✅ |
| Art 04: owner = persona role; 10 §5.4 columns in order with §5.4 types; same IDs for all 3 | ✅ |
| Art 04 captured as `FORGE_ADMIN` with no secondary roles (masking came from the procedures) | ✅ |
| Replay: all six §6 rows × 3 personas pass on art 04 via the live code path | ✅ 18 + 3 shape |
| Practice rows (`mock_data`) == art 04 as read through the live path | ✅ |
| Same screen chips and rows drawer follow the real rows | ✅ |
| Break-it: 10 planted errors in copies of art 03/04 (renamed column, dropped policy, ERP date, wrong mask ×3, column order, owner, value, secondary roles) | ✅ all red |

**How it differs from the Steps above:**
- **The replay runs inside `test_masking.py`** as a third `forge` mode, `[replay]` (via
  indirect parametrisation), not as a copy of the §6 checks. The same six checks now run
  on mock, live and real captured data. `ReplaySession` in `tests/conftest.py` serves
  art 04 like Snowpark: NUMBER as `Decimal`, NULL as `None`, columns in `result_columns`
  order. Any other statement raises, so a fallback to mock fails the test.
- **`config.SAMPLE_COLUMNS` (§5.4)** was added next to `GOVERNED_COLUMNS`. The masking
  tests and `mock_data` use it, and a unit test checks it against the §5.4 table.
- **`mock_data.masking_sample()` masks the captured rows by `config.MASKING_MATRIX`.** The
  real values are stored once, and its NUMBER columns are float/NaN, exactly what the
  live branch returns.
- **Same screen drawer redesigned (the user chose this, 2026-09-28).** With real data, the
  10-column per-team tables wrapped customer names onto 5 lines and cut off the email
  column behind a sideways scroll. The drawer now shows **one record with the three teams
  side by side**, with Record 1/2/3 buttons:
  - The rows are IDs first, then the six protected fields.
  - Masked values read "hidden", "restricted" or "masked" with a lock icon.
  - `payloads.same()` sends ready-to-render `records`.
  - The browser test checks the headers, the record switch, and that the table doesn't
    overflow sideways.
  - Checked in light and dark screenshots.

---

## On completion

1. This card
2. `.agents/NEXT.md` (C6a ✅)
3. `.agents/HANDOFF.md` ("Latest from Claude Code"): Stage 1 reconciled, result
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
