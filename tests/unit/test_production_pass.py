"""C09: the app on realistic data. Missing values, long results, JSON safety, dependency
pins. (The live code paths against real captured answers: tests/artifacts/test_replay_live.py.)
"""

import json
import re
from pathlib import Path

import pandas as pd
import pytest
import streamlit as st

from ui import payloads, theme, view
from utils import agent_response, config, forge_data, mock_data

APP = Path(__file__).resolve().parents[2] / "app"


@pytest.fixture(autouse=True)
def mock_mode(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    st.cache_data.clear()


# ── Missing values ───────────────────────────────────────────────────────────

@pytest.mark.parametrize("value", [None, float("nan"), pd.NA, "", "abc"])
def test_missing_values_read_as_none_and_show_as_a_dash(value):
    assert config.as_number(value) is None
    assert config.format_value("fill_rate", value) == config.MISSING


def test_numbers_still_format_as_before():
    assert config.as_number("0.5") == 0.5
    assert config.format_value("fill_rate", 0.9265) == "92.7%"
    assert config.format_value("avg_landed_cost", 518.97125) == "$518.97"


def test_personas_compare_null_only_with_null(monkeypatch):
    real = mock_data.persona_metrics_row

    def with_nulls(persona):
        row = real(persona)
        row["FILL_RATE"] = None                                   # NULL for all three: identical
        row["AVG_LANDED_COST"] = None if persona == "Buyer" else 1.0  # NULL for one: differs
        return row

    monkeypatch.setattr(mock_data, "persona_metrics_row", with_nulls)
    grid = forge_data.compare_across_personas().set_index("METRIC")
    assert grid.loc["fill_rate", "IDENTICAL"]
    assert not grid.loc["avg_landed_cost", "IDENTICAL"]


def test_practice_data_mirrors_the_real_order_status_shape():
    """Art 05: fill rate is NULL for OPEN/CANCELLED; shipment metrics exist only for shipped orders."""
    fill = mock_data.metric_frame("fill_rate", "orders.order_status").set_index("ORDER_STATUS")["FILL_RATE"]
    assert fill[["OPEN", "CANCELLED"]].isna().all() and fill[["SHIPPED", "DELIVERED"]].notna().all()
    otd = mock_data.metric_frame("on_time_delivery_rate", "orders.order_status")
    assert set(otd["ORDER_STATUS"]) == {"SHIPPED", "DELIVERED"}


def test_explore_offers_order_status_where_the_contract_allows_it():
    data = payloads.explore("mock")
    for key, items in data["breakdowns"].items():
        status = next(i for i in items if i["id"] == "status")
        assert status["allowed"] == ("orders.order_status" in config.VALID_PAIRINGS[key])
    fill = next(i for i in data["breakdowns"]["fill_rate"] if i["id"] == "status")
    assert [r["value"] is None for r in fill["rows"]] == [False, False, True, True]


def test_views_never_receive_nan():
    """JSON.parse rejects NaN, which would blank the screen: view.build turns it into null."""
    document = view.build("explore", {"rows": [float("nan"), 1.5, {"x": float("inf")}]}, theme.LIGHT)
    raw = document.split('id="forge-data">')[1].split("</script>")[0]
    assert json.loads(raw) == {"rows": [None, 1.5, {"x": None}]}


# ── Long results ─────────────────────────────────────────────────────────────

def result_set(rows: int, label="ORDER_DATE"):
    return {"resultSetMetaData": {"numRows": rows, "rowType": [{"name": label, "type": "DATE"},
                                                               {"name": "FILL_RATE", "type": "FIXED"}]},
            "data": [[f"2016-01-{i % 28 + 1:02d}#{i:05d}", "0.93"] for i in range(rows)]}


def test_agent_tables_are_capped_but_keep_their_true_row_count():
    resp = {"content": [{"type": "tool_result", "tool_result": {"content": [{"json": {
        "sql": "SELECT 1", "result_set": result_set(3650)}}]}}]}
    parsed = agent_response.parse_agent_response(resp)
    assert len(parsed["tables"][0]) == agent_response.MAX_TABLE_ROWS
    assert parsed["row_counts"] == [3650]


def test_answer_chart_shows_the_most_recent_rows_of_a_time_series():
    table = [{"ORDER_DATE": f"2026-{m:02d}-01", "FILL_RATE": 0.9} for m in range(1, 13)] + \
            [{"ORDER_DATE": f"2025-{m:02d}-01", "FILL_RATE": 0.9} for m in range(1, 13)]
    data = payloads.answer("q", {"answer": "a", "sql": "s", "metric_used": ["fill_rate"], "tables": [table],
                                 "row_counts": [3650], "verified_query_used": True, "warnings": [],
                                 "raw": {}, "source": "live"})
    labels = [r["label"] for r in data["chart"]["rows"]]
    assert len(labels) == payloads.BARS_SHOWN and labels == sorted(labels) and labels[0] == "2026-01-01"
    assert data["chart"]["total"] == 3650


def test_answer_chart_keeps_a_null_value_as_missing():
    table = [{"ORDER_STATUS": "SHIPPED", "FILL_RATE": 0.92}, {"ORDER_STATUS": "OPEN", "FILL_RATE": None}]
    data = payloads.answer("q", {"answer": "a", "sql": "s", "metric_used": ["fill_rate"], "tables": [table],
                                 "row_counts": [2], "verified_query_used": None, "warnings": [],
                                 "raw": {}, "source": "live"})
    assert [r["value"] for r in data["chart"]["rows"]] == [0.92, None]


# ── Dependencies ─────────────────────────────────────────────────────────────

def test_environment_yml_and_requirements_pin_the_same_streamlit():
    conda = re.search(r"streamlit=([\d.]+)", (APP / "environment.yml").read_text(encoding="utf-8")).group(1)
    pip = re.search(r"streamlit==([\d.]+)", (APP / "requirements.txt").read_text(encoding="utf-8")).group(1)
    assert conda == pip
