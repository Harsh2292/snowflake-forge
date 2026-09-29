# Reference — Snowflake Scripting and SQL stored procedures

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/blocks> |
| | <https://docs.snowflake.com/en/developer-guide/stored-procedure/stored-procedures-snowflake-scripting> |
| | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/variables> |
| | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/resultsets> |
| | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/cursors> |
| | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/loops> |
| | <https://docs.snowflake.com/en/developer-guide/snowflake-scripting/exceptions> |
| | <https://docs.snowflake.com/en/sql-reference/sql/execute-immediate> |
| | <https://docs.snowflake.com/en/sql-reference/identifier-literal> |
| **Fetched** | 2026-09-29 |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

---

## 1. Block structure

```sql
DECLARE
  -- variable, cursor, RESULTSET, exception declarations
BEGIN
  -- SQL statements and Snowflake Scripting constructs
EXCEPTION
  -- exception handlers
END;
```

`DECLARE` and `EXCEPTION` are optional. A minimal block is just `BEGIN ... END;`.
Blocks can nest. `BEGIN` for a block is distinct from `BEGIN TRANSACTION` — Snowflake
recommends `BEGIN TRANSACTION` for transactions to avoid confusion.

---

## 2. Anonymous blocks and EXECUTE IMMEDIATE

In Snowsight, an anonymous block runs directly:

```sql
DECLARE
  x INTEGER := 42;
BEGIN
  RETURN x;
END;
```

In SnowSQL, Snowflake CLI, or the Python connector, wrap it in `EXECUTE IMMEDIATE $$...$$`:

```sql
EXECUTE IMMEDIATE $$
DECLARE
  x INTEGER := 42;
BEGIN
  RETURN x;
END;
$$;
```

**CoCo runs files through the Python connector**, so all anonymous blocks must use
the `EXECUTE IMMEDIATE $$ ... $$;` form.

---

## 3. Variables

### Declaring

```sql
-- In DECLARE section:
DECLARE
  my_var INTEGER DEFAULT 0;
  name VARCHAR;

-- In BEGIN section with LET:
BEGIN
  LET my_var INTEGER := 0;
  LET name VARCHAR DEFAULT 'hello';
  ...
END;
```

### Assigning

```sql
my_var := 42;
my_var := (SELECT COUNT(*) FROM my_table);  -- scalar sub-query
```

### Using in SQL statements — the colon prefix

When a variable appears **inside a SQL statement** (SELECT, INSERT, UPDATE, etc.),
prefix it with `:` so Snowflake knows it is a variable, not a column name:

```sql
DECLARE
  threshold INTEGER := 100;
BEGIN
  -- :threshold is a bind variable referring to the scripting variable
  SELECT * FROM orders WHERE amount > :threshold;
END;
```

Without the colon, `threshold` would be interpreted as a column identifier and
would error with `"invalid identifier 'THRESHOLD'"`.

**This applies to procedure parameters too:**

```sql
CREATE PROCEDURE get_order(p_id INTEGER)
RETURNS TABLE(id INTEGER, amount NUMBER)
LANGUAGE SQL
AS $$
BEGIN
  -- :p_id binds the procedure parameter
  RETURN TABLE(SELECT id, amount FROM orders WHERE id = :p_id);
END;
$$;
```

The colon is NOT used in control-flow expressions (IF, WHILE conditions) or the
left side of assignments, because those are Scripting contexts, not SQL contexts.

---

## 4. IDENTIFIER(:var) for dynamic object names

Bind variables (`:var`) work for **values** in SQL statements, but not for **object
names** (tables, columns, schemas). For dynamic object names, use `IDENTIFIER()`:

```sql
DECLARE
  tbl VARCHAR := 'my_schema.my_table';
BEGIN
  SELECT COUNT(*) FROM IDENTIFIER(:tbl);
END;
```

`IDENTIFIER()` accepts string literals, session variables (`$var`), bind variables
(`?` or `:var`), and Snowflake Scripting variables (`:var`). It prevents SQL injection
when used with scripting variables.

You can also use `TABLE(:var)` as a synonym for `IDENTIFIER(:var)` in a FROM clause.

---

## 5. EXECUTE IMMEDIATE with a string (dynamic SQL)

For fully dynamic statements where the SQL text is built at runtime:

```sql
DECLARE
  sql_text VARCHAR;
  result INTEGER;
BEGIN
  sql_text := 'CREATE TABLE ' || :schema_name || '.t (id INT)';
  EXECUTE IMMEDIATE sql_text;

  -- With bind variables in the dynamic SQL (use ? placeholders):
  sql_text := 'SELECT COUNT(*) FROM orders WHERE status = ?';
  result := (EXECUTE IMMEDIATE :sql_text USING ('DELIVERED'));
  RETURN result;
END;
```

The `USING` clause binds **values** (not identifiers) to `?` placeholders in the
dynamic string. The string can contain only one statement (a block counts as one).

---

## 6. RESULTSET

A RESULTSET holds the result of a query. Assign with parentheses:

```sql
DECLARE
  rs RESULTSET;
BEGIN
  rs := (SELECT id, price FROM invoices WHERE price > 10);
  RETURN TABLE(rs);
END;
```

A RESULTSET can also be created from EXECUTE IMMEDIATE:

```sql
rs := (EXECUTE IMMEDIATE :query USING (min_price, max_price));
RETURN TABLE(rs);
```

`RETURN TABLE(rs)` returns the RESULTSET as a tabular result from the procedure.

---

## 7. Cursors

Cursors iterate through query results row by row.

```sql
DECLARE
  total FLOAT := 0.0;
  c1 CURSOR FOR SELECT price FROM invoices;
BEGIN
  FOR rec IN c1 DO
    total := total + rec.price;
  END FOR;
  RETURN total;
END;
```

- `FOR rec IN cursor DO ... END FOR;` auto-opens and auto-closes the cursor.
- Inside a FOR loop, do NOT manually FETCH — the FOR loop fetches automatically. A manual FETCH inside the loop skips every other row.
- Bind parameters in cursors use `?` placeholders and `OPEN c1 USING (var1, var2)`.

### Cursor → RESULTSET

```sql
DECLARE
  c1 CURSOR FOR SELECT * FROM invoices;
BEGIN
  OPEN c1;
  RETURN TABLE(RESULTSET_FROM_CURSOR(c1));
END;
```

`RESULTSET_FROM_CURSOR` always returns all rows, regardless of prior FETCH calls.

---

## 8. FOR loops (counter and RESULTSET)

```sql
-- Counter loop
FOR i IN 1 TO 10 DO
  INSERT INTO t VALUES (:i);
END FOR;

-- RESULTSET loop
FOR rec IN rs DO
  -- rec.column_name to access fields
END FOR;

-- Inline query loop
FOR rec IN (SELECT id FROM orders) DO
  ...
END FOR;
```

`REVERSE` keyword reverses counter direction: `FOR i IN REVERSE 10 TO 1 DO`.

### WHILE and LOOP

```sql
WHILE (counter < 10) DO
  counter := counter + 1;
END WHILE;

LOOP
  IF (done) THEN
    BREAK;
  END IF;
END LOOP;
```

`BREAK` exits the innermost loop; `CONTINUE` skips to next iteration. Both accept
a label: `BREAK outer_label;`.

---

## 9. IF / CASE

```sql
IF (x > 0) THEN
  RETURN 'positive';
ELSEIF (x = 0) THEN
  RETURN 'zero';
ELSE
  RETURN 'negative';
END IF;
```

```sql
CASE (status)
  WHEN 'DELIVERED' THEN ...
  WHEN 'PENDING'   THEN ...
  ELSE ...
END CASE;
```

Note: `ELSEIF` (one word), not `ELSE IF`.

---

## 10. RETURN

### Scalar

```sql
RETURN 42;
RETURN 'hello';
```

### VARIANT via OBJECT_CONSTRUCT

```sql
-- Procedure declared with RETURNS VARIANT
RETURN OBJECT_CONSTRUCT(
  'rows_inserted', row_count,
  'status', 'OK'
);
```

### Table

```sql
-- Procedure declared with RETURNS TABLE(id INT, name VARCHAR)
RETURN TABLE(rs);   -- rs is a RESULTSET
```

---

## 11. CREATE PROCEDURE ... LANGUAGE SQL

```sql
CREATE OR REPLACE PROCEDURE my_proc(p_name VARCHAR, p_limit INTEGER)
RETURNS TABLE(id INTEGER, name VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
  rs RESULTSET;
BEGIN
  rs := (SELECT id, name FROM items WHERE name = :p_name LIMIT :p_limit);
  RETURN TABLE(rs);
END;
$$;
```

### RETURNS TABLE(...) vs RETURNS VARIANT

| | RETURNS TABLE(col type, ...) | RETURNS VARIANT |
|-|-----|------|
| Result | Tabular — columns appear in the result set | Single VARIANT value |
| RETURN | `RETURN TABLE(resultset)` | `RETURN OBJECT_CONSTRUCT(...)` or scalar |
| Use case | Queries, reporting | Status objects, multi-value returns |

### EXECUTE AS OWNER vs EXECUTE AS CALLER

| | OWNER (default) | CALLER |
|-|------|--------|
| SQL runs as | The role that owns the procedure | The role of the calling session |
| Can USE DATABASE / USE SCHEMA | **No** — owner's rights procedures cannot change the session context | **Yes** |
| Can ALTER SESSION | **No** | **Yes** |
| Security | Tighter — caller can't escalate beyond what the proc exposes | More flexible — inherits caller's grants |
| Temp tables visible to caller | No (procedure-scoped) | Yes (session-scoped) |

Use `EXECUTE AS CALLER` when the procedure needs to operate on objects the caller
has access to, or needs to change session state. Use `EXECUTE AS OWNER` (the
default) for locked-down operations.

---

## 12. SQLROWCOUNT, LAST_QUERY_ID()

```sql
INSERT INTO t SELECT * FROM source;
LET rows_affected := SQLROWCOUNT;   -- number of rows from last DML
LET qid := LAST_QUERY_ID();         -- query ID of the last statement
```

`SQLROWCOUNT` is set after DML statements (INSERT, UPDATE, DELETE, MERGE, COPY). It is
not set after SELECT.

---

## 13. Exception handling

```sql
DECLARE
  my_exception EXCEPTION (-20001, 'Custom error message');
BEGIN
  IF (bad_condition) THEN
    RAISE my_exception;
  END IF;
EXCEPTION
  WHEN my_exception THEN
    RETURN 'Caught: ' || SQLERRM;
  WHEN OTHER THEN
    RETURN 'Unexpected: ' || SQLCODE || ' — ' || SQLERRM || ' [' || SQLSTATE || ']';
END;
```

### Built-in exception variables

| Variable | Content |
|----------|---------|
| `SQLCODE` | Snowflake error code (integer), or the user-defined code for custom exceptions |
| `SQLERRM` | Error message text |
| `SQLSTATE` | 5-character SQLSTATE code |

### RAISE

```sql
RAISE my_exception;           -- raise a declared exception
RAISE;                         -- re-raise the current exception (inside EXCEPTION block only)
```

An exception handler applies only to statements between `BEGIN` and `EXCEPTION` in
the same block. It does not cover the `DECLARE` section.

---

## 14. Delimiter rules

When creating procedures or running anonymous blocks through SnowSQL, Snowflake CLI,
or the Python connector, wrap the body in `$$`:

```sql
CREATE OR REPLACE PROCEDURE my_proc()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
  RETURN 'hello';
END;
$$;
```

The `$$` delimiter avoids conflicts with single quotes inside the body. The closing
`$$;` must have the semicolon outside the delimiter.

In Snowsight, `$$` is optional (Snowsight auto-detects the block boundary), but
using it is harmless and portable.

---

## Gotchas

1. **Colon prefix is mandatory for variables in SQL statements.** `WHERE id = p_id` fails; `WHERE id = :p_id` works. This is the #1 Snowflake Scripting mistake.
2. **IDENTIFIER(:var) for table/column names, not :var.** Bind variables work for values only. `SELECT * FROM :tbl` fails; `SELECT * FROM IDENTIFIER(:tbl)` works.
3. **EXECUTE IMMEDIATE takes one statement.** A block (`BEGIN...END`) counts as one. Multiple bare statements separated by `;` do not.
4. **ELSEIF is one word**, not `ELSE IF`. The latter causes a syntax error.
5. **Owner's rights procedures cannot USE DATABASE or ALTER SESSION.** If your procedure needs to switch context, use `EXECUTE AS CALLER`.
6. **FOR loop over a cursor auto-fetches.** Do not FETCH manually inside a FOR loop — you will skip every other row.
7. **SQLROWCOUNT is reset by each DML.** Read it immediately after the statement you care about.
8. **Temp tables in owner's rights procedures are procedure-scoped** and invisible to the caller. In caller's rights procedures, session-scope temp tables are visible to the caller.
9. **$$ delimiters are required outside Snowsight.** CoCo runs through the Python connector, so always use them.
10. **RESULTSET assignment needs parentheses:** `rs := (SELECT ...);` not `rs := SELECT ...;`.
