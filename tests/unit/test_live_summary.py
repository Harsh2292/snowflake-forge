"""C13: the live audit's per-section summary, on fake results (no Snowflake needed)."""

import importlib.util
import re
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("tests_conftest", ROOT / "tests" / "conftest.py")
_conftest = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_conftest)
CONTRACT_SECTIONS, live_summary = _conftest.CONTRACT_SECTIONS, _conftest.live_summary


def report(nodeid, outcome, message=None):
    crash = SimpleNamespace(message=message) if message else None
    return SimpleNamespace(nodeid=nodeid, outcome=outcome, longrepr=SimpleNamespace(reprcrash=crash))


def test_nothing_is_printed_without_a_live_run():
    assert live_summary([report("tests/semantic/test_metric_ranges.py::t[mock-x]", "passed"),
                         report("tests/semantic/test_metric_ranges.py::t[live-x]", "skipped")]) == []


def test_counts_per_section_and_names_the_failing_object():
    lines = live_summary([
        report("tests/semantic/test_metric_ranges.py::test_a[live-fill_rate]", "passed"),
        report("tests/governance/test_governed_columns.py::test_v[live-V_PART]", "failed",
               "AssertionError: SUPPLY_CHAIN_FORGE.GOVERNED.V_PART lacks contract §7 columns ['unit_cost']"),
        report("tests/quality/test_data_health_live.py::test_ref[live]", "skipped"),
        report("tests/semantic/test_metric_ranges.py::test_a[mock-fill_rate]", "passed"),  # not live: ignored
    ])
    text = "\n".join(lines)
    assert "§3 metric ranges" in text and "§7 governed view columns" in text and "DATA_SPEC §7.2" in text
    row = next(line for line in lines if line.startswith("§7 governed view columns"))
    assert row.split()[-3:] == ["0", "1", "0"]
    assert "GOVERNED.V_PART lacks contract §7 columns" in text


def test_a_failed_teardown_counts_as_the_test_failing():
    lines = live_summary([report("tests/agent/test_x.py::t[live]", "passed"),
                          report("tests/agent/test_x.py::t[live]", "failed", "boom")])
    row = next(line for line in lines if line.startswith("§5.3"))
    assert row.split()[-3:] == ["0", "1", "0"]


def test_every_live_test_file_maps_to_a_section():
    live_files = [p for p in (ROOT / "tests").rglob("test_*.py")
                  if not {"unit", "ui", "artifacts", "scale"} & set(p.parts)
                  and re.search(r"mark\.live|def test_\w+\(forge\b", p.read_text(encoding="utf-8"))]
    assert live_files
    for path in live_files:
        rel = path.relative_to(ROOT).as_posix()
        assert any(rel.startswith(prefix) for prefix, _ in CONTRACT_SECTIONS), rel
