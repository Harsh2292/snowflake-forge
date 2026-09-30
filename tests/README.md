# Tests

The contract (`docs/CONTRACT.md`) and the data spec (`docs/DATA_SPEC.md`) as executable
checks. Run everything from the repo root.

| Command | What runs | Needs |
|---|---|---|
| `python -m pytest -q` | unit + contract tests on the mock data (the last Snowflake capture, C6b), the replay tests (CoCo's real output through the app's live code), the SQL structure tests. **Live variants skip.** This is what CI runs | `app/requirements.txt` + `tests/requirements.txt` |
| `python -m pytest -m ui -q` | every screen in a real browser, light and dark (~60 s). Screenshots in `tests/ui/_screenshots/` | + `python -m playwright install chromium` |
| `python -m pytest -m live -q` | **the live contract audit** (CoCo at B14): 148 checks against real Snowflake, with a per-section summary at the end | a Snowflake connection (below) |

## The live audit

```
set SNOWFLAKE_CONNECTION_NAME=<your connection>      # Windows; export … on macOS/Linux
python -m pytest -m live -q
```

- **Needs:** a connection in `~/.snowflake/connections.toml` (or the secrets connection the
  app uses), Python 3.11 and `pip install -r app/requirements.txt -r tests/requirements.txt`.
  Nothing else. If no session opens, every live test skips and says why.
- **Role:**
  - **B14:** run as `FORGE_ADMIN`, the app owner's view.
  - **B15a:** run it again with a connection whose role is `FORGE_APP_ROLE` (the public
    app's role). The masking and persona checks go through the `SP_*_AS_*` procedures, so
    they hold for any caller.
  - A `FORGE_APP_ROLE` run proves the role has every grant the app needs: a missing grant
    fails the test that uses it, naming the object.
- **Cost:** 10 Cortex Agent calls (the 8 canonical questions, the cross-grain refusal,
  the data-health question), plus ~150 small queries on `FORGE_WH`. A few cents,
  ~3–5 minutes.
- **A live fallback fails the test.** The app falls back to saved data when Snowflake
  errors; in a live test that becomes a failure showing the Snowflake error (the `forge`
  fixture in `conftest.py`).

### Reading the result

The run ends with a table, one row per contract section:

```
============================ Live contract audit (C13) ============================
Contract section                                     passed  failed  skipped
§3 metric ranges · §5.1 shape · §8 naive vs governed     11       0        0
§4 pairings · §5.2 shape                                 68       0        0
§1/§3/§4 objects in the semantic view                     6       0        0
§6 masking (§5.4 samples)                                21       0        0
§7 governed view columns                                  9       0        0
§6 invariant: one number for every persona                8       0        0
§5.3 / §9 agent (CR-007)                                 10       0        0
DATA_SPEC §7.2 data health + DMFs                        15       0        0
```

Each failure follows as one line that names the Snowflake object, for example
`SUPPLY_CHAIN_FORGE.GOVERNED.V_PART lacks contract §7 columns ['unit_cost']`.

| Section | Files |
|---|---|
| §3 / §5.1 / §8 | `semantic/test_metric_ranges.py` |
| §4 / §5.2 | `semantic/test_dimension_pairings.py` |
| §1 / §3 / §4 in the view | `semantic/test_semantic_objects.py` (live only) |
| §6 masking | `governance/test_masking.py` |
| §7 | `governance/test_governed_columns.py` (live only) |
| §6 invariant | `consistency/test_cross_persona.py` |
| §5.3 / §9 | `agent/test_canonical_questions.py`, `agent/test_agent_behaviour.py` |
| DATA_SPEC §7.2 | `quality/test_data_health_live.py` |

**Expected after C16 and before its re-run:** `test_reference_data_is_not_judged_on_age`
and `test_all_is_not_failing_and_is_dated` fail until CoCo re-runs
`quality/30_sp_data_health.sql` (C16, in the handoff lock). That's the audit doing its job.

## Other folders

- `artifacts/`: CoCo's captured output replayed through the live code (`[replay]` tests).
- `unit/`: the app, the data layer, the SQL files (`data_gen/`, `quality/`, `eval/`,
  `tests/scale/`) and the no-secrets check.
- `scale/`: the scale harness CoCo runs in Snowflake (C12), not pytest.
- `tools/build_captured.py`: rebuilds `app/utils/captured.json` after a re-capture.
