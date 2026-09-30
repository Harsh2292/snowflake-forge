"""DATA_SPEC §7.2 (the data-health tool) and the DMF results, against Snowflake (C13).

Shape and cleaned-data checks run on both mock (the art 10 capture) and live. The freshness
rules (C16: reference data reads REFERENCE; ALL isn't FAIL) are live only: the capture
predates the fix.
"""

from datetime import date

import pytest

from utils import config, forge_data

live_only = pytest.mark.parametrize("forge", [pytest.param("live", marks=pytest.mark.live)], indirect=True)
PROC = config.DATA_HEALTH_PROC
TOP_KEYS = {"entity", "generated_at", "as_of_date", "status", "summary", "entities"}
ENTITY_KEYS = {"entity", "table", "row_count", "latest_business_date", "latest_load_ts", "freshness_hours",
               "freshness_status", "status", "checks"}
REFERENCE = {"suppliers", "parts", "sourcing", "plants", "customers"}


@pytest.mark.parametrize("entity", ["ALL", *forge_data.HEALTH_ENTITIES])
def test_data_health_has_the_spec_shape(forge, entity):
    data = forge.get_data_health(entity)
    assert TOP_KEYS <= set(data), f"{PROC}({entity!r}) lacks keys {TOP_KEYS - set(data)}"
    assert data["status"] in {"OK", "WARN", "FAIL", "UNKNOWN"}, f"{PROC}({entity!r}) status {data['status']!r}"
    assert len(data["entities"]) == (9 if entity == "ALL" else 1), f"{PROC}({entity!r}) entity count"
    for e in data["entities"]:
        assert ENTITY_KEYS <= set(e), f"{PROC}({entity!r}) {e.get('entity')} lacks {ENTITY_KEYS - set(e)}"


@live_only
def test_reference_data_is_not_judged_on_age(forge):
    """C16 (freshness fix 1): the 5 reference entities read REFERENCE, the daily ones never do."""
    kinds = {e["entity"]: e["freshness_status"] for e in forge.get_data_health("ALL")["entities"]}
    assert {e for e, k in kinds.items() if k == "REFERENCE"} == REFERENCE, f"{PROC}('ALL') freshness: {kinds}"


@live_only
def test_all_is_not_failing_and_is_dated(forge):
    data = forge.get_data_health("ALL")
    assert data["status"] != "FAIL", f"{PROC}('ALL') is FAIL: {data['summary']}"
    assert data["as_of_date"] and date.fromisoformat(data["as_of_date"]) <= date.today(), \
        f"{PROC}('ALL') as_of_date {data['as_of_date']!r}"


@live_only
def test_all_fits_the_agent_tool_budget(forge):
    import json
    size = len(json.dumps(forge.get_data_health("ALL")))
    assert size <= 16_384, f"{PROC}('ALL') is {size} bytes, over the agent tool budget"


def test_cleaned_data_passes_every_zero_check(forge):
    df = forge.get_quality_results()
    zero = df[(df["TABLE_SCHEMA"] == "CONFORMED") & df["METRIC_NAME"].str.upper().isin(forge_data._QUALITY_EXPECT_ZERO)]
    assert len(zero), "no DMF results on the CONFORMED tables (SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS)"
    failing = zero[zero["STATUS"] != "PASS"]
    assert failing.empty, "CONFORMED checks not at zero: " + ", ".join(
        f"{r.TABLE_NAME}.{r.METRIC_NAME}={r.VALUE}" for r in failing.itertuples())


@live_only
def test_every_dmf_association_reports(forge):
    """C10 attached 77 DMF associations (runs/C10_run.md); each has a latest result."""
    n = len(forge.get_quality_results())
    assert n >= 77, f"only {n} DMF results in SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS (want 77)"
