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
    """Art 05 (B09): fill rate is NULL for OPEN/CANCELLED; shipment metrics exist only for
    orders that have shipments (never OPEN; the B08c data has shipments on a few orders
    cancelled after shipping)."""
    fill = mock_data.metric_frame("fill_rate", "orders.order_status").set_index("ORDER_STATUS")["FILL_RATE"]
    assert fill[["OPEN", "CANCELLED"]].isna().all() and fill[["SHIPPED", "DELIVERED"]].notna().all()
    otd = mock_data.metric_frame("on_time_delivery_rate", "orders.order_status")
    assert set(otd["ORDER_STATUS"]) == {"SHIPPED", "DELIVERED", "CANCELLED"}


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


def _answer(tables, **extra):
    return payloads.answer("q", {"answer": "a", "sql": "s", "metric_used": [], "tables": tables,
                                 "row_counts": [len(t) for t in tables], "verified_query_used": None,
                                 "warnings": [], "raw": {}, "source": "live", **extra})


def test_a_combined_answer_charts_every_table_that_can_be_charted():
    """1 Oct: the agent put the one-row shipment count first, so the tier breakdown after it
    got no chart. Every table with two or more rows gets its own chart now."""
    count = [{"SHIPMENT_COUNT": 95513}]
    tiers = [{"SUPPLIER_TIER": "1", "AVG_LEAD_TIME_DAYS": 11.2}, {"SUPPLIER_TIER": "2", "AVG_LEAD_TIME_DAYS": 22.8},
             {"SUPPLIER_TIER": "3", "AVG_LEAD_TIME_DAYS": 30.0}]
    data = _answer([count, tiers])
    assert len(data["charts"]) == 1 and data["chart"] is data["charts"][0]
    chart = data["chart"]
    assert chart["kind"] == "bars" and chart["format"] == "number" and chart["axis"] == "Supplier tier"
    assert [r["label"] for r in chart["rows"]] == ["1", "2", "3"]  # the agent's order is kept


def test_periods_are_columns_and_metric_columns_keep_their_format():
    quarters = [{"ORDER_YEAR_QUARTER": q, "ON_TIME_DELIVERY_RATE": v} for q, v in
                [("2025-Q4", 0.87), ("2026-Q1", 0.88), ("2026-Q2", 0.86)]]
    regions = [{"PLANT_REGION": r, "FILL_RATE": v} for r, v in [("AMER", 0.92), ("APAC", 0.93)]]
    data = _answer([quarters, regions])
    assert [c["kind"] for c in data["charts"]] == ["columns", "bars"]
    assert [c["format"] for c in data["charts"]] == ["percent", "percent"]


def test_an_instant_breakdown_is_drawn_highest_first_unless_ranked():
    regions = [{"PLANT_REGION": r, "FILL_RATE": v} for r, v in [("AMER", 0.92), ("APAC", 0.93), ("EMEA", 0.91)]]
    plain = _answer([regions], route="instant")
    assert [r["label"] for r in plain["chart"]["rows"]] == ["APAC", "AMER", "EMEA"]
    ranked = _answer([list(reversed(regions))], route="instant", raw={"ranked": "asc"})
    assert [r["label"] for r in ranked["chart"]["rows"]] == ["EMEA", "APAC", "AMER"]


# ── As-of date and time window (contract §3a) ────────────────────────────────

def test_every_screen_states_the_window_and_the_as_of_date():
    from streamlit.testing.v1 import AppTest
    for step in ["problem", "same", "explore", "health", "ask"]:
        at = AppTest.from_file(str(APP / "streamlit_app.py"), default_timeout=30)
        at.session_state["step"] = step
        at.run()
        line = next(m.value for m in at.markdown if "sf-asof" in m.value)
        assert "Data as of 29 Sep 2026" in line and "last 12 months" in line, step


def test_a_practice_as_of_date_is_never_shown_as_live(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", None)
    monkeypatch.delenv("SNOWFLAKE_CONNECTION_NAME", raising=False)
    assert payloads.as_of("live") == ""
    assert payloads.as_of("mock") == "29 Sep 2026"


def test_explore_labels_each_metric_with_its_window():
    windows = {m["key"]: m["window"] for m in payloads.explore("mock")["metrics"]}
    assert windows == {"on_time_delivery_rate": "last 12 months", "fill_rate": "last 12 months",
                       "days_of_inventory": "latest snapshot", "avg_landed_cost": "last 12 months"}


# ── Dependencies ─────────────────────────────────────────────────────────────

def test_environment_yml_and_requirements_pin_the_same_streamlit():
    sis = APP.parent / "deploy" / "sis" / "environment.yml"  # moved out of app/ (C15)
    conda = re.search(r"streamlit=([\d.]+)", sis.read_text(encoding="utf-8")).group(1)
    pip = re.search(r"streamlit==([\d.]+)", (APP / "requirements.txt").read_text(encoding="utf-8")).group(1)
    assert conda == pip


# ── Data health at real scale (C6b: 77 DMF results in art 10) ────────────────

def test_health_shows_one_row_per_kind_of_check_and_fits_its_view():
    data = payloads.health("mock")
    results = forge_data.get_quality_results()
    assert len(results) == 77 and len(data["checks"]) == 17  # ROW_COUNT / FRESHNESS live in the table
    kinds = {(c["name"], bool(c["note"])) for c in data["checks"]}
    assert len(kinds) == len(data["checks"])
    assert all(not c["note"] for c in data["checks"][:9]) and all(c["note"] for c in data["checks"][9:])
    tech = " ".join(c["tech"] for c in data["checks"])
    assert "CONFORMED.CUSTOMER, CONFORMED.CUSTOMER" not in tech  # each table named once
    scored = results[results["STATUS"] != "INFO"]
    assert (data["passing"], data["scored"]) == (int((scored["STATUS"] == "PASS").sum()), len(scored))
    assert payloads.health_height(data) > payloads.health_height({**data, "checks": data["checks"][:3]})


# ── External review fixes (1 Oct) ─────────────────────────────────────────────

def test_explore_quarters_carry_their_year():
    """Review #8: a rolling 12-month window spans two years; Q1-Q4 alone would merge them."""
    data = payloads.explore("mock")
    for key, items in data["breakdowns"].items():
        quarter = next(i for i in items if i["id"] == "quarter")
        if quarter["allowed"]:
            assert quarter["rows"] and all(re.fullmatch(r"\d{4}-Q[1-4]", r["name"]) for r in quarter["rows"]), key


def test_the_otd_formula_states_its_denominator():
    """Review #9: delivered shipments WITH a promised date, as the metric counts them."""
    assert "with a promised date" in payloads.FORMULAS["on_time_delivery_rate"]


def test_the_raw_tab_leaves_out_the_agents_thinking():
    """Review #17: the reasoning can paraphrase the agent's instructions."""
    raw = {"content": [{"type": "thinking", "thinking": {"text": "My instructions say: Which tool, when..."}},
                       {"type": "text", "text": "Fill rate is 92.6%."}]}
    data = payloads.answer("q", {"answer": "a", "sql": "", "metric_used": [], "tables": [], "row_counts": [],
                                 "verified_query_used": None, "warnings": [], "raw": raw, "source": "live"})
    assert "Which tool, when" not in data["raw"] and "Fill rate is 92.6%" in data["raw"]


def test_an_agent_query_with_a_forbidden_pairing_is_flagged():
    """Review #2: Snowflake accepts OTD by part category (art 06); the app flags it."""
    from utils import agent_response
    bad = ("SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS parts.category "
           "METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()))")
    good = forge_data.build_metric_sql("on_time_delivery_rate", "plants.plant_region")
    (warning,) = agent_response.pairing_warnings([bad, good])
    assert "on-time delivery down by category" in warning and "contract §4" in warning
    assert agent_response.pairing_warnings([good]) == []
    for q in config.CANONICAL_QUESTIONS:  # nothing the app itself runs is ever flagged
        result = forge_data.ask_agent(q)
        assert not any("contract §4" in w.get("message", "") for w in result["warnings"]), q


def test_a_daily_check_that_did_not_rerun_is_called_out(monkeypatch):
    """Review #10: shown, not hidden. A check on daily data measured 3 days before the latest
    one gets a note; old checks on reference tables don't (they only run when data changes)."""
    import pandas as pd
    real = forge_data.get_quality_results()
    latest = pd.to_datetime(real["MEASUREMENT_TIME"]).max()

    def aged(table_name):
        df = real.copy()
        df.loc[df["TABLE_NAME"] == table_name, "MEASUREMENT_TIME"] = latest - pd.Timedelta(days=3)
        return df

    import streamlit as st
    for table, expect_note in (("SHIPMENT", True), ("SUPPLIER", False)):
        st.cache_data.clear()
        monkeypatch.setattr(forge_data, "get_quality_results", lambda t=table: aged(t))
        note = payloads.health("mock")["stale_note"]
        assert bool(note) is expect_note, table
        if expect_note:
            assert "may not reflect the latest load" in note
    st.cache_data.clear()
