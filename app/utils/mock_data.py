"""Deterministic mock data shaped exactly like live Snowflake output.

Contract fixtures (MOCK_METRICS, MOCK_BY_REGION) are used verbatim. Anything the
contract doesn't fix is generated deterministically inside the §3 ranges and labelled
with obviously synthetic names (MOCK-PLANT-01, ...). Once CoCo's artifacts land, real
captured values replace these (the persona samples already use artifact 04).
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


# By order status, the real data (art 05) has no value for fill rate on OPEN and CANCELLED
# orders (NULL by definition, CR-005), and shipment metrics only for orders that shipped.
_UNSHIPPED = {"OPEN", "CANCELLED"}


def metric_frame(metric_key: str, dimension=None) -> pd.DataFrame:
    metric_col = config.column_name(config.METRICS[metric_key]["id"])
    if dimension is None:
        return pd.DataFrame({metric_col: [metric_value(metric_key)]})
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
    return pd.DataFrame([{config.column_name(m["id"]): config.MOCK_METRICS[k]
                          for k, m in config.METRICS.items()}])


def persona_metrics_row(persona: str) -> dict:
    """Shape of one CR-002 persona metric procedure result. Mock values are identical by design."""
    row = {"PERSONA": persona.upper()}
    row.update({config.column_name(m["id"]): config.MOCK_METRICS[k] for k, m in config.METRICS.items()})
    return row


# The rows SP_SAMPLE_AS_* really return, unmasked where some persona sees them (artifact
# 04_persona_outputs.json, B07b). Copied because the deployed app can't read docs/;
# tests/artifacts checks that they still match.
_SAMPLE_ROWS = [
    # part, unit cost, supplier, payment terms, customer, customer name, contract price, email
    ("MAT000001", 42.01, "SUP00001", "2/10 NET30", "CUST00001",
     "Beacon Global Logistics - Division 001", 40.33, "accounts.payable001@clientcorp.com"),
    ("MAT000002", 79.02, "SUP00002", "2/10 NET30", "CUST00002",
     "Crestview Automotive Group - Division 002", 76.65, "accounts.payable002@clientcorp.com"),
    ("MAT000003", 116.03, "SUP00003", "2/10 NET30", "CUST00003",
     "Delta Energy Dynamics - Division 003", 113.71, "accounts.payable003@clientcorp.com"),
]


def masking_sample(persona: str) -> pd.DataFrame:
    """Contract §5.4 result shape (v1.3): the captured rows, masked per the §6 matrix."""

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
    """DMF results by layer (DATA_SPEC §7.2): the raw SOURCE tables carry the injected
    defects on purpose; the cleaned CONFORMED tables must show zero."""
    measured = pd.Timestamp("2026-09-01 06:00:00")
    rows = [
        ("CONFORMED", "SHIPMENT", "NULL_COUNT", "promised_delivery_date", 0),
        ("CONFORMED", "ORDER_LINE", "DUPLICATE_COUNT", "line_id", 0),
        ("CONFORMED", "INVENTORY", "FRESHNESS", "load_ts", 3600),
        ("CONFORMED", "ORDER_LINE", "DMF_ORPHAN_ORDER_LINES", "order_id", 0),
        ("CONFORMED", "ORDER_LINE", "DMF_OVERSHIP_COUNT", "quantity_ordered, quantity_shipped", 0),
        ("ERP_SOURCE", "VBAP", "DUPLICATE_COUNT", "LINE_ID", 29870),
        ("TMS_SOURCE", "VTTK", "NULL_COUNT", "PROM_DLV_DT", 5712),
    ]
    return pd.DataFrame(
        [{"TABLE_SCHEMA": sc, "TABLE_NAME": t, "METRIC_NAME": m, "ARGUMENT_NAMES": a, "VALUE": v,
          "MEASUREMENT_TIME": measured} for sc, t, m, a, v in rows]
    )


# Practice SP_DATA_HEALTH output (DATA_SPEC §7.2 shape). The as-of date is the latest
# business date loaded; the real procedure reports it at B12 (C10).
MOCK_AS_OF = "2026-09-29"
_HEALTH_ROWS = {  # entity: (CONFORMED table, rows at SF 1)
    "suppliers": ("SUPPLIER", 150), "parts": ("PART", 1200), "sourcing": ("SOURCING", 2400),
    "plants": ("PLANT", 12), "inventory": ("INVENTORY", 2160000), "customers": ("CUSTOMER", 2000),
    "orders": ("SALES_ORDER", 636000), "order_lines": ("ORDER_LINE", 1980000), "shipments": ("SHIPMENT", 705000),
}


def data_health(entity: str = "ALL") -> dict:
    names = list(_HEALTH_ROWS) if entity == "ALL" else [entity]
    entities = []
    for name in names:
        table, count = _HEALTH_ROWS[name]
        checks = []
        if name == "shipments":
            checks.append({"check": "missing_promised_date", "code": "E01", "layer": "SOURCE",
                           "dmf": "SNOWFLAKE.CORE.NULL_COUNT", "table": "SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK",
                           "columns": ["PROM_DLV_DT"], "value": 5712, "rate": 0.0079, "threshold_rate": 0.016,
                           "status": "OK", "handled_by": "Excluded from on-time delivery",
                           "measured_at": "2026-09-30T06:00:00Z"})
        entities.append({"entity": name, "table": f"SUPPLY_CHAIN_FORGE.CONFORMED.{table}", "row_count": count,
                         "latest_business_date": MOCK_AS_OF, "latest_load_ts": "2026-09-30T02:41:00",
                         "freshness_hours": 5.3, "freshness_status": "OK", "status": "OK", "checks": checks})
    return {"entity": entity, "generated_at": "2026-09-30T08:00:00Z", "as_of_date": MOCK_AS_OF, "status": "OK",
            "summary": "Every table is fresh; edge cases are handled and no repairable defects are left.",
            "entities": entities}


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
