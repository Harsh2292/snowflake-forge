# Reference — Data Metric Functions (DMFs)

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/user-guide/data-quality-intro> |
| | <https://docs.snowflake.com/en/user-guide/data-quality-system-dmfs> |
| | <https://docs.snowflake.com/en/user-guide/data-quality-custom-dmfs> |
| | <https://docs.snowflake.com/en/user-guide/data-quality-working> |
| | <https://docs.snowflake.com/en/user-guide/data-quality-expectations> |
| | <https://docs.snowflake.com/en/sql-reference/sql/create-data-metric-function> |
| | <https://docs.snowflake.com/en/sql-reference/local/data_quality_monitoring_results> |
| | <https://docs.snowflake.com/en/sql-reference/functions/data_metric_function_references> |
| **Fetched** | 2026-09-29 (raw `.md` versions) |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

> Everything below is transcribed from the fetched pages unless marked **INFERRED**.

---

## 1. Edition requirement

Data Quality Monitoring requires **Enterprise Edition** (or higher).

---

## 2. System DMFs in `SNOWFLAKE.CORE`

Snowflake provides system DMFs in the `CORE` schema of the shared `SNOWFLAKE` database.
They are grouped by category:

### Accuracy

| DMF | Signature (ad-hoc call) | Description |
|-----|------------------------|-------------|
| `NULL_COUNT` | `(SELECT col FROM t)` | Count of NULL values in a column. |
| `NULL_PERCENT` | `(SELECT col FROM t)` | Percentage of NULL values. |
| `BLANK_COUNT` | `(SELECT col FROM t)` | Count of blank (empty string) values. |
| `BLANK_PERCENT` | `(SELECT col FROM t)` | Percentage of blank values. |
| `CASE_FORMAT_VIOLATION_COUNT` | `(SELECT col FROM t)` | Non-NULL values with inconsistent casing. |
| `CASE_FORMAT_VIOLATION_PERCENT` | `(SELECT col FROM t)` | Percentage with inconsistent casing. |
| `FUTURE_TIMESTAMP_COUNT` | `(SELECT col FROM t)` | Values in the future relative to evaluation time. |
| `FUTURE_TIMESTAMP_PERCENT` | `(SELECT col FROM t)` | Percentage of future timestamps. |
| `INVALID_JSON_COUNT` | `(SELECT col FROM t)` | Non-NULL values that are not valid JSON. |
| `INVALID_JSON_PERCENT` | `(SELECT col FROM t)` | Percentage not valid JSON. |
| `INVALID_NUMERIC_TYPE_CAST_COUNT` | `(SELECT col FROM t)` | Non-NULL string values that can't be parsed as numeric. |
| `INVALID_NUMERIC_TYPE_CAST_PERCENT` | `(SELECT col FROM t)` | Percentage not parseable as numeric. |
| `NEGATIVE_COUNT` | `(SELECT col FROM t)` | Negative values in a numeric column. |
| `NEGATIVE_PERCENT` | `(SELECT col FROM t)` | Percentage negative. |
| `SPECIAL_CHARACTER_COUNT` | `(SELECT col FROM t)` | Non-NULL values with non-alphanumeric characters. |
| `SPECIAL_CHARACTER_PERCENT` | `(SELECT col FROM t)` | Percentage with special characters. |
| `UNTRIMMED_STRING_COUNT` | `(SELECT col FROM t)` | Non-NULL values with leading/trailing whitespace. |
| `UNTRIMMED_STRING_PERCENT` | `(SELECT col FROM t)` | Percentage untrimmed. |
| `ZERO_COUNT` | `(SELECT col FROM t)` | Count of zero values. |
| `ZERO_PERCENT` | `(SELECT col FROM t)` | Percentage of zero values. |

### Freshness

| DMF | Description |
|-----|-------------|
| `FRESHNESS` | Seconds since last DML (no column) or since max timestamp (with column). See §3. |
| `DATA_METRIC_SCHEDULE_TIME` | Returns the scheduled evaluation time; used to define custom freshness metrics. Cannot be called ad-hoc. |

### Schema

| DMF | Description |
|-----|-------------|
| `SCHEMA_CHANGE_COUNT` | Count of column add/drop/rename/type-change since the previous evaluation. |

### Statistics

`APPROX_QUANTILE_25`, `APPROX_QUANTILE_50`, `APPROX_QUANTILE_99`, `AVG`, `EXTREME_OUTLIER_COUNT`,
`EXTREME_OUTLIER_IQR_COUNT`, `EXTREME_OUTLIER_IQR_PERCENT`, `EXTREME_OUTLIER_PERCENT`,
`EXTREME_OUTLIER_ZSCORE_COUNT`, `EXTREME_OUTLIER_ZSCORE_PERCENT`, `MAX`, `MEDIAN`, `MIN`,
`OUTLIER_COUNT`, `OUTLIER_IQR_COUNT`, `OUTLIER_IQR_PERCENT`, `OUTLIER_PERCENT`,
`OUTLIER_ZSCORE_COUNT`, `OUTLIER_ZSCORE_PERCENT`, `STDDEV`, `STRING_LENGTH_AVG`,
`STRING_LENGTH_MAX`, `STRING_LENGTH_MIN`, `VARIANCE`.

All take `(SELECT col FROM t)` ad-hoc. Numeric columns only (string-length DMFs: string columns).

### Uniqueness

| DMF | Description |
|-----|-------------|
| `ACCEPTED_VALUES` | Count of records NOT matching a lambda expression. Special syntax—see §4. |
| `DUPLICATE_COUNT` | Count of duplicate values (including NULLs). |
| `UNIQUE_COUNT` | Count of unique non-NULL values. |

### Volume

| DMF | Description |
|-----|-------------|
| `ROW_COUNT` | Total row count. Cannot be called ad-hoc; associate with `ON ()`. |

---

## 3. FRESHNESS details

```sql
-- Associate without a column (freshness = seconds since last DML):
ALTER TABLE t1 ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();

-- Associate with a timestamp column:
ALTER TABLE t1 ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (last_updated);

-- Ad-hoc (requires a column):
SELECT SNOWFLAKE.CORE.FRESHNESS(SELECT last_updated FROM t1);
```

When no column is specified, freshness is calculated from the last DML operation.
When a column is specified, it compares `CURRENT_TIMESTAMP` (or the scheduled time) to `MAX(col)`.
You **must** specify a column to use FRESHNESS on a view or external table.

---

## 4. ACCEPTED_VALUES details

Cannot be called ad-hoc via `SELECT`. Must be associated. Uses a lambda expression:

```sql
ALTER TABLE t1
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (order_status, order_status -> order_status IN ('Pending', 'Dispatched', 'Delivered'));
```

Returns the count of records where the value does **not** match the expression.
Cannot be associated with the same column more than once.
Renaming the column breaks the association.

---

## 5. CREATE DATA METRIC FUNCTION syntax

```sql
CREATE [ OR REPLACE ] [ SECURE ] DATA METRIC FUNCTION [ IF NOT EXISTS ] <name>
  ( <table_arg> TABLE( <col_arg> <data_type> [, ...] )
    [, <table_arg> TABLE( <col_arg> <data_type> [, ...] ) ] )
  RETURNS NUMBER [ [NOT] NULL ]
  [ LANGUAGE SQL ]
  [ COMMENT = '<string>' ]
  AS '<expression>' | $$ <expression> $$
```

- **Must return NUMBER.** No other return types.
- **Language SQL only.** No JavaScript, Python, etc.
- The expression must be deterministic and return a scalar.
- Cannot reference UDFs/UDTFs or use nondeterministic functions.

### Single-table example

```sql
CREATE OR REPLACE DATA METRIC FUNCTION governance.dmfs.count_positive(
  arg_t TABLE(arg_c1 NUMBER, arg_c2 NUMBER)
)
RETURNS NUMBER
AS $$ SELECT COUNT(*) FROM arg_t WHERE arg_c1 > 0 AND arg_c2 > 0 $$;
```

### Multi-table example (referential integrity)

```sql
CREATE OR REPLACE DATA METRIC FUNCTION governance.dmfs.referential_check(
  arg_t1 TABLE(arg_c1 INT),
  arg_t2 TABLE(arg_c2 INT)
)
RETURNS NUMBER
AS 'SELECT COUNT(*) FROM arg_t1 WHERE arg_c1 NOT IN (SELECT arg_c2 FROM arg_t2)';
```

### CREATE OR ALTER variant

Updates an existing DMF without drop-and-recreate. You cannot modify the arguments
(new arguments create a new overloaded function).

Privilege required: `CREATE DATA METRIC FUNCTION ON SCHEMA`.

---

## 6. Associating DMFs with objects

### ALTER TABLE / ALTER VIEW / WITH DATA METRIC FUNCTION

```sql
ALTER TABLE t ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1);
ALTER VIEW v ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- Multi-table DMF: first arg = the table itself, second arg = explicit table reference:
ALTER TABLE salesorders
  ADD DATA METRIC FUNCTION governance.dmfs.referential_check
    ON (sp_id, TABLE(my_db.sch1.salespeople(sp_id)));
```

### Attach at creation time

```sql
CREATE OR REPLACE TABLE orders (order_id NUMBER, customer_id NUMBER)
WITH DATA METRIC FUNCTION (
  SNOWFLAKE.CORE.NULL_COUNT ON (customer_id)
    EXPECTATION no_null_customers (VALUE = 0),
  SNOWFLAKE.CORE.DUPLICATE_COUNT ON (order_id)
    EXPECTATION no_dup_orders (VALUE = 0)
);
```

Also supported on views, materialized views, dynamic tables, external tables, and event tables.
For views/dynamic tables, the `WITH DATA METRIC FUNCTION` clause goes **before** `AS SELECT`.

### Supported object types

DMFs can be set on:
- Tables (regular, temporary, transient)
- Views
- Materialized views
- Dynamic tables
- External tables
- Event tables
- Iceberg tables

DMFs **cannot** be set on hybrid tables or streams.

### Drop a DMF from an object

```sql
ALTER TABLE t DROP DATA METRIC FUNCTION governance.dmfs.count_positive ON (c1, c2);
```

---

## 7. DATA_METRIC_SCHEDULE

All DMFs on a table share one schedule. Default: **1 hour**.

### Minutes form

```sql
ALTER TABLE t SET DATA_METRIC_SCHEDULE = '5 MINUTE';
```

### CRON form

```sql
ALTER TABLE t SET DATA_METRIC_SCHEDULE = 'USING CRON 0 8 * * * UTC';
-- Daily at 08:00 UTC

ALTER TABLE t SET DATA_METRIC_SCHEDULE = 'USING CRON 0 8 * * MON,TUE,WED,THU,FRI UTC';
-- Weekdays only
```

### Trigger on changes

```sql
ALTER TABLE t SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
```

Runs when a DML change occurs. Reclustering does **not** trigger a run.
Only available for certain table kinds (not views, not all external tables).

### Suspend / resume

```sql
-- Suspend one DMF:
ALTER TABLE t1 MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1) SUSPEND;
-- Resume it:
ALTER TABLE t1 MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1) RESUME;

-- Suspend ALL DMFs on a table:
ALTER TABLE t1 SET DATA_METRIC_SCHEDULE = '';
```

### Latency

There is a **10-minute lag** from modifying the schedule for changes to take effect on
existing associations. New DMF associations are not subject to this delay.

---

## 8. Expectations

An expectation defines pass/fail criteria for a DMF result. The keyword `VALUE` represents
the DMF's return value.

```sql
-- Add expectation when associating:
ALTER TABLE t ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1)
  EXPECTATION my_exp (VALUE < 10);

-- Multiple expectations:
ALTER TABLE emp ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (last_updated)
  EXPECTATION lt_5min (VALUE < 300), lt_30min (VALUE < 1800);

-- Add to existing association:
ALTER TABLE t MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1)
  ADD EXPECTATION my_exp (VALUE < 10);

-- Modify:
ALTER TABLE t MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1)
  MODIFY EXPECTATION my_exp (VALUE < 15);

-- Drop:
ALTER TABLE t MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (c1)
  DROP EXPECTATION my_exp;
```

Expressions support comparison and logical operators only. No table references, no UDFs.

### Test expectations ad-hoc

```sql
SELECT * FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
  REF_ENTITY_NAME => 'my_db.sch.t1'));
```

---

## 9. Reading results

### SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS

Key columns:

| Column | Type | Description |
|--------|------|-------------|
| `scheduled_time` | TIMESTAMP_LTZ | When the DMF was scheduled. |
| `change_commit_time` | TIMESTAMP_LTZ | When the trigger DML occurred (NULL if not trigger-based). |
| `measurement_time` | TIMESTAMP_LTZ | When the DMF actually ran. **Use this for evaluation.** |
| `table_database` | VARCHAR | Database of the monitored table. |
| `table_schema` | VARCHAR | Schema of the monitored table. |
| `table_name` | VARCHAR | Name of the monitored table. |
| `metric_database` | VARCHAR | Database of the DMF. |
| `metric_schema` | VARCHAR | Schema of the DMF. |
| `metric_name` | VARCHAR | Name of the DMF. |
| `argument_names` | ARRAY | Column names passed as arguments. |
| `value` | VARIANT | The DMF result. |

Requires the `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` or
`SNOWFLAKE.DATA_QUALITY_MONITORING_ADMIN` application role.

### Expectation results

- `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS_RAW` — raw event table with both
  `EVALUATION_RESULT` and `EXPECTATION_VIOLATION_STATUS` rows.
- `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS` — flattened view of
  expectation violations.

### DATA_METRIC_FUNCTION_REFERENCES (Information Schema table function)

```sql
-- All DMFs on a table:
SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME => 'my_db.sch.t1', REF_ENTITY_DOMAIN => 'TABLE'));

-- All objects using a specific DMF:
SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  METRIC_NAME => 'governance.dmfs.count_positive'));
```

Returns: `metric_name`, `argument_signature`, `ref_entity_name`, `ref_entity_domain`,
`schedule`, `schedule_status` (`STARTED` / `SUSPENDED` / …), `use_role`, `level`,
`anomaly_detection_status`, `data_quality_notification_status`, etc.

Use `REF_ENTITY_DOMAIN => 'TABLE'` for all supported table types (including views and DTs).

### Calling a DMF ad-hoc

```sql
SELECT SNOWFLAKE.CORE.NULL_COUNT(SELECT ssn FROM hr.tables.empl_info);

-- Custom multi-table DMF:
SELECT governance.dmfs.referential_check(
  (SELECT id FROM salesorders), (SELECT id FROM salespeople));
```

`ROW_COUNT` and `DATA_METRIC_SCHEDULE_TIME` cannot be called ad-hoc.

---

## 10. Privileges

| Privilege / Role | Purpose |
|-----------------|---------|
| `CREATE DATA METRIC FUNCTION ON SCHEMA` | Create custom DMFs. |
| `EXECUTE DATA METRIC FUNCTION ON ACCOUNT` | Required by the table-owner role for scheduled DMFs to run. |
| `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` | Read `DATA_QUALITY_MONITORING_RESULTS` and expectation views. |
| `SNOWFLAKE.DATA_QUALITY_MONITORING_ADMIN` | Full admin access (superset of VIEWER). |
| `DATA_METRIC_USER` (database role on SNOWFLAKE) | Grants access to system DMFs for the role. |

---

## 11. Cost

DMFs use **serverless compute** (no user warehouse). Billed under the
"Data Quality Monitoring" category. You are billed only when a scheduled DMF is computed
on an object — ad-hoc `SELECT` calls are **not** billed.

Track consumption via:
- `SNOWFLAKE.ACCOUNT_USAGE.DATA_QUALITY_MONITORING_USAGE_HISTORY`
- `SNOWFLAKE.ORGANIZATION_USAGE.METERING_DAILY_HISTORY` (service_type = `DATA_QUALITY_MONITORING`)

---

## 12. Limitations

- Max 50,000 total DMF-to-object associations per account.
- Cannot grant DMF privileges to a share or set a DMF on a shared table.
- Setting a DMF on an object tag is not supported.
- Reader accounts and trial accounts do not support DMFs.
- Cannot set a DMF on a hybrid table or a stream.

---

## Gotchas

1. **Dynamic tables and views are fully supported.** DMFs can be set on dynamic tables, views,
   materialized views, external tables, and event tables — not just regular tables.
2. `TRIGGER_ON_CHANGES` is only for certain table kinds; views and some external tables don't
   support it.
3. `ROW_COUNT` and `DATA_METRIC_SCHEDULE_TIME` cannot be called ad-hoc; they must be associated.
4. `ACCEPTED_VALUES` also cannot be called ad-hoc (use `SYSTEM$DATA_METRIC_SCAN` instead).
5. The schedule is per-table, not per-DMF. All DMFs on one table share the same schedule.
6. Use `measurement_time` (not `scheduled_time`) when evaluating results — DML can occur
   between the scheduled time and the actual evaluation.
7. There is a **10-minute lag** for schedule changes to take effect on existing associations.
8. The system DMF list is large (~50 functions). The categories above cover all of them as of
   2026-09-29. **INFERRED**: The list may grow; check the system DMFs page for updates.
