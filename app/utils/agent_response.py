"""Parse a SNOWFLAKE.CORTEX.DATA_AGENT_RUN response into what the Ask tab renders.

Built against the real responses CoCo captured at B10 (C6c): docs/artifacts/07_agent_response.json
(one full response) and 08_agent_answers.md (all 30 evaluation answers). What they show:
- content items: thinking, tool_use, tool_result, text, table, text, suggested_queries
- the agent repeats its SQL at the end of the text as a ```sql block
- a `table` item repeats the tool_result's result set (same query_id)
- `system_*` tools are Snowflake's internal plumbing (system_execute_sql runs a verified
  query or Analyst's SQL); the agent's own tools are supply_chain_analyst, data_to_chart,
  data_health
"""

import json
import re

from . import config

# Rows kept per result table. A 10-year daily breakdown is ~3,650 rows; the app shows at
# most a dozen, and everything kept travels to the browser (SiS caps a message at 32 MB).
MAX_TABLE_ROWS = 500

# Tool name or type -> what the answer card says. Internal system_* tools are left out,
# except that system_execute_sql running a verified query is worth saying.
TOOL_LABELS = {
    "supply_chain_analyst": "Cortex Analyst",
    "cortex_analyst_text_to_sql": "Cortex Analyst",
    "data_to_chart": "Chart",
    "data_health": "Data health check",
}
_FENCED = re.compile(r"```[a-zA-Z]*\n?(.*?)```", re.S)


def parse_agent_response(resp) -> dict:
    """Extract answer text, SQL, tables, tools, suggestions and lineage from a raw agent
    response. Accepts the parsed dict or its JSON string. Never raises on odd shapes:
    unknown content types are skipped, as the docs require."""
    if isinstance(resp, str):
        try:
            resp = json.loads(resp)
        except ValueError:
            resp = None
    if not isinstance(resp, dict):
        return _empty(resp, status="unparseable")

    texts, sqls, tools, suggestions = [], [], [], []
    tables = {}  # query_id (or a position) -> (records, row count, title): one entry per result
    verified, data_health = None, None

    for item in resp.get("content") or []:
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind == "text":
            if item.get("text"):
                texts.append(item["text"])
        elif kind == "tool_use":
            tool_use = item.get("tool_use") or {}
            tools.append(tool_use.get("name") or tool_use.get("type"))
            _add_sql(sqls, (tool_use.get("input") or {}).get("sql"))
        elif kind == "tool_result":
            result = item.get("tool_result") or {}
            for part in result.get("content") or []:
                payload = part.get("json") if isinstance(part, dict) else None
                if not isinstance(payload, dict):
                    continue
                if "data_health" in (result.get("name"), result.get("type")):
                    data_health = payload
                    continue
                _add_sql(sqls, payload.get("sql"))
                if "verified_query_used" in payload:
                    verified = bool(payload["verified_query_used"])
                if payload.get("result_set"):
                    key = payload.get("query_id") or f"result-{len(tables)}"
                    tables.setdefault(key, _table(payload["result_set"]))
        elif kind == "table":
            table = item.get("table") or {}
            if table.get("result_set"):  # the same result as its tool_result: keep one, with its title
                key = table.get("query_id") or f"result-{len(tables)}"
                tables[key] = _table(table["result_set"], table.get("title"))
        elif kind == "suggested_queries":
            suggestions += [q.get("query") for q in item.get("suggested_queries") or []
                            if isinstance(q, dict) and q.get("query")]

    raw_text = "\n\n".join(texts)
    for block in _FENCED.findall(raw_text):  # the SQL the agent repeats in its text
        if block.strip().upper().startswith(("SELECT", "WITH")):
            _add_sql(sqls, block.strip())
    sql = sqls[0] if sqls else None
    return {
        "answer": clean_answer(raw_text),
        "sql": sql,
        "metric_used": metrics_in_sql(sql),
        "verified_query_used": verified,
        "tools_used": tool_labels(tools, verified),
        "tools_raw": list(dict.fromkeys(t for t in tools if t)),
        "tables": [t[0] for t in tables.values()],
        "row_counts": [t[1] for t in tables.values()],
        "table_titles": [t[2] for t in tables.values()],
        "suggestions": list(dict.fromkeys(suggestions)),
        "data_health": data_health,
        "warnings": resp.get("warnings") or [],
        "status": resp.get("status", "completed"),
        "raw": resp,
    }


def clean_answer(text: str) -> str:
    """The answer as prose: fenced code blocks removed (the SQL has its own tab), blank
    and whitespace-only lines collapsed, line breaks inside a paragraph kept."""
    text = _FENCED.sub("", text or "")
    paragraphs = ["\n".join(line.rstrip() for line in block.splitlines() if line.strip())
                  for block in re.split(r"\n\s*\n", text)]
    return "\n\n".join(p.strip() for p in paragraphs if p.strip())


def tool_labels(tools, verified) -> list[str]:
    """What the agent used, in words, in order, without Snowflake's internal tools."""
    labels = []
    for tool in tools:
        if not tool:
            continue
        if tool == "system_execute_sql" and verified:
            labels.append("Verified query")
        elif tool in TOOL_LABELS:
            labels.append(TOOL_LABELS[tool])
        elif not tool.startswith(("system_", "server_")) and tool != "generic":
            labels.append(tool)
    return list(dict.fromkeys(labels))


def _table(result_set: dict, title=None) -> tuple:
    """(the first MAX_TABLE_ROWS rows, the table's true row count, its title)."""
    rows = len(result_set.get("data") or [])
    total = (result_set.get("resultSetMetaData") or {}).get("numRows")
    count = total if isinstance(total, int) and total >= rows else rows
    return result_set_to_records(result_set, limit=MAX_TABLE_ROWS), count, title


def result_set_to_records(result_set: dict, limit=None) -> list[dict]:
    """Turn a SQL-API ResultSet into a list of row dicts (the first `limit` rows).

    Values arrive as strings, and `rowType` may be absent (the docs' own example omits
    it). In that case columns are named COL_1, COL_2, ...
    """
    data = (result_set.get("data") or [])[:limit]
    row_type = (result_set.get("resultSetMetaData") or {}).get("rowType") or []
    width = max((len(row) for row in data), default=len(row_type))
    names = [col.get("name") for col in row_type] if row_type else []
    names += [f"COL_{i + 1}" for i in range(len(names), width)]
    types = [(col.get("type") or "").upper() for col in row_type]
    return [
        {names[i]: _cast(value, types[i] if i < len(types) else "") for i, value in enumerate(row)}
        for row in data
    ]


def metrics_in_sql(sql) -> list[str]:
    """Contract metric keys referenced in the SQL, in contract order."""
    if not sql:
        return []
    return [key for key in config.METRICS if re.search(rf"\b{key}\b", sql, re.IGNORECASE)]


def _add_sql(sqls: list, sql) -> None:
    """Keep each distinct statement once (whitespace doesn't make a new one)."""
    if not sql:
        return
    squashed = " ".join(sql.split())
    if all(" ".join(s.split()) != squashed for s in sqls):
        sqls.append(sql)


def _cast(value, sf_type: str):
    if value is None or not isinstance(value, str):
        return value
    if sf_type in ("FIXED", "NUMBER", "REAL", "FLOAT", "DOUBLE", "DECIMAL") or not sf_type:
        try:
            number = float(value)
        except ValueError:
            return value
        return int(number) if number.is_integer() and "." not in value else number
    return value


def paused_result() -> dict:
    """What ask_agent returns when the agent can't be used right now (the Ask screen says
    it's paused, and nothing is cached)."""
    return _empty(None, status="paused")


def _empty(raw, status: str) -> dict:
    return {"answer": "", "sql": None, "metric_used": [], "verified_query_used": None, "tools_used": [],
            "tools_raw": [], "tables": [], "row_counts": [], "table_titles": [], "suggestions": [],
            "data_health": None, "warnings": [], "status": status, "raw": raw}
