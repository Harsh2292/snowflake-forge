"""Shared test setup: app/ on sys.path, the mock/live `forge` fixture, CoCo's captured
artifacts, and marker defaults.

Contract tests take the `forge` fixture, so each one runs twice:
  [mock]    offline, against the mock data layer
  [live]    against real Snowflake; skipped when no session can be opened
A test can add a third mode with
`@pytest.mark.parametrize("forge", [..., "replay"], indirect=True)`:
  [replay]  offline, the live code path fed the real rows CoCo captured in docs/artifacts

In live and replay mode, forge_data's fallback to mock data (right for the demo) would let
a test pass on mock numbers. The `forge` proxy turns any such fallback into a test failure
that shows the error.
"""

import functools
import json
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

from utils import config, forge_data  # noqa: E402

ARTIFACTS = ROOT / "docs" / "artifacts"


@pytest.hookimpl(tryfirst=True)
def pytest_collection_modifyitems(items):
    """Everything that isn't live or ui is an offline test, so `-m mock` selects it."""
    for item in items:
        if not (item.get_closest_marker("live") or item.get_closest_marker("ui")):
            item.add_marker(pytest.mark.mock)


# ── The live audit's summary (C13): pass/fail per contract section ───────────
# (test path prefix, contract section); the first matching prefix wins.
CONTRACT_SECTIONS = [
    ("tests/semantic/test_metric_ranges.py", "§3 metric ranges · §5.1 shape · §8 naive vs governed"),
    ("tests/semantic/test_dimension_pairings.py", "§4 pairings · §5.2 shape"),
    ("tests/semantic/test_semantic_objects.py", "§1/§3/§4 objects in the semantic view"),
    ("tests/governance/test_masking.py", "§6 masking (§5.4 samples)"),
    ("tests/governance/test_governed_columns.py", "§7 governed view columns"),
    ("tests/consistency/", "§6 invariant: one number for every persona"),
    ("tests/agent/", "§5.3 / §9 agent (CR-007)"),
    ("tests/quality/", "DATA_SPEC §7.2 data health + DMFs"),
]


def live_summary(reports) -> list[str]:
    """Lines for the live audit: per contract section, passed / failed / skipped, then each
    failure with its first message line (which names the Snowflake object). `reports` are
    pytest TestReports (nodeid, outcome, longrepr); only [live…] tests count."""
    outcome = {}
    for r in reports:
        if "[live" not in r.nodeid:
            continue
        if r.outcome == "failed" or r.nodeid not in outcome:
            outcome[r.nodeid] = r
    if not any(r.outcome != "skipped" for r in outcome.values()):
        return []  # nothing ran against Snowflake
    table, failures = {}, []
    for nodeid, r in outcome.items():
        path = nodeid.replace("\\", "/")
        section = next((s for prefix, s in CONTRACT_SECTIONS if path.startswith(prefix)), "other")
        counts = table.setdefault(section, {"passed": 0, "failed": 0, "skipped": 0})
        counts[r.outcome if r.outcome in counts else "failed"] += 1
        if r.outcome == "failed":
            message = getattr(r.longrepr, "reprcrash", None)
            message = message.message if message else str(r.longrepr)
            failures.append(f"  ✗ {nodeid}\n      {message.splitlines()[0][:200] if message else ''}")
    order = [s for _, s in CONTRACT_SECTIONS] + ["other"]
    lines = [f"{'Contract section':<52} passed  failed  skipped"]
    for section in sorted(table, key=order.index):
        c = table[section]
        lines.append(f"{section:<52} {c['passed']:>6}  {c['failed']:>6}  {c['skipped']:>7}")
    return lines + (["", "Failures (each names the object):", *failures] if failures else [])


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    reports = [r for key in ("passed", "failed", "skipped", "error")
               for r in terminalreporter.stats.get(key, []) if hasattr(r, "nodeid")]
    lines = live_summary(reports)
    if lines:
        terminalreporter.section("Live contract audit (C13)")
        for line in lines:
            terminalreporter.write_line(line)


@functools.cache
def _no_live_session() -> str | None:
    """None if a Snowflake session opens, else why not (checked once per run)."""
    try:
        forge_data.get_session()
        return None
    except Exception as exc:  # no connector, no connection name, auth failure, ...
        return str(exc).splitlines()[0][:160]


def load_artifact(name: str) -> dict:
    """docs/artifacts/<name> (capture details plus "payload"); skips the test until CoCo has
    captured it."""
    path = ARTIFACTS / name
    if not path.exists():
        pytest.skip(f"docs/artifacts/{name} not captured yet")
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture
def artifact():
    return load_artifact


class ReplaySession:
    """A Snowpark session that answers the app's statements with rows CoCo captured, typed
    the way Snowpark returns them: columns in result order, NUMBER as Decimal, DATE as
    date, NULL as None. Any other statement raises, as it would if the object didn't exist.

    - art 04: the §5.4 sample calls (SP_SAMPLE_AS_*)
    - art 05: every §5.1/§5.2 SEMANTIC_VIEW query (as the app builds it today, windows
      included; the v1 capture itself had no window), rows in the captured order,
      plus SP_METRICS_AS_* built from its overall values as NUMBER(38,6). That last part is
      a stand-in until art 09 captures the procedures themselves.
    """

    def __init__(self, persona_outputs: dict | None = None, metric_values: dict | None = None):
        self.results = {}
        self.query_tag = None
        for out in (persona_outputs or {}).values():
            self.results[f"CALL {out['procedure']}"] = [
                {c["name"]: _typed(row[c["name"]], c["type"]) for c in out["result_columns"]}
                for row in out["rows"]]
        if metric_values:
            self._add_metric_values(metric_values)

    def _add_metric_values(self, payload: dict):
        by_id = {m["id"]: key for key, m in config.METRICS.items()}
        overall = payload["overall"]
        columns = [config.column_name(m["id"]) for m in config.METRICS.values()]
        for key in config.METRICS:
            col = config.column_name(config.METRICS[key]["id"])
            self.results[forge_data.build_metric_sql(key)] = [{col: _number(overall[col])}]
        for group in forge_data._window_groups(config.METRICS):  # get_all_metrics: one call per window
            cols = [config.column_name(config.METRICS[k]["id"]) for k in group]
            self.results[forge_data.build_metric_sql(group)] = [{col: _number(overall[col]) for col in cols}]
        for metric_id, dims in payload["by_dimension"].items():
            key, metric_col = by_id[metric_id], config.column_name(metric_id)
            for dimension, rows in dims.items():
                dim_col = config.column_name(dimension)
                self.results[forge_data.build_metric_sql(key, dimension)] = [
                    {dim_col: _dimension(dim_col, r[dim_col]), metric_col: _number(r[metric_col])}
                    for r in rows]
        for persona, proc in config.PERSONA_METRIC_PROCS.items():
            self.results[forge_data.build_call_sql(proc)] = [{
                "PERSONA": persona.upper(),
                **{col: _number(round(overall[col], 6)) for col in columns}}]

    def add_agent(self, response: dict):
        """art 07 (B10): every agent call gets this real response. The bound request is
        recorded and must be the CR-007 JSON, or the call fails as Snowflake would."""
        self.agent_response = response
        self.agent_requests = []

    def add_quality(self, payload: dict):
        """art 10 (B12): SP_DATA_HEALTH('ALL' / 'shipments') and the latest DMF results,
        typed as Snowpark returns them (VARIANT and ARRAY as JSON text, TIMESTAMP as datetime)."""
        health = payload["data_health_all"]
        self.health = {"ALL": health.get("FORGE_ADMIN", next(iter(health.values()))),
                       "shipments": payload["data_health_shipments"]}
        self.results[forge_data.QUALITY_SQL] = [{
            "TABLE_SCHEMA": r["table_schema"], "TABLE_NAME": r["table_name"], "METRIC_NAME": r["metric_name"],
            "ARGUMENT_NAMES": json.dumps(r["argument_names"], indent=2), "VALUE": json.dumps(r["value"]),
            "MEASUREMENT_TIME": datetime.strptime(r["measurement_time"], "%Y-%m-%d %H:%M:%S.%f %z"),
        } for r in payload["dmf_results_latest"]]

    def sql(self, sql, params=None):
        if sql == forge_data.build_agent_sql() and getattr(self, "agent_response", None):
            request = json.loads(params[0])  # a question bound on its own isn't JSON: fails here
            assert request["messages"][0]["content"][0]["type"] == "text", request
            self.agent_requests.append(params[0])
            return _Captured([{"RESPONSE": json.dumps(self.agent_response)}])
        if sql == forge_data.DATA_HEALTH_SQL and getattr(self, "health", None):
            if params[0] not in self.health:
                raise RuntimeError(f"SP_DATA_HEALTH({params[0]!r}) not captured in docs/artifacts")
            return _Captured([{"SP_DATA_HEALTH": json.dumps(self.health[params[0]])}])
        if sql not in self.results:
            raise RuntimeError(f"not captured in docs/artifacts: {sql}")
        return _Captured(self.results[sql])


class _Captured:
    def __init__(self, rows: list[dict]):
        self.rows = rows

    def collect(self):
        return [_Row(row) for row in self.rows]


class _Row:
    def __init__(self, values: dict):
        self.values = values

    def as_dict(self):
        return dict(self.values)


def _typed(value, sql_type: str):
    return _number(value) if sql_type.startswith("NUMBER") else value


def _number(value):
    return None if value is None else Decimal(str(value))


def _dimension(column: str, value):
    """JSON keeps dates as text; Snowpark returns DATE columns as datetime.date."""
    if value is not None and column.endswith("_DATE"):
        return date.fromisoformat(value)
    return value


def replay_session() -> ReplaySession:
    """Everything captured so far: art 04 (required), and art 05, 07 and 10 when present."""
    def payload(name):
        path = ARTIFACTS / name
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None

    samples = load_artifact("04_persona_outputs.json")["payload"]
    metrics = payload("05_metric_values.json")
    session = ReplaySession(samples, metrics["payload"] if metrics else None)
    agent = payload("07_agent_response.json")
    if agent:
        session.add_agent(agent.get("payload", agent))
    quality = payload("10_dmf_results.json")
    if quality:
        session.add_quality(quality["payload"])
    return session


class Forge:
    """forge_data, where a live call that falls back to mock data fails the test."""

    def __init__(self, mode: str):
        self.mode = mode
        self.live = mode != "mock"

    def __getattr__(self, name):
        attr = getattr(forge_data, name)
        if not callable(attr):
            return attr

        def call(*args, **kwargs):
            result = attr(*args, **kwargs)
            notices = forge_data.pop_notices()
            if self.live and notices:
                pytest.fail("Live query fell back to mock data:\n"
                            + "\n".join(f"  {n.label}: {n.message}" for n in notices), pytrace=False)
            return result

        return call

    def raw(self, sql: str):
        """Run SQL directly on Snowflake, with no fallback (live only)."""
        assert self.mode == "live", "raw() needs Snowflake"
        return forge_data._query(sql)


@pytest.fixture(params=["mock", pytest.param("live", marks=pytest.mark.live)])
def forge(request, monkeypatch):
    if request.param == "live" and (reason := _no_live_session()):
        pytest.skip(f"No Snowflake connection ({reason}). Set SNOWFLAKE_CONNECTION_NAME to run live tests.")
    if request.param == "replay":
        monkeypatch.setattr(forge_data, "_session", replay_session())
    monkeypatch.setattr(config, "USE_MOCK_DATA", request.param == "mock")
    forge_data.pop_notices()
    yield Forge(request.param)
    forge_data.pop_notices()
