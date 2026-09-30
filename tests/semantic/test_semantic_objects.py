"""Contract §1, §3, §4 against the semantic view itself (live only, C13): every contract
metric and dimension exists in SUPPLY_CHAIN_SV, and every §4 pairing is legal for its
metric. Extra v2 content (B09: more metrics, dimensions, filters) is fine: it's additive.
"""

import pytest

from utils import config

live_only = pytest.mark.parametrize("forge", [pytest.param("live", marks=pytest.mark.live)], indirect=True)
VIEW = config.SEMANTIC_VIEW


def _names(forge, sql: str) -> set[str]:
    """table.name of each row, lowercased (SHOW returns table_name and name columns)."""
    rows = forge.raw(sql).to_dict("records")
    def get(row, key):
        return next((v for k, v in row.items() if k.lower() == key), "")
    return {f"{get(r, 'table_name')}.{get(r, 'name')}".lower() for r in rows}


@live_only
def test_every_contract_metric_exists(forge):
    have = _names(forge, f"SHOW SEMANTIC METRICS IN {VIEW}")
    missing = [m["id"] for m in config.METRICS.values() if m["id"].lower() not in have]
    assert not missing, f"{VIEW} lacks contract §3 metrics: {missing}"


@live_only
def test_every_contract_dimension_exists(forge):
    have = _names(forge, f"SHOW SEMANTIC DIMENSIONS IN {VIEW}")
    wanted = [d for dims in config.DIMENSIONS.values() for d in dims]
    missing = [d for d in wanted if d.lower() not in have]
    assert not missing, f"{VIEW} lacks contract §4 dimensions: {missing}"


@live_only
@pytest.mark.parametrize("metric_key", list(config.METRICS))
def test_every_contract_pairing_is_legal(forge, metric_key):
    metric_id = config.METRICS[metric_key]["id"]
    try:
        legal = _names(forge, f"SHOW SEMANTIC DIMENSIONS IN {VIEW} FOR METRIC {metric_id}")
    except Exception:  # some releases want the unqualified metric name here
        legal = _names(forge, f"SHOW SEMANTIC DIMENSIONS IN {VIEW} FOR METRIC {metric_id.split('.')[-1]}")
    missing = [d for d in config.VALID_PAIRINGS[metric_key] if d.lower() not in legal]
    assert not missing, f"{VIEW}: {metric_id} can't be broken down by {missing} (contract §4 says it can)"
