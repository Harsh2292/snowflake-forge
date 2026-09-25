"""Parse a SNOWFLAKE.CORTEX.DATA_AGENT_RUN response into what the Ask tab renders.

Shape reference: docs/references/data_agent_run.md. The field names inside an Analyst
tool_result (`sql`, `verified_query_used`, ...) are INFERRED from the streaming delta
schema. Confirm them against docs/artifacts/07_agent_response.json at C6c.
"""

import json
import re

from . import config


def parse_agent_response(resp) -> dict:
    """Extract answer text, SQL, tables and lineage from a raw agent response.

    Accepts the parsed dict or its JSON string. Never raises on odd shapes: unknown
    content types are skipped, as the docs require.
    """
    if isinstance(resp, str):
        try:
            resp = json.loads(resp)
        except ValueError:
            resp = None
    if not isinstance(resp, dict):
        return _empty(resp, status="unparseable")

    texts, sqls, tables, tools = [], [], [], []
    verified = None

    for item in resp.get("content") or []:
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind == "text":
            if item.get("text"):
                texts.append(item["text"])
        elif kind == "tool_use":
            tool_use = item.get("tool_use") or {}
            if tool_use.get("name"):
                tools.append(tool_use["name"])
            _add_sql(sqls, (tool_use.get("input") or {}).get("sql"))
        elif kind == "tool_result":
            for part in (item.get("tool_result") or {}).get("content") or []:
                payload = part.get("json") if isinstance(part, dict) else None
                if not isinstance(payload, dict):
                    continue
                _add_sql(sqls, payload.get("sql"))
                if "verified_query_used" in payload:
                    verified = bool(payload["verified_query_used"])
                if payload.get("result_set"):
                    tables.append(result_set_to_records(payload["result_set"]))
        elif kind == "table":
            result_set = (item.get("table") or {}).get("result_set")
            if result_set:
                tables.append(result_set_to_records(result_set))

    sql = sqls[-1] if sqls else None
    return {
        "answer": "\n\n".join(texts).strip(),
        "sql": sql,
        "metric_used": metrics_in_sql(sql),
        "verified_query_used": verified,
        "tools_used": list(dict.fromkeys(tools)),
        "tables": tables,
        "warnings": resp.get("warnings") or [],
        "status": resp.get("status", "completed"),
        "raw": resp,
    }


def result_set_to_records(result_set: dict) -> list[dict]:
    """Turn a SQL-API ResultSet into a list of row dicts.

    Values arrive as strings, and `rowType` may be absent (the docs' own example omits
    it). In that case columns are named COL_1, COL_2, ...
    """
    data = result_set.get("data") or []
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
    if sql and sql not in sqls:
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


def _empty(raw, status: str) -> dict:
    return {"answer": "", "sql": None, "metric_used": [], "verified_query_used": None,
            "tools_used": [], "tables": [], "warnings": [], "status": status, "raw": raw}
