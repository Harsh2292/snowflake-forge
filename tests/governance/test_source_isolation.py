"""Contract §8: the naive OTD query is the only one that reads a source schema. Every
other statement the app sends is a contract pattern (§5.1–5.4) or the DMF results read.

Runs offline: every public forge_data function is called in live mode against a fake
session that records each SQL string and then fails, so each live branch builds its SQL
and falls back to mock.
"""

import inspect

import pytest

from utils import config, forge_data

SOURCE_SCHEMAS = ("ERP_SOURCE", "WMS_SOURCE", "TMS_SOURCE", "SRM_SOURCE")

# Public functions that never send SQL of their own.
NOT_QUERIES = {"pop_notices", "data_mode", "get_session", "validate",
               "get_source_schema_summary"}  # static catalog in both modes (C02)


class RecordingSession:
    def __init__(self):
        self.statements = []

    def sql(self, sql, params=None):
        self.statements.append(sql)
        raise RuntimeError("offline test session")


@pytest.fixture
def statements(monkeypatch):
    session = RecordingSession()
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", session)
    yield session.statements
    forge_data.pop_notices()


CALLS = {
    "get_metric": lambda: [forge_data.get_metric(k, d) for k, dims in config.VALID_PAIRINGS.items()
                           for d in [None, *dims]],
    "get_all_metrics": forge_data.get_all_metrics,
    "compare_across_personas": forge_data.compare_across_personas,
    "get_masking_divergence": lambda: [forge_data.get_masking_divergence(p) for p in config.PERSONA_ROLES],
    "ask_agent": lambda: [forge_data.ask_agent(q) for q in config.CANONICAL_QUESTIONS],
    "get_naive_otd": forge_data.get_naive_otd,
    "get_governed_otd": forge_data.get_governed_otd,
    "get_quality_results": forge_data.get_quality_results,
}


def test_every_query_function_is_exercised():
    """A new forge_data function must be added to CALLS so its SQL is checked too."""
    public = {name for name, fn in inspect.getmembers(forge_data, inspect.isfunction)
              if not name.startswith(("_", "build_")) and fn.__module__ == forge_data.__name__}
    assert public - NOT_QUERIES == set(CALLS)


def test_only_the_naive_otd_query_reads_source_schemas(statements):
    for call in CALLS.values():
        call()
    touching_source = {s for s in statements if any(schema in s.upper() for schema in SOURCE_SCHEMAS)}
    assert touching_source == {forge_data.NAIVE_OTD_SQL}


def test_every_statement_is_a_contract_pattern(statements):
    for call in CALLS.values():
        call()
    allowed = [config.SEMANTIC_VIEW, "SNOWFLAKE.CORTEX.DATA_AGENT_RUN",
               *[f"CALL {p}()" for p in config.PERSONA_SAMPLE_PROCS.values()],
               *[f"CALL {p}()" for p in config.PERSONA_METRIC_PROCS.values()],
               "SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS"]
    for sql in set(statements) - {forge_data.NAIVE_OTD_SQL}:
        assert any(a in sql for a in allowed), f"not a contract query pattern:\n{sql}"
