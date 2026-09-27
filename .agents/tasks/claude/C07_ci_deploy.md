# C07 — Automated tests on GitHub + one-command app deploy

| | |
|---|---|
| **Owner** | Claude Code (writes); CoCo (runs the deploy at B15) |
| **Milestone** | M2 (parallel with CoCo B04) |
| **Prerequisite** | C04 ✅ (test suite) |
| **Est. effort** | Half a session |
| **Writes** | `.github/workflows/tests.yml`, `deploy/deploy_app.py`, `tests/unit/test_deploy_app.py`, `docs/references/streamlit_in_snowflake.md` §7, the Boundaries and Commands in `CLAUDE.md` |
| **Status** | ✅ **DONE** 2026-09-27 (local gate). First GitHub run happens when the user pushes. |

---

## Goal

Every push to GitHub runs the test suite automatically, and CoCo can deploy (and
redeploy) the whole app to Streamlit in Snowflake with one command that never misses a
file.

---

## Why

- **The documented deploy steps were out of date.** `docs/references/streamlit_in_snowflake.md`
  §7 uploads only `streamlit_app.py`, `environment.yml` and `utils/*.py`. The app also
  needs `ui/`, `ui/screens/`, `ui/views/` (HTML/CSS/JS) and `.streamlit/config.toml`.
  Copied as written at B15, the app would fail to start in Snowflake.
- **A script walks the `app/` folder**, so new files are always included and a redeploy
  after a fix is one command, not a hand-typed list of `PUT`s.
- **Tests on every push** show judges a working quality check (a green badge) and catch
  a broken commit before B15. They need no Snowflake credentials, because the live
  tests skip there.
- Not doing: deploy environments, auto-deploy from GitHub (that would put Snowflake
  secrets on GitHub), Docker. HLD §3 rules out extra infrastructure for the hackathon.

---

## Steps

1. **Fix the reference** (`docs/references/streamlit_in_snowflake.md` §7): upload the
   whole `app/` folder with subfolders, point to the script, and add redeploy facts
   from the docs (fetched 2026-09-27): `FROM` copies files once; `CREATE OR REPLACE
   STREAMLIT` redeploys; viewers of a warehouse-runtime app see changes after a rerun.
2. **`deploy/deploy_app.py`** (Snowpark, the same named connection as `pytest -m live`):
   - Collects every file under `app/`, skipping `__pycache__`, `*.pyc` and local-only
     files, and keeps relative folders.
   - `USE ROLE FORGE_ADMIN` (the app owner; `--role` overrides), `USE WAREHOUSE FORGE_WH`.
   - `CREATE STAGE IF NOT EXISTS SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE`, then removes the old
     `@…/app` copy so deleted files don't linger, then `session.file.put` for each folder
     (`auto_compress=False`, `overwrite=True`).
   - `CREATE OR REPLACE STREAMLIT SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO FROM '@…/app'
     MAIN_FILE='streamlit_app.py' QUERY_WAREHOUSE=FORGE_WH TITLE='Supply Chain Forge'`, then
     `ALTER STREAMLIT … ADD LIVE VERSION FROM LAST`.
   - Re-grants `USAGE` to any `--grant-usage ROLE`, because a replaced object loses its grants.
   - Checks that the app is live afterwards and prints where to open it.
   - `--dry-run` prints the file list and every SQL statement without connecting.
3. **`tests/unit/test_deploy_app.py`** (offline): every app file is included, nothing
   local-only is, `environment.yml` and `streamlit_app.py` sit at the root, SQL uses the
   contract FQNs, and the dry run needs no Snowflake.
4. **`.github/workflows/tests.yml`**, run on push and pull request:
   - `tests` job: Python 3.11, installs `app/requirements.txt` + `tests/requirements.txt`,
     runs `pytest -q`.
   - `browser` job: installs Chromium and runs `pytest -m ui`, uploading the screenshots
     as a build artifact.
   - Actions pinned to their current majors (`checkout@v7`, `setup-python@v7`,
     `upload-artifact@v7`, latest releases checked 2026-09-27).
5. **Local proof**: a fresh virtual environment built only from the two requirements files
   runs `pytest -q` green (the same thing CI does); `deploy_app.py --dry-run` prints a
   complete plan.
6. `CLAUDE.md`: Claude Code also owns `.github/` and `deploy/`; add the deploy command.

---

## Gate

- `pytest -q` green locally, including the new deploy tests.
- A fresh venv from `app/requirements.txt` + `tests/requirements.txt` passes `pytest -q`.
- `python deploy/deploy_app.py --dry-run` lists every file under `app/` (views included)
  and the full SQL.
- The workflow file is valid YAML with both jobs. It first runs on GitHub when the user
  pushes; that result is recorded here.

---

## Result (2026-09-27)

| Check | Result |
|-------|--------|
| `pytest -q` (repo `.venv`) | **186 passed**, 112 skipped (live twins), incl. 10 new deploy tests |
| Fresh venv from `app/requirements.txt` + `tests/requirements.txt` (what CI installs) | 186 passed; with Snowpark installed, live tests skip with "SNOWFLAKE_CONNECTION_NAME is unset" |
| Same venv, `pytest -m ui` | 18 passed |
| `deploy_app.py --dry-run` | 25 files, views and `.streamlit/` included; full SQL printed |
| Workflow YAML | parses; jobs `tests` and `browser` |
| First run on GitHub | ⏳ after the user pushes |

- Found while doing this: `app/utils/persona_queries.py` is an unused legacy placeholder.
  It deploys harmlessly; left in place.
- The deploy script prints ASCII only (Windows consoles use cp1252).
- Risk on GitHub: the browser job loads the Instrument Sans font from fonts.gstatic.com.
  If that were blocked, Linux fallback fonts are wider and the 1280 px header check could
  fail. Not seen locally.

## On completion ✅

1. ✅ This card
2. ✅ `.agents/NEXT.md` progress table (C07 row)
3. ✅ `.agents/HANDOFF.md` ("Latest from Claude Code"): B15 now = run `deploy/deploy_app.py`
4. ✅ `docs/SESSION_LOG.md`
5. ✅ `.agents/tasks/README.md` "Written:" list
