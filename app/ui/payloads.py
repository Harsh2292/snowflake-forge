"""Build the data each HTML view needs, from utils.forge_data only.

Every function returns plain JSON-able dicts. They're cached per data mode for
config.SCREEN_CACHE_SECONDS, shared by every visitor, so
switching screens doesn't re-query Snowflake in live mode.
"""

import json

import pandas as pd
import streamlit as st

from utils import config, forge_data, mock_data, router

FORMULAS = {
    "on_time_delivery_rate": "Delivered on or before the promised date ÷ delivered shipments with a promised date",
    "fill_rate": "Quantity shipped ÷ quantity ordered",
    "days_of_inventory": "Average stock on hand ÷ average daily usage",
    "avg_landed_cost": "Average of freight + duties + handling per shipment",
}
UNITS = {"days_of_inventory": "days"}

BREAKDOWNS = [
    ("region", "By region", "Region", "plants.plant_region"),
    ("plant", "By plant", "Plant", "plants.plant_name"),
    ("category", "By product category", "Product category", "parts.category"),
    # year and quarter (2026-Q3): a rolling 12-month window spans two years, and the bare
    # quarter (Q1-Q4) would merge them into one bar (review #8). The agent uses the same one.
    ("quarter", "By quarter", "Quarter", "orders.order_year_quarter"),
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
PRACTICE_NOTE = (f"Last captured Snowflake results ({mock_data.CAPTURED_ON}). Live, each team’s number comes "
                 "from its own query, run under that team’s role (contract §5.4).")


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


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def problem(mode: str) -> dict:
    catalog = forge_data.get_source_schema_summary()
    return {"naive": _num(forge_data.get_naive_otd()), "governed": _num(forge_data.get_governed_otd()),
            "systems": SYSTEMS, "catalog": catalog.to_dict("records")}


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
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


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def same(mode: str) -> dict:
    grid = forge_data.compare_across_personas().set_index("METRIC")
    personas = list(config.PERSONA_ROLES)
    samples = dict(zip(personas, (df for df, _ in router.run_parallel(
        [lambda p=p: forge_data.get_masking_divergence(p) for p in personas], max_workers=len(personas)))))
    personas = [{"key": p.upper(), "label": config.PERSONA_LABELS[p], "desc": config.PERSONA_DESCRIPTIONS[p],
                 "initials": INITIALS[p], "visibility": _visibility(sample)} for p, sample in samples.items()]
    grid_out = {k: {"values": {p: _num(grid.loc[k, p]) for p in ("PLANNER", "BUYER", "LOGISTICS")},
                    "identical": bool(grid.loc[k, "IDENTICAL"])} for k in config.METRICS}
    return {"metrics": metrics_meta(), "grid": grid_out, "personas": personas, "records": _records(samples),
            "dp": config.CONSISTENCY_DP, "practice": PRACTICE_NOTE if grid.attrs.get("source") != "live" else ""}


EXPLORE_WORKERS = 8  # Explore's ~19 breakdown queries run this many at a time (thread-safe session)


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def explore(mode: str) -> dict:
    # Live, the first visit after a restart ran these one by one: minutes on a cold app
    # (1 Oct). They're independent, so they run at once; the cache keeps them for 12 h.
    pairs = [(key, dimension) for key in config.METRICS for *_, dimension in BREAKDOWNS
             if dimension in config.VALID_PAIRINGS[key]]
    frames = dict(zip(pairs, (df for df, _ in router.run_parallel(
        [lambda k=k, d=d: forge_data.get_metric(k, d) for k, d in pairs], max_workers=EXPLORE_WORKERS))))
    breakdowns = {}
    for key in config.METRICS:
        items = []
        for bid, label, dim_name, dimension in BREAKDOWNS:
            allowed = dimension in config.VALID_PAIRINGS[key]
            rows = []
            if allowed:
                df = frames[(key, dimension)]
                rows = [{"name": str(n), "value": _num(v)} for n, v in zip(df[config.column_name(dimension)], df[_metric_col(key)])]
                if bid not in IN_NATURAL_ORDER:
                    rows = _by_value(rows)
            items.append({"id": bid, "label": label, "dim_name": dim_name, "allowed": allowed, "rows": rows,
                          "reason": "" if allowed else f"Not available for {config.METRICS[key]['label'].lower()}: {WHY_NOT[key]}.",
                          "reason_short": WHY_NOT[key]})
        breakdowns[key] = items
    return {"metrics": metrics_meta(), "breakdowns": breakdowns, "bars": BARS_SHOWN}


PLAIN_CHECKS = {
    "NULL_COUNT": ("Missing promised dates, left out of on-time delivery", "missing promised dates"),
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


# Row counts and data age are per table, and the freshness table below the checks shows
# them; one row each here would repeat it for every table (C6b: 77 live DMF results).
IN_FRESHNESS_TABLE = {"ROW_COUNT", "FRESHNESS"}
# Tables the nightly feed changes (raw and cleaned); reference tables rarely change, so their
# checks rightly stay old (DMFs run on change).
DAILY_TABLES = {"VBAK", "VBAP", "VTTK", "MARD", "TCURR", "SALES_ORDER", "ORDER_LINE", "SHIPMENT", "INVENTORY", "FX_RATE"}
STALE_CHECK_HOURS = 48
TABLES_NAMED = 3  # a check row names this many tables, then "+N more"
_STATUS_ORDER = {"FAIL": 0, "PASS": 1, "INFO": 2}


def _check_row(metric: str, raw: bool, group: pd.DataFrame) -> dict:
    """One row per kind of check and layer: every table it runs on, its total, the worst status."""
    name, unit = PLAIN_CHECKS.get(metric, (metric, "problems"))
    values = [v for v in map(_num, group["VALUE"]) if v is not None]
    if not values:
        result = "Not measured yet"
    elif metric == "FRESHNESS":
        result = _age(max(values))
    else:
        result = f"{int(sum(values)):,} {unit}" if unit else f"{int(sum(values)):,}"
    statuses = set(group["STATUS"])
    status = "FAIL" if "FAIL" in statuses else "PASS" if "PASS" in statuses else "INFO"
    where = list(dict.fromkeys(f"{s}.{t}" if s else str(t)  # distinct tables, in order
                               for s, t in zip(group["TABLE_SCHEMA"].fillna(""), group["TABLE_NAME"])))
    shown = ", ".join(where[:TABLES_NAMED]) + (f" +{len(where) - TABLES_NAMED} more" if len(where) > TABLES_NAMED else "")
    columns = ", ".join(a for a in group["ARGUMENT_NAMES"].astype(str) if a)
    tables = f"{len(where)} tables: {shown}" if len(where) > 1 else f"{shown} ({columns})" if columns else shown
    return {"name": f"Raw data: {unit}, handled before use" if raw and unit else name,
            "tech": f"{metric} on {tables}", "result": result, "status": status, "note": RAW_NOTE if raw else ""}


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def health(mode: str) -> dict:
    df = forge_data.get_quality_results()
    if df.empty:
        return {"checks": [], "passing": 0, "scored": 0, "checked": ""}
    df = df.assign(METRIC=df["METRIC_NAME"].astype(str).str.upper(),
                   RAW=df["TABLE_SCHEMA"].fillna("").astype(str).str.upper().str.endswith("_SOURCE"))
    shown = df[~df["METRIC"].isin(IN_FRESHNESS_TABLE)]
    checks = [_check_row(metric, raw, group) for (raw, metric), group in shown.groupby(["RAW", "METRIC"], sort=False)]
    # the cleaned data first (failures first), then the raw data; stable within each
    checks.sort(key=lambda c: (bool(c["note"]), _STATUS_ORDER[c["status"]]))
    scored = df[df["STATUS"] != "INFO"]  # counted per table: every DMF association is one check
    measured = pd.to_datetime(df["MEASUREMENT_TIME"])
    checked = measured.max()
    # Review #10: a check on a daily table measured well before the latest one hasn't run since
    # the data changed, so its "passing" may describe an older load. Said, not hidden.
    daily = df["TABLE_NAME"].astype(str).str.upper().isin(DAILY_TABLES)
    stale = int((daily & (measured < checked - pd.Timedelta(hours=STALE_CHECK_HOURS))).sum())
    stale_note = (f"{stale} check{'s' if stale != 1 else ''} on daily data last ran more than "
                  f"{STALE_CHECK_HOURS} hours before the latest one, so may not reflect the latest load.") if stale else ""
    return {"checks": checks, "passing": int((scored["STATUS"] == "PASS").sum()), "scored": len(scored),
            "checked": f"{checked:%d %b %Y, %H:%M}", "stale_note": stale_note, **_tables_health()}


def health_height(data: dict) -> int:
    """The Data health view's height follows its content (live results vary in number)."""
    rows = len(data.get("checks") or [])
    tables = len(data.get("tables") or [])
    return 470 + 80 * rows + (150 + 40 * tables if tables else 0)


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


@st.cache_data(ttl=config.AS_OF_CACHE_SECONDS, show_spinner=False)
def as_of(mode: str) -> str:
    """The as-of date shown with every metric (contract §3a): the latest business date
    loaded, from SP_DATA_HEALTH. Empty in live mode if the procedure isn't reachable, so a
    practice date is never shown as a live one."""
    data = forge_data.get_data_health("shipments")
    forge_data.pop_notices()  # its absence is shown by the missing date, not a toast
    if mode == "live" and data.get("source") != "live":
        return ""
    return _date_label(data.get("as_of_date"))


def data_version() -> str:
    """The key every cached screen and answer shares: the data mode and the data's as-of
    date (review #5). When the nightly load moves the as-of date, all of them roll over at
    once, instead of each on its own 12-hour clock."""
    mode = forge_data.data_mode()
    return f"{mode}|{as_of(mode)}"


def _chart_window(label_col: str, rows: list[dict]) -> list[dict]:
    """At most BARS_SHOWN rows. A time series keeps its most recent rows, in time order;
    anything else keeps the agent's order (it ranks and limits the rows itself)."""
    if len(rows) <= BARS_SHOWN:
        return rows
    if any(word in label_col.upper() for word in TIME_WORDS):
        return sorted(rows, key=lambda r: r["label"])[-BARS_SHOWN:]
    return rows[:BARS_SHOWN]


def _health_note(data) -> str:
    """One line from the agent's data-health tool output (SP_DATA_HEALTH shape), if it ran."""
    if not isinstance(data, dict) or not data.get("status"):
        return ""
    as_of = f", data as of {_date_label(data['as_of_date'])}" if data.get("as_of_date") else ""
    return f"Data health check: {str(data['status']).upper()}{as_of}"


def _public_raw(raw):
    """The agent response for the Raw tab, without its "thinking" blocks: the orchestrator's
    reasoning can paraphrase its own instructions (review #17). Everything else is data the
    masked app role may already see."""
    if not isinstance(raw, dict) or not isinstance(raw.get("content"), list):
        return raw
    return {**raw, "content": [item for item in raw["content"]
                               if not (isinstance(item, dict) and item.get("type") == "thinking")]}


def _elapsed(seconds) -> str:
    return "" if seconds is None else f"{seconds:.1f} s"


TIME_WORDS = ("DATE", "DAY", "WEEK", "MONTH", "QUARTER", "YEAR")
MAX_CHARTS = 3  # an agent answer to a combined question can carry a table per part


def _value_format(value_col: str, keys: list, single: bool) -> str:
    """The value column's format: the contract metric it names, else (one table) the
    answer's metric, else a plain number (lead time, counts)."""
    for key in config.METRICS:
        if value_col.upper() == _metric_col(key):
            return config.METRICS[key]["format"]
    return config.METRICS[keys[0]]["format"] if keys and single else "number"


def _chart(table: list, total, title, keys: list, single: bool, sort: bool):
    """A chart from one result table (a label column, then a numeric one), or None.
    Periods draw as columns in time order; anything else as horizontal bars, the
    same style as Explore (1 Oct: the old columns looked dated)."""
    if not table or len(table) < 2 or len(table[0]) < 2:
        return None
    label_col, value_col = list(table[0])[:2]
    rows = [{"label": str(r[label_col]), "value": _num(r[value_col])} for r in table]
    if all(r["value"] is None for r in rows) or any(
            r[value_col] is not None and _num(r[value_col]) is None for r in table):
        return None
    is_time = any(word in label_col.upper() for word in TIME_WORDS)
    if sort and not is_time:
        rows = _by_value([{"name": r["label"], "value": r["value"]} for r in rows])
        rows = [{"label": r["name"], "value": r["value"]} for r in rows]
    return {"rows": _chart_window(label_col, rows), "total": total, "kind": "columns" if is_time else "bars",
            "format": _value_format(value_col, keys, single), "axis": label_col.replace("_", " ").capitalize(),
            "title": title or f"{value_col.replace('_', ' ').capitalize()} by {label_col.replace('_', ' ').lower()}"}


def answer(question: str, result: dict, part: str = "") -> dict:
    """One Ask answer, for the answer card view. `question` is the bubble above the card
    (empty under a split question's first card); `part` is the part this card answers."""
    keys = result["metric_used"]
    instant = result.get("route") == "instant"
    tables = result["tables"] or []
    counts = result.get("row_counts") or [len(t) for t in tables]
    titles = result.get("table_titles") or [None] * len(tables)  # the agent's own titles (art 07)
    # an instant answer that isn't ranked is drawn highest first; the agent's order is kept
    sort = instant and not (result.get("raw") or {}).get("ranked")
    charts = [c for c in (_chart(t, n, title, keys, len(tables) == 1, sort)
                          for t, n, title in zip(tables, counts, titles)) if c][:MAX_CHARTS]
    chart = charts[0] if charts else None
    return {
        "question": question, "part": part,
        # which path answered (C14): the instant shortcut or the agent
        "via": router.INSTANT_LABEL if instant else "Supply Chain Agent", "instant": instant,
        "elapsed": _elapsed(result.get("elapsed")),
        "answer": result["answer"] or "The agent returned no text.",
        "sql": result["sql"] or "", "verified": bool(result["verified_query_used"]),
        "metrics": [config.METRICS[k]["label"] for k in keys],
        "definitions": [{"label": config.METRICS[k]["label"], "formula": FORMULAS[k],
                         "definition": config.METRICS[k]["definition"], "id": config.METRICS[k]["id"]} for k in keys],
        "semantic_view": config.SEMANTIC_VIEW, "chart": chart, "charts": charts,
        # what the agent used, in words ("Verified query" has its own chip)
        "tools": [x for x in result.get("tools_used") or [] if x != "Verified query"],
        "health": _health_note(result.get("data_health")),
        "warnings": [w.get("message", "The agent reported a warning.") for w in result["warnings"]],
        "practice": result.get("source") != "live",
        "raw": json.dumps(_public_raw(result["raw"]), indent=2, default=str)[:20000],
    }
