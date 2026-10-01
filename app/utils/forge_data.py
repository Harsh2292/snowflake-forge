"""The only module that talks to Snowflake. Every UI tab and test goes through here.

Each public function has a mock branch and a live branch, selected by
config.USE_MOCK_DATA. A failing live branch never raises to the UI: it records a Notice
(read with pop_notices()) and returns mock data instead, so the demo survives a network
drop on stage.

DataFrames carry df.attrs["source"] = "mock" | "live" | "mock_fallback" so the UI can
label what it shows. This module never imports Streamlit, so it can be tested alone.
"""

import json
import logging
import os
import re
import threading
import time
from dataclasses import dataclass

import pandas as pd

from . import config, mock_data, source_catalog
from .agent_response import paused_result, parse_agent_response

PERSONAS = list(config.PERSONA_ROLES)
log = logging.getLogger("forge")  # WARNING lines reach Community Cloud's log panel (stderr)


# ── Notices and mode ─────────────────────────────────────────────────────────

@dataclass
class Notice:
    label: str
    message: str
    error_code: object = None


# Per thread: Streamlit runs each visitor's script run in its own thread, so on a public
# app one visitor's fallback never shows up on another visitor's screen.
_local = threading.local()


def _notices() -> list[Notice]:
    if not hasattr(_local, "notices"):
        _local.notices = []
    return _local.notices


def pop_notices() -> list[Notice]:
    """Fallback warnings since the last call, for the UI to display."""
    drained = list(_notices())
    _notices().clear()
    return drained


def add_notices(notices) -> None:
    """Hand notices from a worker thread to this one (router.run_parallel)."""
    _notices().extend(notices)


def data_mode() -> str:
    return "mock" if config.USE_MOCK_DATA else "live"


# ── Session ──────────────────────────────────────────────────────────────────
# One session per process, shared by every visitor. Where it comes from, in order:
#   1. Streamlit in Snowflake: get_active_session()
#   2. Streamlit Community Cloud: the [connections.snowflake] secrets, key-pair JWT (C15)
#   3. Local development: the named connection in SNOWFLAKE_CONNECTION_NAME

_session = None
_connection: dict | None = None  # the [connections.snowflake] secrets, set by configure()
_login = {"failed_at": None, "error": ""}
_session_lock = threading.Lock()

_PASSED_THROUGH = ("account", "user", "role", "warehouse", "database", "schema")


def configure(connection=None, settings=None) -> None:
    """Called by streamlit_app.py on every run, with the secrets sections as plain dicts.
    Live mode is the default wherever Snowflake is reachable: in SiS, or with a secrets
    connection. `[forge] mode = "mock"` (or "live") in secrets overrides that."""
    global _connection
    _connection = dict(connection) if connection else None
    mode = str((settings or {}).get("mode", "")).strip().lower()
    if mode in ("live", "mock"):
        config.USE_MOCK_DATA = mode == "mock"
    elif _connection or _in_snowflake():
        config.USE_MOCK_DATA = False


_sis = {"checked": False, "session": None}


def _in_snowflake() -> bool:
    if not _sis["checked"]:
        _sis["checked"] = True
        try:
            from snowflake.snowpark.context import get_active_session
            _sis["session"] = get_active_session()
        except Exception:
            _sis["session"] = None
    return _sis["session"] is not None


def session_params(section) -> dict:
    """Snowpark/connector parameters from the [connections.snowflake] secrets section.
    The private key arrives as PEM text (Community Cloud has no key file) and is passed as
    DER bytes, which every connector version accepts (docs/references/community_cloud.md §4).
    Errors name missing keys, never values."""
    section = dict(section or {})
    missing = [k for k in ("account", "user") if not section.get(k)]
    if not (section.get("private_key") or section.get("private_key_file")):
        missing.append("private_key")
    if missing:
        raise ValueError(f"Snowflake secrets are missing: {', '.join(missing)}")
    params = {k: section[k] for k in _PASSED_THROUGH if section.get(k)}
    params.setdefault("warehouse", config.WAREHOUSE)
    params.setdefault("database", config.DATABASE)
    if section.get("private_key"):
        params["private_key"] = _der_private_key(section["private_key"], section.get("private_key_passphrase"))
    else:
        params["private_key_file"] = section["private_key_file"]
        if section.get("private_key_file_pwd"):
            params["private_key_file_pwd"] = section["private_key_file_pwd"]
    params.update({
        "authenticator": "SNOWFLAKE_JWT",
        "client_session_keep_alive": True,
        "login_timeout": config.LOGIN_TIMEOUT_SECONDS,
        "session_parameters": {"STATEMENT_TIMEOUT_IN_SECONDS": config.STATEMENT_TIMEOUT_SECONDS,
                               "QUERY_TAG": "forge_app"},
    })
    return params


_PEM_BLOCK = re.compile(r"-----BEGIN ([A-Z0-9 ]+)-----(.*?)-----END \1-----", re.S)


def pem_text(text: str) -> str:
    """The key as clean PEM, repairing what a paste into a secrets box does to it: indented
    lines, literal "\\n" in a one-line value, the whole key on one line. Errors say what's
    wrong in words and never contain key material."""
    text = str(text or "").replace("\\n", "\n")
    block = _PEM_BLOCK.search(text)
    bare = re.sub(r"\s+", "", text)
    if not block and len(bare) > 100 and re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", bare):
        # the body pasted without its BEGIN / END lines (1 Oct): wrap it
        text = f"-----BEGIN PRIVATE KEY-----\n{bare}\n-----END PRIVATE KEY-----"
        block = _PEM_BLOCK.search(text)
    if not block:
        raise ValueError("private_key in the Snowflake secrets has no '-----BEGIN PRIVATE KEY-----' "
                         "… '-----END PRIVATE KEY-----' block: paste the whole of rsa_key.p8")
    kind, body = block.group(1).strip(), re.sub(r"\s+", "", block.group(2))
    if "PUBLIC" in kind:
        raise ValueError("private_key in the Snowflake secrets is a PUBLIC key: paste rsa_key.p8 "
                         "(the private key), not rsa_key.pub")
    if "PRIVATE" not in kind:
        raise ValueError(f"private_key in the Snowflake secrets is a {kind} block, not a private key")
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "\n".join([f"-----BEGIN {kind}-----", *lines, f"-----END {kind}-----", ""])


def _der_private_key(text: str, passphrase=None) -> bytes:
    from cryptography.hazmat.primitives import serialization
    password = passphrase.encode() if isinstance(passphrase, str) and passphrase else None
    pem = pem_text(text)
    if "ENCRYPTED" in pem.splitlines()[0] and password is None:
        raise ValueError("private_key in the Snowflake secrets is encrypted: add private_key_passphrase, "
                         "or make the key with -nocrypt (deploy/RUNBOOK.md §1)")
    try:
        key = serialization.load_pem_private_key(pem.encode(), password=password)
    except Exception:
        # from None: never chain an exception that could carry key material into a log
        raise ValueError("private_key in the Snowflake secrets is not a readable PEM private key "
                         "(its text was damaged, or it's incomplete)") from None
    return key.private_bytes(encoding=serialization.Encoding.DER,
                             format=serialization.PrivateFormat.PKCS8,
                             encryption_algorithm=serialization.NoEncryption())


def get_session():
    """The shared Snowpark session, created on first use (see the order above)."""
    global _session
    if _session is not None:
        return _session
    with _session_lock:
        if _session is None:
            _session = _new_session()
    return _session


def _new_session():
    if _in_snowflake():
        return _sis["session"]
    from snowflake.snowpark import Session
    if _connection:
        failed_at = _login["failed_at"]
        if failed_at is not None and time.monotonic() - failed_at < config.LOGIN_RETRY_SECONDS:
            raise RuntimeError(f"Snowflake login failed moments ago ({_login['error']}); not retrying yet")
        try:
            session = Session.builder.configs(session_params(_connection)).create()
        except Exception as exc:
            _login["failed_at"] = time.monotonic()
            _login["error"] = (str(exc).splitlines() or [type(exc).__name__])[0][:300]
            log.warning("forge: Snowflake login as %s failed: %s", _connection.get("user"), _login["error"])
            raise
        _login["failed_at"] = None
        return session
    name = os.environ.get("SNOWFLAKE_CONNECTION_NAME")
    if not name:
        raise RuntimeError("No active Snowflake session, no secrets connection, and SNOWFLAKE_CONNECTION_NAME is unset")
    return Session.builder.config("connection_name", name).create()


# Connector / server codes for a session that is gone: 390111 session no longer exists,
# 390112 / 390114 token expired, 250001 / 250002 connection failed / closed.
_GONE_CODES = {"390111", "390112", "390114", "250001", "250002"}
_GONE_WORDS = ("token has expired", "session no longer exists", "connection is closed")


def _session_gone(exc: Exception) -> bool:
    code = str(getattr(exc, "sql_error_code", None) or getattr(exc, "errno", None) or "")
    return code in _GONE_CODES or any(w in str(exc).lower() for w in _GONE_WORDS)


def _drop_session() -> bool:
    """Forget a dead session so the next call logs in again. False if there was none, or
    if it's the SiS session (that one can't be replaced from here)."""
    global _session
    with _session_lock:
        dead, _session = _session, None
    if dead is None or dead is _sis["session"]:
        return False
    try:
        dead.close()
    except Exception:
        pass
    return True


# ── SQL builders (pure; identifiers only ever come from the config allow-lists) ──

def validate(metric_key: str, dimension=None) -> None:
    if metric_key not in config.METRICS:
        raise ValueError(f"Unknown metric {metric_key!r}; expected one of {list(config.METRICS)}")
    if dimension is not None and dimension not in config.VALID_PAIRINGS[metric_key]:
        raise ValueError(f"{metric_key} cannot be broken down by {dimension} (contract §4 pairings)")


def default_where(metric_key: str) -> str:
    """Contract §3a / §5.1: the default time window of a metric (no period named)."""
    if metric_key not in config.WINDOW_DATE:
        return config.LATEST_SNAPSHOT
    date = config.WINDOW_DATE[metric_key]
    months = config.WINDOW_MONTHS
    return (f"{date} > DATEADD(month, -{months}, CURRENT_DATE())\n"
            f"    AND {date} <= CURRENT_DATE()")


def _window_groups(keys) -> list[list[str]]:
    """Metrics that share a default window, in contract order. One SEMANTIC_VIEW call per
    group: one WHERE can't apply a ship-date and an order-date window at once (§5.1)."""
    groups: dict[str, list[str]] = {}
    for key in keys:
        groups.setdefault(default_where(key), []).append(key)
    return list(groups.values())


def build_metric_sql(metric_keys, dimension=None) -> str:
    """Contract §5.1 / §5.2 query for one or more metrics that share a default window,
    optionally by one dimension, with the §3a time rule applied."""
    keys = [metric_keys] if isinstance(metric_keys, str) else list(metric_keys)
    for key in keys:
        validate(key, dimension)
    if len(_window_groups(keys)) > 1:
        raise ValueError(f"{keys} have different default windows; query them separately (contract §5.1)")
    metric_ids = ",\n          ".join(config.METRICS[k]["id"] for k in keys)
    where = default_where(keys[0])
    if dimension is None:
        return (f"SELECT * FROM SEMANTIC_VIEW(\n  {config.SEMANTIC_VIEW}\n"
                f"  METRICS {metric_ids}\n  WHERE {where}\n)")
    return (f"SELECT * FROM SEMANTIC_VIEW(\n  {config.SEMANTIC_VIEW}\n"
            f"  DIMENSIONS {dimension}\n  METRICS {metric_ids}\n  WHERE {where}\n"
            f") ORDER BY {config.column_name(dimension).lower()}")


def build_agent_sql() -> str:
    """Contract §5.3 as CR-007 amends it (accepted 2026-09-30): DATA_AGENT_RUN needs its
    request as a constant, so the whole request JSON is bound as the single `?`
    (agent_request()). Building it in SQL with OBJECT_CONSTRUCT is rejected live."""
    return (
        "SELECT TRY_PARSE_JSON(\n"
        "  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(\n"
        f"    '{config.AGENT}',\n"
        "    ?,\n"
        "    TRUE\n"
        "  )\n"
        ") AS response"
    )


def agent_request(question: str) -> str:
    """The value bound to build_agent_sql()'s `?`: one user message, as JSON text.
    json.dumps escapes quotes and newlines, so no question can break out of it."""
    return json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]})


# Contract §8. The ONLY query in the app that reads a source schema.
NAIVE_OTD_SQL = (
    "SELECT COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL))\n"
    "FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK s\n"
    "JOIN SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN\n"
    "WHERE s.DPTBG > DATEADD(month, -12, CURRENT_DATE()) AND s.DPTBG <= CURRENT_DATE()"
)

QUALITY_SQL = (
    "SELECT table_schema, table_name, metric_name, argument_names, value, measurement_time\n"
    "FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS\n"
    f"WHERE table_database = '{config.DATABASE}'\n"
    "QUALIFY ROW_NUMBER() OVER (PARTITION BY reference_id ORDER BY measurement_time DESC) = 1\n"
    "ORDER BY table_name, metric_name"
)


def build_call_sql(procedure_fqn: str) -> str:
    return f"CALL {procedure_fqn}()"


# The agent's data-health tool (CR-006, DATA_SPEC §7.2); ENTITY is bound, never formatted in.
DATA_HEALTH_SQL = f"CALL {config.DATA_HEALTH_PROC}(?)"
HEALTH_ENTITIES = ["suppliers", "parts", "sourcing", "plants", "inventory", "customers",
                   "orders", "order_lines", "shipments"]


# ── Internals ────────────────────────────────────────────────────────────────

def _run(label: str, live_fn, mock_fn):
    """Mock mode → mock. Live mode → live, degrading to mock with a Notice on any failure."""
    if config.USE_MOCK_DATA:
        return _tag(mock_fn(), "mock")
    _local.path = label.split("(")[0]
    for attempt in (1, 2):
        try:
            return _tag(live_fn(), "live")
        except Exception as exc:  # the UI must never see a stack trace on stage
            # A long-lived public app outlives its login: log in again once, then give up.
            if attempt == 1 and _session_gone(exc) and _drop_session():
                log.warning("forge: Snowflake session expired during %s; logging in again", label)
                continue
            code = getattr(exc, "sql_error_code", None) or getattr(exc, "error_code", None)
            message = (str(exc).splitlines() or [type(exc).__name__])[0][:300]
            _notices().append(Notice(label, message, code))
            log.warning("forge[%s]: live call %s failed, showing saved results: %s",
                        current_visitor() or "-", label, message)
            return _tag(mock_fn(), "mock_fallback")


# Query labels (core system rule 9, and "who asked what", CoCo 1 Oct): every query carries
# forge_app:<function>:<visitor>, where <visitor> is a random 8-character id per browser
# session (no personal data). Set per statement, not on the session: all visitors share one
# session, and parallel queries would overwrite a session-wide label.
_tags = {"enabled": True}
_VISITOR = re.compile(r"^[0-9a-f]{8}$")


def set_visitor(visitor_id) -> None:
    """The current visitor for this thread's queries (streamlit_app.py, every run)."""
    _local.visitor = visitor_id if isinstance(visitor_id, str) and _VISITOR.match(visitor_id) else None


def current_visitor():
    return getattr(_local, "visitor", None)


def query_tag(path: str) -> str:
    visitor = current_visitor()
    return f"forge_app:{path}" + (f":{visitor}" if visitor else "")


def _tag(result, source: str):
    if isinstance(result, pd.DataFrame):
        result.attrs["source"] = source
    elif isinstance(result, dict):
        result["source"] = source
    return result


def _query(sql: str, params=None) -> pd.DataFrame:
    # collect() rather than to_pandas(): to_pandas() rejects non-SELECT statements (CALL).
    statement = get_session().sql(sql, params=params)
    if not _tags["enabled"]:
        return pd.DataFrame([row.as_dict() for row in statement.collect()])
    try:
        rows = statement.collect(statement_params={"QUERY_TAG": query_tag(getattr(_local, "path", "query"))})
    except Exception as exc:
        if "query_tag" not in str(exc).lower():
            raise
        _tags["enabled"] = False  # an environment that refuses labels: run unlabelled from now on
        log.warning("forge: query labels refused, running without them")
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
        # One call per default window (§5.1): OTD + landed cost, fill rate, days of inventory.
        parts = [_query(build_metric_sql(group)) for group in _window_groups(config.METRICS)]
        df = pd.concat(parts, axis=1)[_metric_columns()]
        return _numeric(df, _metric_columns())

    return _run("get_all_metrics", live, mock_data.all_metrics_frame)


def compare_across_personas(metric_key=None) -> pd.DataFrame:
    """Each metric computed as each persona role (CR-002 procedures).

    Columns: METRIC, LABEL, PLANNER, BUYER, LOGISTICS, IDENTICAL, where IDENTICAL means
    the values match after rounding to config.CONSISTENCY_DP places. A NULL (None) matches
    only another NULL.
    """
    keys = [metric_key] if metric_key else list(config.METRICS)
    for key in keys:
        validate(key)

    def build(rows_by_persona: dict) -> pd.DataFrame:
        records = []
        for key in keys:
            col = config.column_name(config.METRICS[key]["id"])
            values = {p.upper(): config.as_number(rows_by_persona[p][col]) for p in PERSONAS}
            rounded = {None if v is None else round(v, config.CONSISTENCY_DP) for v in values.values()}
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
    tools_used, tables, warnings, status, raw, source}. status is "paused" when the app's
    role may not use the agent (agent_unavailable()).

    `role` is unused: DATA_AGENT_RUN runs as the app's own role (the owner's in SiS,
    FORGE_APP_ROLE on Community Cloud). Cost limits are the Ask screen's (utils/ask_guard.py).
    """

    def live():
        try:
            df = _query(build_agent_sql(), params=[agent_request(question)])
        except Exception as exc:
            if agent_unavailable(exc):  # the Cortex budget switched Ask off: not a fallback
                log.warning("forge: the agent is not available to this role; Ask is paused")
                return paused_result()
            raise
        raw = df.iloc[0, 0] if not df.empty else None
        if raw is None:
            raise RuntimeError("DATA_AGENT_RUN returned no parseable response")
        return parse_agent_response(json.loads(raw) if isinstance(raw, str) else raw)

    return _run("ask_agent", live, lambda: parse_agent_response(_mock_agent_raw(question)))


# ── Streaming the agent (CR-008, contract §5.3b; docs/references/agent_run_rest.md) ──

class AgentStreamError(RuntimeError):
    """The stream couldn't be used (no token, an HTTP error): fall back to §5.3."""


class StreamInterrupted(AgentStreamError):
    """The stream started, then failed (an error event, the network, no final response).
    The agent has already run and been paid for, so there's no second call (review #12):
    the visitor keeps what was written, marked incomplete, and nothing is cached (#13)."""

    def __init__(self, message: str, text: str = ""):
        super().__init__(message)
        self.text = text


INTERRUPTED_NOTE = "The answer was interrupted before it finished: this is what was written."


def interrupted_result(text: str) -> dict:
    result = paused_result()  # the empty parsed shape
    result.update(answer=text.strip() or "The agent's answer was interrupted before any text arrived.",
                  status="incomplete", warnings=[{"message": INTERRUPTED_NOTE}])
    return result


def agent_run_url(host: str) -> str:
    database, schema, name = config.AGENT.split(".")
    return f"https://{host}/api/v2/databases/{database}/schemas/{schema}/agents/{name}:run"


def agent_stream_body(question: str) -> dict:
    """The §5.3 messages (CR-007's JSON), with "stream": true."""
    return {**json.loads(agent_request(question)), "stream": True}


def sse_events(lines):
    """(event, data) pairs from Server-Sent Event lines: `event:` / `data:` fields, a blank
    line dispatches, `:` starts a comment, several data lines join with a newline."""
    event, data = None, []
    for raw in lines:
        line = (raw.decode("utf-8") if isinstance(raw, bytes) else str(raw)).rstrip("\r\n")
        if not line:
            if data:
                yield event or "message", "\n".join(data)
            event, data = None, []
            continue
        if line.startswith(":"):
            continue
        field, _, value = line.partition(":")
        value = value[1:] if value.startswith(" ") else value
        if field == "event":
            event = value
        elif field == "data":
            data.append(value)
    if data:
        yield event or "message", "\n".join(data)


# Content blocks the stream announces one by one, as the final response holds them.
_STREAM_ITEMS = {"response.text": "text", "response.tool_use": "tool_use",
                 "response.tool_result": "tool_result", "response.table": "table"}


def assemble_stream(events, on_text, on_status=None) -> dict:
    """The agent's raw response from its events: text deltas go to on_text as they arrive,
    and the final `response` event is the whole response, the same shape DATA_AGENT_RUN
    returns. Without it the run didn't finish: StreamInterrupted, with the text so far."""
    items, final, written = [], None, []
    for event, data in events:
        try:
            payload = json.loads(data) if data else {}
        except ValueError:
            continue  # a keep-alive or a line we don't know: skip it, as the docs require
        if event == "response.text.delta":
            if payload.get("text"):
                written.append(payload["text"])
                on_text(payload["text"])
        elif event == "response.status":
            if on_status and payload.get("message"):
                on_status(payload["message"])
        elif event in _STREAM_ITEMS:
            kind = _STREAM_ITEMS[event]
            items.append({"type": "text", "text": payload.get("text", "")} if kind == "text" else {"type": kind, kind: payload})
        elif event == "response":
            final = payload
        elif event == "error":
            raise StreamInterrupted(f"agent error event: {payload.get('code')} {payload.get('message')}", "".join(written))
    if final is None:  # no terminal `response` event: never presented as a complete answer
        raise StreamInterrupted("the stream ended without its final response", "".join(written))
    return final


def _stream_live(question: str, on_text, on_status=None) -> dict:
    import requests  # a Streamlit dependency; imported here so the module loads without it
    connection = get_session().connection
    token, host = getattr(getattr(connection, "rest", None), "token", None), getattr(connection, "host", None)
    if not token or not host:
        raise AgentStreamError("no session token to reuse (SiS warehouse runtime, or not logged in)")
    response = requests.post(
        agent_run_url(host), json=agent_stream_body(question), stream=True,
        timeout=(10, config.STATEMENT_TIMEOUT_SECONDS),
        headers={"Authorization": f'Snowflake Token="{token}"', "Content-Type": "application/json",
                 "Accept": "text/event-stream"})
    with response:
        if response.status_code != 200:
            raise AgentStreamError(f"HTTP {response.status_code}: {response.text[:300]}")
        written = []

        def keep(text):
            written.append(text)
            on_text(text)

        try:
            return assemble_stream(sse_events(response.iter_lines()), keep, on_status)
        except StreamInterrupted:
            raise
        except Exception as exc:  # the network dropped mid-stream: the agent already ran
            raise StreamInterrupted(f"{type(exc).__name__}: {exc}", "".join(written)) from None


def ask_agent_stream(question: str, on_text=None, on_status=None) -> dict:
    """ask_agent, streamed (CR-008): the answer text goes to on_text as the agent writes it,
    on the app's own session (its token, no second login). A failure before the stream
    starts falls back to the §5.3 call, ask_agent(), which also decides "paused" and saved
    results; once it has started, an interruption keeps what was written (no second paid
    call, review #12) and is marked incomplete (never cached, #13). Mock mode has
    nothing to stream. on_status gets the agent's own progress messages ("Planning…").
    A Stop click raises Streamlit's BaseException-based rerun inside a callback: it isn't
    caught here, so the stream simply ends (the request closes with it)."""
    if config.USE_MOCK_DATA:
        return ask_agent(question)
    _local.path = "ask_agent_stream"
    try:
        result = parse_agent_response(_stream_live(question, on_text or (lambda text: None), on_status))
    except Exception as exc:  # the UI must never see a stack trace on stage
        if agent_unavailable(exc):
            log.warning("forge[%s]: the agent is not available to this role; Ask is paused", current_visitor() or "-")
            return _tag(paused_result(), "live")
        if isinstance(exc, StreamInterrupted):
            log.warning("forge[%s]: the agent's stream was interrupted, keeping the partial answer: %s",
                        current_visitor() or "-", str(exc)[:300])
            return _tag(interrupted_result(exc.text), "live")
        message = (str(exc).splitlines() or [type(exc).__name__])[0][:300]
        log.warning("forge[%s]: streaming the agent failed, using DATA_AGENT_RUN: %s", current_visitor() or "-", message)
        return ask_agent(question)
    result["streamed"] = True
    return _tag(result, "live")


def agent_unavailable(exc: Exception) -> bool:
    """The agent call failed because the role may not use the agent. CoCo's Cortex budget
    (sql/05_app_access/02) revokes USAGE at 100%, and Snowflake then says the agent "does
    not exist or not authorized". Ask shows "paused" for this, not the fallback banner."""
    return "does not exist or not authorized" in str(exc).lower()


def _mock_agent_raw(question: str) -> dict:
    match = next((q for q in mock_data.CANNED_QUESTIONS
                  if q.lower().rstrip("?") == question.strip().lower().rstrip("?")), None)
    if match is None:
        return mock_data.agent_response(mock_data.FREE_TEXT_ANSWER)
    metric_key, dimension = mock_data.CANNED_QUESTIONS[match]
    frame = mock_data.metric_frame(metric_key, dimension)
    label = config.METRICS[metric_key]["label"]
    title = label if dimension is None else f"{label} by {config.column_name(dimension).replace('_', ' ').title()}"
    others = [q for q in mock_data.CANNED_QUESTIONS if q != match]
    at = list(mock_data.CANNED_QUESTIONS).index(match)
    return mock_data.agent_response(
        mock_data.canned_answer(metric_key, dimension, frame),
        sql=build_metric_sql(metric_key, dimension), frame=frame, title=title,
        suggestions=(others[at:] + others[:at])[:3])  # the next canonical questions, like the agent's


def get_naive_otd():
    """OTD using ERP's promised date (the wrong one). Contract §8, for Tab 3. None if NULL."""
    return _run("get_naive_otd",
                lambda: config.as_number(_query(NAIVE_OTD_SQL).iloc[0, 0]),
                lambda: mock_data.MOCK_NAIVE_OTD)


def get_governed_otd():
    """OTD from the semantic view (the authoritative one). Contract §8, for Tab 3. None if NULL."""
    df = get_metric("on_time_delivery_rate")
    return config.as_number(df.iloc[0, 0])


def get_source_schema_summary() -> pd.DataFrame:
    """The four source systems' cryptic columns and their governed names. Static in both modes."""
    return _tag(source_catalog.catalog(), data_mode())


def get_data_health(entity: str = "ALL") -> dict:
    """SEMANTIC.SP_DATA_HEALTH(entity): freshness, the as-of date and data-quality status,
    in the DATA_SPEC §7.2 shape ({entity, as_of_date, status, summary, entities: [...]})."""
    if entity != "ALL" and entity not in HEALTH_ENTITIES:
        raise ValueError(f"Unknown entity {entity!r}; expected one of {HEALTH_ENTITIES} or ALL")

    def live():
        df = _query(DATA_HEALTH_SQL, params=[entity])
        raw = df.iloc[0, 0] if not df.empty else None
        data = json.loads(raw) if isinstance(raw, str) else raw
        if not isinstance(data, dict):
            raise RuntimeError("SP_DATA_HEALTH returned no JSON object")
        return data

    return _run("get_data_health", live, lambda: mock_data.data_health(entity))


# DMF value expectations, judged by layer (DATA_SPEC §7.2): zero is expected only in the
# cleaned data (CONFORMED, and the GOVERNED views on it). In the raw SOURCE schemas the
# injected defects are real and expected, so those results are informational. FRESHNESS and
# ROW_COUNT are informational everywhere: demo data is loaded once, so its age only grows.
# NULL_COUNT is informational too: the one on CONFORMED (promised_delivery_date, E01) counts
# rows kept on purpose and left out of on-time delivery, so it's non-zero by rule (C10).
_QUALITY_EXPECT_ZERO = {"DUPLICATE_COUNT", "DMF_ORPHAN_ORDER_LINES", "DMF_ORPHAN_SHIPMENTS",
                        "DMF_OVERSHIP_COUNT", "DMF_NEGATIVE_ON_HAND_COUNT", "DMF_TEST_RECORD_COUNT",
                        "DMF_NONCONTRACT_CODE_COUNT"}


def get_quality_results() -> pd.DataFrame:
    """Latest result per DMF association. Columns: TABLE_SCHEMA, TABLE_NAME, METRIC_NAME,
    ARGUMENT_NAMES, VALUE, MEASUREMENT_TIME, STATUS (PASS / FAIL / INFO)."""

    def live():
        df = _query(QUALITY_SQL)
        if df.empty:
            return pd.DataFrame(columns=["TABLE_SCHEMA", "TABLE_NAME", "METRIC_NAME", "ARGUMENT_NAMES",
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
        if config.as_number(row["VALUE"]) is None:
            return "INFO"  # not measured yet: neither a pass nor a failure
        if str(row.get("TABLE_SCHEMA", "")).upper().endswith("_SOURCE"):
            return "INFO"  # raw data: defects are expected here and repaired downstream
        if name in _QUALITY_EXPECT_ZERO:
            return "PASS" if row["VALUE"] == 0 else "FAIL"
        return "INFO"

    df["STATUS"] = df.apply(status, axis=1) if not df.empty else pd.Series(dtype=str)
    return df
