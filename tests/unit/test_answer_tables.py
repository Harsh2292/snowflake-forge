"""2 Oct: an agent answer must always show its data. The user's screenshots: "top 5 EMEA
suppliers by lead time" came back as SUPPLIER_ID, SUPPLIER_NAME, REGION, LEAD_TIME_DAYS. The
chart read only the first two columns (an ID and a name), found no number, and drew nothing,
so the card showed one sentence and no rows."""

from pathlib import Path

from ui import payloads
from ui.screens import ask
from utils import agent_response

ROOT = Path(__file__).resolve().parents[2]

SUPPLIERS = [
    {"SUPPLIER_ID": "SUP103", "SUPPLIER_NAME": "Kyoto Semiconductor Corp 103", "SUPPLIER_REGION": "EMEA", "AVG_LEAD_TIME_DAYS": 5},
    {"SUPPLIER_ID": "SUP098", "SUPPLIER_NAME": "Pacific Rim Materials 098", "SUPPLIER_REGION": "EMEA", "AVG_LEAD_TIME_DAYS": 6},
    {"SUPPLIER_ID": "SUP041", "SUPPLIER_NAME": "Nordic Alloys 041", "SUPPLIER_REGION": "EMEA", "AVG_LEAD_TIME_DAYS": 7.5},
]


def _result(tables, metrics=()):
    result = agent_response._empty({"content": []}, status="completed")
    return {**result, "answer": "Seven suppliers...", "tables": tables, "row_counts": [len(t) for t in tables],
            "table_titles": [None] * len(tables), "metric_used": list(metrics), "source": "live"}


def test_a_measure_after_an_id_name_and_region_is_charted_by_name():
    card = payloads.answer("Top 5 EMEA suppliers by lead time", _result([SUPPLIERS]))
    chart = card["chart"]
    assert chart and chart["kind"] == "bars"
    assert [r["label"] for r in chart["rows"]] == [s["SUPPLIER_NAME"] for s in SUPPLIERS]
    assert [r["value"] for r in chart["rows"]] == [5, 6, 7.5]
    assert card["grids"] == []


def test_two_columns_still_chart_as_before():
    table = [{"PLANT_REGION": "EMEA", "ON_TIME_DELIVERY_RATE": 0.884}, {"PLANT_REGION": "APAC", "ON_TIME_DELIVERY_RATE": 0.868}]
    chart = payloads.answer("OTD by region", _result([table], ["on_time_delivery_rate"]))["chart"]
    assert chart["axis"] == "Plant region" and chart["format"] == "percent"


def test_a_period_label_with_a_numeric_year_draws_columns():
    table = [{"ORDER_YEAR": 2024, "FILL_RATE": 0.92}, {"ORDER_YEAR": 2025, "FILL_RATE": 0.93}]
    chart = payloads.answer("Fill rate by year", _result([table], ["fill_rate"]))["chart"]
    assert chart["kind"] == "columns" and [r["label"] for r in chart["rows"]] == ["2024", "2025"]


def test_numeric_ids_are_never_the_measure():
    table = [{"ORDER_NUMBER": 1001, "CUSTOMER_NAME": "Acme"}, {"ORDER_NUMBER": 1002, "CUSTOMER_NAME": "Globex"}]
    card = payloads.answer("Orders", _result([table]))
    assert card["chart"] is None and len(card["grids"]) == 1


def test_rows_that_cant_be_charted_show_as_a_table():
    names = [{"SUPPLIER_NAME": s["SUPPLIER_NAME"], "SUPPLIER_REGION": "EMEA"} for s in SUPPLIERS]
    card = payloads.answer("Which suppliers are in EMEA?", _result([names]))
    assert card["chart"] is None
    grid = card["grids"][0]
    assert [c["label"] for c in grid["columns"]] == ["Supplier name", "Supplier region"]
    assert grid["rows"][0] == ["Kyoto Semiconductor Corp 103", "EMEA"] and grid["total"] == 3


def test_a_one_row_lookup_is_a_table_and_a_single_value_is_text_only():
    lookup = [{"ORDER_ID": "ORD000123", "ORDER_STATUS": "SHIPPED", "NET_VALUE_USD": 1520.5}]
    grid = payloads.answer("Order ORD000123", _result([lookup]))["grids"][0]
    assert [c["format"] for c in grid["columns"]] == ["text", "text", "number"]
    assert payloads.answer("How many suppliers?", _result([[{"SUPPLIERS": 150}]]))["grids"] == []


def test_a_grid_shows_ten_rows_and_says_how_many_there_are():
    rows = [{"SUPPLIER_NAME": f"S{i}", "SUPPLIER_TIER": "Tier 1"} for i in range(25)]
    grid = payloads.answer("Suppliers", _result([rows]))["grids"][0]
    assert len(grid["rows"]) == payloads.GRID_ROWS and grid["total"] == 25


def test_the_card_is_tall_enough_for_its_table():
    names = [{"SUPPLIER_NAME": s["SUPPLIER_NAME"], "SUPPLIER_REGION": "EMEA"} for s in SUPPLIERS]
    with_grid = payloads.answer("Which suppliers are in EMEA?", _result([names]))
    without = {**with_grid, "grids": []}
    assert ask._card_height(with_grid) - ask._card_height(without) == ask._grid_height(with_grid["grids"][0])


def test_the_view_renders_grids():
    html = (ROOT / "app" / "ui" / "views" / "answer.html").read_text(encoding="utf-8")
    assert "(D.grids || []).map(gridHtml)" in html


def test_the_agent_lists_rows_instead_of_cutting_them_short():
    """The live answer said "led by" two suppliers when seven matched (the brief-answer rule)."""
    spec = (ROOT / "agent" / "01_agent.sql").read_text(encoding="utf-8")
    response = spec.split("  response: |")[1].split("  sample_questions:")[0]
    assert "Keep answers brief" not in response and "one or two sentences" not in response
    assert "one sentence" not in response  # 2 Oct: it squeezed lists into one line
    assert 'Never shorten the list with "led by"' in response and "Show every row" in response
    assert "markdown tables" in response  # the card shows prose; a pipe table would print raw
    orchestration = spec.split("  orchestration: |")[1].split("  response: |")[0]
    assert "Make one supply_chain_analyst call per question" in orchestration  # speed: no re-checking calls
    assert "short table" not in spec
    assert "TO ROLE FORGE_APP_ROLE;" in spec  # a re-create must not switch Ask off
