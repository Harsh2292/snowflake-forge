# C09 — App production pass

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M6 (app production pass); replan Day 1–2 (29–30 Sep) |
| **Prerequisite** | C03 ✅, C04 ✅, C6a ✅. Part B needs `docs/DATA_SPEC.md` + CR-006 (CoCo B08b) |
| **Est. effort** | Part A: one session. Part B: under an hour once the spec lands |
| **Writes** | `app/ui/payloads.py`, `app/ui/views/{base.js,explore.html,same.html,answer.html,problem.html}`, `app/utils/{forge_data.py,agent_response.py,mock_data.py,config.py}`, `app/streamlit_app.py`, `tests/conftest.py`, `tests/unit/*`, `tests/artifacts/test_replay_live.py` (new), `tests/ui/test_browser.py` |
| **Status** | ✅ **DONE** 2026-09-29: part A and part B (contract v1.5). `pytest -q` 285 passed, `pytest -m ui` 20 passed. See **Result** (part A) and **Result — Part B** |

---

## Goal

The app keeps working, and stays honest, when it switches from practice data to real
Snowflake data. That data is 10 years long, messy, and sometimes has no value for a group.

---

## Why

Five things break or mislead today once the data is real:

1. **A missing value crashes a screen.** Snowflake returns `NULL` where a metric has
   nothing to measure: fill rate for OPEN and CANCELLED orders is `NULL` by design
   (CR-005; art 05 shows it). The app does `float(value)` in 8 places and `v.toFixed()` in
   the views, so one `NULL` breaks Explore, Same for everyone or an answer card.
2. **Long results.** With 10 years of data a breakdown like order date has about 3,650
   rows. The answer chart would draw the *first* 12 days of 2016, and the app would keep
   every row in memory and in the message sent to the browser.
3. **A fallback can hide.** If Snowflake fails in live mode, the app shows practice values
   with one toast, then *caches* those values for 5 minutes. The header still says "Live",
   so a practice number could appear in the video as real.
4. **The live code paths are untested against real shapes.** `SP_METRICS_AS_*` now exist
   (B08), and art 05 holds real answers for all 55 pairings. Nothing yet runs those real
   answers through the app's own live code.
5. **Cost attribution** (core rule 9): Snowflake can't tell which screen spent the credits,
   unless the app tags its queries.

---

## Steps — Part A (now, no spec needed)

1. **Missing values show as "—"**, everywhere:
   - `payloads.py`: one `_num()` helper instead of `float()`; `NULL`/`NaN` becomes JSON
     `null`.
   - `config.format_value(None)` returns "—".
   - `base.js` `fmt()` returns "—" for `null`, with a tooltip: "No value: nothing in this
     group meets the metric's definition".
   - The views skip bar widths and deltas for `null`: Explore, Same (`toFixed`), answer
     chart, Problem.
   - `compare_across_personas()`: `NULL` in all three counts as identical; `NULL` in only
     some does not.
2. **Explore gets a "By order status" breakdown**, so a real "—" is visible and the CR-005
   rule is shown, not just stated. It's a valid §4 pairing for OTD, fill rate and landed
   cost; days of inventory stays switched off with its reason. The practice data mirrors
   the real shape (art 05):
   - fill rate for OPEN and CANCELLED is `NULL`
   - OTD and landed cost have only SHIPPED and DELIVERED rows
3. **Long results are bounded:**
   - `agent_response`: keep at most 500 rows per table, plus the true row count.
   - Answer card: at most 12 bars, with "12 of N rows". A date or time label takes the
     most recent 12; anything else takes the first 12 in the agent's order.
   - Explore: at most 12 bars, "Showing 12 of N"; the table view lists all.
4. **The data source is always visible:**
   - The header badge shows what the current screen is actually showing: **Live**,
     **Mock data**, or **Practice values (Snowflake unreachable)**.
   - A screen built from a fallback isn't cached, so the next visit retries Snowflake.
5. **Replay the real artifacts through the live code** (new
   `tests/artifacts/test_replay_live.py`, offline):
   - `ReplaySession` also answers each `SEMANTIC_VIEW(…)` query from art 05, typed like
     Snowpark (`Decimal`, `None`). Rows are in art 05's unsorted order, as CoCo warns.
   - It answers `SP_METRICS_AS_*` from art 05's overall values, as `NUMBER(38,6)`.
   - Then: all 55 pairings through `get_metric()` (live), and the Explore, Fix and Same
     payloads built in live mode. No crash, `NULL` preserved, and every value equals art 05.
   - The whole app runs in AppTest with `USE_MOCK_DATA = False` on the replay session. The
     screens with data render; the ones without (agent, data health) show the fallback
     label.
6. **Query tags** (to verify at B15): `forge_data` tags its session once per path, for
   example `forge_app:explore`. Owner's-rights apps may not allow it, so it's tried once
   and skipped silently if refused. CoCo confirms at B15 in query history.
7. **Dependencies in step**: a unit test that `environment.yml` and `requirements.txt` pin
   the same Streamlit version.
8. **Browser check**: `pytest -m ui` with new checks:
   - Explore → fill rate → by order status shows "—" twice, and nothing reads `NaN`
   - the header badge text

   Then screenshots, light and dark.

## Steps — Part B (when `docs/DATA_SPEC.md` + CR-006 land)

9. **As-of date** on every metric screen, from the CR-006 time rule, identical for the app
   and the agent.
10. **Data health shows `SEMANTIC.SP_DATA_HEALTH`** output (the shape from DATA_SPEC
    §Interfaces) next to the DMF results; practice data mirrors the shape.
11. **Remove `MCP_SERVER`** from `config.py` once CR-006 is approved.

Not in scope:
- flipping `USE_MOCK_DATA` (C6c)
- new practice numbers (C6b, after contract v1.5)
- the agent parser against real JSON (C6c)

---

## Gate

- `pytest -q` and `pytest -m ui` green.
- All 55 art 05 pairings pass through the live path, values equal to art 05, `NULL` shown
  as "—".
- Screenshots (light and dark) show "—" for a missing value and the correct data-source
  badge.
- Part B: the as-of date is on every metric screen; `SP_DATA_HEALTH` output renders.

---

## Result — Part A (2026-09-29)

**Gate for part A: passed.**

| Check | Result |
|---|---|
| `pytest -q` | **250 passed**, 112 skipped (live twins); 23 new tests |
| `pytest -m ui` | **20 passed** (18 before, plus the Explore missing-value check in light and dark) |
| All 55 art 05 pairings through the live path | ✅ values equal art 05; `NULL` kept (4 pairings have `NULL`s) |
| Whole app in live mode (AppTest on the replay session) | ✅ Explore and Same say **Live**; Data health says **Practice values (Snowflake unreachable)**, because the checks don't exist yet |
| Screenshots | `tests/ui/_screenshots/{light,dark}-explore-missing.png`: fill rate by order status, OPEN and CANCELLED show "—" and sort last, with the note |

**What changed:**
- **Missing values**:
  - `config.as_number()` (float or `None`, including pandas `NA`); `config.format_value` gives "—".
  - Payloads use it everywhere `float()` was.
  - `base.js` has `missing()`, `valueHtml()` (the dash with a "No value" tooltip) and `diff()`.
  - The Explore, Same, Problem and answer views are `NULL`-safe.
  - `compare_across_personas`: `NULL` matches only `NULL`.
  - A `NULL` data-quality result reads "Not measured yet" (INFO), not a failure.
- **JSON safety net**: `view.build` turns NaN/inf into `null` (`allow_nan=False`). Before, one stray NaN would have blanked a screen.
- **Explore → "By order status"** for OTD, fill rate and landed cost. Days of inventory stays off, with its reason. The practice data mirrors art 05:
  - fill rate is `NULL` for OPEN and CANCELLED
  - shipment metrics only for SHIPPED and DELIVERED
- **Long results**:
  - The agent parser keeps at most 500 rows per table, plus `row_counts` (the true total).
  - Answer charts: at most 12 bars, "12 of N rows"; time series show the most recent 12, in time order.
  - Explore: at most 12 bars, "Showing 12 of N"; the table lists all.
- **Source badge**: the screen is built before the header, which shows **Live**, **Mock data** or **Practice values (Snowflake unreachable)**. A screen built from a fallback is removed from the cache, so the next visit retries.
- **Query tags**: `forge_app:<function>` per path, set only when the path changes. If the session refuses (possible under owner's rights), tagging switches itself off. **To verify at B15** in query history.
- **Tests**:
  - `ReplaySession` (conftest) now also serves art 05, plus `SP_METRICS_AS_*` built from its overall values as a stand-in until art 09.
  - New `tests/artifacts/test_replay_live.py` (9) and `tests/unit/test_production_pass.py` (14).
- **Contract test fixed**: `test_valid_pairing_returns_rows` required every value to be present. Real Snowflake returns `NULL` by design (art 05), so the `[live]` run would have failed. It now needs at least one value, with every value in bounds.
- Found by the new tests: pandas' `NA` crashed `as_number`; fixed.

**Not done yet (part B):** the as-of date, `SP_DATA_HEALTH` on Data health, removing
`MCP_SERVER`.

---

## Result — Part B (2026-09-29, contract v1.5)

**Gate: passed.** `pytest -q` **285 passed** (116 live skips). `pytest -m ui` **20 passed**.
The as-of line and the Data health tables were checked in screenshots, light and dark.

- **§3 definitions**: `config.METRICS` is copied from contract v1.5 word for word, and the
  existing test compares it with the contract's own block.
- **§3a time rule in every metric query**:
  - `forge_data.default_where()` adds the ship-date window for OTD and landed cost, the
    order-date window for fill rate, and the latest snapshot for days of inventory
  - `build_metric_sql()` refuses to mix windows; `get_all_metrics()` makes one call per
    window (3)
  - the §5.1, §5.2 and §8 contract tests pass again
- **§8 naive OTD** has the same 12-month window.
- **§4**: `orders.order_year_quarter` added. The valid pairings go from 55 to **58**, the
  refused days-of-inventory pairings from 9 to 10. The practice data has `2025-Q4` …
  `2026-Q3`.
- **§1 / CR-006**: `MCP_SERVER` removed; `DATA_HEALTH_PROC` added.
- **`SP_DATA_HEALTH`**:
  - `forge_data.get_data_health(entity)` calls `CALL …SP_DATA_HEALTH(?)` with the entity
    bound; unknown entities are refused; the practice data mirrors the DATA_SPEC §7.2
    shape
  - **the as-of date** is on every screen: "Data as of 29 Sep 2026 · Metrics cover the last
    12 months unless stated; days of inventory uses the latest snapshot". In live mode, if
    the procedure isn't reachable, **the date is hidden**, so a practice date is never shown
    as live.
  - **Data health** adds a "Freshness by table" section (rows, latest data, freshness,
    status per table).
- **Data quality judged by layer** (DATA_SPEC §7.2): `QUALITY_SQL` reads `table_schema`.
  Results on `*_SOURCE` are informational ("Expected in raw data"); zero is required only
  in the cleaned data. New DMF names are labelled in plain words.
- **Explore**: each chart title states its window ("· last 12 months" / "· latest snapshot").
- **Source catalog**: 10 tables (`TCURR` and the currency columns added, not exposed
  downstream).
- **Frame heights**: Problem 850, Fix 1200, Data health 1340. The longer definitions and
  the new sections grew them; the browser layout checks caught all three.
- **Tests added**: time rule per metric (and against the §5.1 table), no mixed windows, one
  call per window, the §7.2 shape, quality by layer, the as-of date on every screen and
  hidden in live without the procedure, window labels. The replay session now serves the
  per-window queries.

Still depends on CoCo:
- `SP_DATA_HEALTH` exists at B12 (C10 writes it)
- the §10 practice numbers change at B09 → C6b

---

## On completion

1. This card
2. `.agents/NEXT.md` (C09 row)
3. `.agents/HANDOFF.md` ("Latest from Claude Code"): what the app now expects; query tags to
   check at B15
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
