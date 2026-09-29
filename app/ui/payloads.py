"""Build the data each HTML view needs, from utils.forge_data only.

Every function returns plain JSON-able dicts. They're cached per data mode, so
switching screens doesn't re-query Snowflake in live mode.
"""

import json

import pandas as pd
import streamlit as st

from utils import config, forge_data

FORMULAS = {
    "on_time_delivery_rate": "Delivered on or before the promised date ÷ all delivered shipments",
    "fill_rate": "Quantity shipped ÷ quantity ordered",
    "days_of_inventory": "Average stock on hand ÷ average daily usage",
    "avg_landed_cost": "Average of freight + duties + handling per shipment",
}
UNITS = {"days_of_inventory": "days"}

BREAKDOWNS = [
    ("region", "By region", "Region", "plants.plant_region"),
    ("plant", "By plant", "Plant", "plants.plant_name"),
    ("category", "By product category", "Product category", "parts.category"),
    ("quarter", "By quarter", "Quarter", "orders.order_quarter"),
    ("segment", "By customer segment", "Customer segment", "customers.customer_segment"),
    ("status", "By order status", "Order status", "orders.order_status"),
]
IN_NATURAL_ORDER = {"quarter"}
BARS_SHOWN = 12  # Explore bars and answer charts show at most this many rows; tables show all
WHY_NOT = {  # why a breakdown is impossible (contract §4 pairings), in words
    "on_time_delivery_rate": "shipments aren’t linked to products",
    "avg_landed_cost": "shipments aren’t linked to products",
    "days_of_inventory": "inventory isn’t linked to orders, shipments or customers",
    "fill_rate": "",
}

SYSTEMS = [
    {"code": "ERP", "name": "Enterprise resource planning (e.g. SAP)", "team": "Sales & planning",
     "holds": ["Sales orders", "Customers", "Order lines", "Exchange rates"], "column": "ERDAT", "means": "Its own “promised” date"},
    {"code": "WMS", "name": "Warehouse management", "team": "Warehouses",
     "holds": ["Plant inventory snapshots", "Daily usage"], "column": "LABST", "means": "Stock on hand"},
    {"code": "TMS", "name": "Transport management", "team": "Logistics",
     "holds": ["Freight carriers", "Shipments", "Actual delivery dates"], "column": "PROM_DLV_DT", "means": "Carrier promised date"},
    {"code": "SRM", "name": "Supplier relationship management", "team": "Procurement",
     "holds": ["Suppliers", "Part specifications", "Procurement contracts"], "column": "ZTERM", "means": "Payment terms"},
]

ONTOLOGY = ["Supplier", "Part", "Plant", "Shipment", "Order", "Customer"]
INITIALS = {"Planner": "PP", "Buyer": "PL", "Logistics": "LC"}
PRACTICE_NOTE = ("Practice values. In live mode each team’s number comes from its own query, run under that "
                 "team’s role (contract §5.4).")


_num = config.as_number  # float, or None where Snowflake returned NULL (JSON null → "—")


def _by_value(rows: list[dict]) -> list[dict]:
    """Highest value first; rows without a value (NULL) last."""
    return sorted(rows, key=lambda r: (r["value"] is None, -(r["value"] or 0)))


def _metric_col(key: str) -> str:
    return config.column_name(config.METRICS[key]["id"])


def metrics_meta() -> list[dict]:
    head = forge_data.get_all_metrics().iloc[0]
    out = []
    for key, m in config.METRICS.items():
        value = _num(head[_metric_col(key)])
        out.append({"key": key, "label": m["label"], "format": m["format"], "definition": m["definition"],
                    "id": m["id"], "formula": FORMULAS[key], "unit": UNITS.get(key, ""), "overall": value,
                    "window": config.WINDOW_LABEL[key],
                    "display": config.format_value(key, value) + (f" {UNITS[key]}" if key in UNITS else "")})
    return out


@st.cache_data(ttl=300, show_spinner=False)
def problem(mode: str) -> dict:
    catalog = forge_data.get_source_schema_summary()
    return {"naive": _num(forge_data.get_naive_otd()), "governed": _num(forge_data.get_governed_otd()),
            "systems": SYSTEMS, "catalog": catalog.to_dict("records")}


@st.cache_data(ttl=300, show_spinner=False)
def fix(mode: str) -> dict:
    catalog = forge_data.get_source_schema_summary()
    tables = catalog["SOURCE_TABLE"].nunique()
    views = catalog.loc[catalog["GOVERNED_VIEW"] != "", "GOVERNED_VIEW"].nunique()
    layers = [
        {"id": "source", "name": "Source", "sub": "Four source systems, as they are", "count": f"{tables} tables",
         "summary": "The raw data stays exactly as each system produces it: cryptic SAP-style names and two conflicting promised dates.",
         "points": ["ERP_SOURCE, WMS_SOURCE, TMS_SOURCE and SRM_SOURCE schemas",
                    "Column names like ERDAT, LABST and ZTERM that only specialists can read",
                    "Nothing here is shown to business users directly"]},
        {"id": "governed", "name": "Governed", "sub": "Clean, protected views", "count": f"{views} views",
         "summary": "Conformed views rename every column to a business name, pick the one true promised date, and protect sensitive fields.",
         "points": ["Business names for every column",
                    "Masking policies hide pricing and personal data by role",
                    "Data quality checks run automatically on a schedule"]},
        {"id": "semantic", "name": "Semantic", "sub": "The single source of truth", "count": f"{len(config.METRICS)} metrics",
         "summary": "One Snowflake semantic view encodes the business entities, how they connect, and the exact formula for each metric.",
         "points": ["Each canonical metric is defined once, in code",
                    "Relationships between entities form the supply chain ontology",
                    "Verified queries pin the answers to the key questions"]},
        {"id": "conversation", "name": "Conversation", "sub": "Cortex Agent and this app", "count": "3 personas",
         "summary": "People ask in plain English. The agent answers from the semantic view and shows the SQL and definition it used.",
         "points": ["Planner, Buyer and Logistics all get the same governed numbers",
                    "Each answer shows its working",
                    "Masked details stay masked for each role"]},
    ]
    cryptic = catalog.loc[catalog["SYSTEM"].isin(["ERP", "WMS", "TMS", "SRM"]), "SOURCE_COLUMN"].head(8).tolist()
    return {"layers": layers, "metrics": metrics_meta(), "ontology": ONTOLOGY, "cryptic": cryptic,
            "sample_question": config.CANONICAL_QUESTIONS[1]}


def _visibility(sample: pd.DataFrame) -> list[dict]:
    def shown(col):
        values = sample[col]
        return bool(values.notna().any()) and not values.astype(str).str.startswith("***").all()
    return [{"label": label, "visible": shown(col)} for label, col in
            [("Customer names", "CUSTOMER_NAME"), ("Unit cost", "UNIT_COST"),
             ("Payment terms", "PAYMENT_TERMS"), ("Credit limit", "CREDIT_LIMIT")]]


# The "rows each team gets" drawer: one sample record, the three teams side by side.
RECORD_IDS = [("Part", "SAMPLE_PART_ID"), ("Supplier", "SAMPLE_SUPPLIER_ID"), ("Customer", "SAMPLE_CUSTOMER_ID")]
RECORD_FIELDS = [("Unit cost", "UNIT_COST"), ("Contract price", "CONTRACT_PRICE"),
                 ("Payment terms", "PAYMENT_TERMS"), ("Customer name", "CUSTOMER_NAME"),
                 ("Customer email", "CUSTOMER_EMAIL"), ("Credit limit", "CREDIT_LIMIT")]
MASKED_WORDS = {"*** RESTRICTED ***": "restricted", "*** MASKED ***": "masked"}


def _cell(value) -> dict:
    if pd.isna(value):
        return {"text": "hidden", "masked": True}
    if str(value) in MASKED_WORDS:
        return {"text": MASKED_WORDS[str(value)], "masked": True}
    return {"text": f"{value:,.2f}" if isinstance(value, float) else str(value), "masked": False}


def _records(samples: dict) -> list[dict]:
    """Per sample record: its IDs and each protected field as every persona sees it."""
    count = min(len(df) for df in samples.values())
    return [{"ids": [{"label": label, "cells": [_cell(df[col].iloc[i]) for df in samples.values()]}
                     for label, col in RECORD_IDS],
             "fields": [{"label": label, "cells": [_cell(df[col].iloc[i]) for df in samples.values()]}
                        for label, col in RECORD_FIELDS]} for i in range(count)]


@st.cache_data(ttl=300, show_spinner=False)
def same(mode: str) -> dict:
    grid = forge_data.compare_across_personas().set_index("METRIC")
    samples = {p: forge_data.get_masking_divergence(p) for p in config.PERSONA_ROLES}
    personas = [{"key": p.upper(), "label": config.PERSONA_LABELS[p], "desc": config.PERSONA_DESCRIPTIONS[p],
                 "initials": INITIALS[p], "visibility": _visibility(sample)} for p, sample in samples.items()]
    grid_out = {k: {"values": {p: _num(grid.loc[k, p]) for p in ("PLANNER", "BUYER", "LOGISTICS")},
                    "identical": bool(grid.loc[k, "IDENTICAL"])} for k in config.METRICS}
    return {"metrics": metrics_meta(), "grid": grid_out, "personas": personas, "records": _records(samples),
            "dp": config.CONSISTENCY_DP, "practice": PRACTICE_NOTE if grid.attrs.get("source") != "live" else ""}


@st.cache_data(ttl=300, show_spinner=False)
def explore(mode: str) -> dict:
    breakdowns = {}
    for key in config.METRICS:
        items = []
        for bid, label, dim_name, dimension in BREAKDOWNS:
            allowed = dimension in config.VALID_PAIRINGS[key]
            rows = []
            if allowed:
                df = forge_data.get_metric(key, dimension)
                rows = [{"name": str(n), "value": _num(v)} for n, v in zip(df[config.column_name(dimension)], df[_metric_col(key)])]
                if bid not in IN_NATURAL_ORDER:
                    rows = _by_value(rows)
            items.append({"id": bid, "label": label, "dim_name": dim_name, "allowed": allowed, "rows": rows,
                          "reason": "" if allowed else f"Not available for {config.METRICS[key]['label'].lower()}: {WHY_NOT[key]}.",
                          "reason_short": WHY_NOT[key]})
        breakdowns[key] = items
    return {"metrics": metrics_meta(), "breakdowns": breakdowns, "bars": BARS_SHOWN}


PLAIN_CHECKS = {
    "NULL_COUNT": ("No missing promised dates", "missing"),
    "DUPLICATE_COUNT": ("No duplicate records", "duplicates"),
    "DMF_ORPHAN_ORDER_LINES": ("Every order line belongs to an order", "orphaned lines"),
    "DMF_ORPHAN_SHIPMENTS": ("Every shipment belongs to an order", "orphaned shipments"),
    "DMF_OVERSHIP_COUNT": ("Nothing shipped beyond what was ordered", "over-shipped lines"),
    "DMF_NEGATIVE_ON_HAND_COUNT": ("No negative stock", "negative stock rows"),
    "DMF_TEST_RECORD_COUNT": ("No test records", "test records"),
    "DMF_NONCONTRACT_CODE_COUNT": ("Every code is a standard value", "non-standard codes"),
    "DMF_COST_OUTLIER_COUNT": ("Implausible costs set aside", "outliers"),
    "ROW_COUNT": ("Rows loaded", "rows"),
    "FRESHNESS": ("Data age", None),
}
RAW_NOTE = "Expected in raw data"


def _age(seconds: float) -> str:
    if seconds < 3600:
        return f"Updated {max(1, round(seconds / 60))} minutes ago"
    if seconds < 172800:
        hours = round(seconds / 3600)
        return f"Updated {hours} hour{'s' if hours != 1 else ''} ago"
    return f"Updated {round(seconds / 86400)} days ago"


@st.cache_data(ttl=300, show_spinner=False)
def health(mode: str) -> dict:
    df = forge_data.get_quality_results()
    if df.empty:
        return {"checks": [], "passing": 0, "scored": 0, "checked": ""}
    checks = []
    for r in df.itertuples():
        metric = str(r.METRIC_NAME).upper()
        name, unit = PLAIN_CHECKS.get(metric, (str(r.METRIC_NAME), "problems"))
        schema = str(getattr(r, "TABLE_SCHEMA", "") or "")
        raw = schema.upper().endswith("_SOURCE")
        value = _num(r.VALUE)
        if value is None:
            result = "Not measured yet"
        elif metric == "FRESHNESS":
            result = _age(value)
        else:
            result = f"{int(value):,} {unit}"
        where = f"{schema}.{r.TABLE_NAME}" if schema else str(r.TABLE_NAME)
        checks.append({"name": f"Raw data: {unit}, repaired before use" if raw and unit else name,
                       "tech": f"{r.METRIC_NAME} on {where}.{r.ARGUMENT_NAMES}",
                       "result": result, "status": r.STATUS, "note": RAW_NOTE if raw else ""})
    scored = df[df["STATUS"] != "INFO"]
    checked = pd.to_datetime(df["MEASUREMENT_TIME"]).max()
    return {"checks": checks, "passing": int((scored["STATUS"] == "PASS").sum()), "scored": len(scored),
            "checked": f"{checked:%d %b %Y, %H:%M}", **_tables_health()}


def _tables_health() -> dict:
    """Per-table freshness and status from SP_DATA_HEALTH('ALL') (DATA_SPEC §7.2)."""
    data = forge_data.get_data_health("ALL")
    tables = [{"name": str(e.get("entity", "")).replace("_", " ").capitalize(),
               "rows": f"{int(e['row_count']):,}" if _num(e.get("row_count")) is not None else config.MISSING,
               "latest": e.get("latest_business_date") or config.MISSING,
               "freshness": e.get("freshness_status") or "UNKNOWN",
               "status": e.get("status") or "UNKNOWN"} for e in data.get("entities") or []]
    return {"tables": tables, "summary": data.get("summary") or "", "overall": data.get("status") or "UNKNOWN",
            "tables_practice": data.get("source") != "live"}


def _date_label(value) -> str:
    try:
        return f"{pd.Timestamp(value):%d %b %Y}"
    except (TypeError, ValueError):
        return ""


@st.cache_data(ttl=300, show_spinner=False)
def as_of(mode: str) -> str:
    """The as-of date shown with every metric (contract §3a): the latest business date
    loaded, from SP_DATA_HEALTH. Empty in live mode if the procedure isn't reachable, so a
    practice date is never shown as a live one."""
    data = forge_data.get_data_health("shipments")
    forge_data.pop_notices()  # its absence is shown by the missing date, not a toast
    if mode == "live" and data.get("source") != "live":
        return ""
    return _date_label(data.get("as_of_date"))


def _chart_window(label_col: str, rows: list[dict]) -> list[dict]:
    """At most BARS_SHOWN rows. A time series keeps its most recent rows, in time order;
    anything else keeps the agent's order (it ranks and limits the rows itself)."""
    if len(rows) <= BARS_SHOWN:
        return rows
    if any(word in label_col.upper() for word in ("DATE", "DAY", "WEEK", "MONTH", "QUARTER", "YEAR")):
        return sorted(rows, key=lambda r: r["label"])[-BARS_SHOWN:]
    return rows[:BARS_SHOWN]


def answer(question: str, result: dict) -> dict:
    """One Ask answer, for the answer card view."""
    keys = result["metric_used"]
    chart = None
    table = result["tables"][0] if result["tables"] else None
    total = (result.get("row_counts") or [len(table or [])])[0]
    if table and len(table) >= 2 and len(table[0]) >= 2:
        label_col, value_col = list(table[0])[:2]
        rows = [{"label": str(r[label_col]), "value": _num(r[value_col])} for r in table]
        if any(r["value"] is not None for r in rows) and all(
                r[value_col] is None or _num(r[value_col]) is not None for r in table):
            fmt = config.METRICS[keys[0]]["format"] if keys else "number"
            chart = {"rows": _chart_window(label_col, rows), "total": total, "format": fmt,
                     "title": f"{label_col.replace('_', ' ').title()} by value"}
    return {
        "question": question, "answer": result["answer"] or "The agent returned no text.",
        "sql": result["sql"] or "", "verified": bool(result["verified_query_used"]),
        "metrics": [config.METRICS[k]["label"] for k in keys],
        "definitions": [{"label": config.METRICS[k]["label"], "formula": FORMULAS[k],
                         "definition": config.METRICS[k]["definition"], "id": config.METRICS[k]["id"]} for k in keys],
        "semantic_view": config.SEMANTIC_VIEW, "chart": chart,
        "warnings": [w.get("message", "The agent reported a warning.") for w in result["warnings"]],
        "practice": result.get("source") != "live",
        "raw": json.dumps(result["raw"], indent=2, default=str)[:20000],
    }
