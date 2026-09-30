# C6b — Reconcile the semantic layer: practice data becomes the last captured Snowflake results

| | |
|---|---|
| **Owner** | Claude Code (offline, no Snowflake) |
| **Milestone** | Replan Day 2 (30 Sep) |
| **Prerequisite** | B09 ✅ (art 05, 06, 09 re-captured; contract §10 updated), B12 ✅ (art 10), B08c run (the §8 naive value) |
| **Writes** | `app/utils/config.py` (§10 verbatim), `app/utils/mock_data.py`, new `app/utils/captured.json` + its builder `tests/tools/build_captured.py`, `app/ui/payloads.py` (the wording "practice values"), tests (`tests/artifacts/test_replay_live.py`, a new `tests/unit/test_captured.py`) |
| **Status** | ✅ **DONE** 2026-09-30: approved by the user and built. `pytest -q` 451 passed; the 3 failures left are the C10/C11 follow-ups' (CoCo's run fixes). `pytest -m ui` 20/20 |

---

## Goal

When the app shows saved data (mock mode, or a live fallback on the public link), every
number is **the last real Snowflake result CoCo captured**, not a made-up practice value.
That makes the C15 banner's promise true ("showing the last captured Snowflake results"),
and it makes mock mode an honest rehearsal of the live demo.

## Why

- Contract §10 changed at B09 (the new data plus the §3a time windows), and the app still
  has the old values. That's 1 of today's failing tests.
- Art 05 now has **58** pairings (the contract's 55 + `orders.order_year_quarter` ×3), and
  the replay test still expects 55. That's the other failing test.
- Most Explore breakdowns in mock mode are generated values with fake names
  (`MOCK-PLANT-01`). A judge seeing a fallback would see fake plants.

## Design

1. **`config.py` §10:** `MOCK_METRICS` / `MOCK_BY_REGION` copied verbatim from the contract
   (OTD 0.8753, fill 0.9261, DOI 36.4, landed cost 604.84).
2. **`app/utils/captured.json`** (about 300 KB, 4,465 rows, generated, never hand-edited).
   It sits inside `app/` so Community Cloud and SiS both have it. It holds:
   - art 05: every one of the 58 pairings' rows, and the overall values
   - art 09: persona metrics and masked samples
   - art 10: the latest DMF results and `SP_DATA_HEALTH('ALL')` / `('shipments')`
   - the §8 naive OTD, **0.681651** (B08c run, gate 5)

   Each section carries its artifact, build step and capture date.
3. **`tests/tools/build_captured.py`** rebuilds the file from `docs/artifacts/`. A test fails
   if the file drifts from the artifacts, so after every re-capture: run the script, and the
   tests go green.
4. **`mock_data.py`** reads `captured.json` once:
   - `metric_frame(metric, dim)` returns the captured rows, in the same shape as the live
     path: numbers as float, NULL as missing
   - `quality_results()`, `data_health()`, `masking_sample()` and `MOCK_NAIVE_OTD` come from
     it
   - the mock agent's canned answers are built from those frames, so they quote real numbers

   The synthetic generator stays only as a safety net if a pairing is missing, and a test
   checks that nothing uses it.
5. **Wording:** "Practice values" notes become "Last captured Snowflake results (29 Sep)".
   The header tag in mock mode stays "Mock data".
6. **Art 06 reconcile:** a test checks that `config.VALID_PAIRINGS` equals art 06's 58
   PASS rows, and that none of art 06's 20 "accepted but multi-counting" pairings is in
   `VALID_PAIRINGS`.
7. **Art 09 reconcile:** a test checks the three personas' metrics are identical to 6 dp
   and equal art 05's overall values.

## Not in C6b (queued after it; see NEXT)
- **CR-007** (the live Ask call fails as written) → **C6c**, together with the agent parser
  against art 07.
- The C10 / C11 follow-ups from CoCo's run reports:
  - adopt the run fixes into my tests
  - E04 tolerance
  - master-data freshness in `SP_DATA_HEALTH`
  - Q30 + the 4th batch
  - Q17's ground truth

## As built (30 Sep)

**Saved data**
- `app/utils/captured.json` (299 KB, compact JSON) is built by `tests/tools/build_captured.py`
  from art 05, 09 and 10, plus the §8 naive value from `runs/B08c_run.md`.
- `mock_data` serves it everywhere:
  - every metric pairing (58/58), the overall values and the persona rows (art 09, in
    §5.4 column order)
  - the masked samples (the §6 matrix reproduces art 09 exactly)
  - DMF results (77) and `SP_DATA_HEALTH`
  - `MOCK_NAIVE_OTD = 0.681651`

  The synthetic generator is now only a safety net, and a test proves nothing uses it.
- `config.py` §10 is verbatim (it's the capture, rounded; tested).
- **The problem screen:** 68.2% vs 87.5%, 19.4 points apart (was 79.4% vs 87.1%).
- **Wording:** "Last captured Snowflake results (29 Sep 2026)", "Saved answer", "(last
  captured results)".

**Found and fixed on the way (it would have broken live too)**
- **The Data health view was 5,460 px too short for 77 real checks.** It now shows one row
  per kind of check and layer: 17 rows, the cleaned data first, then the raw data. Each row
  names its distinct tables and gives the total.
- ROW_COUNT and FRESHNESS moved out of the list, because the freshness table shows them per
  table.
- The view's height follows its content (`payloads.health_height`), so live works for any
  count.
- The header still counts each DMF association: **22 of 22 checks passing**.

**Reconcile (`tests/unit/test_captured.py`, 11 tests; zero unexplained mismatches)**
- `captured.json` == the builder's output.
- Art 05 pairings == contract §4 (58).
- Art 06: its ✅ rows == `VALID_PAIRINGS`, all PASS, and its row counts == art 05's. Its 20
  "accepted but multi-counting" pairings are outside the app.
- Art 09 personas are identical to 6 dp and equal art 05.
- The masked samples == art 09.
- §10 == the capture, rounded.
- The naive value is ≥ 8 points below the governed one.

**Deliberate break:** editing one value in `captured.json` made 2 tests fail; restoring it
gave 11 passed.

**Notes**
- Art 06 is stored double-encoded (✅ appears as `âœ…`), so the test accepts both. This is
  cosmetic, and it's CoCo's file.
- The captured `SP_DATA_HEALTH` reports FAIL for master data (suppliers, parts, sourcing,
  plants, customers). That's real output, and it shows red in the freshness table until the
  C10 follow-up fixes the procedure and CoCo re-captures (then run the builder).
- **After any re-capture:** run `.venv/Scripts/python tests/tools/build_captured.py`.

## Steps
1. Write `build_captured.py` and generate `captured.json`; write the drift test first.
2. `config.py` §10; switch `mock_data.py` to the captured values; wording.
3. Update the replay test to 58 pairings; add the art 06 / art 09 reconcile tests.
4. `pytest -q` and `pytest -m ui`, then check the screenshots: the numbers match art 05
   (e.g. OTD 87.5%, naive 68.2%).

## Gate
- [ ] `pytest -q`: the 2 C6b failures fixed, and nothing new fails (the 3 C10 / C11
      failures stay until their card)
- [ ] every mock number traces to an artifact: `captured.json` equals the builder's output
- [ ] `pytest -m ui` green; screenshots show real plant names and art 05 values
- [ ] zero unexplained mismatches between art 05, art 06, art 09 and the contract

## On completion
Update this card, the NEXT progress table (and the user's table if anything is left for the
user), HANDOFF "Latest from Claude Code", SESSION_LOG, and `.agents/tasks/README.md`
"Written:".
