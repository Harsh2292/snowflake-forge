# C15 — Community Cloud readiness (the public prototype link, live on Snowflake)

| | |
|---|---|
| **Owner** | Claude Code builds; CoCo + the user run the live trial (**B15a**, 30 Sep, old account) |
| **Milestone** | Replan Day 2 (30 Sep). ADR-009: the submitted Prototype Deployed Link is Streamlit Community Cloud |
| **Prerequisite** | CoCo's request in HANDOFF ("Latest from CoCo", 29 Sep, items 1–5). CoCo scripts `sql/05_app_access/01_app_service_user.sql` (user `FORGE_APP_SVC`, role `FORGE_APP_ROLE`) |
| **Writes** | `app/utils/forge_data.py`, `app/utils/config.py`, `app/streamlit_app.py`, `app/ui/screens/ask.py`, `app/requirements.txt`, `deploy/sis/environment.yml` (moved from `app/`), `deploy/deploy_app.py`, `.streamlit/config.toml` + `.streamlit/secrets.toml.example` (repo root), `.gitignore`, `.github/workflows/keep_awake.yml`, `app/ui/payloads.py` (cache TTL), `deploy/RUNBOOK.md`, `docs/references/community_cloud.md`; tests `tests/unit/test_community_cloud.py`, `tests/unit/test_no_secrets.py`, updates to `test_deploy_app.py` / `test_production_pass.py` |
| **Status** | ✅ **DONE (offline gate)** 2026-09-30: approved by the user and built. `pytest -q` 437 passed; the 5 failures are in files C15 doesn't touch (C6b, and CoCo's run fixes to quality/ and eval/; see "As built"). `pytest -m ui` 20/20. The live gate is CoCo's **B15a** |

---

## Goal

The same `app/` code runs in three places with no edits:

| Where | Session | Data mode |
|---|---|---|
| Streamlit Community Cloud (the public link) | Snowpark session from `st.secrets["connections"]["snowflake"]`, key-pair JWT as `FORGE_APP_SVC` | **live** |
| Streamlit in Snowflake (kept as the fallback) | `get_active_session()` | live |
| Local dev / CI | `SNOWFLAKE_CONNECTION_NAME`, or none | mock (as today) |

A judge opening the link sees live governed numbers. If Snowflake fails, the screen says so
in a banner that stays put, not only a toast. A public link can't run up an unbounded
Cortex bill, and no key or account name ever reaches the repo.

## Why

- ADR-009: judges must open the link without a Snowflake login. SiS can't do that.
- The public link is anonymous. Every Ask question is a Cortex Agent call that costs
  money, so the app needs its own limits on top of CoCo's warehouse resource monitor
  (the monitor doesn't cover Cortex AI spend).
- The B15a gate fails on any mock fallback, so a fallback has to be impossible to miss.

## Facts checked (details and sources go in `docs/references/community_cloud.md`)

1. **Dependency file precedence (Streamlit docs):** `uv.lock` > `Pipfile` > `environment.yml`
   > `requirements.txt` > `pyproject.toml`. The entrypoint's folder is searched first, and
   only the first file found is used. **`app/` has both files today, so Community Cloud
   would install from `environment.yml` (conda, Snowflake channel), not our pip file.**
2. **Working directory:** Community Cloud runs `streamlit run` from the **repo root**, and
   reads `.streamlit/config.toml` **only from the repo root**. Our theme file sits in
   `app/.streamlit/`, so the public app would lose its theme colours. Imports and view files
   are fine: `view.py` uses `Path(__file__)`, and Streamlit puts the script's folder on
   `sys.path`.
3. **Python version:** chosen in the deploy dialog's *Advanced settings* (default 3.12). We
   choose **3.11**, the same as CI and `environment.yml`.
4. **Private key from a string (connector 4.7.5 source, `auth/keypair.py`):** `private_key`
   accepts DER `bytes`, a **base64 DER `str`** (not PEM), or a key object.
   `private_key_file` needs a file path, and Community Cloud has no key file. So the app
   parses the PEM text from secrets with `cryptography` and passes DER bytes. That works on
   every connector version.
5. **Secrets:** pasted into *Advanced settings → Secrets* in TOML, and read with
   `st.secrets`. Locally, Streamlit reads `.streamlit/secrets.toml` from the working
   directory.

## Design

### 1. Session factory (`forge_data.get_session`)
Order: `get_active_session()` (SiS), then the secrets connection, then
`SNOWFLAKE_CONNECTION_NAME` (local).
- `forge_data` still never imports Streamlit. `streamlit_app.py` calls
  `forge_data.configure(connection=…, settings=…)` once, passing the
  `[connections.snowflake]` and `[forge]` secrets sections as plain dicts.
- The pure helper `session_params(section) -> dict`:
  - copies `account`, `user`, `role`, `warehouse`, `database`, `schema`
  - turns a PEM `private_key` (with an optional `private_key_passphrase`) into PKCS#8 DER
    bytes
  - sets `authenticator = SNOWFLAKE_JWT` and `client_session_keep_alive = True`
  - if a key is missing, the error names the missing key, never a value
- The account comes only from secrets. No account identifier appears in code, tests or docs;
  a test checks this.
- **Reconnect once:** Community Cloud keeps one process for many visitors for hours. If a
  live call fails because the session or token expired or the connection closed, the cached
  session is dropped and the call is retried once before any fallback.
- One shared session per process. Query tags stay best-effort: with visitors running at the
  same time, a tag can name the wrong path. That's acceptable for attribution, and B15a
  checks the tags in `QUERY_HISTORY`.

### 2. Dependency files
- `app/requirements.txt` becomes **the** Community Cloud file:
  - `streamlit==1.52.2`, pandas and Snowpark as today
  - plus `cryptography` (explicit, for the PEM parsing)
- **`app/environment.yml` moves to `deploy/sis/environment.yml`.** `deploy_app.py` uploads
  it to the stage root, so SiS still gets it. The existing test keeping the two Streamlit
  pins equal follows the move.
- The theme `config.toml` is copied to the repo root `.streamlit/`, and a test keeps both
  copies identical. (SiS and local-from-`app/` read `app/.streamlit/`; Community Cloud reads
  the root.)

### 3. Secrets hygiene
- `.streamlit/secrets.toml.example` holds only the shape: the connection section with
  placeholders, and a `[forge]` section with the Ask limits.
- `.gitignore`: `secrets.toml` anywhere, `*.p8`, `*.pem`, `rsa_key*`.
- `deploy_app.py` already skips `secrets.toml`. A test confirms it also skips key files.
- **CI check `tests/unit/test_no_secrets.py`** (runs inside the existing `pytest -q` job,
  with no new dependency). It scans every file git tracks, or would track (`git ls-files -co
  --exclude-standard`), for:
  - PEM private-key blocks
  - key files (`.p8`, `.pem`, `.key`)
  - a tracked `secrets.toml`
  - `snowflakecomputing.com` hostnames
  - `account = "…"` values that aren't placeholders

  It also checks that `git check-ignore` ignores `.streamlit/secrets.toml` and
  `app/.streamlit/secrets.toml`.

### 4. Cost guard: rate limiter + caps (Ask screen)
A per-visitor cap alone is weak: a new tab or private window starts a fresh session. So the
limits that really protect the bill are **global** (all visitors, one process), in
`st.cache_resource` behind a lock:

| Limit | Scope | Default | Stops |
|---|---|---|---|
| One question at a time, 10 s cooldown | per visitor | on | double clicks, spam |
| 10 questions | per visitor session | 10 | one person using up the day's budget |
| **3 agent calls in flight** | global | 3 | a burst of tabs or a bot running calls in parallel |
| **30 agent calls per rolling hour** | global | 30 | one visitor burning the daily cap in minutes |
| 200 agent calls per UTC day | global | 200 | total daily spend |

The counters reset if the app restarts. CoCo's warehouse monitor and Cortex budget stay the
hard cap.
- **Answer cache:** a live answer is cached for 1 hour, keyed by the normalised question.
  A cache hit costs nothing and doesn't count toward either limit, so the 8 suggested
  questions are nearly free after the first visitor. Fallback answers are never cached.
- Questions are capped at 500 characters.
- When a limit is reached, the Ask screen says so in plain words, and the rest of the app
  keeps working. Both limits can be overridden in `[forge]` secrets, so no commit is needed
  to change them.
- Query tags: unchanged (`forge_app:<function>`); the runbook tells CoCo how to read them.

### 4b. Other public-link guards
- **Other screens are already rate-limited by the cache:** `payloads.*` use
  `st.cache_data`, which is shared by all visitors. So Snowflake runs each screen's queries
  at most once per TTL, however many people visit. Explore has a finite set of
  metric × dimension pairs (58). The demo data is loaded once, so **TTL goes from 5 min to
  12 h** (see 4c). Fallback results are still never cached.
- **Statement timeout:** the session sets `STATEMENT_TIMEOUT_IN_SECONDS = 120`, so no
  query or agent call can run on unbounded. CoCo can set the same on the user or warehouse.
- **No error text on screen:** the banner and toasts show only the screen name, never the
  exception, so object names and hostnames can't leak. The full error goes to the server
  log.
- **Keep the link awake for judges:** Community Cloud puts an app to sleep after a period
  with no traffic, and a sleeping app shows a "wake up" button instead of the demo.
  `.github/workflows/keep_awake.yml` (cron, every 6 h, Playwright headless) opens the public
  URL, which comes from a repo variable, never committed, and checks the page loads. That
  costs a few cached queries per run.

### 4c. Judge experience (hackathon only)
- **A warm first load:** the screen cache TTL is **12 h** (the data is static), and
  `keep_awake.yml` clicks through every screen, so a judge never waits for a cold warehouse
  or a cold cache.
- **The suggested questions answer instantly:** the answer cache is **24 h** for the 8
  canonical questions (about 8 agent calls a day), and 1 h for free text.
- **Ask sets expectations:** the spinner says it "usually takes 20–30 s" and shows the
  steps (understanding → querying the semantic view → answering), so a slow answer doesn't
  look like a hang.
- **A judge-friendly fallback message:** after C6b the mock values are the last captured
  live numbers. So the banner reads "Live connection paused: showing the last captured
  Snowflake results", not "practice values".
- **Logs:** each fallback, limit hit and reconnect writes one line through `logging`, which
  the owner can read in Community Cloud's log panel.
- **Runbook extras:**
  - a custom subdomain (e.g. `supply-chain-forge.streamlit.app`, set by the user)
  - a **judging-day checklist**: the app is awake, the banner is absent, Ask answers, and
    the Cortex budget and monitor have headroom

Out of scope (overkill for the hackathon): login, CAPTCHA, an external store for the
limits (Redis), an observability stack, multi-region.

### 5. Live by default, and a visible fallback
- `configure()` switches `USE_MOCK_DATA` to False when a secrets connection is present, or
  when SiS is detected. An optional `[forge] mode = "mock"` forces mock without a commit.
  Local dev and CI with no secrets stay on mock, so the tests don't change.
- A fallback adds a **banner under the header that stays on screen**: "Snowflake unreachable
  for <screen>: showing saved practice values", on top of today's header tag and toast. The
  banner carries `data-source="mock_fallback"` so B15a can check it with a script.

### 6. Runbook and handover
- `deploy/RUNBOOK.md` (Community Cloud part):
  - generate the key pair (openssl, unencrypted PKCS#8)
  - hand the public key to CoCo's script
  - create the app from the public repo: branch, entrypoint `app/streamlit_app.py`, Python
    3.11
  - paste the secrets
  - the B15a checklist
  - key rotation
  - cutover to the new account, where only the secrets change
- HANDOFF (my section) tells CoCo which objects `forge_data` needs beyond FORGE_APP_ROLE's
  list (below).

## Objects `forge_data` touches vs FORGE_APP_ROLE's list (for CoCo)

| App call | Needs | In CoCo's list? |
|---|---|---|
| `get_metric` / `get_all_metrics` / `get_governed_otd` | `SELECT` on `SEMANTIC.SUPPLY_CHAIN_SV`; DOI's window subquery reads `GOVERNED.V_INVENTORY` | ✅ (verify whether querying the view needs `SELECT` on its base tables, including B09's `primary_sourcing`) |
| persona screens | `USAGE` on the 6 `SP_*_AS_*` procedures | ✅ |
| `ask_agent` | `USAGE` on the agent, `SNOWFLAKE.CORTEX_USER`; the agent's tools run as the caller (semantic view + `SP_DATA_HEALTH`) | ✅ |
| `get_data_health` | `USAGE` on `SP_DATA_HEALTH` | ✅ |
| `get_naive_otd` (§8) | `SELECT` on `TMS_SOURCE.VTTK`, `ERP_SOURCE.VBAK` | ✅ |
| **`get_quality_results`** (Data health screen) | **application role `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER`**, to read `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS`. Please verify the view returns rows for the tables C10 monitors when read by FORGE_APP_ROLE | ❌ **missing** |
| all | `USAGE` on the database and on schemas `SEMANTIC`, `GOVERNED`, `TMS_SOURCE`, `ERP_SOURCE` | implied; please state it in the script |

Not needed: any write privilege, `CONFORMED`/other source tables directly, `APP` schema.

## As built (30 Sep)

**Session and mode (`app/utils/forge_data.py`, `app/ui/settings.py`)**
- `configure()` is called on every run from `streamlit_app.py`, with the secrets read by
  `ui/settings.py` (an empty dict when there's no secrets file).
- `session_params()`: PEM → PKCS#8 DER; JWT; `login_timeout` 20 s;
  `STATEMENT_TIMEOUT_IN_SECONDS = 120`; base `QUERY_TAG = 'forge_app'`.
- One shared session behind a lock.
- **Login breaker:** after a failed login, calls fall back at once for 60 s instead of each
  waiting on its own login. The real login error is logged once and carried in later
  notices.
- **Reconnect once** on 390111 / 390112 / 390114 / 250001 / 250002, or on "token has
  expired" / "connection is closed" text. The SiS session is never replaced.
- **Notices are per thread**, i.e. per visitor's script run. Before C15 they were
  process-global, so one visitor's fallback could have shown on another visitor's screen.
- In SiS the active session is detected and live mode switches on by itself, so no flag
  needs flipping before a deploy.

**Screens**
- The fallback banner `.sf-alert[data-source="mock_fallback"]` sits under the as-of line in
  both themes; screenshots checked in light and dark. The header tag reads **Saved results**
  (the longer text was clipped at 1440 px).
- The toast now says "the last captured results".
- A missed as-of date is cleared from the cache at once, so it isn't kept for 12 h.
- `payloads` TTL = `config.SCREEN_CACHE_SECONDS` (12 h).

**Ask (`app/utils/ask_guard.py`, `app/ui/screens/ask.py`)**
- `AskLimiter` (global, `st.cache_resource`) and `AnswerCache` (24 h canonical / 1 h free
  text, live answers only).
- The per-visitor cooldown and cap live in `session_state`.
- Guarded in live mode only: mock answers cost nothing.
- Refusals show a plain `.sf-alert.note`.
- `st.chat_input(max_chars=500)`.

**Files**
- `app/environment.yml` moved (git mv) to `deploy/sis/environment.yml`; `deploy_app.py`
  uploads it through `EXTRA_FILES` and skips `.p8/.pem/.key`.
- Root `.streamlit/config.toml` (a copy) and `.streamlit/secrets.toml.example`.
- `.gitignore` covers secrets and keys.
- `.github/workflows/keep_awake.yml` + `.github/scripts/keep_awake.py`.
- `deploy/RUNBOOK.md`.

**Tests**
- `tests/unit/test_community_cloud.py` (29) and `tests/unit/test_no_secrets.py` (11).
- 2 new tests in `test_deploy_app.py`; `test_production_pass` / `test_replay_live` /
  `test_source_isolation` follow the changes.

**Offline gate evidence**
- **Real run from the repo root with secrets for a non-existent account:**
  - login failed once in the log (`290404 … 404 Not Found`)
  - every other call fell back instantly (breaker)
  - the banner shows on every data screen
  - `keep_awake.py` against it printed FALLBACK per screen and exited 1
  - the key used was generated in the scratchpad and deleted afterwards
- **Deliberate break:** a real PEM key planted in `planted_notes.md` made
  `test_no_secrets.py` fail; after removing it, 11 passed. Planted key, key-file, secrets-file,
  hostname and account-value cases are also permanent tests.

**Failures outside C15** (all in files C15 doesn't touch):
- `test_replay_live::test_every_captured_pairing…` (art 05 now has 58 pairings) and
  `test_data_layer::test_personas_and_mock_fixtures…` (contract §10 re-captured at B09):
  both are **C6b's** job, next.
- `test_eval_sql::test_no_semicolon_in_a_comment[quality/00_setup.sql]`,
  `test_quality_sql::test_catalogue_covers_the_spec_minimum_set` and
  `test_eval_sql::test_runner_calls_the_agent_as_the_app_does`: these follow CoCo's run
  fixes to `quality/` and `eval/` (B10/B12 run reports). I'll pick them up with C6b / the
  C11 add-on.

**Browser suite:** 20/20. One run in three had a 5 s dialog-visibility timeout in the Ask
card test (mock path). It passes alone and on reruns, so I'm treating it as timing
flakiness and watching it.

## Steps
1. `docs/references/community_cloud.md`: the fetched facts above, with sources and dates.
2. Session factory, `configure()`, reconnect-once, `session_params` (tests first: a key
   generated with `cryptography` in the test, PEM → DER, missing-key message, no secret in
   the error text, retry on an expired token).
3. Dependency files: move `environment.yml`, update `deploy_app.py` and its tests, root
   `config.toml` copy.
4. Secrets: the example file, `.gitignore`, `test_no_secrets.py` (plant a fake key in a temp
   copy to prove it catches one).
5. The Ask rate limiter and caps, and the answer cache. Unit tests on the limiter with a
   fake clock:
   - the cooldown
   - the 11th question in a session
   - the 4th in-flight call
   - the 31st call in an hour
   - the 201st call in a day

   A cache hit doesn't count. The payload TTL goes to 1 h, and the statement timeout is
   set.
5b. `keep_awake.yml`: skips cleanly while the `PUBLIC_APP_URL` repo variable is unset.
6. The fallback banner (unit test, plus `pytest -m ui` screenshots in live-fallback mode).
7. `deploy/RUNBOOK.md`, HANDOFF, NEXT, SESSION_LOG, README "Written:".

## Gate
- [ ] `pytest -q` green; `pytest -m ui` green, with screenshots checked (the banner in both
      themes)
- [ ] `test_no_secrets.py` catches a planted PEM key, `.p8` file and account hostname (3
      deliberate breaks, each caught)
- [ ] `session_params` builds a JWT config from a PEM string: DER bytes, no file, no account
      in code
- [ ] `app/` contains exactly one dependency file; `deploy --dry-run` still uploads
      `environment.yml`
- [ ] Offline run from the repo root (`streamlit run app/streamlit_app.py`) with a secrets
      file pointing at an unreachable account: the banner shows and nothing crashes
- [ ] **Live (B15a, CoCo + user):** the public URL loads every screen in a private window,
      numbers equal art 05/09, Ask answers, no fallback banner, and `QUERY_HISTORY` shows
      `forge_app:*` tags under `FORGE_APP_SVC`

## On completion
Update this card, NEXT progress table, HANDOFF "Latest from Claude Code", SESSION_LOG,
`.agents/tasks/README.md` "Written:".
