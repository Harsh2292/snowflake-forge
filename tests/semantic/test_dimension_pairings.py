"""Contract §4 metric × dimension pairings and §5.2 result shape.

Every guaranteed pairing returns rows, with columns named per §5.2 and dimension values
from §4's lists. days_of_inventory × orders.*/shipments.* is refused: by the app in both
modes, and (live) by Snowflake itself, because inventory has no path to those entities.
"""

import pytest

from utils import config

VALID = [(k, d) for k, dims in config.VALID_PAIRINGS.items() for d in dims]
INVALID_DOI = config.DIMENSIONS["orders"] + config.DIMENSIONS["shipments"]


@pytest.mark.parametrize("metric_key,dimension", VALID, ids=[f"{k}-{d}" for k, d in VALID])
def test_valid_pairing_returns_rows(forge, metric_key, dimension):
    df = forge.get_metric(metric_key, dimension)
    dim_col, metric_col = config.column_name(dimension), config.column_name(config.METRICS[metric_key]["id"])
    assert list(df.columns) == [dim_col, metric_col]
    assert len(df) > 0
    if dimension in config.DIMENSION_VALUES:
        unexpected = set(df[dim_col].astype(str)) - set(config.DIMENSION_VALUES[dimension])
        assert not unexpected, f"{dimension} values outside contract §4: {sorted(unexpected)}"
    values = df[metric_col].astype(float)
    assert values.notna().all()
    if config.METRICS[metric_key]["format"] == "percent":
        assert values.between(0, 1).all()
    else:
        assert (values >= 0).all()


@pytest.mark.parametrize("dimension", INVALID_DOI)
def test_days_of_inventory_by_orders_or_shipments_is_refused(forge, dimension):
    with pytest.raises(ValueError):
        forge.get_metric("days_of_inventory", dimension)
    if forge.live:
        sql = (f"SELECT * FROM SEMANTIC_VIEW({config.SEMANTIC_VIEW} "
               f"DIMENSIONS {dimension} METRICS {config.METRICS['days_of_inventory']['id']})")
        with pytest.raises(Exception):
            forge.raw(sql)


def test_every_pairing_is_covered():
    """55 guaranteed pairings (§4 with entity.* expanded), 9 refused."""
    assert len(VALID) == 55
    assert len(INVALID_DOI) == 9
