# B15 — Production hardening + final checks on the submitted link

| | |
|---|---|
| **Owner** | CoCo |
| **Status** | ✅ 1 Oct (Snowflake side). Left: the 2 Oct morning check of the first nightly run, and a live check of CR-008 streaming when Claude Code ships it |
| **Public link** | <https://supply-chain-forge.streamlit.app/> (Streamlit Community Cloud, live on `QURFOQP-XU04029`) |

## Final checks (1 Oct)

| Check | Result |
|---|---|
| Public link is live (B15a) | the user confirmed the header says **Live** with no fallback banner. In Snowflake, `FORGE_APP_SVC` ran queries from every screen (`forge_app:*` tags, 0 failures) and an Ask question reached the agent: SUCCESS, 33 s, correct numbers |
| Contract audit | 148/148 as the app user (`11_contract_audit.md` §1) |
| Security review | `11_contract_audit.md` §2; no open high-severity finding |
| Adversarial eval | 10/10 safe (`runs/B14_adv_run.md`) |
| Freshness | nightly append live (`OPS.FORGE_NIGHTLY_APPEND`, 05:30 UTC); data health OK (`runs/C17b_run.md`) |
| Monitoring | hourly e-mail alert `OPS.FORGE_OPS_WATCH`; ops views `OPS.V_AGENT_REQUESTS`, `OPS.V_APP_ERRORS` |

## Cost (1 Oct, ~12:00 UTC)

| Item | Value |
|---|---|
| Event account balance | **$391.13** of $400 (`REMAINING_BALANCE_DAILY`, 1 Oct; lags a few hours) |
| Spend 30 Sep (the B08m replay day) | warehouse $3.41 · Cortex agents $3.16 · DQ monitoring $0.40 · cloud services $0.28 |
| Spend 1 Oct so far | warehouse $0.63 · Cortex agents $0.55 · serverless tasks/alerts $0.04 · cloud services $0.06 |
| `FORGE_WH_MONITOR` today | 1.17 of 5 credits (notify 75%, suspend 100%) |
| Guardrails | 9 scans, 0 flagged |
| Expected steady state | nightly append ~0.03 credits; hourly alert seconds of serverless; Ask ≈ agent tokens per question (capped: 200 calls/day, the 25-credit/month Cortex budget) |

CoCo's own session tokens bill to the connected account. This session ran on the old account's
connection (now unused), so its cost isn't in the figures above.

## Left

- **2 Oct, after 05:30 UTC:** `TASK_HISTORY` for `FORGE_NIGHTLY_APPEND` = SUCCEEDED, and
  `SP_DATA_HEALTH('ALL')` = OK with the as-of date 2026-10-01.
- **After Claude Code's CR-008:** on the public link, check the time to first text, and that the
  final answer equals the `DATA_AGENT_RUN` answer for the 8 canonical questions.
- **Optional:** B13 scale proof (art 12) on a clone of the new account. Credits only; not needed
  for the submission.
