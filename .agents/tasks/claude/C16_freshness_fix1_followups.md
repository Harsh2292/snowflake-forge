# C16 — Freshness fix 1 + the C10/C11 follow-ups from CoCo's runs

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs it (handoff lock) and re-captures art 10 |
| **Milestone** | Replan Day 2–3. **In the handoff lock by the end of 1 Oct** (CoCo's ask, user-approved) |
| **Prerequisite** | CoCo's run reports `runs/C10_run.md` and `runs/C11_run.md` (B12, B10); `docs/DATA_SPEC.md` §7.2 "Status rules" (revised 30 Sep, freshness fix 1) |
| **Writes** | `quality/30_sp_data_health.sql`, `quality/40_sp_dq_self_checks.sql`, `quality/00_setup.sql` (comment only), `eval/10_questions.sql`, `eval/99_run.sql`, `app/ui/views/health.html` + `app/ui/payloads.py` (the new status), tests (`tests/unit/test_quality_sql.py`, `test_eval_sql.py`, app tests) |
| **Status** | ✅ **READY** 2026-09-30: built, offline gate green (`pytest -q` 495 passed, 0 failed; `pytest -m ui` 22/22), in the handoff lock for CoCo (2 rows). The live gate = CoCo's re-run + the art 10 re-capture |

---

## Goal

The data-health check tells the truth on camera:
- reference data that rarely changes is no longer called stale
- every small issue CoCo found when running my data-quality and evaluation SQL is fixed in
  the files themselves

The test suite is green again: today's last 3 failures.

## Why

- `SP_DATA_HEALTH('ALL')` reads **FAIL** today only because suppliers, parts, plants,
  sourcing and customers were loaded long ago. That's normal for reference data, but the
  Data health screen shows red and the agent would tell a judge the data is stale.
- CoCo had to patch my files to run them (FRESHNESS signature, the CR-007 agent call) and
  asked for four small changes. Until they're in the files, a re-run in the new account (B08m
  cutover) would repeat the old problems.

## Design

**1. Freshness fix 1** (`quality/30_sp_data_health.sql`, DATA_SPEC §7.2)
- **Daily entities** (orders, order_lines, shipments, inventory): unchanged. OK ≤ 36 h,
  WARN ≤ 72 h, FAIL beyond.
- **Reference entities** (suppliers, parts, sourcing, plants, customers):
  - `freshness_status = 'REFERENCE'`, and it **doesn't count toward `status`**
  - `latest_load_ts` and `freshness_hours` are still reported
  - all their data-quality checks still run and still count
- The summary text says so, e.g. "5 reference tables are not judged on age".
- The thresholds are **not** raised (CoCo: that would hide a real warning).
- `SP_DQ_SELF_CHECKS`: add a check that the 5 reference entities read `REFERENCE`, and
  that `ALL`'s status ignores them.

**2. The app** (`health.html`, `payloads.py`): `REFERENCE` shows in a neutral grey as
"Reference", with a one-line note under the freshness table: "Reference data (suppliers,
parts, plants…) changes rarely, so it isn't judged on age." It never shows red. The mock
data stays the art 10 capture until CoCo re-captures; a unit test proves the view renders
`REFERENCE` neutrally.

**3. Adopt CoCo's run fixes as my own**
- `quality/00_setup.sql`: the FRESHNESS rows use `ON ()` (already in the file from CoCo).
  I fix its comment's `;`, which breaks CoCo's statement splitter rule, and update
  `test_quality_sql` to expect `COLUMNS NULL`.
- `eval/20_sp_run_eval.sql`: the CR-007 request-then-call form (already in the file). My
  test now checks the runner builds the same JSON request as the app (`agent_request`).

**4. CoCo's requests from the runs**
- **E04 tolerance:** the self-check accepts a measured count ≥ 0.95 × injected (was ≥ 1×;
  measured 19,390 vs 19,589).
- **Q30** ("What is on-time delivery rate by part category?", CROSS_GRAIN, expect a
  refusal or a clarification) goes into `10_questions.sql` verbatim from CoCo's insert.
  `99_run.sql` gets the 4th batch `'Q3%'` and expects 30 questions.
- **Q17's ground truth:** count parts below reorder point for **all 12 plants, zeros
  included** (LEFT JOIN), matching what the agent correctly returns.

## As built (30 Sep)

**`quality/30_sp_data_health.sql`**
- The entity list carries a KIND, DAILY or REFERENCE.
- REFERENCE is decided before the age rules, and scores 0, like OK.
- The entity sentence: "… are reference data, which changes rarely, so not judged on age
  (last loaded N days ago)".
- The `ALL` summary appends "5 reference tables change rarely and are not judged on age."
- An unreadable table is still UNKNOWN.

**`quality/40_sp_dq_self_checks.sql`**
- `HEALTH_REFERENCE_KINDS`: exactly the 5 read REFERENCE.
- `HEALTH_REFERENCE_NOT_AGED`: a reference entity is never worse than its worst check.
- The source-defect lower bound is ×0.95 (E04 19,390 of 19,589).
- 93 self-check rows expected.

**`quality/00_setup.sql`:** only the `;` in CoCo's comment became `:`. The `ON ()`
FRESHNESS rows are CoCo's, adopted; `test_quality_sql` now expects `COLUMNS NULL`.

**`eval/`**
- Q30 `CROSS_GRAIN` (REFUSE) is in `10_questions.sql`, and the category list now includes
  CROSS_GRAIN.
- Q17's ground truth uses a `V_PLANT` LEFT JOIN with `COUNT_IF`, so all 12 plants appear,
  zeros included.
- `99_run.sql`: 30 questions, 4 batches.
- `test_eval_sql` checks the runner builds the same request JSON as the app
  (`agent_request`) and calls `DATA_AGENT_RUN('<agent>', :req_text, TRUE)`.

**The app:** `health.html` shows REFERENCE as "Reference" in the muted tone, with a note
under the freshness table. Checked by the new `tests/ui/test_health_reference.py`, both
themes, 2 tests: the computed colour is not the critical red, and a screenshot was
reviewed.

**Tests:**
- new: `test_reference_entities_are_not_judged_on_age`,
  `test_self_checks_prove_the_reference_rule`,
  `test_source_defects_may_measure_a_little_under_the_injected_count`,
  `test_30_questions_with_stable_ids`, `test_driver_runs_four_batches…`, `test_q30…`,
  `test_q17…`
- `pytest -q` 495 passed, 0 failed; `pytest -m ui` 22/22

**After CoCo's run:** run `tests/tools/build_captured.py` on the new art 10 (the saved data
still has the old FAILs until then).

## Steps
1. Tests first: REFERENCE rules in the procedure text; Q30 present; 4 batches; Q17 keeps
   zeros; E04 0.95×; the runner request = the app's; comment rule.
2. Edit `quality/` and `eval/`; the app's neutral status.
3. `pytest -q` fully green (0 failures) and `pytest -m ui` (Data health screenshot with a
   REFERENCE row in both themes).
4. Hand over under the lock: the "Ready for CoCo to run" rows for `quality/30`, `40`, `00`
   (comment) and `eval/10`, `99`, with expected results. CoCo re-runs them and re-captures
   art 10, then I run `tests/tools/build_captured.py`.

## Gate
- [ ] `pytest -q` 0 failures; `pytest -m ui` green
- [ ] CoCo's run (in the lock): `SP_DATA_HEALTH('ALL')` reads OK (or WARN only for a real
      reason), the reference entities read REFERENCE, self-checks all TRUE, eval 30
      questions
- [ ] After the re-capture: `captured.json` rebuilt, and the Data health screen has no red
      caused by reference data
