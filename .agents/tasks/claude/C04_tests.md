# C04 — Test Suite (the contract as executable checks)

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M2 (parallel with CoCo B03 → B07) |
| **Prerequisite** | C02 ✅ (`forge_data.py`), C03 ✅ (app + HTML views) |
| **Est. effort** | One session |
| **Writes** | `pytest.ini`, `tests/conftest.py`, `tests/requirements.txt`, `tests/consistency/`, `tests/governance/`, `tests/semantic/`, `tests/agent/`, `tests/ui/`, edits to `tests/unit/`, `docs/CONTRACT.md` §11 (append only, CR-004), the Test line in `CLAUDE.md`; layout fix in `app/ui/theme.py` and `app/streamlit_app.py` (user request) |
| **Status** | ✅ **DONE** 2026-09-25. Gate passed: 170 passed + 118 skipped (default run), 18/18 browser tests, break-it check red for every rule. CR-004 raised, accepted by CoCo (contract v1.3) and applied: 176 passed, 0 skipped offline. |

---

## Goal

Turn every rule in `docs/CONTRACT.md` into a test that runs three ways: offline against
the mock data (now, green), against real Snowflake (skipped until a connection exists,
then a real conformance check), and in a real browser against the running app.

---

## Why

- **The contract is the spec, so it should be executable.** Today the rules (same number
  for every persona, masking per role, metric ranges, valid pairings) are checked only
  loosely inside the C02 unit tests, and only against mock data.
- **One test body, two data sources.** Each contract test is written once and runs as a
  `[mock]` variant and a `[live]` variant. When Snowflake is ready, nothing is rewritten;
  the live variants start running.
- **A live test must never pass on mock data.** `forge_data` quietly falls back to mock
  when a live query fails (good on stage, bad in a test). In live mode the test fixture
  turns any fallback into a failure that shows Snowflake's error message.
- **The HTML views are invisible to unit tests.** C03 checked them with throwaway
  Playwright scripts in a session scratchpad. They become a committed, repeatable `ui`
  suite, so later changes (C05, C06) can't silently break a screen.
- **Claude Code has no Snowflake credentials.** Live variants skip cleanly for Claude.
  CoCo, which has a connection, can run `pytest -m live` as an extra conformance check
  (optional; suggested at B13).

---

## Layout

```
pytest.ini                          markers mock / live / ui; default run excludes ui
tests/
  requirements.txt                  pytest, playwright (local dev only, never deployed)
  conftest.py                       app/ on sys.path; `forge` fixture (mock | live); auto-marks
  consistency/test_cross_persona.py     §6 invariant: 4 metrics identical across personas
  governance/test_masking.py            §6 matrix: one test per row
  governance/test_source_isolation.py   §8: only get_naive_otd() touches *_SOURCE schemas
  semantic/test_metric_ranges.py        §3 ranges, §8 naive ≠ governed
  semantic/test_dimension_pairings.py   §4 valid pairings, values, and the DOI exclusions
  agent/test_canonical_questions.py     §9: all 8 questions answer
  ui/conftest.py                        starts Streamlit on a free port, launches Chromium
  ui/test_browser.py                    every screen, light + dark, the C03 interactions
  unit/                                 existing C02/C03 tests (tidied, see step 7)
```

### Markers

| Marker | Meaning | Runs by default? |
|--------|---------|------------------|
| `mock` | Offline, mock data. Applied automatically to everything that isn't `live` or `ui`. | yes |
| `live` | Real Snowflake through `forge_data` with `USE_MOCK_DATA = False`. Skips when no session can be opened. | yes (skips) |
| `ui` | Real browser (Playwright + Chromium) against a local Streamlit server in mock mode. | no: `pytest -m ui` |

`pytest.ini` sets `addopts = -m "not ui"`; a `-m` on the command line overrides it.

---

## Steps

1. **`pytest.ini`** at the repo root: `testpaths = tests`, the three markers, `addopts`.
   `tests/requirements.txt`: `pytest`, `playwright` (both already in `.venv`; Chromium
   is installed).
2. **`tests/conftest.py`**
   - Put `app/` on `sys.path` once (removes the copies in the unit tests).
   - `forge` fixture, parametrised `mock` / `live` (the live param carries the `live`
     mark). It returns a thin proxy over `forge_data`:
     - mock: `USE_MOCK_DATA = True`.
     - live: `USE_MOCK_DATA = False`; if `forge_data.get_session()` fails →
       `pytest.skip("No Snowflake connection; set SNOWFLAKE_CONNECTION_NAME")`. After
       every call the proxy drains `pop_notices()`; any notice means the live query fell
       back to mock → `pytest.fail(<Snowflake error>)`.
   - Hook that adds the `mock` mark to every test without `live` or `ui`.
3. **Contract tests** (each uses `forge`, so each has `[mock]` and `[live]` variants):

   | File | Tests | Contract |
   |------|-------|----------|
   | `consistency/test_cross_persona.py` | `test_otd_identical_across_personas`, `test_fill_rate_…`, `test_doi_…`, `test_landed_cost_…` (6 dp); persona values equal the app-owner governed number | §5.4, §6 |
   | `governance/test_masking.py` | one test per §6 row, per persona; returned columns match §5.4 exactly | §5.4, §6 |
   | `semantic/test_metric_ranges.py` | each metric inside its §3 range; naive OTD ≠ governed OTD, both in 0–1 | §3, §8 |
   | `semantic/test_dimension_pairings.py` | every valid pairing (55) returns rows with columns `[DIM, METRIC]` in §5.2 naming; values inside §4 value lists where listed; DOI × `orders.*`/`shipments.*` (9) rejected: by the app (mock) and by Snowflake itself (live, raw SQL) | §4, §5.2 |
   | `agent/test_canonical_questions.py` | each of the 8 questions returns a non-empty answer; mock also checks SQL + metric lineage. Richer live checks wait for artifact `07` (C6c) | §5.3, §9 |

   The existing mock "a mismatch is detected" test stays, so the proof is shown able to
   fail.
4. **`governance/test_source_isolation.py`** (offline): run every public `forge_data`
   function in live mode against a fake session that records each SQL string and then
   errors. Assert that `ERP_SOURCE` / `WMS_SOURCE` / `TMS_SOURCE` / `SRM_SOURCE` appear
   only in the §8 naive query. This exercises the live branches' SQL without Snowflake.
5. **CR-004 (proposed, needs the user's OK before appending to §11).** §6 has six masked
   columns, but the §5.4 sample procedures return only four of them (`UNIT_COST`,
   `PAYMENT_TERMS`, `CUSTOMER_NAME`, `CREDIT_LIMIT`). `V_SOURCING.contract_price` and
   `V_CUSTOMER.email` can't be checked per persona. Proposal: add `CONTRACT_PRICE` and
   `CUSTOMER_EMAIL` to the `SP_SAMPLE_AS_*` output. CoCo hasn't built these procedures
   yet (B07b), so there's no rework. Until accepted, those two rows are
   `skip("pending CR-004")`, not silently dropped.
6. **`tests/ui/`** (Playwright, headless Chromium, 1366 and 1600 wide):
   - `ui/conftest.py`: session fixture starts `python -m streamlit run streamlit_app.py`
     from `app/` on a free port (headless, mock mode), waits on `/_stcore/health`, and
     stops it after the run. Skips if Chromium is missing.
   - Checks, each in light and dark: header nav reaches every screen (the C03 click
     bug); problem drawer opens, filters, closes; fix layer click; same: metric tile
     updates all three persona cards; explore: bar focus, table view, impossible
     breakdowns disabled with a reason; ask: question card → answer card, SQL and
     Definition tabs; no JavaScript console errors on any screen.
   - A screenshot of every screen × theme goes to `tests/ui/_screenshots/` (gitignored)
     for a human look.
7. **Tidy `tests/unit/`**: drop the `sys.path` lines; move the four checks now covered
   by contract tests (valid pairings, DOI rejection, persona identical, masking matrix)
   out of `test_data_layer.py` so each rule is tested in one place. Replace the
   placeholder in `consistency/test_cross_persona.py`.
8. **Break-it check (not committed):** temporarily skew a mock value, a mask and a range,
   and confirm the matching contract test goes red. Record the result in this card.
9. Update the Test command in `CLAUDE.md` (`pytest -q`, plus `-m live` / `-m ui`).

---

## Gate

- `.venv/Scripts/python -m pytest -q` green: unit + all `[mock]` variants; `[live]`
  variants skip with the reason "No Snowflake connection".
- `pytest -m mock` green; `pytest -m live` collects with no import errors and every test
  skips cleanly.
- `pytest -m ui` green: every screen, light and dark, no JS errors; screenshots reviewed.
- The break-it check turns each contract test red, as recorded here.
- No Snowflake query run by Claude Code; zero credits.

---

## Decisions

| Decision | Why |
|----------|-----|
| One test body, `[mock]` + `[live]` variants via a fixture | The contract is written once; going live needs no rewrite. |
| Live fallback = test failure | Otherwise live tests pass on mock numbers and prove nothing. |
| Live skips only when there's no connection | With a connection, a missing object is a real conformance failure CoCo should see. |
| `ui` excluded from the default run | It starts a server and a browser (~1 min). Run it after UI changes. |
| Artifacts are not fixtures yet | Their shapes are unknown until CoCo captures them. C6a–c plug `docs/artifacts/` into these same tests. |

---

## Result (2026-09-25)

### Test counts

| Run | Result |
|-----|--------|
| `pytest -q` (default) | **170 passed, 118 skipped** (112 live variants + 6 pending CR-004), ~1 s |
| `pytest -m mock` | 170 passed, 6 skipped |
| `pytest -m live` | 112 collected, all skip: "No Snowflake connection (No module named 'snowflake')…" |
| `pytest -m ui` | **18 passed**, ~40 s; 36 screenshots (6 screens × 2 themes × 1280/1366/1600) reviewed |

Offline tests by folder: unit 58, consistency 8, governance 25, semantic 76, agent 9
(each contract test also has a `[live]` twin).

### Break-it check (scratch pytest plugin, not committed)

| Rule broken in the mock layer | Went red |
|-------------------------------|----------|
| Buyer fill rate +0.00001 | `test_fill_rate_identical_across_personas`, `test_persona_values_equal_the_governed_number` |
| Planner sees unit cost | `test_part_unit_cost[Planner]` |
| Days of inventory = 50 | `test_metric_inside_contract_range[days_of_inventory]` |
| Naive OTD = governed OTD | `test_naive_and_governed_otd_differ` |
| DOI × `orders.order_date` allowed | `test_days_of_inventory_by_orders_or_shipments_is_refused[orders.order_date]` |
| Region "LATAM" appears | `test_valid_pairing_returns_rows` for all 7 region pairings |
| DMF query reads `ERP_SOURCE` | both source-isolation tests |
| Agent returns an empty answer | all 8 canonical-question tests |
| Live mode, every query fails | live tests fail with "Live query fell back to mock data: … does not exist" |

### CR-004 applied (after CoCo accepted it, contract v1.3)
- `mock_data.masking_sample` gains `CONTRACT_PRICE` (visible to Buyer only) and
  `CUSTOMER_EMAIL` (`*** MASKED ***` for Buyer); `forge_data` casts `CONTRACT_PRICE` to a number.
- `test_masking.py`: the "pending CR-004" skips are gone, and the sample shape must match
  all ten §5.4 columns exactly.
- Now: `pytest -q` **176 passed, 112 skipped** (only the live twins); `pytest -m mock` 176 passed, 0 skipped.
- The Same screen still shows four visibility chips (unchanged design); its "rows each
  team gets" drawer shows all ten columns.

### What changed from the plan
- Browser helpers live in `tests/ui/app_driver.py` (not the conftest), so the test file
  imports them by a unique module name. If Playwright isn't installed, `tests/ui` is
  skipped at collection and the rest of the suite still runs.
- Added `test_next_buttons_follow_the_story` and a no-sideways-scroll check (page and
  each view) to the browser suite.
- Added two offline source-isolation checks: a new `forge_data` function must be listed
  in the test, and every statement the app sends matches a contract pattern.

### Findings
- **Streamlit's own console error:** `st.chat_input`'s audio code logs "Recording error:
  Container not found" when leaving Ask. It's harmless and from Streamlit's bundle, so
  the browser tests ignore console errors from `/static/js/` and count only our views'
  errors and uncaught exceptions.
- **Streamlit scrolls inside `.stMain`**, not the page, so screenshots stretch the
  window to the content height first.
- **Layout at 1366 px, fixed at the user's request (2026-09-25):** the selected "Explore
  metrics" pill touched "Data health", and The fix's "next" button wrapped.
  - Cause: header and "next" columns had fixed shares of the width, whatever their
    labels needed; the bold selected pill then spilled over.
  - Fix (`app/ui/theme.py`): those columns now size to their labels, the header row never
    wraps, the brand column gives way first, and below 1400 px nav pills are slightly
    tighter (11 px padding, 15 px text).
  - Adding 1280 px to the tests also showed The problem and The fix views cut off at the
    bottom, so their heights went from 800 → 820 and 1060 → 1120 (`app/streamlit_app.py`).
  - New browser checks keep it fixed: header on one row with no label spilling or
    overlapping, "next" button on one line, and no view cut off at the bottom, at 1280,
    1366 and 1600 px. Browser suite now **18 passed**.
- One intermittent Playwright `evaluate` error in about 70 browser-test runs, not
  reproduced in the next 54. The screenshot helper's height lookup now has a fallback.
- `snowflake-snowpark-python` isn't installed in `.venv`. That doesn't matter for Claude
  Code (no credentials), but CoCo needs it to run `pytest -m live` locally.

## On completion ✅

1. ✅ This card: status, break-it results, final test counts
2. ✅ `.agents/NEXT.md`: C04 ✅, C05 NEXT
3. ✅ `.agents/HANDOFF.md` ("Latest from Claude Code"): how CoCo can run `pytest -m live`; CR-004
4. ✅ `docs/SESSION_LOG.md`: Session 13
5. ✅ `.agents/tasks/README.md`: `C04` added to "Written:"
