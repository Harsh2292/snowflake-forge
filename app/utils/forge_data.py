"""The only module that talks to Snowflake. Every UI tab and test goes through here.

Each public function has a mock branch and a live branch, selected by
config.USE_MOCK_DATA. A failing live branch never raises to the UI: it records a Notice
(read with pop_notices()) and returns mock data instead, so the demo survives a network
drop on stage.

DataFrames carry df.attrs["source"] = "mock" | "live" | "mock_fallback" so the UI can
label what it shows. This module never imports Streamlit, so it can be tested alone.
"""

import json
import os
from dataclasses import dataclass

import pandas as pd

from . import config, mock_data, source_catalog
from .agent_response import parse_agent_response

PERSONAS = list(config.PERSONA_ROLES)


# ── Notices and mode ─────────────────────────────────────────────────────────

@dataclass
class Notice:
    label: str
    message: str
    error_code: object = None


_notices: list[Notice] = []


def pop_notices() -> list[Notice]:
    """Fallback warnings since the last call, for the UI to display."""
    drained = list(_notices)
    _notices.clear()
    return drained


def data_mode() -> str:
    return "mock" if config.USE_MOCK_DATA else "live"


# ── Session ──────────────────────────────────────────────────────────────────

_session = None


def get_session():
    """Snowpark session: the active one inside SiS, else a local named connection."""
    global _session
    if _session is None:
        try:
            from snowflake.snowpark.context import get_active_session
            _session = get_active_session()
        except Exception:
            from snowflake.snowpark import Session
            name = os.environ.get("SNOWFLAKE_CONNECTION_NAME")
            if not name:
                raise RuntimeError("No active Snowflake session and SNOWFLAKE_CONNECTION_NAME is unset")
            _session = Session.builder.config("connection_name", name).create()
    return _session


# ── SQL builders (pure; identifiers only ever come from the config allow-lists) ──

def validate(metric_key: str, dimension=None) -> None:
    if metric_key not in config.METRICS:
        raise ValueError(f"Unknown metric {metric_key!r}; expected one of {list(config.METRICS)}")
    if dimension is not None and dimension not in config.VALID_PAIRINGS[metric_key]:
        raise ValueError(f"{metric_key} cannot be broken down by {dimension} (contract §4 pairings)")


def build_metric_sql(metric_keys, dimension=None) -> str:
    """Contract §5.1 / §5.2 query for one or more metrics, optionally by one dimension."""
    keys = [metric_keys] if isinstance(metric_keys, str) else list(metric_keys)
    for key in keys:
        validate(key, dimension)
    metric_ids = ",\n          ".join(config.METRICS[k]["id"] for k in keys)
    if dimension is None:
        return (f"SELECT * FROM SEMANTIC_VIEW(\n  {config.SEMANTIC_VIEW}\n"
                f"  METRICS {metric_ids}\n)")
    return (f"SELECT * FROM SEMANTIC_VIEW(\n  {config.SEMANTIC_VIEW}\n"
            f"  DIMENSIONS {dimension}\n  METRICS {metric_ids}\n"
            f") ORDER BY {config.column_name(dimension).lower()}")


def build_agent_sql() -> str:
    """Contract §5.3. The question is bound as the single `?` parameter."""
    return (
        "SELECT TRY_PARSE_JSON(\n"
        "  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(\n"
        f"    '{config.AGENT}',\n"
        "    OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(\n"
        "      OBJECT_CONSTRUCT('role', 'user', 'content',\n"
        "        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', ?)))))::VARCHAR,\n"
        "    TRUE\n"
        "  )\n"
        ") AS response"
    )


# Contract §8. The ONLY query in the app that reads a source schema.
NAIVE_OTD_SQL = (
    "SELECT COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL))\n"
    "FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK s\n"
    "JOIN SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN"
)

QUALITY_SQL = (
    "SELECT table_name, metric_name, argument_names, value, measurement_time\n"
    "FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS\n"
    f"WHERE table_database = '{config.DATABASE}'\n"
    "QUALIFY ROW_NUMBER() OVER (PARTITION BY reference_id ORDER BY measurement_time DESC) = 1\n"
    "ORDER BY table_name, metric_name"
)


def build_call_sql(procedure_fqn: str) -> str:
    return f"CALL {procedure_fqn}()"


# ── Internals ────────────────────────────────────────────────────────────────

def _run(label: str, live_fn, mock_fn):
    """Mock mode → mock. Live mode → live, degrading to mock with a Notice on any failure."""
    if config.USE_MOCK_DATA:
        return _tag(mock_fn(), "mock")
    try:
        return _tag(live_fn(), "live")
    except Exception as exc:  # the UI must never see a stack trace on stage
        code = getattr(exc, "sql_error_code", None) or getattr(exc, "error_code", None)
        _notices.append(Notice(label, str(exc).splitlines()[0][:300], code))
        return _tag(mock_fn(), "mock_fallback")


def _tag(result, source: str):
    if isinstance(result, pd.DataFrame):
        result.attrs["source"] = source
    elif isinstance(result, dict):
        result["source"] = source
    return result


def _query(sql: str, params=None) -> pd.DataFrame:
    # collect() rather than to_pandas(): to_pandas() rejects non-SELECT statements (CALL).
    rows = get_session().sql(sql, params=params).collect()
    return pd.DataFrame([row.as_dict() for row in rows])


def _numeric(df: pd.DataFrame, columns) -> pd.DataFrame:
    for col in columns:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def _metric_columns(keys=None) -> list[str]:
    return [config.column_name(config.METRICS[k]["id"]) for k in (keys or config.METRICS)]


def _persona_key(persona_or_role: str) -> str:
    for key, role in config.PERSONA_ROLES.items():
        if persona_or_role.lower() in (key.lower(), role.lower()):
            return key
    raise ValueError(f"Unknown persona {persona_or_role!r}; expected one of {PERSONAS}")


# ── Public API ───────────────────────────────────────────────────────────────

def get_metric(metric_key: str, dimension=None, role=None) -> pd.DataFrame:
    """One metric, optionally by a dimension. Columns: [DIMENSION,] METRIC (uppercase).

    `role` is accepted for interface stability but unused. Metric definitions are
    role-independent (contract §6); per-persona values come from compare_across_personas().
    """
    sql = build_metric_sql(metric_key, dimension)
    return _run(
        f"get_metric({metric_key}, {dimension})",
        lambda: _numeric(_query(sql), _metric_columns([metric_key])),
        lambda: mock_data.metric_frame(metric_key, dimension),
    )


def get_all_metrics(role=None) -> pd.DataFrame:
    """All four canonical metrics as one row."""

    def live():
        try:
            df = _query(build_metric_sql(list(config.METRICS)))
        except Exception:
            # A combined query is expected to work (references/semantic_view_query.md §5);
            # if it doesn't, query each metric separately.
            df = pd.concat([_query(build_metric_sql(k)) for k in config.METRICS], axis=1)
        return _numeric(df, _metric_columns())

    return _run("get_all_metrics", live, mock_data.all_metrics_frame)


def compare_across_personas(metric_key=None) -> pd.DataFrame:
    """Each metric computed as each persona role (CR-002 procedures).

    Columns: METRIC, LABEL, PLANNER, BUYER, LOGISTICS, IDENTICAL, where IDENTICAL means
    the values match after rounding to config.CONSISTENCY_DP places.
    """
    keys = [metric_key] if metric_key else list(config.METRICS)
    for key in keys:
        validate(key)

    def build(rows_by_persona: dict) -> pd.DataFrame:
        records = []
        for key in keys:
            col = config.column_name(config.METRICS[key]["id"])
            values = {p.upper(): float(rows_by_persona[p][col]) for p in PERSONAS}
            rounded = {round(v, config.CONSISTENCY_DP) for v in values.values()}
            records.append({"METRIC": key, "LABEL": config.METRICS[key]["label"],
                            **values, "IDENTICAL": len(rounded) == 1})
        return pd.DataFrame(records)

    def live():
        rows = {}
        for persona in PERSONAS:
            df = _query(build_call_sql(config.PERSONA_METRIC_PROCS[persona]))
            rows[persona] = _numeric(df, _metric_columns()).iloc[0]
        return build(rows)

    return _run("compare_across_personas", live,
                lambda: build({p: mock_data.persona_metrics_row(p) for p in PERSONAS}))


def get_masking_divergence(role) -> pd.DataFrame:
    """Sample governed rows as one persona sees them (contract §5.4 shape)."""
    persona = _persona_key(role)
    return _run(
        f"get_masking_divergence({persona})",
        lambda: _numeric(_query(build_call_sql(config.PERSONA_SAMPLE_PROCS[persona])),
                         ["UNIT_COST", "CREDIT_LIMIT", "CONTRACT_PRICE"]),
        lambda: mock_data.masking_sample(persona),
    )


def ask_agent(question: str, role=None) -> dict:
    """Ask the Cortex Agent. Returns {answer, sql, metric_used, verified_query_used,
    tools_used, tables, warnings, status, raw, source}.

    `role` is unused: DATA_AGENT_RUN runs with the app owner's rights inside SiS.
    """

    def live():
        df = _query(build_agent_sql(), params=[question])
        raw = df.iloc[0, 0] if not df.empty else None
        if raw is None:
            raise RuntimeError("DATA_AGENT_RUN returned no parseable response")
        return parse_agent_response(json.loads(raw) if isinstance(raw, str) else raw)

    return _run("ask_agent", live, lambda: parse_agent_response(_mock_agent_raw(question)))


def _mock_agent_raw(question: str) -> dict:
    match = next((q for q in mock_data.CANNED_QUESTIONS
                  if q.lower().rstrip("?") == question.strip().lower().rstrip("?")), None)
    if match is None:
        return mock_data.agent_response(mock_data.FREE_TEXT_ANSWER)
    metric_key, dimension = mock_data.CANNED_QUESTIONS[match]
    frame = mock_data.metric_frame(metric_key, dimension)
    return mock_data.agent_response(
        mock_data.canned_answer(metric_key, dimension, frame),
        sql=build_metric_sql(metric_key, dimension), frame=frame)


def get_naive_otd() -> float:
    """OTD using ERP's promised date (the wrong one). Contract §8, for Tab 3."""
    return _run("get_naive_otd",
                lambda: float(_query(NAIVE_OTD_SQL).iloc[0, 0]),
                lambda: mock_data.MOCK_NAIVE_OTD)


def get_governed_otd() -> float:
    """OTD from the semantic view (the authoritative one). Contract §8, for Tab 3."""
    df = get_metric("on_time_delivery_rate")
    return float(df.iloc[0, 0])


def get_source_schema_summary() -> pd.DataFrame:
    """The four source systems' cryptic columns and their governed names. Static in both modes."""
    return _tag(source_catalog.catalog(), data_mode())


# DMF value expectations. FRESHNESS is informational: the demo data is loaded once, so
# its age grows every day and a PASS/FAIL on it would show a false red on stage.
_QUALITY_EXPECT_ZERO = {"NULL_COUNT", "DUPLICATE_COUNT", "DMF_ORPHAN_ORDER_LINES", "DMF_OVERSHIP_COUNT"}


def get_quality_results() -> pd.DataFrame:
    """Latest result per DMF association. Columns: TABLE_NAME, METRIC_NAME,
    ARGUMENT_NAMES, VALUE, MEASUREMENT_TIME, STATUS (PASS / FAIL / INFO)."""

    def live():
        df = _query(QUALITY_SQL)
        if df.empty:
            return pd.DataFrame(columns=["TABLE_NAME", "METRIC_NAME", "ARGUMENT_NAMES",
                                         "VALUE", "MEASUREMENT_TIME"])
        df["ARGUMENT_NAMES"] = df["ARGUMENT_NAMES"].map(_join_json_list)
        return _numeric(df, ["VALUE"])

    return _add_quality_status(_run("get_quality_results", live, mock_data.quality_results))


def _join_json_list(value) -> str:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return value
    return ", ".join(map(str, value)) if isinstance(value, list) else str(value)


def _add_quality_status(df: pd.DataFrame) -> pd.DataFrame:
    def status(row):
        name = str(row["METRIC_NAME"]).upper()
        if name in _QUALITY_EXPECT_ZERO:
            return "PASS" if row["VALUE"] == 0 else "FAIL"
        return "INFO"

    df["STATUS"] = df.apply(status, axis=1) if not df.empty else pd.Series(dtype=str)
    return df
