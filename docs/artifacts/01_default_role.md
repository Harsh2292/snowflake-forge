# Artifact 01 — Default Role & Warehouse Settings

- **Build Step**: `B02`
- **Captured At**: `2026-09-24 09:25:00 UTC`
- **Captured By**: CoCo
- **Purpose**: Record user default role and warehouse configuration for Cortex Agent execution. (Cortex Agents determine permissions from the querying user's default role and default warehouse, not dynamic session role).

---

## 1. User Principal Configuration

```sql
DESC USER LAZYBOY;
```

| Property | Value |
|---|---|
| `NAME` | `LAZYBOY` |
| `DEFAULT_ROLE` | `ACCOUNTADMIN` |
| `DEFAULT_WAREHOUSE` | `COMPUTE_WH` |
| `DEFAULT_SECONDARY_ROLES` | `["ALL"]` |

---

## 2. Agent Permission Verification

Because Cortex Agent execution operates under the caller's default role (`ACCOUNTADMIN`), the following database role grants have been verified and applied:

```sql
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE FORGE_WH TO ROLE ACCOUNTADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE FORGE_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE PLANNER_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE BUYER_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE LOGISTICS_ROLE;
```

---

## 3. Verified Persona Roles & Hierarchy

- `FORGE_ADMIN` (Admin / Owner, unmasked)
  - Inherits: `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
- `PLANNER_ROLE` (Production Planner persona)
- `BUYER_ROLE` (Procurement Lead persona)
- `LOGISTICS_ROLE` (Logistics Coordinator persona)

*Note: Persona roles do not inherit one another to ensure clean masking policy and scope boundaries.*
