# Runbook: the public prototype link (Streamlit Community Cloud, live on Snowflake)

The submitted **Prototype Deployed Link** is this repo's `app/` on Streamlit Community
Cloud (ADR-009). It reads Snowflake live as the key-pair service user `FORGE_APP_SVC` with
the read-only role `FORGE_APP_ROLE`. The design is in `.agents/tasks/claude/C15_community_cloud.md`,
and the facts behind it are in `docs/references/community_cloud.md`.

**Who does what:** the user runs steps 1, 3 and 4. CoCo runs step 2 (and B15a / B15). No
key, secret or account name ever goes into the repo: `.gitignore` covers them, and
`tests/unit/test_no_secrets.py` fails CI if one slips in.

---

## 1. Generate the key pair (the user, once per account)

In a folder **outside the repo**:
```
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```
- `rsa_key.pub`: give its body (the lines between `BEGIN` and `END`) to CoCo for step 2.
- `rsa_key.p8`: the private key. It goes only into Community Cloud's secrets (step 3).
  Keep it in your password manager and never commit it.

## 2. Service user and role (CoCo: `sql/05_app_access/01_app_service_user.sql`)
- `FORGE_APP_ROLE`, read-only. It holds exactly what `app/utils/forge_data.py` touches;
  the list is in the C15 card and in HANDOFF, including
  `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` for the Data health screen.
- `FORGE_APP_SVC` `TYPE = SERVICE`, `DEFAULT_ROLE = FORGE_APP_ROLE`,
  `DEFAULT_WAREHOUSE = FORGE_WH`, and `RSA_PUBLIC_KEY` from step 1.
- Cost caps:
  - the resource monitor on `FORGE_WH`
  - the Cortex budget
  - optionally, `STATEMENT_TIMEOUT_IN_SECONDS = 120` on the user (the app sets it on its
    session too)

## 3. Create the Community Cloud app (the user)
1. <https://share.streamlit.io> → **Create app** → *Deploy a public app from GitHub*.
2. Repository: this repo. Branch: the one to show (`main` after the merge). **Main file
   path: `app/streamlit_app.py`**.
3. **App URL:** choose a readable subdomain, e.g. `supply-chain-forge`, which gives
   `supply-chain-forge.streamlit.app`.
4. **Advanced settings:**
   - **Python version: 3.11** (the same as CI and SiS)
   - **Secrets:** paste a filled-in copy of `.streamlit/secrets.toml.example`: the account
     identifier, and the whole of `rsa_key.p8` inside the `"""` quotes, header and footer
     lines included
5. Deploy. The first build takes a few minutes. It installs from `app/requirements.txt`,
   which is the only dependency file in `app/` on purpose.

**To change a secret later:** app menu → Settings → Secrets. The app restarts by itself.

## 4. Check it (the B15a gate), in a private browser window
- [ ] The header tag says **Live**, and no "Live connection paused" banner shows on any
      screen
- [ ] The numbers equal art 05 / art 09
- [ ] Ask: a suggested question returns an agent answer (the second time, instantly: it's
      cached)
- [ ] Data health shows the data-health date and the DMF checks
- [ ] In Snowflake (CoCo):
      ```
      SELECT query_tag, COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
      WHERE user_name = 'FORGE_APP_SVC' AND start_time > DATEADD(hour, -2, CURRENT_TIMESTAMP())
      GROUP BY 1 ORDER BY 2 DESC;
      ```
      shows `forge_app:*` tags. ACCOUNT_USAGE lags by up to about 45 minutes; for
      anything sooner, use `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER`.

If a screen falls back:
- the app log (app menu → *Manage app* → logs) has one `forge: live call … failed` line
  with the Snowflake error
- the usual causes are a missing grant, a wrong secret, or a suspended warehouse

## 5. Keep it awake (the user, once)
Community Cloud puts an app to sleep when nobody visits for a while. Judges would then see
a "wake up" button.
1. GitHub → repo **Settings → Secrets and variables → Actions → Variables** → New variable:
   `PUBLIC_APP_URL` = `https://supply-chain-forge.streamlit.app`.
2. The **keep awake** workflow (`.github/workflows/keep_awake.yml`) runs every 6 hours
   **from the default branch only**, so merge to `main`. To check it now, go to Actions →
   keep awake → *Run workflow*.
3. It clicks through every screen, which also warms the caches. It fails, and GitHub
   emails you, if any screen shows the fallback banner.

## 6. Cost guard (already in the app)
- Ask limits:
  - per visitor: a 10 s gap and 10 questions a session
  - across all visitors: 3 at once, 30 an hour, 200 a day
- Screen data is cached for 12 h, shared by all visitors.
- Answers are cached: 24 h for the suggested questions, 1 h for typed ones. A cache hit
  costs nothing.
- To change a limit without a commit, add it under `[forge]` in the secrets (the names are
  in the example file). To force practice data, set `mode = "mock"`.
- The app's counters reset when it restarts, so the warehouse monitor and the Cortex
  budget remain the hard cap.

## 7. Cutover to the event account (B08m / B15)
Only the secrets change: the new account identifier, and a new key pair if you want one.
CoCo re-runs step 2 in the new account. Paste the new secrets (step 3, "to change a
secret"), then repeat step 4.

## 8. Rotate or revoke the key
1. Generate a new pair (step 1).
2. CoCo sets `RSA_PUBLIC_KEY_2` to the new public key.
3. Paste the new private key into the secrets.
4. CoCo unsets `RSA_PUBLIC_KEY`.

**To revoke at once:** `ALTER USER FORGE_APP_SVC SET DISABLED = TRUE`. The app then shows
the fallback banner.

## 9. Judging-day checklist (3–4 Oct)
- [ ] Open the public URL in a private window: it's awake, the tag says Live, and there's
      no banner
- [ ] Ask one suggested question: an answer comes back
- [ ] The last keep-awake run is green (GitHub → Actions)
- [ ] Resource monitor and Cortex budget: headroom left for the judging days
- [ ] The URL in the submission form is the custom subdomain

---

## Streamlit in Snowflake (kept as the fallback)
`python deploy/deploy_app.py` (CoCo) uploads `app/` plus `deploy/sis/environment.yml` and
(re)creates `SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO`. Inside Snowflake the app detects the
active session and runs live by itself. `--dry-run` shows the files and SQL without
connecting.
