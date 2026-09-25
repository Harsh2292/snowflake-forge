"""Contract §6 invariant: masking changes column visibility only. Each canonical metric,
computed separately under each persona role (§5.4 SP_METRICS_AS_* procedures), is
identical for Planner, Buyer and Logistics to 6 decimal places.
"""

import pytest

from utils import config, mock_data

DP = config.CONSISTENCY_DP
PERSONA_COLUMNS = [p.upper() for p in config.PERSONA_ROLES]  # PLANNER, BUYER, LOGISTICS
METRIC_COLUMNS = [config.column_name(m["id"]) for m in config.METRICS.values()]


def assert_identical_across_personas(forge, metric_key):
    row = forge.compare_across_personas(metric_key).iloc[0]
    values = {p: float(row[p]) for p in PERSONA_COLUMNS}
    assert len({round(v, DP) for v in values.values()}) == 1, \
        f"{metric_key} differs across personas at {DP} dp: {values}"


def test_otd_identical_across_personas(forge):
    assert_identical_across_personas(forge, "on_time_delivery_rate")


def test_fill_rate_identical_across_personas(forge):
    assert_identical_across_personas(forge, "fill_rate")


def test_doi_identical_across_personas(forge):
    assert_identical_across_personas(forge, "days_of_inventory")


def test_landed_cost_identical_across_personas(forge):
    assert_identical_across_personas(forge, "avg_landed_cost")


def test_persona_values_equal_the_governed_number(forge):
    """Each persona's number is the semantic view's number, not just equal to each other."""
    governed = forge.get_all_metrics().iloc[0]
    for _, row in forge.compare_across_personas().iterrows():
        expected = round(float(governed[config.column_name(config.METRICS[row["METRIC"]]["id"])]), DP)
        for persona in PERSONA_COLUMNS:
            assert round(float(row[persona]), DP) == expected, (row["METRIC"], persona)


@pytest.mark.parametrize("persona", list(config.PERSONA_METRIC_PROCS))
def test_metric_procedure_returns_one_row_in_contract_shape(forge, persona):
    """§5.4: one row, PERSONA plus the four metric columns."""
    if forge.live:
        rows = forge.raw(forge.build_call_sql(config.PERSONA_METRIC_PROCS[persona])).to_dict("records")
    else:
        rows = [mock_data.persona_metrics_row(persona)]
    assert len(rows) == 1
    assert list(rows[0]) == ["PERSONA", *METRIC_COLUMNS]
    assert rows[0]["PERSONA"] == persona.upper()
