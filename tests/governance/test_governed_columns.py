"""Contract §7 against Snowflake (live only, C13): each governed view has the contract's
columns, in the contract's order. Extra columns are allowed (additive); a missing or
reordered one names the view."""

import pytest

from utils import config

live_only = pytest.mark.parametrize("forge", [pytest.param("live", marks=pytest.mark.live)], indirect=True)
SQL = (f"SELECT table_name, column_name FROM {config.DATABASE}.INFORMATION_SCHEMA.COLUMNS "
       "WHERE table_schema = 'GOVERNED' ORDER BY table_name, ordinal_position")


def _in_order(wanted: list[str], have: list[str]) -> bool:
    it = iter(have)
    return all(any(w == h for h in it) for w in wanted)


@live_only
@pytest.mark.parametrize("view", list(config.GOVERNED_COLUMNS))
def test_governed_view_has_the_contract_columns_in_order(forge, view):
    rows = forge.raw(SQL).to_dict("records")
    have = [str(next(v for k, v in r.items() if k.lower() == "column_name")).lower()
            for r in rows if str(next(v for k, v in r.items() if k.lower() == "table_name")).upper() == view]
    fqn = f"{config.DATABASE}.GOVERNED.{view}"
    assert have, f"{fqn} not found (or not visible to this role)"
    wanted = config.GOVERNED_COLUMNS[view]
    missing = [c for c in wanted if c not in have]
    assert not missing, f"{fqn} lacks contract §7 columns {missing}"
    assert _in_order(wanted, have), f"{fqn} columns out of contract order: {have}"
