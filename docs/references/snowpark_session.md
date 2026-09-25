# Reference — Snowpark Python `Session` essentials

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.Session.sql> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.Session.call> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.DataFrame.collect> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.DataFrame.to_pandas> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.context.get_active_session> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.exceptions.SnowparkSQLException> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/python/creating-session> |
| **Fetched** | 2026-09-24. API reference pages are for **snowpark-python v1.54.0**. |
| **Used by** | `forge_data.py` live branches (C02), `tests/conftest.py` (C04) |

---

## 1. Getting a session

| Context | Code |
|---------|------|
| Inside SiS / a stored proc | `from snowflake.snowpark.context import get_active_session`<br>`session = get_active_session()` |
| Local, named connection | `Session.builder.config("connection_name", "myconnection").create()` (reads `connections.toml`) |
| Local, explicit dict | `Session.builder.configs({...}).create()` |

`get_active_session()` **raises `SnowparkSessionException`** when there are zero or more
than one active sessions. Catch it to detect "not running in Snowflake".

> Local reality for this project: `connections.toml` uses `OAUTH_AUTHORIZATION_CODE`
> (browser-based). A local live session would pop a browser. Claude Code never needs one;
> mock mode and the artifacts cover development.

---

## 2. `Session.sql(query, params=None) -> DataFrame`

- **Lazy.** Nothing runs until `.collect()` / `.to_pandas()`.
- `params`: **qmark (`?`) binding only**, as a sequence.

```python
session.sql("select * from values (?, ?), (?, ?)", params=[1, "a", 2, "b"]).collect()
# [Row(COLUMN1=1, COLUMN2='a'), Row(COLUMN1=2, COLUMN2='b')]
```

Use `params` for **values** (the agent question text). **Identifiers** (metric and
dimension names in `SEMANTIC_VIEW`) can't be bound. Build them only from the contract
allow-list.

---

## 3. Materialising results

### `DataFrame.collect() -> List[Row]`
- `block=True` (default) waits; `block=False` returns an `AsyncJob`.
- `case_sensitive=True` (default) for Row field names.
- `Row` → dict: `row.as_dict()`. Field access `row["ON_TIME_DELIVERY_RATE"]`.

### `DataFrame.to_pandas() -> pandas.DataFrame`
- Requires pandas installed.
- ⚠ **"If you use `Session.sql()` with this method, the input query of `Session.sql()`
  can only be a SELECT statement."**
  → `session.sql("CALL …").to_pandas()` is **not** valid.
  For the persona procedures use `.collect()` and build the frame yourself (§4).
- `TIMESTAMP_LTZ` / `_TZ` → `datetime64[ns, tz]`; `TIMESTAMP_NTZ` → `datetime64[ns]`.
- Numeric columns from `NUMBER(p,s)` may arrive as `Decimal` / object dtype. Cast with
  `pd.to_numeric` before charting or comparing to 6 dp.

---

## 4. Calling stored procedures

### Option A — `Session.call()`

```python
session.call(sproc_name: str, *args, statement_params=None, block=True,
             log_on_exception=False, return_dataframe: Optional[bool] = None)
```

- `return_dataframe=True` → returns a Snowpark `DataFrame` (use for `RETURNS TABLE` procs).
- Otherwise returns the scalar result.

```python
df = session.call("SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER",
                  return_dataframe=True).to_pandas()
```

### Option B — plain `CALL` + `collect()` (always works)

```python
rows = session.sql("CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()").collect()
df = pd.DataFrame([r.as_dict() for r in rows])
```

**Decision for C02**: use **Option B**. It avoids any ambiguity about `to_pandas()` on a
non-SELECT and matches contract §5.4 literally. If B07b artifacts show Option A is cleaner,
switch then.

---

## 5. Errors

`snowflake.snowpark.exceptions.SnowparkSQLException(message, *, error_code, conn_error,
sfqid, query, sql_error_code, raw_message, debug_context)`

- Base class `SnowparkClientException`.
- Raised for SQL errors from executed statements.
- Useful attributes: `sql_error_code` (int, e.g. **10234** for the semantic-view
  granularity error `010234`), `sfqid` (query id), `message` / `raw_message`.

Pattern for every live branch (task card C02: "degrade to mock with a visible warning,
never a stack trace on stage"):

```python
from snowflake.snowpark.exceptions import SnowparkSQLException

try:
    rows = session.sql(sql, params=params).collect()
except SnowparkSQLException as e:
    st.warning(f"Live query failed ({e.sql_error_code}); showing cached values.")
    return mock_result
except Exception as e:                # connection or session problems
    st.warning("Snowflake unavailable; showing cached values.")
    return mock_result
```

Keep the `st.warning` out of `forge_data.py` itself. Return a flag or raise a typed
error, and let the UI decide how to show it. That keeps the data layer testable without
Streamlit.

---

## 6. Agent call through Snowpark (ties to `data_agent_run.md`)

```python
import json
sql = """
SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
  OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
    OBJECT_CONSTRUCT('role','user','content',
      ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type','text','text', ?)))))::VARCHAR,
  TRUE)) AS RESPONSE
"""
row = session.sql(sql, params=[question]).collect()[0]
resp = row["RESPONSE"]
resp = json.loads(resp) if isinstance(resp, str) else resp   # VARIANT comes back as a JSON string
if resp is None:                                              # TRY_PARSE_JSON failed
    ...
```

**INFERRED**: Snowpark returns `VARIANT` columns as JSON **strings** in `Row`, so
`json.loads` is needed. The `isinstance` guard covers both cases. Confirm at C6c.
