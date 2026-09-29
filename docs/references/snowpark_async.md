# Reference — Snowpark Python async queries

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/snowpark/api/snowflake.snowpark.AsyncJob> |
| | <https://docs.snowflake.com/en/developer-guide/snowpark/python/working-with-dataframes> (§ "Performing Actions Asynchronously" and § "Submit Snowpark queries concurrently") |
| | <https://docs.snowflake.com/en/developer-guide/stored-procedure/python/procedure-python-examples> (§ "Using Snowpark APIs for asynchronous processing") |
| **Fetched** | 2026-09-29 |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

---

## 1. Core API

Every DataFrame action method that ends in `_nowait` returns an `AsyncJob` instead
of blocking. Equivalently, pass `block=False` to the synchronous method.

```python
# These two are identical:
async_job = df.collect_nowait()
async_job = df.collect(block=False)
```

### Available async action methods

| Sync method | Async equivalent |
|-------------|-----------------|
| `df.collect()` | `df.collect_nowait()` or `df.collect(block=False)` |
| `df.to_pandas()` | `df.to_pandas(block=False)` |
| `df.first()` | `df.first(block=False)` |
| `df.count()` | `df.count(block=False)` |
| `df.write.save_as_table(...)` | `df.write.save_as_table(..., block=False)` |
| `df.write.copy_into_location(...)` | `df.write.copy_into_location(..., block=False)` |
| `session.sql(...)` | `session.sql(...).collect_nowait()` |
| `table.merge(...)` | `table.merge(..., block=False)` |
| `table.update(...)` | `table.update(..., block=False)` |
| `table.delete(...)` | `table.delete(..., block=False)` |

---

## 2. AsyncJob class

```python
from snowflake.snowpark import AsyncJob
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `query_id` | `str` | The Snowflake query ID of the running query. |
| `query` | `str | None` | The SQL text of the executed query. |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `is_done()` | `bool` | `True` if the query has finished (success or failure). Non-blocking. |
| `is_failed()` | `bool` | `True` if the query finished with an error. |
| `status()` | `str` | Current query status as a string (e.g. `'RUNNING'`, `'SUCCESS'`, `'FAILED_WITH_ERROR'`). |
| `result(result_type=...)` | varies | Blocks until done, then returns results. Default returns `list[Row]`. Pass `result_type="pandas"` for a pandas DataFrame. |
| `cancel()` | `None` | Cancels the running query. |
| `to_df()` | `DataFrame` | Returns a DataFrame built on the query result. The query must have finished. |

### Example: fire and check

```python
async_job = session.sql("SELECT SYSTEM$WAIT(5)").collect_nowait()
print(async_job.query_id)        # e.g. '01b12345-...'
print(async_job.is_done())       # False (immediately)

# Block until result:
rows = async_job.result()        # list[Row]
```

---

## 3. Creating an AsyncJob from a query ID

If you have a query ID from another source (e.g. stored in a table or returned by
another process), you can wrap it:

```python
async_job = session.create_async_job(query_id)
print(async_job.query)    # the SQL text
rows = async_job.result() # blocks until done
df = async_job.to_df()    # convert to DataFrame for further transforms
```

---

## 4. Running N independent queries concurrently

### 4a. Using async jobs (simple, no threading)

Fire all queries, then collect results in order:

```python
jobs = [
    session.sql(q).collect_nowait()
    for q in [query_a, query_b, query_c, query_d]
]

# All are running concurrently on Snowflake.
# Collect results in the original order:
results = [job.result() for job in jobs]
# results[0] → rows from query_a, etc.
```

Each `collect_nowait()` submits the query and returns immediately. The Snowflake
server executes them concurrently (up to warehouse concurrency limits). `result()`
blocks only on the specific job.

### 4b. Using thread-safe sessions (Snowpark ≥ 1.24, server ≥ 8.46)

For workloads that also do client-side processing (transforms, writes), use Python
threading with a single shared session:

```python
import threading
from concurrent.futures import ThreadPoolExecutor

def process_table(table_name: str):
    df = session.table(table_name)
    df_agg = df.group_by("region").agg({"amount": "sum"})
    df_agg.write.save_as_table(f"{table_name}_summary", mode="overwrite")

tables = ["orders_q1", "orders_q2", "orders_q3", "orders_q4"]

with ThreadPoolExecutor(max_workers=4) as pool:
    pool.map(process_table, tables)
```

Thread-safe sessions release the GIL before submitting queries, so true concurrency
is achieved for I/O-bound work.

**Limitations of thread-safe sessions:**
- Multiple threads on one session do NOT support concurrent transactions.
- Do not change session config (database, schema, warehouse) while other threads are active.

### When to use which

| Approach | Best for | Client-side parallelism? |
|----------|----------|--------------------------|
| `collect_nowait()` + `result()` | Fire-and-forget, simple fan-out of SQL | No — one thread, non-blocking submit |
| ThreadPoolExecutor + shared session | Multi-step pipelines with transforms | Yes — multiple threads |

---

## 5. Behaviour in stored procedures

Async child jobs work inside Python stored procedures:

```python
CREATE OR REPLACE PROCEDURE my_proc()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = 3.12
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'handler'
EXECUTE AS CALLER
AS $$
def handler(session):
    job = session.sql("SELECT SYSTEM$WAIT(5)").collect_nowait()
    # do other work...
    return str(job.result())
$$;
```

**Critical rule:** If the parent procedure returns before the child job finishes,
the child job is **cancelled**. You must call `job.result()` (which blocks) or
otherwise ensure the parent waits.

---

## 6. Streamlit in Snowflake (SiS) — warehouse runtime

In SiS (warehouse runtime, which is what our app uses):

- `session` is provided by the framework (`snowflake.snowpark.context.get_active_session()`).
- `collect_nowait()` and `block=False` work normally.
- Thread-safe sessions work (Snowpark ≥ 1.24).
- The warehouse's concurrency limit applies — the multi-cluster auto-scaling
  behaviour of the warehouse determines how many queries run truly in parallel.

### Pattern for the app: parallel metric fetch

```python
from snowflake.snowpark.context import get_active_session

session = get_active_session()

# Fire four metric queries concurrently
queries = {
    "otd": "SELECT * FROM SEMANTIC_VIEW(...METRICS shipments.on_time_delivery_rate)",
    "fill": "SELECT * FROM SEMANTIC_VIEW(...METRICS order_lines.fill_rate)",
    "doi": "SELECT * FROM SEMANTIC_VIEW(...METRICS inventory.days_of_inventory)",
    "alc": "SELECT * FROM SEMANTIC_VIEW(...METRICS shipments.avg_landed_cost)",
}

jobs = {k: session.sql(q).collect_nowait() for k, q in queries.items()}

# Collect in deterministic order
results = {k: job.result() for k, job in jobs.items()}
```

All four hit Snowflake concurrently, and `result()` blocks only on each individual
query. Wall time ≈ max(query times) instead of sum(query times).

### Caveats for SiS

- **No background threads that outlive a Streamlit re-run.** Each re-run is a fresh
  execution. Use `st.cache_data` or `st.session_state` to avoid re-fetching.
- **No SPCS / container runtime features.** SiS warehouse runtime is serverless;
  you get Snowpark but not raw networking or long-lived processes.

---

## 7. Error handling

```python
job = session.sql("SELECT 1/0").collect_nowait()

import time
while not job.is_done():
    time.sleep(0.5)

if job.is_failed():
    print(f"Query {job.query_id} failed: {job.status()}")
else:
    rows = job.result()
```

Calling `result()` on a failed job raises a `SnowparkSQLException`. Wrap in
try/except if needed:

```python
try:
    rows = job.result()
except Exception as e:
    print(f"Error: {e}")
```

---

## 8. Multi-statement DataFrames

If a DataFrame is backed by multiple queries (e.g. `session.create_dataframe()`
with large local data), the data upload happens **synchronously** even with
`collect_nowait()` — only the final fetch is async. For other multi-query
DataFrames, Snowpark wraps them in an anonymous block and submits as one async query.

Temporary objects created during async evaluation are dropped only when you call
`result()`, not before.

---

## Gotchas

1. **`result()` is required to keep child jobs alive in stored procedures.** If the parent returns first, the child is cancelled and no data is written.
2. **`to_df()` on an unfinished job raises an error** (`"Result for query ... has expired"`). Always check `is_done()` or call `result()` first.
3. **`RANDOM(seed)` is not reproducible** — relevant when using async, because worker parallelism may differ between runs. Use HASH for deterministic data.
4. **Thread-safe sessions require Snowpark ≥ 1.24 and server ≥ 8.46.** Older versions raise errors or silently corrupt state.
5. **Do not change session context (USE DATABASE, etc.) while async jobs from the same session are running.** This applies to both async jobs and threaded sessions.
6. **Temp objects from async queries are cleaned up only when `result()` is called.** If you fire many async jobs and never call `result()`, temp tables accumulate.
7. **`collect_nowait()` on DDL (CREATE TABLE, etc.) works** but is rarely useful — DDL is fast and you usually need to know it succeeded before proceeding.
