"""C6b: the app's saved data is the last real Snowflake capture, and the captures agree.

- app/utils/captured.json is exactly what tests/tools/build_captured.py builds from
  docs/artifacts (re-run the script after every re-capture)
- every contract §4 pairing is captured, so the synthetic safety net is never used
- art 05 (metrics), art 06 (the pairing matrix), art 09 (personas) and contract §4 / §10
  reconcile with each other and with config.py
"""

import importlib.util
import json
import math
import re
from pathlib import Path

import pandas as pd
import pytest

from utils import config, mock_data

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "docs" / "artifacts"
_spec = importlib.util.spec_from_file_location("build_captured", ROOT / "tests" / "tools" / "build_captured.py")
build_captured = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_captured)

VALID = {(config.METRICS[k]["id"], d) for k, dims in config.VALID_PAIRINGS.items() for d in dims}
ART05 = json.loads((ARTIFACTS / "05_metric_values.json").read_text(encoding="utf-8"))["payload"]
ART09 = json.loads((ARTIFACTS / "09_consistency_proof.json").read_text(encoding="utf-8"))["payload"]


def test_captured_json_is_exactly_the_builder_output():
    """If this fails after a re-capture: run tests/tools/build_captured.py."""
    on_disk = (ROOT / "app" / "utils" / "captured.json").read_text(encoding="utf-8")
    assert on_disk == build_captured.render(build_captured.build())


def test_every_contract_pairing_is_captured_so_nothing_is_synthetic():
    captured = {(m, d) for m, dims in ART05["by_dimension"].items() for d in dims}
    assert captured == VALID
    for key, dims in config.VALID_PAIRINGS.items():
        for dim in dims:
            assert mock_data.captured_rows(key, dim), (key, dim)
            assert "MOCK-" not in " ".join(map(str, mock_data.metric_frame(key, dim).iloc[:, 0]))


def _art06() -> dict:
    """(metric id, dimension) -> (in §4, result, rows) from art 06's tables."""
    cells, metric = {}, None
    for line in (ARTIFACTS / "06_dimension_matrix.md").read_text(encoding="utf-8").splitlines():
        heading = re.match(r"## `([a-z_]+\.[a-z_]+)`", line)
        if heading:
            metric = heading.group(1)
            continue
        row = re.match(r"\| `([a-z_]+\.[a-z_]+)` \| (\S+) \| (PASS|FAIL)[^|]*\| (\d*) \|", line)
        if metric and row:
            # "in §4" is ✅ or a dash; the file is double-encoded UTF-8, so accept both spellings
            in4 = row.group(2) not in {"—", "â€”"}
            cells[(metric, row.group(1))] = (in4, row.group(3), row.group(4))
    return cells


def test_art06_passes_exactly_the_contract_pairings():
    cells = _art06()
    in_contract = {pair for pair, (in4, _, _) in cells.items() if in4}
    assert in_contract == VALID
    assert all(cells[pair][1] == "PASS" for pair in VALID)


def test_multi_counting_pairings_snowflake_accepts_stay_out_of_the_app():
    """B09 finding: some non-§4 pairings now run but multi-count. The app never offers them."""
    accepted_outside = {pair for pair, (in4, result, _) in _art06().items() if not in4 and result == "PASS"}
    assert accepted_outside and not (accepted_outside & VALID)


def test_art06_row_counts_match_the_captured_rows():
    cells = _art06()
    for metric, dims in ART05["by_dimension"].items():
        for dim, rows in dims.items():
            assert int(cells[(metric, dim)][2]) == len(rows), (metric, dim)


def test_art09_personas_are_identical_and_equal_art05():
    columns = [config.column_name(m["id"]) for m in config.METRICS.values()]
    rows = [ART09["metrics_by_persona"][p.upper()][0] for p in config.PERSONA_ROLES]
    for col in columns:
        values = {round(r[col], config.CONSISTENCY_DP) for r in rows}
        assert len(values) == 1, col
        assert math.isclose(values.pop(), ART05["overall"][col], abs_tol=10 ** -config.CONSISTENCY_DP), col


@pytest.mark.parametrize("persona", list(config.PERSONA_ROLES))
def test_masking_sample_is_what_each_persona_really_saw(persona):
    """The §6 masking matrix applied to the unmasked values reproduces art 09 exactly."""
    ours = mock_data.masking_sample(persona)
    theirs = pd.DataFrame(ART09["samples_by_persona"][persona.upper()])[config.SAMPLE_COLUMNS]
    for (_, a), (_, b) in zip(ours.iterrows(), theirs.iterrows()):
        for col in config.SAMPLE_COLUMNS:
            same = (pd.isna(a[col]) and pd.isna(b[col])) or a[col] == b[col]
            assert same, (persona, col, a[col], b[col])


def test_contract_10_is_the_capture_rounded():
    dp = {"on_time_delivery_rate": 4, "fill_rate": 4, "days_of_inventory": 1, "avg_landed_cost": 2}
    for key, places in dp.items():
        assert round(mock_data.captured_overall(key), places) == config.MOCK_METRICS[key], key
        for row in mock_data.captured_rows(key, "plants.plant_region"):
            col = config.column_name(config.METRICS[key]["id"])
            assert round(row[col], places) == config.MOCK_BY_REGION[row["PLANT_REGION"]][key], (key, row)


def test_saved_naive_otd_is_the_current_data_measurement():
    assert mock_data.MOCK_NAIVE_OTD == 0.681651
    assert mock_data.MOCK_NAIVE_OTD < mock_data.captured_overall("on_time_delivery_rate") - 0.08  # B08c gate 5
