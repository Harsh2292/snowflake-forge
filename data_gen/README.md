# data_gen — realistic, deterministic source data (C08)

Three procedures in `SUPPLY_CHAIN_FORGE.OPS` fill the 10 source tables (`ERP_SOURCE`,
`WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`) with 10 years of supply chain data ending the day
before `END_DATE`. They then damage it the way real systems do, and check both. Spec:
`docs/DATA_SPEC.md`. Card: `.agents/tasks/claude/C08_data_generator.md`. Written by Claude
Code; **run by CoCo** (Claude Code has no Snowflake access).

| File | What it creates | Run as |
|---|---|---|
| `00_setup.sql` | schema `OPS` (if missing); log tables `GEN_LOG`, `GEN_STATS`, `GEN_MESS_LOG` | ACCOUNTADMIN |
| `10_sp_generate_data.sql` | `OPS.SP_GENERATE_DATA(TARGET_DB, SCALE_FACTOR, SEED, END_DATE)`: the clean load | ACCOUNTADMIN |
| `20_sp_inject_mess.sql` | `OPS.SP_INJECT_MESS(TARGET_DB, SEED, END_DATE)`: the §4 defects, exact counts | ACCOUNTADMIN |
| `30_sp_gen_self_checks.sql` | `OPS.SP_GEN_SELF_CHECKS(TARGET_DB)`: a table of checks | ACCOUNTADMIN |
| `40_sp_append_day.sql` | `OPS.SP_APPEND_DAY(TARGET_DB, SCALE_FACTOR, SEED, NEW_END_DATE)`: adds every business day up to `NEW_END_DATE` (the nightly feed, DATA_SPEC §7.1a): new orders, shipments leaving and arriving, status versions, the day's stock and FX, with the §4 mess on new rows. Idempotent; one transaction per day | ACCOUNTADMIN |
| `99_run.sql` | the calls: a dry run at SF 0.01 (twice), then SF 1; Step 3: the day-append on a clone, its checks, then production | ACCOUNTADMIN |

**Order on an empty account**:
1. CoCo's `sql/01_setup` (database, roles, warehouse)
2. the v2 source DDL (B08c)
3. `00` → `10` → `20` → `30` → `99`

Every file is re-runnable (`CREATE OR REPLACE` / `IF NOT EXISTS`, and the generator
truncates what it writes), and none names an account.

**Design rules** (DATA_SPEC §6):
- **Randomness is hash-based only**: `BITAND(HASH(SEED, '<TABLE>', <key>, '<attr>'),
  4294967295) / 4294967295.0`. No `RANDOM()`, and no clock in the data.
- **Sums that feed the data are exact `NUMBER` sums**, because floating-point sums can
  change with parallelism.
- **Gap-free, business-ordered IDs**: `ORD000000001` is the oldest order.
- **Chunked by history year**, so no statement grows past one year of data at any scale
  factor (B13 runs SF 50+ on a clone).
- **Defects are picked by exact count** (`ROUND(rate × base)`, the lowest hashes). So the
  §4 rates hold even at SF 0.01, and every run picks the same rows.

**Where the spec left room**: see the card's "Decisions" section (e.g. an order-level home
plant, so an order ships ~1.1 times; lower-case IDs for M07 on `VTTK.VBELN`).

**Offline checks**: `tests/unit/test_data_gen_sql.py` checks every file: no `RANDOM()`, no
account names, headers present, every §4 code injected at its rate, balanced `$$`.
