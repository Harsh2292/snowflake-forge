"""C09: the app's live code paths, fed the real answers CoCo captured (art 05, art 04).

Everything here runs in live mode (USE_MOCK_DATA = False) against the replay session in
tests/conftest.py, so a fallback to practice data fails the test. It proves the live
branches handle Snowflake's real shapes: unsorted rows, Decimal numbers, DATE values and
NULL metric values (fill rate for OPEN/CANCELLED orders; OTD on days with nothing
delivered).
"""

import json
import math
from pathlib import Path

import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

from ui import payloads, theme, view
from utils import config, forge_data

APP = Path(__file__).resolve().parents[2] / "app" / "streamlit_app.py"
BY_ID = {m["id"]: k for k, m in config.METRICS.items()}

pytestmark = pytest.mark.parametrize("forge", ["replay"], indirect=True)


@pytest.fixture
def captured(artifact):
    return artifact("05_metric_values.json")["payload"]


@pytest.fixture(autouse=True)
def fresh_cache():
    st.cache_data.clear()


def pairings(captured):
    return [(BY_ID[m], d, rows) for m, dims in captured["by_dimension"].items() for d, rows in dims.items()]


def same(a, b) -> bool:
    a, b = config.as_number(a), config.as_number(b)
    return (a is None and b is None) or (a is not None and b is not None and math.isclose(a, b, abs_tol=1e-9))


def test_every_captured_pairing_goes_through_the_live_path(forge, captured):
    assert len(pairings(captured)) == 55
    for key, dimension, rows in pairings(captured):
        df = forge.get_metric(key, dimension)
        dim_col, metric_col = config.column_name(dimension), config.column_name(config.METRICS[key]["id"])
        assert df.attrs["source"] == "live"
        assert list(df.columns) == [dim_col, metric_col]
        assert len(df) == len(rows)
        for got, want in zip(df.to_dict("records"), rows):
            assert str(got[dim_col]) == str(want[dim_col])
            assert same(got[metric_col], want[metric_col]), (key, dimension, got, want)


def test_null_metric_values_survive_as_missing(forge, captured):
    """The four captured pairings with NULLs keep them: no zero, no crash."""
    with_nulls = [(k, d) for k, d, rows in pairings(captured) if any(v is None for r in rows for v in r.values())]
    assert ("fill_rate", "orders.order_status") in with_nulls
    for key, dimension in with_nulls:
        df = forge.get_metric(key, dimension)
        assert df[config.column_name(config.METRICS[key]["id"])].isna().any()


def test_overall_metrics_and_personas_are_live_and_identical(forge, captured):
    overall = forge.get_all_metrics().iloc[0]
    for col, value in captured["overall"].items():
        assert same(overall[col], value)
    grid = forge.compare_across_personas()
    assert grid.attrs["source"] == "live"
    assert grid["IDENTICAL"].all()


@pytest.mark.parametrize("name", ["fix", "same", "explore"])
def test_screens_build_from_live_data_without_fallback(forge, name):
    data = getattr(payloads, name)("replay")
    assert forge_data.pop_notices() == [], "a live call fell back to practice data"
    json.dumps(data, allow_nan=False)  # NaN would break JSON.parse in the browser
    assert 'id="forge-data"' in view.build(name, data, theme.LIGHT)


def test_explore_shows_missing_fill_rate_for_open_and_cancelled(forge):
    data = payloads.explore("replay")
    status = next(b for b in data["breakdowns"]["fill_rate"] if b["id"] == "status")
    values = {r["name"]: r["value"] for r in status["rows"]}
    assert values["OPEN"] is None and values["CANCELLED"] is None
    assert values["SHIPPED"] is not None and values["DELIVERED"] is not None
    assert [r["value"] is None for r in status["rows"]] == [False, False, True, True]  # missing last


def test_whole_app_runs_live_and_labels_its_source(forge, monkeypatch):
    """AppTest in live mode: screens with captured data say Live; the ones whose objects
    don't exist yet (data quality checks) say practice values, and aren't cached."""
    for step, badge in [("explore", "Live"), ("same", "Live"),
                        ("health", "Practice values (Snowflake unreachable)")]:
        at = AppTest.from_file(str(APP), default_timeout=30)
        at.session_state["step"] = step
        at.run()
        assert not at.exception, at.exception
        header = " ".join(m.value for m in at.markdown)
        assert f'sf-tag">{badge}<' in header, step
    forge_data.pop_notices()


def test_queries_are_tagged_per_path(forge):
    forge_data._query_tag.update(path=None, enabled=True)
    forge.get_metric("fill_rate", "parts.category")
    assert forge_data.get_session().query_tag == "forge_app:get_metric"
    forge.compare_across_personas()
    assert forge_data.get_session().query_tag == "forge_app:compare_across_personas"
