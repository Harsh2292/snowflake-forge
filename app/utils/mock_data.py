"""Deterministic mock data shaped exactly like live Snowflake output.

Contract fixtures (MOCK_METRICS, MOCK_BY_REGION) are used verbatim. Anything the
contract doesn't fix is generated deterministically inside the §3 ranges and labelled
with obviously synthetic names (MOCK-PLANT-01, ...). Once CoCo's artifacts land (B05,
B08), real captured values replace these.
"""

import zlib
from datetime import date, timedelta

import pandas as pd

from . import config

# Illustrative only; artifact 02_raw_metrics.md (B05) supplies the real naive value.
MOCK_NAIVE_OTD = 0.7942

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
    "shipments.carrier": [f"MOCK-CARRIER-{c}" for c in "ABCDE"],
    "orders.order_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
    "shipments.ship_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
    "inventory.snapshot_date": [_END - timedelta(days=i) for i in range(29, -1, -1)],
}


def dimension_values(dimension: str) -> list:
    if dimension in config.DIMENSION_VALUES:
        return list(config.DIMENSION_VALUES[dimension])
    return list(_SYNTHETIC_VALUES[dimension])


def metric_value(metric_key: str, dimension=None, member=None) -> float:
    """One mock value: contract fixture where one exists, else deterministic in range."""
    if dimension is None:
        return config.MOCK_METRICS[metric_key]
    if dimension in _REGION_DIMS:
        return config.MOCK_BY_REGION[member][metric_key]
    low, high = config.METRIC_RANGES[metric_key]
    seed = zlib.crc32(f"{metric_key}|{dimension}|{member}".encode())
    fraction = 0.15 + 0.7 * (seed % 10_000) / 10_000  # keep clear of the range edges
    value = low + (high - low) * fraction
    return round(value, 4 if high <= 1 else 2)


def metric_frame(metric_key: str, dimension=None) -> pd.DataFrame:
    metric_col = config.column_name(config.METRICS[metric_key]["id"])
    if dimension is None:
        return pd.DataFrame({metric_col: [metric_value(metric_key)]})
    dim_col = config.column_name(dimension)
    members = dimension_values(dimension)
    return pd.DataFrame({
        dim_col: members,
        metric_col: [metric_value(metric_key, dimension, m) for m in members],
    })


def all_metrics_frame() -> pd.DataFrame:
    return pd.DataFrame([{config.column_name(m["id"]): config.MOCK_METRICS[k]
                          for k, m in config.METRICS.items()}])


def persona_metrics_row(persona: str) -> dict:
    """Shape of one CR-002 persona metric procedure result. Mock values are identical by design."""
    row = {"PERSONA": persona.upper()}
    row.update({config.column_name(m["id"]): config.MOCK_METRICS[k] for k, m in config.METRICS.items()})
    return row


def masking_sample(persona: str) -> pd.DataFrame:
    """Contract §5.4 result shape (v1.3), with masking applied per the §6 matrix."""
    buyer = persona == "Buyer"
    rows = []
    for i in range(1, 4):
        rows.append({
            "PERSONA": persona.upper(),
            "SAMPLE_PART_ID": f"MOCK-PART-{i:02d}",
            "UNIT_COST": round(40.0 + 17.5 * i, 2) if buyer else None,
            "SAMPLE_SUPPLIER_ID": f"MOCK-SUP-{i:03d}",
            "PAYMENT_TERMS": ["NET30", "NET45", "NET60"][i - 1] if buyer else "*** RESTRICTED ***",
            "SAMPLE_CUSTOMER_ID": f"MOCK-CUST-{i:03d}",
            "CUSTOMER_NAME": "*** MASKED ***" if buyer else f"Mock Customer {i}",
            "CREDIT_LIMIT": None,
            "CONTRACT_PRICE": round(36.0 + 15.25 * i, 2) if buyer else None,  # v1.3, CR-004
            "CUSTOMER_EMAIL": "*** MASKED ***" if buyer else f"customer{i}@mock.example",
        })
    return pd.DataFrame(rows)


def quality_results() -> pd.DataFrame:
    """DMFs from LLD §5.4 / GAPS_RESOLVED GAP-3, all healthy."""
    measured = pd.Timestamp("2026-09-01 06:00:00")
    rows = [
        ("V_SHIPMENT", "NULL_COUNT", "promised_delivery_date", 0),
        ("V_ORDER_LINE", "DUPLICATE_COUNT", "line_id", 0),
        ("V_INVENTORY", "FRESHNESS", "snapshot_date", 3600),
        ("V_ORDER_LINE", "DMF_ORPHAN_ORDER_LINES", "order_id", 0),
        ("V_ORDER_LINE", "DMF_OVERSHIP_COUNT", "quantity_ordered, quantity_shipped", 0),
    ]
    return pd.DataFrame(
        [{"TABLE_NAME": t, "METRIC_NAME": m, "ARGUMENT_NAMES": a, "VALUE": v,
          "MEASUREMENT_TIME": measured} for t, m, a, v in rows]
    )


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


def agent_response(text: str, sql=None, frame=None, verified=True) -> dict:
    """A raw response in the documented DATA_AGENT_RUN shape (docs/references/data_agent_run.md)."""
    content = [{"type": "thinking", "thinking": {"text": "Mock orchestration."}}]
    if sql:
        content.append({"type": "tool_use", "tool_use": {
            "tool_use_id": "mock_tool_1", "type": "cortex_analyst_text_to_sql",
            "name": "SupplyChainAnalyst", "input": {"query": text}}})
        content.append({"type": "tool_result", "tool_result": {
            "tool_use_id": "mock_tool_1", "type": "cortex_analyst_text_to_sql",
            "name": "SupplyChainAnalyst", "status": "success",
            "content": [{"type": "json", "json": {
                "sql": sql, "verified_query_used": verified, "query_id": "mock-query-id",
                "result_set": _result_set(frame)}}]}})
    content.append({"type": "text", "text": text})
    return {"role": "assistant", "content": content, "status": "completed",
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
