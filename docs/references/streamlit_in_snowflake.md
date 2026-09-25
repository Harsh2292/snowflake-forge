# Reference — Streamlit in Snowflake (SiS)

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/object-management/owners-rights> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/features/row-access> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/app-development/runtime-environments> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/app-development/file-organization> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/app-development/dependency-management> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/app-development/creating-your-app> |
| | <https://docs.snowflake.com/en/developer-guide/streamlit/limitations> |
| | <https://docs.snowflake.com/en/sql-reference/sql/create-streamlit> |
| | <https://docs.snowflake.com/en/developer-guide/stored-procedure/stored-procedures-rights> |
| | <https://docs.snowflake.com/en/user-guide/security-column-advanced> |
| | <https://docs.snowflake.com/en/sql-reference/functions/is_role_in_session> |
| **Fetched** | 2026-09-24 (raw `.md` versions) |
| **Used by** | C02 (`get_session`, persona calls), C03 (app), B15 (CoCo deploys) |

---

## 1. ✅ Verdict on contract §6a — CONFIRMED, no Change Request needed

§6a makes two claims. The docs support both.

### Claim A — `USE ROLE` inside SiS can't drive persona masking

> "In a Streamlit in Snowflake app, you can't use row access policies that use
> CURRENT_ROLE. Streamlit in Snowflake apps run with owner's rights, so using
> **CURRENT_ROLE inside a Streamlit app always returns the app owner role**."
> — *Row access policies in SiS*

> "Warehouse-runtime apps run as a stored procedure and are subject to the same
> restrictions as owner's rights stored procedures."
> — *Understanding owner's rights and SiS apps*

> "**Owner's rights stored procedures are not permitted to change session state.**"
> — *Caller's rights and owner's rights stored procedures*

So `USE ROLE` (a session-state change) isn't available to a warehouse-runtime app, and
even if it were, `CURRENT_ROLE()` would still report the owner. ✅

### Claim B — an owner's-rights procedure owned by `PLANNER_ROLE` evaluates masking as `PLANNER_ROLE`

Three independent statements:

> "An owner's rights stored procedure **always behaves as an owner's rights stored
> procedure, no matter where it was called from**."
> — *Nested stored procedures with different rights*

> IS_ROLE_IN_SESSION "looks only at the *currently* active set of roles … The currently
> active roles can differ from the session roles, for example, **when executing an owner's
> rights procedure or a Streamlit**."
> — *IS_ROLE_IN_SESSION*

> Execution-context table: "Stored procedure with owner's right → **Stored procedure
> owner role**."
> — *Advanced column-level security, INVOKER_ROLE*

So the call chain is:

```
SiS app (owner's rights, as app owner)
  └─ CALL GOVERNED.SP_SAMPLE_AS_PLANNER()   ← owner's rights, owned by PLANNER_ROLE
       └─ SELECT … FROM GOVERNED.V_PART      ← active role = PLANNER_ROLE → masking applies
```

✅ The mechanism in §5.4 / §6a is sound.

### ⚠ Condition CoCo must meet at B06 (masking policies)

The confirmation holds **only if** the masking policy bodies test the role with
**`CURRENT_ROLE()`** or **`IS_ROLE_IN_SESSION()`**.

**Do not use `INVOKER_ROLE()`.** Per the same execution-context table, when the masked
column is reached **through a view**, `INVOKER_ROLE()` evaluates to the **view owner's
role**, not the procedure owner. All three personas would then get identical output.
This is exactly the silent failure §6a exists to prevent.

Also watch the role hierarchy. `IS_ROLE_IN_SESSION('BUYER_ROLE')` is true for any role
that *inherits* `BUYER_ROLE`. If `FORGE_ADMIN` is granted all three persona roles (so it
can own the app and call procs), that's fine. But persona roles must **not** inherit each
other, or the Planner proc would see Buyer-visible columns.

`sql/04_governance/policies.sql` is still a placeholder, so nothing is wrong yet. This is
passed to CoCo via `.agents/HANDOFF.md`. Artifact `04_persona_outputs.json` (B07b) is the
empirical proof.

### Other owner's-rights requirements

- "If you use any context functions, you must grant the global **READ SESSION** privilege
  to the app owner role." → `GRANT READ SESSION ON ACCOUNT TO ROLE <app owner>` (already
  in GAPS_RESOLVED GAP-1).
- The app owner needs **`USAGE` on each persona procedure**. The procedure owner (persona
  role) needs `SELECT` on the governed views it reads.
- Owner's-rights procs "inherit the current warehouse of the caller". The persona procs
  run on the app's warehouse. **INFERRED**: persona roles may also need `USAGE` on
  `FORGE_WH`. Verify at B07b.

---

## 2. Owner's-rights model — full rules

By default, SiS apps:
- Run with the **privileges of the owner**, not the viewer.
- Run with the **warehouse provisioned by the app owner**.
- Use the **database and schema the app was created in**, not the caller's.
- Viewers can use **all privileges of the owner's role** through the app.

Warehouse-runtime restrictions (inherited from owner's-rights procs):
- Only `SELECT`, DML, DDL, `GRANT/REVOKE`, variable assignment, `DESCRIBE`, `SHOW`
  (limited), `LIST` (limited) can run. **Not `USE ROLE` / `USE SECONDARY ROLES`.**
- Not allowed: `SHOW PARAMETERS IN SESSION`, `SHOW VARIABLES`, `SHOW GRANTS` without an
  `IN/ON/TO/OF` clause, `SHOW LOCKS`, `SHOW TRANSACTIONS`.
- Can't read or set the caller's session variables.
- **INFERRED**: `SHOW SEMANTIC DIMENSIONS … FOR METRIC` is a `SHOW` that doesn't depend on
  the current user, so it should be allowed. Not needed at runtime anyway.

Container runtime is **not** subject to the stored-procedure restrictions and supports
Restricted Caller's Rights (Preview). GAPS_RESOLVED GAP-1 chose **warehouse runtime**
deliberately; this reference doesn't change that.

---

## 3. Warehouse runtime vs container runtime

| | **Warehouse** (our choice) | Container |
|---|---|---|
| Compute | Virtual warehouse for code + queries | Compute pool for code, warehouse for queries |
| Instance | **Personal instance per viewer** | Shared instance across viewers |
| Python | 3.9, 3.10, 3.11 | 3.11 |
| Streamlit | 1.22+ (limited selection) | 1.50+ (any) |
| Dependencies | **`environment.yml`**, Snowflake Conda channel only | `requirements.txt` / `pyproject.toml` from PyPI |
| Pin syntax | `pkg=1.2.3`, ranges `pkg=2.*` | `pkg==1.2.3`, `>=` |
| Entrypoint | **Must be in the root** of the source dir | Root or subdir |
| Caching | **Single-session only** (not shared between viewers) | Shared |
| Message size | **32 MB** per Streamlit message | Configurable (200 MB default) |
| Rights | Owner's rights, proc restrictions apply | Owner's rights + optional RCR |
| Startup | Slower per viewer | Faster per viewer |

---

## 4. Getting a session

```python
from snowflake.snowpark.context import get_active_session
session = get_active_session()
```

`get_active_session()` → `Session`. **Raises `SnowparkSessionException`** if there is no
active session or more than one. Locally there is none, so `get_session()` in C02 must:

```python
def get_session():
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()          # inside SiS
    except Exception:
        from snowflake.snowpark import Session
        return Session.builder.config("connection_name", "<name>").create()  # local, live mode only
```

In mock mode `get_session()` is never called. See `snowpark_session.md`.

---

## 5. Streamlit features that differ in SiS

| Feature | SiS behaviour |
|---------|---------------|
| `st.set_page_config` | **`page_title`, `page_icon`, `menu_items` not supported.** `layout="wide"` is fine. Guard it or accept that it's ignored. |
| External JS/CSS | Blocked by the CSP. `st.html(..., unsafe_allow_javascript=True)` silently does nothing. Images/fonts over HTTPS are OK. |
| Custom components | v1 (`components.v1.html/iframe`) OK. v2 **not** on warehouse runtime. |
| `st.query_params` | Keys get a `streamlit-` prefix in the URL (transparent in code). |
| Multipage | `st.navigation` or `pages/`. SiS URLs get a `/!` prefix. We use **tabs in one page**, so N/A. |
| `st.cache_data` | Works, but only within a single viewer session on warehouse runtime. |
| Plotly | Available in the Snowflake Conda channel (docs example pins `plotly=5.0.*`). ✅ |
| External stages, `.so` files, replication | Not supported. |

---

## 6. File layout for our app (warehouse runtime)

```
app/                        ← this directory becomes the stage source root
├── streamlit_app.py        ← entrypoint MUST be at root
├── environment.yml         ← SiS dependencies (Conda). requirements.txt is for local only.
└── utils/
    ├── __init__.py
    ├── config.py
    └── forge_data.py
```

"The root of your app's source directory is Streamlit's working directory." Locally, run
`streamlit run streamlit_app.py` **from inside `app/`** so `from utils import …` resolves
the same way it will in SiS.

`environment.yml` (docs format):

```yaml
name: forge-demo
channels:
  - snowflake
dependencies:
  - python=3.11
  - streamlit=1.52.2          # newest version SiS warehouse runtime supports (list: 1.42.0 … 1.52.2)
  - pandas=2.*
  - plotly=5.*
  - snowflake-snowpark-python
```

Rules: Snowflake channel only, `=` to pin, `*` for ranges, **no `pip:` section**.

---

## 7. Deployment (CoCo does this at B15; recorded so C03 builds a deployable shape)

```sql
CREATE STAGE IF NOT EXISTS SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE;
PUT file:///…/app/streamlit_app.py  @SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE/app AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file:///…/app/environment.yml   @SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE/app AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file:///…/app/utils/*.py        @SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE/app/utils AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO
  FROM '@SUPPLY_CHAIN_FORGE.APP.FORGE_STAGE/app'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = FORGE_WH
  TITLE = 'Supply Chain Forge';
  -- warehouse runtime: omit RUNTIME_NAME / COMPUTE_POOL
  -- (explicit form: RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME')

ALTER STREAMLIT SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO ADD LIVE VERSION FROM LAST;
```

- `FROM` copies files **once** at create time. Later stage changes don't propagate
  automatically.
- `ALTER STREAMLIT … ADD LIVE VERSION FROM LAST` is **required** before users with only
  `USAGE` can view it.
- `QUERY_WAREHOUSE` is required for the app to run.
- `ROOT_LOCATION` is legacy. Don't use it.
- The `snow` CLI path (`snowflake.yml`, CLI ≥ 3.14) also exists, but the CLI isn't
  installed here.
