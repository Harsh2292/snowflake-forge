"""The app's saved data: the last real Snowflake results CoCo captured (C6b), shaped
exactly like live output.

Everything comes from utils/captured.json, which tests/tools/build_captured.py generates
from docs/artifacts (art 05 metrics, art 09 personas, art 10 data quality, the §8 naive
value). Mock mode shows it, and so does a live fallback, as "the last captured Snowflake
results". A deterministic generator inside the §3 ranges (with obviously synthetic names,
MOCK-PLANT-01, ...) remains only as a safety net for a pairing the capture lacks; a test
checks that nothing uses it today.
"""

import json
import re
import zlib
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

from . import config

_CAPTURED_FILE = Path(__file__).with_name("captured.json")
CAPTURED = json.loads(_CAPTURED_FILE.read_text(encoding="utf-8")) if _CAPTURED_FILE.exists() else {}

def _captured_on() -> str:
    """The metrics' capture date for labels, e.g. "29 Sep 2026"."""
    found = re.search(r"captured (\d{4}-\d{2}-\d{2})", CAPTURED.get("metrics", {}).get("source", ""))
    return f"{date.fromisoformat(found.group(1)):%d %b %Y}" if found else "the last capture"


CAPTURED_ON = _captured_on()

# Contract §8's naive ERP-date OTD, as measured on the current data (B08c gate 5).
MOCK_NAIVE_OTD = CAPTURED.get("naive_otd", {}).get("value", 0.6817)

_REGION_DIMS = {"plants.plant_region", "customers.customer_region", "suppliers.supplier_region"}
_END = date(2026, 9, 1)

_SYNTHETIC_VALUES = {
    "plants.plant_name": [f"MOCK-PLANT-{i:02d}" for i in range(1, 13)],
    "plants.plant_country": ["IN", "SG", "JP", "AU", "DE", "FR", "GB", "NL", "US", "MX", "BR", "CA"],
    "parts.part_name": [f"MOCK-PART-{i:02d}" for i in range(1, 11)],
    "parts.subcategory": [f"MOCK-SUBCAT-{i:02d}" for i in range(1, 7)],
    "parts.is_critical": [True, False],
    "orders.order_month": [f"{2025 + (9 + i) // 12}-{(9 + i) % 12 + 1:02d}" for i in range(12)],
    "orders.order_year": [2025, 2026],
    "orders.order_year_quarter": ["2025-Q4", "2026-Q1", "2026-Q2", "2026-Q3"],
    "shipments.carrier": [f"MOCK-CARRIER-{c}" for c in "ABCDE"],
    "orders.order_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
    "shipments.ship_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
    "inventory.snapshot_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
}


def dimension_values(dimension: str) -> list:
    if dimension in config.DIMENSION_VALUES:
        return list(config.DIMENSION_VALUES[dimension])
    return list(_SYNTHETIC_VALUES[dimension])


def captured_overall(metric_key: str):
    """The captured headline value (art 05 `overall`), or None if not captured."""
    col = config.column_name(config.METRICS[metric_key]["id"])
    return CAPTURED.get("metrics", {}).get("overall", {}).get(col)


def captured_rows(metric_key: str, dimension: str):
    """The captured rows of one pairing (art 05), ordered by the dimension, or None."""
    return CAPTURED.get("metrics", {}).get("by_dimension", {}).get(config.METRICS[metric_key]["id"], {}).get(dimension)


def metric_value(metric_key: str, dimension=None, member=None) -> float:
    """One value: captured where it exists, else the contract fixture, else deterministic
    inside the §3 range (the safety net)."""
    if dimension is None:
        captured = captured_overall(metric_key)
        return config.MOCK_METRICS[metric_key] if captured is None else captured
    if dimension in _REGION_DIMS:
        return config.MOCK_BY_REGION[member][metric_key]
    low, high = config.METRIC_RANGES[metric_key]
    seed = zlib.crc32(f"{metric_key}|{dimension}|{member}".encode())
    fraction = 0.15 + 0.7 * (seed % 10_000) / 10_000  # keep clear of the range edges
    value = low + (high - low) * fraction
    return round(value, 4 if high <= 1 else 2)


# By order status, the real data (art 05) has no value for fill rate on OPEN and CANCELLED
# orders (NULL by definition, CR-005), and shipment metrics only for orders that shipped.
_UNSHIPPED = {"OPEN", "CANCELLED"}


_DATE_DIMS = {"orders.order_date", "shipments.ship_date", "inventory.snapshot_date"}


def metric_frame(metric_key: str, dimension=None) -> pd.DataFrame:
    metric_col = config.column_name(config.METRICS[metric_key]["id"])
    if dimension is None:
        return pd.DataFrame({metric_col: [metric_value(metric_key)]})
    dim_col = config.column_name(dimension)
    rows = captured_rows(metric_key, dimension)
    if rows is not None:
        members = [r.get(dim_col) for r in rows]
        if dimension in _DATE_DIMS:  # JSON keeps dates as text; Snowpark returns datetime.date
            members = [date.fromisoformat(m) if isinstance(m, str) else m for m in members]
        return pd.DataFrame({dim_col: members, metric_col: [config.as_number(r.get(metric_col)) for r in rows]}
                            ).astype({metric_col: float})
    return synthetic_frame(metric_key, dimension)


def synthetic_frame(metric_key: str, dimension: str) -> pd.DataFrame:
    """The safety net for a pairing the capture lacks: in range, obviously synthetic."""
    metric_col = config.column_name(config.METRICS[metric_key]["id"])
    dim_col = config.column_name(dimension)
    members = dimension_values(dimension)
    no_value = set()
    if dimension == "orders.order_status":
        if config.METRICS[metric_key]["id"].startswith("shipments."):
            members = [m for m in members if m not in _UNSHIPPED]
        elif metric_key == "fill_rate":
            no_value = _UNSHIPPED
    return pd.DataFrame({
        dim_col: members,
        metric_col: [None if m in no_value else metric_value(metric_key, dimension, m) for m in members],
    }).astype({metric_col: float})


def all_metrics_frame() -> pd.DataFrame:
    return pd.DataFrame([{config.column_name(m["id"]): metric_value(k) for k, m in config.METRICS.items()}])


def persona_metrics_row(persona: str) -> dict:
    """One CR-002 persona metric procedure result, as captured (art 09): identical for every
    persona, which is the point."""
    captured = CAPTURED.get("personas", {}).get("metrics_by_persona", {}).get(persona.upper())
    columns = [config.column_name(m["id"]) for m in config.METRICS.values()]
    if captured:  # in the procedure's column order (§5.4); JSON sorted the keys
        return {"PERSONA": captured[0]["PERSONA"], **{c: captured[0][c] for c in columns}}
    row = {"PERSONA": persona.upper()}
    row.update({config.column_name(m["id"]): metric_value(k) for k, m in config.METRICS.items()})
    return row


def captured_sample(persona: str):
    """The rows SP_SAMPLE_AS_<persona> returned (art 09), or None."""
    return CAPTURED.get("personas", {}).get("samples_by_persona", {}).get(persona.upper())


def _unmasked_sample_rows() -> list[tuple]:
    """Each sample record with every field as the persona allowed to see it saw it (§6):
    costs and terms from the Buyer, customer details from the Planner."""
    buyer, planner = captured_sample("Buyer"), captured_sample("Planner")
    return [(b["SAMPLE_PART_ID"], b["UNIT_COST"], b["SAMPLE_SUPPLIER_ID"], b["PAYMENT_TERMS"], b["SAMPLE_CUSTOMER_ID"],
             p["CUSTOMER_NAME"], b["CONTRACT_PRICE"], p["CUSTOMER_EMAIL"]) for b, p in zip(buyer, planner)]


# part, unit cost, supplier, payment terms, customer, customer name, contract price, email
_SAMPLE_ROWS = _unmasked_sample_rows() if CAPTURED else [
    ("MAT000001", 22.20, "SUP00107", "NET90", "CUST00001",
     "Beacon Global Logistics - Division 0001", 20.17, "accounts.payable0001@clientcorp.com"),
]


def masking_sample(persona: str) -> pd.DataFrame:
    """Contract §5.4 result shape (v1.3): the captured rows, masked per the §6 matrix. (A
    test checks this equals what each persona's procedure really returned, art 09.)"""

    def seen(matrix_row, value):
        rule = config.MASKING_MATRIX[matrix_row][persona]
        return value if rule == "visible" else rule

    rows = [{
        "PERSONA": persona.upper(),
        "SAMPLE_PART_ID": part,
        "UNIT_COST": seen("V_PART.unit_cost", cost),
        "SAMPLE_SUPPLIER_ID": supplier,
        "PAYMENT_TERMS": seen("V_SUPPLIER.payment_terms", terms),
        "SAMPLE_CUSTOMER_ID": customer,
        "CUSTOMER_NAME": seen("V_CUSTOMER.customer_name", name),
        "CREDIT_LIMIT": seen("V_CUSTOMER.credit_limit", None),  # never captured unmasked
        "CONTRACT_PRICE": seen("V_SOURCING.contract_price", price),
        "CUSTOMER_EMAIL": seen("V_CUSTOMER.email", email),
    } for part, cost, supplier, terms, customer, name, price, email in _SAMPLE_ROWS]
    # NUMBER columns as float, NULL as NaN: what forge_data's live branch returns.
    return pd.DataFrame(rows, columns=config.SAMPLE_COLUMNS).astype(
        {"UNIT_COST": float, "CREDIT_LIMIT": float, "CONTRACT_PRICE": float})


def quality_results() -> pd.DataFrame:
    """The latest result per DMF association, as captured (art 10, B12), in the live path's
    shape. By layer (DATA_SPEC §7.2): the raw SOURCE tables carry the injected defects on
    purpose; the cleaned CONFORMED tables must show zero, except missing promised dates (E01),
    which stay visible by rule and are left out of on-time delivery."""
    rows = CAPTURED.get("quality", {}).get("dmf_results_latest") or _PRACTICE_DMF_ROWS
    return pd.DataFrame([{
        "TABLE_SCHEMA": r["table_schema"], "TABLE_NAME": r["table_name"], "METRIC_NAME": r["metric_name"],
        "ARGUMENT_NAMES": ", ".join(map(str, r["argument_names"])), "VALUE": config.as_number(r["value"]),
        "MEASUREMENT_TIME": pd.Timestamp(r["measurement_time"]),
    } for r in rows])


# Used only if captured.json is missing: a few rows in the art 10 shape.
_PRACTICE_DMF_ROWS = [
    {"table_schema": sc, "table_name": t, "metric_name": m, "argument_names": a, "value": v,
     "measurement_time": "2026-09-30 03:20:00 -0700"}
    for sc, t, m, a, v in [
        ("CONFORMED", "SHIPMENT", "NULL_COUNT", ["PROMISED_DELIVERY_DATE"], 5534),
        ("CONFORMED", "ORDER_LINE", "DUPLICATE_COUNT", ["LINE_ID"], 0),
        ("ERP_SOURCE", "VBAP", "DUPLICATE_COUNT", ["LINE_ID"], 29870),
    ]
]


def data_health(entity: str = "ALL") -> dict:
    """SP_DATA_HEALTH(entity) as captured (art 10, B12): ALL and shipments verbatim; any
    other entity is its part of ALL, in the same shape."""
    quality = CAPTURED.get("quality", {})
    if entity == "ALL" and quality.get("data_health_all"):
        return json.loads(json.dumps(quality["data_health_all"]))  # a copy: callers may tag it
    if entity == "shipments" and quality.get("data_health_shipments"):
        return json.loads(json.dumps(quality["data_health_shipments"]))
    whole = quality.get("data_health_all")
    if whole:
        entities = [e for e in whole["entities"] if e["entity"] == entity]
        status = entities[0]["status"] if entities else "UNKNOWN"
        return {**{k: v for k, v in whole.items() if k != "entities"}, "entity": entity, "status": status,
                "entities": json.loads(json.dumps(entities))}
    return {"entity": entity, "as_of_date": MOCK_AS_OF, "status": "UNKNOWN", "summary": "", "entities": []}


MOCK_AS_OF = (CAPTURED.get("quality", {}).get("data_health_all") or {}).get("as_of_date", "2026-09-29")


# ── Mock agent ───────────────────────────────────────────────────────────────
# Canonical question → (metric_key, dimension).
CANNED_QUESTIONS = {
    config.CANONICAL_QUESTIONS[0]: ("on_time_delivery_rate", None),
    config.CANONICAL_QUESTIONS[1]: ("on_time_delivery_rate", "plants.plant_region"),
    config.CANONICAL_QUESTIONS[2]: ("on_time_delivery_rate", "orders.order_quarter"),
    config.CANONICAL_QUESTIONS[3]: ("fill_rate", None),
    config.CANONICAL_QUESTIONS[4]: ("fill_rate", "parts.category"),
    config.CANONICAL_QUESTIONS[5]: ("days_of_inventory", "plants.plant_name"),
    config.CANONICAL_QUESTIONS[6]: ("avg_landed_cost", "plants.plant_region"),
    config.CANONICAL_QUESTIONS[7]: ("on_time_delivery_rate", "plants.plant_name"),
}

FREE_TEXT_ANSWER = (
    "Mock mode only has canned answers for the 8 suggested questions. "
    "Pick one of the suggestions, or switch to live mode."
)


def canned_answer(metric_key: str, dimension, frame: pd.DataFrame) -> str:
    metric = config.METRICS[metric_key]
    metric_col = config.column_name(metric["id"])
    if dimension is None:
        value = config.format_value(metric_key, frame[metric_col].iloc[0])
        return f"{value}. {metric['label']} across the full 12-month window. Definition: {metric['definition']}"
    dim_col = config.column_name(dimension)
    best = frame.loc[frame[metric_col].idxmax()]
    worst = frame.loc[frame[metric_col].idxmin()]
    return (
        f"{metric['label']} by {dim_col.replace('_', ' ').lower()} over the full 12-month window: "
        f"highest {best[dim_col]} at {config.format_value(metric_key, best[metric_col])}, "
        f"lowest {worst[dim_col]} at {config.format_value(metric_key, worst[metric_col])}. "
        f"Definition: {metric['definition']}"
    )


def agent_response(text: str, sql=None, frame=None, verified=True, title=None, suggestions=()) -> dict:
    """A raw response in the shape the real agent returns (art 07, B10): a verified query
    run by system_execute_sql, the answer text, the result as a `table` item repeating the
    tool_result, the SQL again as a ```sql block, then suggested follow-up questions."""
    content = [{"type": "thinking", "thinking": {"text": "Mock orchestration."}}]
    if sql:
        content.append({"type": "tool_use", "tool_use": {
            "tool_use_id": "mock_tool_1", "type": "system_execute_sql", "name": "system_execute_sql",
            "client_side_execute": False, "input": {"sql": sql}}})
        content.append({"type": "tool_result", "tool_result": {
            "tool_use_id": "mock_tool_1", "type": "system_execute_sql", "name": "system_execute_sql",
            "status": "success", "content": [{"type": "json", "json": {
                "sql": sql, "verified_query_used": verified, "query_id": "mock-query-id",
                "result_set": _result_set(frame)}}]}})
    content.append({"type": "text", "text": text + "\n\n"})
    if sql:
        content.append({"type": "table", "table": {"query_id": "mock-query-id", "tool_use_id": "mock_tool_1",
                                                   "title": title, "result_set": _result_set(frame)}})
        content.append({"type": "text", "text": f"\n\n```sql\n{sql}\n```"})
    if suggestions:
        content.append({"type": "suggested_queries",
                        "suggested_queries": [{"query": q} for q in suggestions]})
    return {"role": "assistant", "content": content, "status": "completed", "schema_version": "v2",
            "metadata": {"run_id": "mock-run", "thread_id": 0}}


def _result_set(frame) -> dict:
    if frame is None:
        return {}
    return {
        "statementHandle": "mock-query-id",
        "resultSetMetaData": {
            "numRows": len(frame), "format": "jsonv2",
            "rowType": [{"name": c, "type": "FIXED" if pd.api.types.is_numeric_dtype(frame[c]) else "TEXT"}
                        for c in frame.columns]},
        "data": [[None if pd.isna(v) else str(v) for v in row] for row in frame.itertuples(index=False)],
    }
