# B15a — Public live link trial on Streamlit Community Cloud (Day 2, old account; ADR-009)

> **Owner**: CoCo · **Milestone**: M6 · **Contract**: v1.6
> **Spec**: `.agents/tasks/COCO_TASKS.md` § B15a · `deploy/RUNBOOK.md` (Claude Code, C15)
> **Status**: 🔄 **Snowflake side done 2026-09-30**. Waiting on the user (key pair,
> Community Cloud app) and Claude Code (C6c: the CR-007 Ask call).

## Done (2026-09-30)

### 1. `sql/05_app_access/01_app_service_user.sql` (ran clean, 31 statements)
- `FORGE_APP_ROLE` (read-only, granted to SYSADMIN):
  - `USAGE`: `FORGE_WH`, the database, and the schemas `SEMANTIC`, `GOVERNED`, `TMS_SOURCE`,
    `ERP_SOURCE`
  - `SELECT`: the semantic view, the 9 governed views, and `VTTK` / `VBAK` (§8)
  - `USAGE` on procedures and the agent: the 6 persona procedures, `SP_DATA_HEALTH`, the agent
  - roles: `SNOWFLAKE.CORTEX_USER`, `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER`
- `FORGE_APP_SVC`: `TYPE = SERVICE`, default role `FORGE_APP_ROLE`, default warehouse
  `FORGE_WH`, secondary roles off. **No public key yet.**

### 2. `sql/05_app_access/02_cost_controls.sql` (ran clean; limits chosen by the user)
- **`FORGE_WH_MONITOR`**: 5 credits a day on `FORGE_WH`. Notify at 75%, suspend at 100%,
  suspend immediately at 110%.
- **`OPS.FORGE_APP_CORTEX_BUDGET`**: 25 credits a month of Cortex Agent use by
  `FORGE_APP_SVC` only (user tag `OPS.COST_SCOPE = 'public_app'`, shared resource
  `CORTEX AGENT`).
  - At 100% (actual), a custom action calls `OPS.SP_STOP_PUBLIC_ASK`. It's owned by
    FORGE_ADMIN and revokes the role's `USAGE` on the agent, so Ask stops and the other
    screens keep working.
  - **Tested:** the grant was revoked, then restored by re-running the grant.
- Measured for sizing:
  - the agent costs ~0.04 credits per question, so 25 credits ≈ 600 questions
  - `FORGE_WH` peaks at 1.3 credits a day on build days
- Resource monitors cover warehouses only, so AI costs need the budget (Snowflake docs).

### 3. Verified as `FORGE_APP_ROLE` with `USE SECONDARY ROLES NONE`

| Check | Result |
|---|---|
| `SEMANTIC_VIEW` with **only** the semantic-view grant | ✅ OTD 0.875272. **The views underneath need no grants**, `primary_sourcing` included (fill rate by `suppliers.supplier_region` ran) |
| DOI query (its window subquery reads `GOVERNED.V_INVENTORY`) | ❌ without SELECT on `V_INVENTORY` (*"does not exist or not authorized"*); ✅ 36.436790 with it |
| `DATA_QUALITY_MONITORING_RESULTS` | ✅ 77 associations, 535 rows, the same as FORGE_ADMIN |
| Masking (the default branch, an unlisted role) | ✅ e-mail `*** MASKED ***`, credit limit NULL |
| Row counts, metric values | ✅ identical to FORGE_ADMIN (693,241 shipments, 2,000,369 lines; OTD 0.875272) |
| `SP_METRICS_AS_BUYER` | ✅ the 4 metrics, the same as the other personas |
| `SP_SAMPLE_AS_*` divergence | ✅ Planner and Logistics see the customer e-mail but not unit cost or terms; Buyer sees unit cost 22.20, NET90, contract price 20.17, and the customer masked |
| §8 naive OTD (`VTTK` ⋈ `VBAK`) | ✅ 0.681790 |
| Account network policy | ✅ none set (Community Cloud egress IPs aren't fixed) |

## Waiting on

1. **The user:** RUNBOOK step 1. Send the **public** key body (`rsa_key.pub`, never the private
   key). CoCo then runs `ALTER USER FORGE_APP_SVC SET RSA_PUBLIC_KEY = '…'` and checks
   `RSA_PUBLIC_KEY_FP`. Then RUNBOOK step 3: create the Community Cloud app and paste the secrets.
2. **Claude Code: C6c** (the CR-007 `ask_agent` change). **The "Ask answers" gate item is not
   run until Claude Code says C6c is done** (their request, 30 Sep).

## Gate (RUNBOOK step 4)

| # | Check | Result |
|---|---|---|
| 1 | Every screen loads from the public URL in a private window | |
| 2 | The numbers equal art 05 / 09 | |
| 3 | Ask returns an agent answer (**after C6c**) | |
| 4 | The data-health date shows | |
| 5 | No fallback to mock data on any screen | |
| 6 | `QUERY_HISTORY` shows the app's queries under `FORGE_APP_SVC` with the `forge_app:*` tags | |
