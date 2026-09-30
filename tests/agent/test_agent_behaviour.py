"""The agent's governed behaviour, live (C13), through the app's CR-007 call: it declines a
breakdown the contract doesn't allow, and it uses its data-health tool when asked about
freshness. Two agent calls (a few cents)."""

import pytest

from utils import config

live_only = pytest.mark.parametrize("forge", [pytest.param("live", marks=pytest.mark.live)], indirect=True)


@live_only
def test_cross_grain_breakdown_is_not_answered_with_multi_counted_sql(forge):
    """Q30 (C11/C16): OTD by part category would count shipments once per order line."""
    assert "parts.category" not in config.VALID_PAIRINGS["on_time_delivery_rate"]
    result = forge.ask_agent("What is on-time delivery rate by part category?")
    sql = (result["sql"] or "").lower()
    assert not ("on_time_delivery_rate" in sql and "category" in sql), \
        f"{config.AGENT} answered a cross-grain pairing with SQL: {result['sql']}"
    assert result["answer"].strip(), f"{config.AGENT} gave no explanation"


@live_only
def test_freshness_question_uses_the_data_health_tool(forge):
    result = forge.ask_agent("Is the shipment data up to date?")
    used = set(result["tools_used"]) | set(result["tools_raw"])
    assert {"Data health check", "data_health"} & used, \
        f"{config.AGENT} didn't call its data_health tool ({config.DATA_HEALTH_PROC}); tools: {sorted(used)}"
