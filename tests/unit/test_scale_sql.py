"""C12: offline checks on the scale harness (tests/scale/). Claude Code can't run it, so
these catch what can be caught without Snowflake: the query catalogue is exactly the app's
own SQL (via the generator), it covers every valid pairing, it names no database, and the
runner writes the DATA_SPEC §7.4 columns.
"""

import importlib.util
import re
from pathlib import Path

import pytest

from utils import config, forge_data

ROOT = Path(__file__).resolve().parents[2]
SCALE = ROOT / "tests" / "scale"
SQL_FILES = sorted(SCALE.glob("*.sql"))
SPEC = (ROOT / "docs" / "DATA_SPEC.md").read_text(encoding="utf-8")
RUNNER = (SCALE / "20_sp_scale_run.sql").read_text(encoding="utf-8")
RUN = (SCALE / "99_run.sql").read_text(encoding="utf-8")


def load_generator():
    spec = importlib.util.spec_from_file_location("build_scale_queries", SCALE / "build_scale_queries.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GEN = load_generator()
QUERIES = GEN.queries()
ACTIVE = [q for q in QUERIES if q["active"]]


def code_only(text: str) -> str:
    return "\n".join(line.split("--")[0] for line in text.splitlines())


# ── Files and headers ────────────────────────────────────────────────────────────

def test_the_files_exist():
    assert [p.name for p in SQL_FILES] == ["00_setup.sql", "10_scale_queries.sql", "20_sp_scale_run.sql", "99_run.sql"]
    for name in ("build_scale_queries.py", "report_template.md", "README.md"):
        assert (SCALE / name).is_file(), name


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_headers_rerunnable_and_no_semicolon_in_comments(path):
    text = path.read_text(encoding="utf-8")
    for field in ("Card:", "Role:", "Warehouse:", "Run order:", "Expected:"):
        assert field in text[:3000], f"{path.name} header lacks {field}"
    sql = code_only(text)
    assert sql.count("$$") % 2 == 0
    for create in re.findall(r"^\s*CREATE\b[^;(]*", sql.upper(), re.M):
        create = create.strip()
        assert create.startswith("CREATE OR REPLACE") or "IF NOT EXISTS" in create, create[:80]
    assert not re.search(r"\bUSE\s+(ROLE|WAREHOUSE)\b", sql, re.I)
    for n, line in enumerate(text.splitlines(), 1):
        in_str = False
        for i, ch in enumerate(line):
            if ch == "'":
                in_str = not in_str
            elif not in_str and line.startswith("--", i):
                assert ";" not in line[i:], f"{path.name}:{n}: ';' in a comment (CoCo's tool splits on it)"
                break


# ── The catalogue is the app's own SQL ───────────────────────────────────────────

def test_committed_catalogue_equals_the_generator():
    """Change the app's queries → re-run tests/scale/build_scale_queries.py."""
    assert (SCALE / "10_scale_queries.sql").read_text(encoding="utf-8") == GEN.render()


def test_every_valid_pairing_is_measured_with_the_apps_sql():
    pairs = {(q["metric"], q["dimension"]): q for q in QUERIES if q["path"] == "SEMANTIC_VIEW" and q["dimension"]}
    want = {(k, d) for k, dims in config.VALID_PAIRINGS.items() for d in dims}
    assert set(pairs) == want and len(want) == 58
    for (key, dim), q in pairs.items():
        assert q["sql"] == GEN.templated(forge_data.build_metric_sql(key, dim))
        assert q["window"] == ("LATEST" if key == "days_of_inventory" else "T12M")


def test_each_metric_all_time_and_in_its_default_window():
    for key in config.METRICS:
        default = next(q for q in QUERIES if q["name"] == f"SV_{key.upper()}_DEFAULT")
        assert default["sql"] == GEN.templated(forge_data.build_metric_sql(key))
        everything = next(q for q in QUERIES if q["name"] == f"SV_{key.upper()}_ALL")
        assert "WHERE" not in everything["sql"] and config.METRICS[key]["id"] in everything["sql"]


def test_procedures_naive_and_agent_paths():
    procs = [q for q in QUERIES if q["path"] == "PROCEDURE"]
    assert [q["sql"] for q in procs] == [GEN.templated(forge_data.build_call_sql(p))
                                         for p in config.PERSONA_METRIC_PROCS.values()]
    # the persona column is left out, so equal fingerprints mean equal numbers
    assert len({q["hash_expr"] for q in procs}) == 1 and "PERSONA" not in procs[0]["hash_expr"]
    naive = [q for q in QUERIES if q["path"] == "NAIVE"]
    assert [q["sql"] for q in naive] == [GEN.templated(forge_data.NAIVE_OTD_SQL)]
    agent = [q for q in QUERIES if q["path"] == "AGENT"]
    assert agent and not any(q["active"] for q in agent) and all(q["hash_expr"] is None for q in agent)
    assert all("'text', ?)" not in q["sql"] for q in agent)  # the question is a literal here, not a bind


def test_no_template_names_a_database():
    for q in QUERIES:
        assert config.DATABASE not in q["sql"], q["name"]
        assert "{{DB}}." in q["sql"], q["name"]


def test_fingerprints_name_the_result_columns():
    for q in (q for q in ACTIVE if q["path"] == "SEMANTIC_VIEW"):
        col = config.METRICS[q["metric"]]["id"].split(".")[1].upper()
        assert q["hash_expr"].endswith(f"ROUND({col}, 6)"), q["name"]
        if q["dimension"]:
            assert q["hash_expr"].startswith(config.column_name(q["dimension"]) + ", ")


def test_catalogue_counts():
    assert len(ACTIVE) == 4 + 4 + 58 + 3 + 1
    assert len({q["name"] for q in QUERIES}) == len(QUERIES)


# ── The runner (DATA_SPEC §7.4) ──────────────────────────────────────────────────

def test_runner_signature():
    assert ("CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN(\n"
            "    TARGET_DB VARCHAR, RUN_LABEL VARCHAR, RESULTS_TABLE VARCHAR, QUERY_FILTER VARCHAR DEFAULT NULL)") in RUNNER
    assert re.search(r"RETURNS VARIANT[\s\S]*?EXECUTE AS CALLER\s+AS\s*\n\$\$", RUNNER)


def test_results_table_has_the_spec_columns():
    section = SPEC.split("### 7.4", 1)[1]
    spec_cols = re.search(r"Writes rows `\(([^)]*)\)`", section.replace("\n", " "))
    want = [re.sub(r"\[.*?\]", "", c).strip().split()[0] for c in re.sub(r"\[[^\]]*\]", "", spec_cols.group(1)).split(",")]
    ddl = RUNNER.split("CREATE TABLE IF NOT EXISTS IDENTIFIER(:RESULTS_TABLE) (", 1)[1].split("\n    )", 1)[0]
    have = [line.split()[0] for line in ddl.strip().splitlines()]
    assert have == want


def test_runner_measures_what_the_spec_asks():
    body = RUNNER.split("AS\n$$", 1)[1]
    for needle in ("USE_CACHED_RESULT = FALSE", "QUERY_TAG = ''forge_scale:", "QUERY_HISTORY_BY_SESSION",
                   "GET_QUERY_OPERATOR_STATS", "partitions_scanned", "partitions_total", "'TableScan'",
                   "HASH_AGG(", "RESULT_SCAN", "HASH(:q_template)", "REPLACE(q_template, '{{DB}}', TARGET_DB)"):
        assert needle in body, needle
    for key in ("run_label", "queries", "failed", "total_elapsed_ms", "max_elapsed_ms"):
        assert f"'{key}'" in body, key
    assert "EXCEPTION" in body  # one failing query never stops the run


def test_driver_runs_the_three_scales_and_the_three_claims():
    calls = re.findall(r"^CALL SUPPLY_CHAIN_FORGE\.OPS\.SP_SCALE_RUN\('([^']+)', '([^']+)', '([^']+)'\);", RUN, re.M)
    assert [c[1] for c in calls] == ["sf1-xs", "clone-xs", "clone-large"]
    assert {c[2] for c in calls} == {"SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS"}
    for claim in ("claim 1", "claim 2", "claim 3"):
        assert f"Art 12, {claim}" in RUN
