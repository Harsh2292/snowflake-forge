"""Contract §3 (each metric inside its expected range), §5.1 (result shape) and §8 (the
naive ERP-date OTD and the governed OTD are different numbers)."""

import pytest

from utils import config

METRIC_COLUMNS = {k: config.column_name(m["id"]) for k, m in config.METRICS.items()}


@pytest.mark.parametrize("metric_key", list(config.METRICS))
def test_metric_inside_contract_range(forge, metric_key):
    value = float(forge.get_all_metrics()[METRIC_COLUMNS[metric_key]].iloc[0])
    low, high = config.METRIC_RANGES[metric_key]
    assert low <= value <= high, f"{metric_key} = {value}, contract range {low}–{high}"


@pytest.mark.parametrize("metric_key", list(config.METRICS))
def test_single_metric_query_is_one_row_one_column(forge, metric_key):
    """§5.1: one row, one column named after the metric, unqualified and uppercased."""
    df = forge.get_metric(metric_key)
    assert list(df.columns) == [METRIC_COLUMNS[metric_key]]
    assert len(df) == 1


def test_all_metrics_is_one_row_of_four_columns(forge):
    df = forge.get_all_metrics()
    assert list(df.columns) == list(METRIC_COLUMNS.values())
    assert len(df) == 1


def test_naive_and_governed_otd_differ(forge):
    """§8: counting against ERP's order date gives a different answer. That's the hook."""
    naive, governed = forge.get_naive_otd(), forge.get_governed_otd()
    assert 0 <= naive <= 1
    assert round(naive, 4) != round(governed, 4), f"naive {naive} == governed {governed}"


def test_governed_otd_is_the_semantic_view_number(forge):
    governed = forge.get_governed_otd()
    assert governed == pytest.approx(float(forge.get_all_metrics()[METRIC_COLUMNS["on_time_delivery_rate"]].iloc[0]))
