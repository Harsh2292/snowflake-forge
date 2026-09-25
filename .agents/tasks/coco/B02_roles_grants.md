# B02 — Roles and Grants

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M1 |
| **Prerequisite** | B01 gate passed |
| **Est. effort** | One session |
| **Writes** | `sql/01_setup/02_roles_grants.sql` |

---

## Goal

Create four roles and grant them correctly, including the grants Cortex Agents and
Streamlit in Snowflake specifically require.

---

## Roles

| Role | Purpose |
|------|---------|
| `FORGE_ADMIN` | Owns all objects. Sees everything unmasked. |
| `PLANNER_ROLE` | Production planner persona |
| `BUYER_ROLE` | Procurement lead persona |
| `LOGISTICS_ROLE` | Logistics coordinator persona |

Names are fixed by `docs/CONTRACT.md` §2. Do not rename.

---

## Three gotchas that will silently break things later

### 1. Cortex Agents use the caller's DEFAULT role, not the session role

From Snowflake docs: *"Cortex Agents determines permissions from the querying user's
default role, not the role active in their session. The user must also have a default
warehouse."*

So grant agent privileges to your **default role**, not just to `FORGE_ADMIN`.

```sql
DESC USER <your_user>;   -- note DEFAULT_ROLE and DEFAULT_WAREHOUSE
```

Then grant `SNOWFLAKE.CORTEX_AGENT_USER` and warehouse `USAGE` to that default role.
Skipping this makes B10 fail with a confusing permissions error.

### 2. Streamlit needs `READ SESSION` if any context function is used

```sql
GRANT READ SESSION ON ACCOUNT TO ROLE FORGE_ADMIN;
```

Required because the persona procedures (B07b) and masking policies rely on
`CURRENT_ROLE()`.

### 3. Persona roles must be grantable to the app owner

The app owner needs `USAGE` on the three persona procedures created in B07b. Ownership of
those procedures transfers to the persona roles, so plan the role hierarchy now:

```
FORGE_ADMIN
  ├── PLANNER_ROLE
  ├── BUYER_ROLE
  └── LOGISTICS_ROLE
```

---

## Steps

1. Create the four roles
2. Build the hierarchy above; grant `FORGE_ADMIN` to `SYSADMIN`
3. Grant on database and all seven schemas:
   - `FORGE_ADMIN` → `USAGE` + `CREATE` on everything
   - Persona roles → `USAGE` on database, `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`,
     `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`
4. Grant `USAGE ON WAREHOUSE FORGE_WH` to all four roles
5. Grant `CREATE SEMANTIC VIEW`, `CREATE AGENT`, `CREATE MCP SERVER` on `SEMANTIC`
   to `FORGE_ADMIN`
6. Grant `CREATE STREAMLIT` on `APP` to `FORGE_ADMIN`
7. Grant `SNOWFLAKE.CORTEX_AGENT_USER` to `FORGE_ADMIN` **and to your default role**
8. Grant `READ SESSION ON ACCOUNT` to `FORGE_ADMIN`
9. Grant all three persona roles to `FORGE_ADMIN`
10. Grant `FORGE_ADMIN` to your user

---

## Gate

```sql
SHOW ROLES LIKE '%ROLE';                    -- 3 persona roles present
SHOW ROLES LIKE 'FORGE_ADMIN';              -- present

SHOW GRANTS TO ROLE PLANNER_ROLE;           -- usage on db, schemas, warehouse
SHOW GRANTS TO ROLE BUYER_ROLE;
SHOW GRANTS TO ROLE LOGISTICS_ROLE;
SHOW GRANTS TO ROLE FORGE_ADMIN;            -- + CORTEX_AGENT_USER, READ SESSION

DESC USER <your_user>;                      -- DEFAULT_ROLE has CORTEX_AGENT_USER
```

Then confirm each role can actually assume context:

```sql
USE ROLE PLANNER_ROLE;   USE WAREHOUSE FORGE_WH;   SELECT CURRENT_ROLE();
USE ROLE BUYER_ROLE;     USE WAREHOUSE FORGE_WH;   SELECT CURRENT_ROLE();
USE ROLE LOGISTICS_ROLE; USE WAREHOUSE FORGE_WH;   SELECT CURRENT_ROLE();
USE ROLE FORGE_ADMIN;
```

---

## On completion

1. Tick B02 as ✅ in `.agents/NEXT.md`, set B03 as NEXT
2. Update `.agents/HANDOFF.md` — mark persona roles DONE
3. Record your default role name in `docs/SESSION_LOG.md`; B10 will need it
