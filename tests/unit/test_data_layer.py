"""C02 gate: the data access layer returns contract-shaped data in mock mode, its SQL
matches docs/CONTRACT.md, and live failures degrade to mock without raising.

The contract rules themselves (pairings, masking, cross-persona consistency, ranges) are
tested once, in mock and live variants, under tests/consistency, governance and semantic.
"""

import re
from pathlib import Path

import pytest

from utils import agent_response, config, forge_data

ROOT = Path(__file__).resolve().parents[2]

CONTRACT = (ROOT / "docs" / "CONTRACT.md").read_text(encoding="utf-8")
METRIC_COLS = {k: config.column_name(m["id"]) for k, m in config.METRICS.items()}


@pytest.fixture(autouse=True)
def mock_mode(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    forge_data.pop_notices()


def contract_sql(section_heading: str, index: int = 0) -> str:
    """The index-th ```sql block after a CONTRACT.md heading."""
    section = CONTRACT[CONTRACT.index(section_heading):]
    return re.findall(r"```sql\n(.*?)```", section, re.S)[index]


def normalise(sql: str) -> str:
    return re.sub(r"\s+", " ", sql).strip().rstrip(";").strip()


# ── Metrics ──────────────────────────────────────────────────────────────────

def test_all_metrics_is_one_row_of_contract_mock_values():
    df = forge_data.get_all_metrics()
    assert list(df.columns) == list(METRIC_COLS.values())
    assert len(df) == 1
    for key, col in METRIC_COLS.items():
        assert df[col].iloc[0] == config.MOCK_METRICS[key]
    assert df.attrs["source"] == "mock"


def test_metric_by_region_uses_contract_fixture():
    df = forge_data.get_metric("on_time_delivery_rate", "plants.plant_region")
    assert list(df.columns) == ["PLANT_REGION", "ON_TIME_DELIVERY_RATE"]
    for _, row in df.iterrows():
        assert row["ON_TIME_DELIVERY_RATE"] == config.MOCK_BY_REGION[row["PLANT_REGION"]]["on_time_delivery_rate"]


def test_unknown_metric_rejected():
    with pytest.raises(ValueError):
        forge_data.get_metric("revenue")


# ── Personas ─────────────────────────────────────────────────────────────────

def test_compare_across_personas_has_one_row_per_metric():
    df = forge_data.compare_across_personas()
    assert list(df["METRIC"]) == list(config.METRICS)
    assert {"PLANNER", "BUYER", "LOGISTICS", "IDENTICAL"} <= set(df.columns)


def test_compare_across_personas_detects_a_mismatch(monkeypatch):
    real = forge_data.mock_data.persona_metrics_row

    def skewed(persona):
        row = real(persona)
        if persona == "Buyer":
            row["FILL_RATE"] += 1e-5  # differs at the 5th decimal place
        return row

    monkeypatch.setattr(forge_data.mock_data, "persona_metrics_row", skewed)
    df = forge_data.compare_across_personas().set_index("METRIC")
    assert not df.loc["fill_rate", "IDENTICAL"]
    assert df.loc["on_time_delivery_rate", "IDENTICAL"]


def test_masking_accepts_role_names():
    assert forge_data.get_masking_divergence("BUYER_ROLE")["PERSONA"].iloc[0] == "BUYER"


# ── Agent ────────────────────────────────────────────────────────────────────

EXPECTED_METRIC = (["on_time_delivery_rate"] * 3 + ["fill_rate"] * 2
                   + ["days_of_inventory", "avg_landed_cost", "on_time_delivery_rate"])


@pytest.mark.parametrize("question,metric_key", list(zip(config.CANONICAL_QUESTIONS, EXPECTED_METRIC)))
def test_canonical_questions_answer_with_sql_and_lineage(question, metric_key):
    result = forge_data.ask_agent(question)
    assert result["answer"]
    assert result["sql"] and config.SEMANTIC_VIEW in result["sql"]
    assert result["metric_used"] == [metric_key]
    assert result["verified_query_used"] is True
    assert result["tools_used"] == ["SupplyChainAnalyst"]
    assert result["tables"] and result["tables"][0]


def test_question_8_is_the_plant_version_from_cr_003():
    assert config.CANONICAL_QUESTIONS[7] == "Which plants have the worst on-time delivery?"
    result = forge_data.ask_agent(config.CANONICAL_QUESTIONS[7])
    assert "plants.plant_name" in result["sql"]
    # the question must use a pairing the contract allows
    assert "plants.plant_name" in config.VALID_PAIRINGS["on_time_delivery_rate"]


def test_free_text_question_in_mock_mode():
    result = forge_data.ask_agent("How many trucks do we own?")
    assert result["answer"] and result["sql"] is None


# The official non-streaming example from the Cortex Agents Run API docs
# (docs/references/data_agent_run.md §5).
DOC_EXAMPLE = {
    "role": "assistant",
    "content": [
        {"thinking": {"text": "\nThe user is asking about types of products...\n"}, "type": "thinking"},
        {"tool_use": {"client_side_execute": False,
                      "input": {"sql": "WITH __table_a AS (...) SELECT ...",
                                "execution_environment": {"type": "warehouse", "warehouse": "my_warehouse"}},
                      "name": "system_execute_sql", "tool_use_id": "<tool_use_id>", "type": "system_execute_sql"},
         "type": "tool_use"},
        {"tool_result": {"content": [{"json": {
            "query_id": "<query_id>",
            "result_set": {"data": [["Electronics", "3", "3"], ["Furniture", "2", "2"]],
                           "resultSetMetaData": {"format": "jsonv2", "numRows": 2, "partition": 0},
                           "statementHandle": "<statement_handle>"},
            "sql": "WITH __table_a AS (...) SELECT ..."}, "type": "json"}],
            "name": "system_execute_sql", "status": "success",
            "tool_use_id": "<tool_use_id>", "type": "system_execute_sql"},
         "type": "tool_result"},
        {"text": "Based on the data available, there are 2 main types of products...", "type": "text"},
    ],
    "warnings": [{"code": "399569", "message": "TOOL_NOT_ACCESSIBLE: Search1 (cortex_search) - ..."}],
}


def test_parser_handles_official_doc_example():
    parsed = agent_response.parse_agent_response(DOC_EXAMPLE)
    assert parsed["answer"].startswith("Based on the data available")
    assert parsed["sql"] == "WITH __table_a AS (...) SELECT ..."  # deduplicated
    assert parsed["tools_used"] == ["system_execute_sql"]
    # rowType is absent in the doc example → positional names, numeric strings cast
    assert parsed["tables"] == [[{"COL_1": "Electronics", "COL_2": 3, "COL_3": 3},
                                 {"COL_1": "Furniture", "COL_2": 2, "COL_3": 2}]]
    assert parsed["warnings"][0]["code"] == "399569"


def test_parser_tolerates_unknown_types_and_junk():
    parsed = agent_response.parse_agent_response(
        {"content": [{"type": "brand_new_type", "x": 1}, "junk", {"type": "text", "text": "ok"}]})
    assert parsed["answer"] == "ok"
    assert agent_response.parse_agent_response(None)["status"] == "unparseable"
    assert agent_response.parse_agent_response("not json")["status"] == "unparseable"
    assert agent_response.parse_agent_response('{"content": []}')["answer"] == ""


# ── Tab 3 / Tab 5 ────────────────────────────────────────────────────────────

def test_divergence_numbers_differ():
    assert forge_data.get_governed_otd() == config.MOCK_METRICS["on_time_delivery_rate"]
    assert forge_data.get_naive_otd() != forge_data.get_governed_otd()


def test_source_catalog_covers_four_systems_and_the_date_conflict():
    df = forge_data.get_source_schema_summary()
    assert set(df["SYSTEM"]) == {"ERP", "WMS", "TMS", "SRM"}
    # LLD §2 defines 9 tables (HANDOFF says "10 source tables"; flagged to CoCo for B03).
    assert df["SOURCE_TABLE"].nunique() == 9
    conflict = df[df["FLAG"] == "CONFLICT"]
    assert set(conflict["SOURCE_COLUMN"]) == {"ERDAT", "PROM_DLV_DT"}


def test_quality_results_have_status():
    df = forge_data.get_quality_results()
    assert set(df["STATUS"]) <= {"PASS", "FAIL", "INFO"}
    assert (df.loc[df["METRIC_NAME"] != "FRESHNESS", "STATUS"] == "PASS").all()


# ── SQL matches the contract text ────────────────────────────────────────────

def test_metric_only_sql_matches_contract_5_1():
    assert normalise(forge_data.build_metric_sql("on_time_delivery_rate")) == \
        normalise(contract_sql("### 5.1 Metric only"))


def test_metric_by_dimension_sql_matches_contract_5_2():
    assert normalise(forge_data.build_metric_sql("on_time_delivery_rate", "plants.plant_region")) == \
        normalise(contract_sql("### 5.2 Metric by dimension"))


def test_agent_sql_matches_contract_5_3():
    assert normalise(forge_data.build_agent_sql()) == normalise(contract_sql("### 5.3 Agent invocation"))


def test_naive_and_governed_sql_match_contract_8():
    assert normalise(forge_data.NAIVE_OTD_SQL) == normalise(contract_sql("## 8. The Divergence Demo", 0))
    assert normalise(forge_data.build_metric_sql("on_time_delivery_rate")) == \
        normalise(contract_sql("## 8. The Divergence Demo", 1))


def test_persona_sample_calls_match_contract_5_4():
    expected = normalise(contract_sql("### 5.4 Persona sample data"))
    for persona, proc in config.PERSONA_SAMPLE_PROCS.items():
        assert normalise(forge_data.build_call_sql(proc)) + ";" in expected + ";"


# ── Live-mode degradation ────────────────────────────────────────────────────

def test_live_failure_degrades_to_mock_with_notice(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", None)
    monkeypatch.delenv("SNOWFLAKE_CONNECTION_NAME", raising=False)

    df = forge_data.get_all_metrics()
    assert df.attrs["source"] == "mock_fallback"
    assert df[METRIC_COLS["fill_rate"]].iloc[0] == config.MOCK_METRICS["fill_rate"]

    answer = forge_data.ask_agent(config.CANONICAL_QUESTIONS[0])
    assert answer["source"] == "mock_fallback" and answer["answer"]

    notices = forge_data.pop_notices()
    assert [n.label for n in notices] == ["get_all_metrics", "ask_agent"]
    assert forge_data.pop_notices() == []


def test_invalid_pairing_still_raises_in_live_mode(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    with pytest.raises(ValueError):
        forge_data.get_metric("days_of_inventory", "orders.order_date")
