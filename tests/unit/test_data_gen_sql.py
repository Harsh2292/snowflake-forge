"""C08: offline checks on the data generator SQL (data_gen/). Claude Code can't run it, so
these catch what can be caught without Snowflake: the determinism rules, no account names,
re-runnable DDL, headers CoCo relies on, and that the injected defects match DATA_SPEC §4.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
DATA_GEN = ROOT / "data_gen"
SQL_FILES = sorted(DATA_GEN.glob("*.sql"))
SPEC = (ROOT / "docs" / "DATA_SPEC.md").read_text(encoding="utf-8")
INJECT = (DATA_GEN / "20_sp_inject_mess.sql").read_text(encoding="utf-8")


def code_only(text: str) -> str:
    """SQL without -- comments."""
    return "\n".join(line.split("--")[0] for line in text.splitlines())


def test_the_five_files_exist():
    assert [p.name for p in SQL_FILES] == ["00_setup.sql", "10_sp_generate_data.sql", "20_sp_inject_mess.sql",
                                           "30_sp_gen_self_checks.sql", "99_run.sql"]


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_header_names_card_role_warehouse_and_run_order(path):
    head = path.read_text(encoding="utf-8")[:1500]
    for field in ("Card:", "Role:", "Warehouse:", "Run order:", "Expected:"):
        assert field in head, f"{path.name} header lacks {field}"


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_randomness_is_hash_based_only(path):
    sql = code_only(path.read_text(encoding="utf-8")).upper()
    for banned in ("RANDOM(", "UNIFORM(", "NORMAL(", "ZIPF(", "RANDSTR(", "SEQ4()"):
        assert banned not in sql, f"{path.name} uses {banned}"


@pytest.mark.parametrize("name", ["10_sp_generate_data.sql", "20_sp_inject_mess.sql"])
def test_no_clock_in_the_data(name):
    """END_DATE is passed in; CURRENT_TIMESTAMP appears only in log rows (GEN_LOG / GEN_STATS /
    GEN_MESS_LOG / timing variables), never in a source-table value."""
    sql = code_only((DATA_GEN / name).read_text(encoding="utf-8")).upper()
    assert "CURRENT_DATE" not in sql and "SYSDATE" not in sql and "GETDATE" not in sql
    for statement in sql.split(";"):
        if "CURRENT_TIMESTAMP" in statement and re.search(r"INSERT INTO (ERP|WMS|TMS|SRM)_SOURCE", statement):
            pytest.fail(f"{name}: clock value written to a source table:\n{statement[:300]}")


def test_no_file_names_an_account():
    """The account switch (1 Oct): nothing in the repo's runnable code may name the account."""
    pattern = re.compile(r"snowflakecomputing\.com|\bDA53081\b|ACCOUNT_LOCATOR|\borganization_name\b", re.I)
    for folder in ("data_gen", "app", "deploy"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in {".sql", ".py", ".yml", ".toml", ".md", ".html", ".js"}:
                assert not pattern.search(path.read_text(encoding="utf-8", errors="ignore")), path


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_ddl_is_re_runnable_and_blocks_are_balanced(path):
    sql = code_only(path.read_text(encoding="utf-8"))
    for create in re.findall(r"CREATE\s+(?!OR\s+REPLACE)[^;]*?(?=\()|CREATE\s+(?!OR\s+REPLACE)\w+\s+\w+", sql, re.I):
        assert "IF NOT EXISTS" in create.upper() or "TEMPORARY" in create.upper(), f"{path.name}: {create[:80]}"
    assert sql.count("$$") % 2 == 0, f"{path.name}: unbalanced $$"


def test_procedures_are_callers_rights_and_switch_to_the_target_database():
    for name in ("10_sp_generate_data.sql", "20_sp_inject_mess.sql", "30_sp_gen_self_checks.sql"):
        sql = (DATA_GEN / name).read_text(encoding="utf-8")
        assert "EXECUTE AS CALLER" in sql
        assert "EXECUTE IMMEDIATE 'USE SCHEMA ' || :TARGET_DB || '.OPS'" in sql


# ── The mess (§4) ────────────────────────────────────────────────────────────

SPEC_RATES = {  # DATA_SPEC §4.1 / §4.2: (code, logged table) -> rate
    ("M01", "VBAK"): 0.02, ("M01", "VBAP"): 0.015, ("M01", "VTTK"): 0.03, ("M01", "MARD"): 0.005, ("M01", "KNA1"): 0.01,
    ("M02", "VBAK"): 0.10, ("M02", "VTTK"): 0.08,
    ("M03", "LFA1.REGIO"): 0.08, ("M03", "KNA1.REGIO"): 0.08, ("M03", "VBAK.GBSTK"): 0.03, ("M03", "VBAK.PRIO"): 0.02,
    ("M03", "VTTK.SHP_STATUS"): 0.03, ("M03", "VTTK.CARRIER_CD"): 0.06, ("M03", "MARA.MATKL"): 0.05,
    ("M03", "KNA1.KTOKD"): 0.03,
    ("M04", "VBAK"): 0.003, ("M04", "VBAP"): 0.001,
    ("M06", "VBAP"): 0.01, ("M06", "VTTK"): 0.01,
    ("M07", "VBAP.MATNR"): 0.005, ("M07", "VTTK.VBELN"): 0.003, ("M07", "VBAP.VBELN"): 0.002,
    ("E01", "VTTK"): 0.008, ("E02", "VBAK"): 0.005, ("E03", "VBAK"): 0.015, ("E03", "VTTK_SHARE"): 0.60,
    ("E04", "VBAP"): 0.01, ("E05", "MARD"): 0.003, ("E06", "MARD_PAIRS"): 0.02,
    ("E07a", "VTTK"): 0.60, ("E07b", "VTTK"): 0.01, ("E07c", "VTTK"): 0.002, ("E08", "VTTK"): 0.001,
    ("E09a", "VBAP"): 0.002, ("E09b", "VTTK"): 0.002, ("E11", "SOURCING"): 0.01, ("E12", "VBAK"): 0.0002,
}
LOG = re.compile(r"GEN_MESS_LOG SELECT :run_id, :TARGET_DB, '(\w+)', '([\w.]+)', [^,]+, ([\d./ ]+), ")


def logged():
    return {(code, table): rate for code, table, rate in LOG.findall(INJECT)}


def test_every_spec_defect_is_injected_and_logged_at_its_rate():
    got = logged()
    for key, rate in SPEC_RATES.items():
        assert key in got, f"{key} not injected"
        assert float(got[key]) == pytest.approx(rate), (key, got[key], rate)


def test_each_pick_uses_the_rate_it_logs():
    """The k := ROUND(base * r) before each log line uses the logged rate."""
    for match in LOG.finditer(INJECT):
        code, table, rate = match.groups()
        before = INJECT[:match.start()]
        picks = re.findall(r"k := ROUND\(base \* ([\d.]+)\)", before)
        if (code, table) in SPEC_RATES and code not in ("E03",) and table not in ("VTTK_SHARE",):
            assert picks and float(picks[-1]) == pytest.approx(float(rate)), (code, table)


def test_code_variants_are_exactly_the_spec_list():
    """§4.3: the injector may use only the listed variants, including their spaces."""
    section = SPEC[SPEC.index("### 4.3 Code map"):SPEC.index("`PLANT_TYPE` and `SUPP_TIER` are never messy")]
    spec = {}
    for row in re.findall(r"^\| `(\w+)` \(.*?\| (.*) \|$", section, re.M):
        domain, cell = row
        for part in cell.split(" · "):
            names = re.findall(r"`([^`]*)`", part)
            spec[(domain, names[0])] = names[1:]
    injected = {(d, c): lst.split("|") for d, c, lst in re.findall(r"\('(\w+)', '(\w+)', '([^']*)'\)", INJECT)
                if d in {k[0] for k in spec}}
    assert injected == spec
