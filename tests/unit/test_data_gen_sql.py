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


def test_the_six_files_exist():
    assert [p.name for p in SQL_FILES] == ["00_setup.sql", "10_sp_generate_data.sql", "20_sp_inject_mess.sql",
                                           "30_sp_gen_self_checks.sql", "40_sp_append_day.sql", "99_run.sql"]


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


@pytest.mark.parametrize("name", ["10_sp_generate_data.sql", "20_sp_inject_mess.sql", "40_sp_append_day.sql"])
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
    for folder in ("data_gen", "quality", "eval", "tests/scale", "app", "deploy"):
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
    for name in ("10_sp_generate_data.sql", "20_sp_inject_mess.sql", "30_sp_gen_self_checks.sql",
                 "40_sp_append_day.sql"):
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


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_no_range_join_to_generate_numbers(path):
    """B12a (CoCo's clone test): `JOIN k ON k.k <= cnt` planned as a Cartesian product, about
    9 minutes per history year instead of ~1 s. Numbers 1..N come from
    LATERAL FLATTEN(ARRAY_GENERATE_RANGE(...)) instead: the same rows, a linear plan."""
    code = "\n".join(line.split("--", 1)[0] for line in path.read_text(encoding="utf-8").splitlines())
    joins = re.findall(r"JOIN\s+(\w+)\s+ON\s+\1\.\w+\s*<=", code)
    assert not joins, f"{path.name}: range join on a number generator ({joins})"
    assert "GENERATOR(ROWCOUNT => :max_k)" not in code


def test_generator_uses_flatten_for_every_expansion():
    code = (DATA_GEN / "10_sp_generate_data.sql").read_text(encoding="utf-8")
    assert code.count("LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(") == 6  # plants, customers, sourcing ×2, orders, lines


# ── C17 part B: the nightly day-append (40_sp_append_day.sql, DATA_SPEC §7.1a) ──

GENERATOR = (DATA_GEN / "10_sp_generate_data.sql").read_text(encoding="utf-8")
APPEND = (DATA_GEN / "40_sp_append_day.sql").read_text(encoding="utf-8")

# Every generator line that decides a value the append re-derives: the calendar, an
# order's customer, priority, plant, ship date and lines, a line's part, quantity, price and
# short-shipping, a shipment's carrier, promise, delivery and costs, stock, and FX.
FORMULA_LINES = re.compile(
    r"HASH\(:SEED, '(VBAK|VBAP|VTTK|MARD|TCURR|KNA1|MARA)'|POWER\(1\.08|DAYOFWEEKISO\(d\) WHEN 6|"
    r"'2020-04-01'|WHEN a\.u_lines <|a\.prio WHEN 'HIGH'|WHEN 'NORMAL' THEN 2 \+|ELSE 3 \+ LEAST\(3|"
    r"u\.u_cancel < 0\.04|b\.u_inreg < 0\.85|b\.u_other < 0\.03|YEAR\(p\.audat\) = 2021|EXP\(LN\(pt\.Q_LO\)|"
    r"pt\.STPRS \* \(1\.15|cd\.SLA \+ CASE|YEAR\(l\.dptbg\) <= 2019|YEAR\(l\.dptbg\) = 2021|cd\.OT_OFF$|"
    r"l\.prio WHEN 'HIGH' THEN 0\.02|l\.ot_offset\)\)|l\.dptbg < '2021-07-01'|<= '2022-12-31'::DATE THEN|"
    r"<= '2023-12-31'::DATE THEN|c\.u_ot < c\.p_ot|ELSE DATEADD\(day, \(1 \+ LEAST\(5|c\.BASE_FREIGHT \*|"
    r"\(0\.6 \+ c\.u_w\)|c\.plant_country = 'USA'|t\.is_domestic THEN 0 ELSE|40 \+ 80 \* t\.u_hand|"
    r"st\.usage_base|st\.cover_base|MONTH\(s\.d\) IN \(9, 10\)|ROUND\(usg \* cover|cm\.t = LEAST|pm\.t = LEAST|"
    r"s\.stock_rank = LEAST|WHEN l\.u_short < l\.p_short")


def _lines(text: str) -> set:
    return {" ".join(line.split()) for line in code_only(text).splitlines() if line.strip()}


def test_the_append_derives_every_value_with_the_generators_own_formulas():
    """The append re-derives the last 40 days of orders exactly as SP_GENERATE_DATA does. If a
    generator formula changes and the append's copy doesn't, existing orders would ship,
    arrive and cost differently from how the generator made them: this test catches that."""
    wanted = {" ".join(line.split()) for line in code_only(GENERATOR).splitlines() if FORMULA_LINES.search(line)}
    # lines that only exist for the full load (its year loop, history-wide stats, masters it writes)
    wanted = {w for w in wanted if not re.search(r"'(LFA1|SOURCING)'|GEN_STATS|u_erdat \* 3650|'load'\), 4294967295\) / 4294967295\.0\)\)\)::INT, *$|"
                                                 r"^ROUND\(usg \* cover, 3\), ROUND", w)}
    missing = [w for w in sorted(wanted) if w not in _lines(APPEND)]
    assert len(wanted) > 60, len(wanted)
    assert not missing, "formulas differ from SP_GENERATE_DATA:\n" + "\n".join(missing[:10])
    # the stock row's four values (the append adds the E05 / E06 mess around them, inline)
    for value in ("ROUND(usg * cover, 3)", "ROUND(usg * cover * 0.10 * u_ins, 3)", "ROUND(usg * reorder_f, 3)",
                  "ROUND(usg, 3)"):
        assert value in APPEND, value


def test_the_append_never_changes_existing_rows():
    """Row versions only (M02 pattern): CONFORMED's "latest LOAD_TS wins" shows the state."""
    sql = code_only(APPEND).upper()
    for verb in ("UPDATE ", "DELETE ", "TRUNCATE ", "MERGE "):
        assert not re.search(rf"\b{verb}(\w+\.)?(ERP|WMS|TMS|SRM)_SOURCE", sql), verb


def test_the_append_is_idempotent_and_one_day_is_one_transaction():
    sql = code_only(APPEND)
    assert "SELECT MAX(LOAD_TS)::DATE INTO :from_end FROM ERP_SOURCE.VBAK" in sql
    assert "IF (n_new <= 0) THEN" in sql and "'days_added', 0" in sql
    loop = sql[sql.index("FOR i IN 1 TO n_new DO"):sql.index("END FOR;")]
    writes = loop[loop.index("BEGIN TRANSACTION;"):loop.index("COMMIT;")]
    inserts = re.findall(r"INSERT INTO (\w+_SOURCE\.\w+)", writes)
    assert inserts[-1] == "ERP_SOURCE.VBAK", "VBAK, which marks a day as done, must be written last"
    assert set(inserts) == {"ERP_SOURCE.TCURR", "WMS_SOURCE.MARD", "TMS_SOURCE.VTTK", "ERP_SOURCE.VBAP",
                            "ERP_SOURCE.VBAK"}
    assert "CREATE" not in writes.upper().replace("CREATE OR REPLACE", "")  # DDL would commit early
    assert "ROLLBACK;" in sql[sql.index("EXCEPTION"):]


def test_every_appended_row_is_loaded_the_night_after_its_business_date():
    """LOAD_TS = D + 1 at 02:00-05:00 (§3.8), so the cap is NEW_END_DATE 05:00 and freshness moves."""
    loop = code_only(APPEND)
    loop = loop[loop.index("BEGIN TRANSACTION;"):loop.index("COMMIT;")]
    for statement in re.findall(r"INSERT INTO \w+_SOURCE\.\w+.*?;", loop, re.S):
        assert ("DATEADD(day, 1, :d)::TIMESTAMP_NTZ" in statement or "DATEADD(day, 1, d)::TIMESTAMP_NTZ" in statement
                or "FROM TMP_FXDAY" in statement), statement[:120]


def test_the_append_is_anchored_on_the_generators_end_date_not_the_clock():
    sql = code_only(APPEND)
    assert "PARAMS:procedure::VARCHAR = 'SP_GENERATE_DATA'" in sql
    assert "SUM(IFF(d <= :l0, w, 0)) OVER () AS tw" in sql  # the generator's total weight
    assert "CURRENT_DATE" not in sql.upper()


# ── SP_GEN_SELF_CHECKS knows about appended days (CoCo, runs/C17b_run.md §3) ──

SELF_CHECKS = (DATA_GEN / "30_sp_gen_self_checks.sql").read_text(encoding="utf-8")


def test_the_injection_cross_checks_count_only_the_generators_load():
    """Appended versions and variants are by design, so the log-vs-data checks stop at END_DATE 05:00."""
    checks = SELF_CHECKS.split("WITH lg AS (SELECT CODE")[1].split("FROM c;")[0]
    # one check per UNION ALL branch; masters (KNA1, LFA1, MARA) are never appended
    counted = [c for c in checks.split("UNION ALL")
               if re.search(r"FROM (?:ERP|TMS|WMS)_SOURCE\.(?:VBAK|VBAP|VTTK|MARD)\b(?!\s+o\b)", c)]
    assert len(counted) == 10
    for count in counted:
        assert "LOAD_TS <= :gen_cap" in count, count[:90]


def test_the_load_cap_moves_to_the_last_appended_day_and_appended_rows_match_the_log():
    assert "COALESCE(:app_end, :gen_end)" in SELF_CHECKS
    assert "'APPEND_ROWS'" in SELF_CHECKS and "PARAMS:procedure::VARCHAR = 'SP_APPEND_DAY'" in SELF_CHECKS
    assert "a.STAGE = 'append'" in SELF_CHECKS


def test_carrier_variants_count_resent_copies_once():
    block = SELF_CHECKS.split("'VTTK.CARRIER_CD',")[1].split("FROM c;")[0]
    assert "COUNT(DISTINCT HASH(TKNUM" in block and "LOAD_TS" not in block.split("FROM TMS_SOURCE.VTTK")[0]
