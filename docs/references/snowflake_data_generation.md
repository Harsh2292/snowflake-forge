# Reference — Synthetic data generation in pure Snowflake SQL

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/sql-reference/functions/generator> |
| | <https://docs.snowflake.com/en/sql-reference/functions-data-generation> |
| | <https://docs.snowflake.com/en/sql-reference/functions/seq1> |
| | <https://docs.snowflake.com/en/sql-reference/functions/random> |
| | <https://docs.snowflake.com/en/sql-reference/functions/uniform> |
| | <https://docs.snowflake.com/en/sql-reference/functions/normal> |
| | <https://docs.snowflake.com/en/sql-reference/functions/zipf> |
| | <https://docs.snowflake.com/en/sql-reference/functions/randstr> |
| | <https://docs.snowflake.com/en/sql-reference/functions/hash> |
| | <https://docs.snowflake.com/en/sql-reference/identifier-literal> |
| | <https://docs.snowflake.com/en/sql-reference/constraints-overview> |
| | <https://docs.snowflake.com/en/user-guide/table-considerations> |
| **Fetched** | 2026-09-29 |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

---

## 1. GENERATOR table function

Produces synthetic rows. Goes in a `FROM TABLE(...)` clause.

```sql
SELECT ...
FROM TABLE(GENERATOR(ROWCOUNT => 1000)) v;
```

### Parameters

| Param | Type | Behaviour |
|-------|------|-----------|
| `ROWCOUNT` | non-negative integer **constant** | Produce exactly this many rows. |
| `TIMELIMIT` | non-negative integer constant (seconds) | Keep producing rows for this many seconds. Non-deterministic row count. |
| Both | | ROWCOUNT wins if reached first; TIMELIMIT wins if it expires first. |
| Neither | | 0 rows. |

**ROWCOUNT must be a constant.** A function call like `DATEDIFF(...)` is not a
constant and will error with `"not a constant"`. To use a computed value, assign
it to a scripting variable first and pass the variable:

```sql
EXECUTE IMMEDIATE $$
DECLARE
  n INTEGER := 5000;
BEGIN
  CREATE OR REPLACE TABLE t AS
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS id
  FROM TABLE(GENERATOR(ROWCOUNT => :n));
END;
$$;
```

If `ROWCOUNT` or `TIMELIMIT` is `NULL`, it is ignored. `GENERATOR(ROWCOUNT => NULL)` → 0 rows.

The content of the rows comes from the **projection clause**, not from GENERATOR itself. GENERATOR produces virtual rows with zero columns.

---

## 2. Sequences: SEQ1 / SEQ2 / SEQ4 / SEQ8

Return monotonically increasing integers starting from 0. The suffix is the byte width (1 = TINYINT, 8 = BIGINT). They wrap around after the max representable value.

```sql
SELECT SEQ8() FROM TABLE(GENERATOR(ROWCOUNT => 5));
-- 0, 1, 2, 3, 4
```

**SEQ functions are NOT guaranteed gap-free.** When rows are produced in parallel, gaps can appear. For a gap-free sequence, use:

```sql
ROW_NUMBER() OVER (ORDER BY SEQ8()) AS id
```

This is the canonical pattern from the docs.

Optional sign argument: `SEQ4(0)` wraps to 0; `SEQ4(1)` wraps to the smallest signed value (e.g. -128 for SEQ1).

---

## 3. Random functions

### 3a. RANDOM([seed])

Returns a pseudo-random **signed 64-bit integer** (Mersenne twister MT19937-64).

```sql
SELECT RANDOM()     FROM TABLE(GENERATOR(ROWCOUNT => 3));  -- different each row
SELECT RANDOM(42)   FROM TABLE(GENERATOR(ROWCOUNT => 3));  -- different each row, but same seed
```

Key rules:
- Same seed, same row → same value. `SELECT RANDOM(42), RANDOM(42)` returns the same value twice *per row*.
- Same seed, different rows → different values.
- **Not reproducible across executions.** Even with a seed, re-running the same statement can return different values because worker count or row processing order may differ.

### 3b. UNIFORM(min, max, gen)

Uniformly distributed value in **[min, max] inclusive**.

```sql
SELECT UNIFORM(1, 10, RANDOM()) FROM TABLE(GENERATOR(ROWCOUNT => 5));
```

- Both `min` and `max` are constants.
- If both are integers → returns integer. If either is float → returns float.
- `gen` must be variable (typically `RANDOM()`). If `gen` is a constant, the output is a constant for every row:

```sql
SELECT UNIFORM(1, 10, 42) FROM TABLE(GENERATOR(ROWCOUNT => 3));
-- 10, 10, 10  (same constant for all rows)
```

### 3c. NORMAL(mean, stddev, gen)

Normal (Gaussian) distribution centred on `mean` with standard deviation `stddev`.

```sql
SELECT NORMAL(100, 15, RANDOM()) FROM TABLE(GENERATOR(ROWCOUNT => 1000));
```

Same constant-gen caveat as UNIFORM.

### 3d. ZIPF(s, N, gen)

Zipf-distributed integer in [1, N] with exponent `s`. Memory cost is O(N), so N is capped at **16 777 215**.

```sql
SELECT ZIPF(1.2, 100, RANDOM()) FROM TABLE(GENERATOR(ROWCOUNT => 1000));
```

Good for "popular items get most picks" distributions (e.g. top suppliers).

### 3e. RANDSTR(length, gen)

Random alphanumeric string (0-9, a-z, A-Z) of exactly `length` characters.

```sql
SELECT RANDSTR(8, RANDOM()) FROM TABLE(GENERATOR(ROWCOUNT => 5));
```

`length` can be an expression. `gen` is the seed.

---

## 4. HASH — deterministic "random" from a key

`HASH(expr [, expr ...])` returns a **signed 64-bit integer** (NUMBER(19,0)). It is:

- **Deterministic**: same inputs always produce the same output, across sessions and executions.
- **Never NULL**, even for NULL inputs.
- NOT cryptographic. Not unique beyond ~2^32 rows.

```sql
SELECT HASH('supplier', 42, 'unit_cost') AS h;
-- Always the same number for these inputs.
```

### Deterministic uniform recipe

Because `RANDOM(seed)` is not reproducible across runs but `HASH` is, use HASH to build reproducible random data:

```sql
-- u is a deterministic uniform float in [0, 1]
BITAND(HASH(seed_string, row_id, 'attribute_name'), 4294967295)
  / 4294967295.0  AS u
```

`4294967295 = 2^32 - 1`. `BITAND` masks the lower 32 bits to get a non-negative integer, then divides to [0, 1].

This is **INFERRED** from HASH's documented properties (deterministic, 64-bit signed). The docs do not provide this recipe, but it follows directly.

### Deterministic integer in a range

```sql
-- Deterministic integer in [lo, hi] inclusive
lo + FLOOR(u * (hi - lo + 1))::INTEGER
```

Where `u` is the uniform from above. Clamp with `LEAST(..., hi)` if paranoid about floating-point edge at 1.0.

### Weighted categorical pick

Given weights that sum to 1.0:

```sql
CASE
  WHEN u < 0.60 THEN 'DELIVERED'  -- 60%
  WHEN u < 0.85 THEN 'IN_TRANSIT' -- 25%
  WHEN u < 0.95 THEN 'PENDING'    -- 10%
  ELSE                'CANCELLED'  --  5%
END
```

### Normal-ish distribution from uniforms

The Central Limit Theorem: the mean of several independent uniforms approximates a normal.

```sql
-- Approximate N(mean, stddev) from 6 independent uniforms
(  BITAND(HASH(seed, id, 'n1'), 4294967295) / 4294967295.0
 + BITAND(HASH(seed, id, 'n2'), 4294967295) / 4294967295.0
 + BITAND(HASH(seed, id, 'n3'), 4294967295) / 4294967295.0
 + BITAND(HASH(seed, id, 'n4'), 4294967295) / 4294967295.0
 + BITAND(HASH(seed, id, 'n5'), 4294967295) / 4294967295.0
 + BITAND(HASH(seed, id, 'n6'), 4294967295) / 4294967295.0
 - 3.0                           -- shift mean to 0
) / SQRT(6.0 / 12.0)            -- scale to stddev=1
* target_stddev + target_mean
```

This is **INFERRED**. Sum of 6 Uniform(0,1) has mean 3 and variance 6×(1/12)=0.5, so stddev = sqrt(0.5). Subtracting 3 and dividing by sqrt(0.5) gives Z ~ N(0,1) approximately.

### Deterministic dates

```sql
DATEADD('day',
  -FLOOR(u * 365)::INTEGER,   -- 0 to 364 days ago
  '2026-09-01'::DATE
) AS order_date
```

---

## 5. Date/time helpers for seasonality

| Function | Example | Notes |
|----------|---------|-------|
| `DATEADD(part, n, date)` | `DATEADD('day', -7, CURRENT_DATE())` | Add/subtract intervals. |
| `DATEDIFF(part, d1, d2)` | `DATEDIFF('day', order_date, ship_date)` | Signed difference. |
| `DATE_TRUNC(part, date)` | `DATE_TRUNC('month', order_date)` | Truncate to start of period. |
| `DAYOFWEEKISO(date)` | `DAYOFWEEKISO(d)` | 1=Monday … 7=Sunday (ISO). |
| `EXTRACT(part FROM date)` | `EXTRACT(MONTH FROM order_date)` | Integer part. |

Use `DAYOFWEEKISO` or `EXTRACT(DOW ...)` for weekend adjustments. Use `EXTRACT(MONTH ...)` for seasonal weighting.

---

## 6. Loading data

### TRUNCATE TABLE

```sql
TRUNCATE TABLE IF EXISTS schema.table_name;
```

Removes all rows instantly. Keeps the table structure. Resets micro-partitions.

### INSERT INTO ... SELECT

```sql
INSERT INTO target_table (col1, col2)
SELECT expr1, expr2
FROM TABLE(GENERATOR(ROWCOUNT => 10000)) v;
```

### INSERT OVERWRITE

```sql
INSERT OVERWRITE INTO target_table
SELECT ... FROM ...;
```

Atomically replaces all rows. Equivalent to TRUNCATE + INSERT in one transaction. Useful for idempotent re-runs.

### Multi-table INSERT ALL

```sql
INSERT ALL
  INTO table_a (c1, c2) VALUES (x, y)
  INTO table_b (c1, c2) VALUES (x, z)
SELECT x, y, z FROM source;
```

Each `INTO` receives every row from the SELECT. Use `INSERT FIRST` for conditional routing.

### CTAS (CREATE TABLE ... AS SELECT)

```sql
CREATE OR REPLACE TABLE schema.my_table AS
SELECT ...
FROM TABLE(GENERATOR(ROWCOUNT => 50000)) v;
```

Creates and populates in one step. Column names and types come from the SELECT. Cannot add constraints inline — use ALTER TABLE afterwards if needed.

**CTAS vs INSERT:** CTAS replaces the table definition each time; INSERT INTO preserves it (and any constraints/comments). For data-gen scripts that run once, either works. For scripts that may re-run, `INSERT OVERWRITE` is safer because it preserves the schema.

---

## 7. Constraint enforcement on standard tables

| Constraint | Enforced? |
|------------|-----------|
| `NOT NULL` | **Yes** — insert/update of NULL into a NOT NULL column raises an error. |
| `CHECK` | **Yes** — expression is evaluated; FALSE fails the DML. |
| `PRIMARY KEY` | **No** — informational only on standard tables. Duplicates and NULLs are silently accepted. |
| `UNIQUE` | **No** — informational only. Duplicates are silently accepted. |
| `FOREIGN KEY` | **No** — informational only. Orphan values are silently accepted. |

Constraints provide metadata for BI tools, join elimination, and semantic views. They do not prevent bad data on standard tables (hybrid tables enforce all constraints).

**Implication for data generation:** Your generator must produce correct data — Snowflake will not reject FK violations or duplicate PKs.

---

## 8. Complete example: deterministic supplier table

```sql
CREATE OR REPLACE TABLE srm_source.suppliers AS
WITH base AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ8()) AS rn,
    BITAND(HASH('sup', rn, 'u1'), 4294967295) / 4294967295.0 AS u1,
    BITAND(HASH('sup', rn, 'u2'), 4294967295) / 4294967295.0 AS u2
  FROM TABLE(GENERATOR(ROWCOUNT => 200))
)
SELECT
  'SUP-' || LPAD(rn::VARCHAR, 4, '0')          AS supplier_id,
  RANDSTR(10, HASH('sup', rn, 'name'))          AS supplier_name,
  CASE WHEN u1 < 0.33 THEN 'APAC'
       WHEN u1 < 0.66 THEN 'EMEA'
       ELSE 'AMER' END                          AS region,
  ROUND(50 + u2 * 50, 1)                        AS reliability_score
FROM base;
```

The output is identical on every run (same table contents), because HASH and ROW_NUMBER are deterministic.

---

## Gotchas

1. **RANDOM(seed) is NOT reproducible across executions.** Worker count or row order can change values even with the same seed. Use HASH for reproducibility.
2. **SEQ functions can have gaps.** Always wrap with `ROW_NUMBER() OVER (ORDER BY SEQ8())` for gap-free IDs.
3. **GENERATOR(ROWCOUNT => expr) fails if `expr` is not a constant.** Wrap in a scripting block and bind the variable.
4. **UNIFORM/NORMAL/ZIPF with a constant `gen` argument produce the same value for every row.** Always pass `RANDOM()` as `gen` for variable output. If you need determinism, use the HASH recipe instead.
5. **HASH returns signed 64-bit.** Use `BITAND(..., 4294967295)` to extract a non-negative 32-bit slice for the uniform recipe. Without BITAND, negative HASH values break the division.
6. **PK/UNIQUE/FK are not enforced on standard tables.** Your data generator is responsible for uniqueness and referential integrity.
7. **ZIPF N is capped at 16 777 215** and memory cost is O(N). For larger domains, use the HASH+CASE weighted approach.
8. **INSERT ALL sends every source row to every INTO clause.** Use INSERT FIRST for mutually exclusive routing.
