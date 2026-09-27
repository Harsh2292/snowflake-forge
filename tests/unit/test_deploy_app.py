"""deploy/deploy_app.py: uploads the whole app (views included), nothing local-only, and
runs the Streamlit-in-Snowflake SQL in the right order. Offline, with a fake session."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

from utils import config

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("deploy_app", ROOT / "deploy" / "deploy_app.py")
deploy_app = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(deploy_app)

FILES = {f.as_posix() for f in deploy_app.app_files()}


def test_every_file_the_app_needs_is_uploaded():
    app = ROOT / "app"
    needed = {p.relative_to(app).as_posix() for p in app.rglob("*")
              if p.is_file() and p.suffix in {".py", ".html", ".css", ".js", ".toml", ".yml"}
              and "__pycache__" not in p.parts and p.name != "requirements.txt"}
    assert needed <= FILES
    assert {"streamlit_app.py", "environment.yml", ".streamlit/config.toml", "ui/views/base.js"} <= FILES


def test_local_only_files_are_left_out():
    assert "requirements.txt" not in FILES
    assert not any("__pycache__" in f or f.endswith(".pyc") for f in FILES)


def test_files_keep_their_folders_on_the_stage():
    assert deploy_app.stage_folder(Path("streamlit_app.py")) == deploy_app.STAGE_PATH
    assert deploy_app.stage_folder(Path("ui/views/fix.html")) == f"{deploy_app.STAGE_PATH}/ui/views"


def test_sql_uses_contract_names_in_order():
    before, after = deploy_app.plan(grant_usage=["PLANNER_ROLE"])
    assert before[0] == "USE ROLE FORGE_ADMIN"
    assert after[0].startswith(f"CREATE OR REPLACE STREAMLIT {config.STREAMLIT_APP}")
    assert f"QUERY_WAREHOUSE = {config.WAREHOUSE}" in after[0]
    assert after[1] == f"ALTER STREAMLIT {config.STREAMLIT_APP} ADD LIVE VERSION FROM LAST"
    assert after[2] == f"GRANT USAGE ON STREAMLIT {config.STREAMLIT_APP} TO ROLE PLANNER_ROLE"


@pytest.mark.parametrize("role", ["PLANNER_ROLE; DROP DATABASE X", "1ROLE", ""])
def test_role_names_are_validated(role):
    with pytest.raises(ValueError):
        deploy_app.plan(grant_usage=[role])


class FakeSession:
    def __init__(self):
        self.log = []
        self.file = SimpleNamespace(put=self._put)

    def sql(self, sql):
        self.log.append(sql.splitlines()[0])
        return SimpleNamespace(collect=lambda: [{"name": "FORGE_DEMO"}])

    def _put(self, local, stage, auto_compress, overwrite):
        assert Path(local).is_file() and auto_compress is False and overwrite is True
        self.log.append(f"PUT {stage}")
        return [SimpleNamespace(status="UPLOADED")]


def test_deploy_uploads_between_setup_and_create():
    session = FakeSession()
    files = deploy_app.app_files()
    deploy_app.deploy(session, files, *deploy_app.plan())
    puts = [i for i, line in enumerate(session.log) if line.startswith("PUT")]
    create = next(i for i, line in enumerate(session.log) if line.startswith("CREATE OR REPLACE STREAMLIT"))
    remove = next(i for i, line in enumerate(session.log) if line.startswith("REMOVE"))
    assert len(puts) == len(files)
    assert remove < min(puts) and max(puts) < create
    assert session.log[-1] == f"DESCRIBE STREAMLIT {config.STREAMLIT_APP}"


def test_failed_upload_stops_the_deploy():
    session = FakeSession()
    session.file.put = lambda *a, **k: [SimpleNamespace(status="ERROR")]
    with pytest.raises(RuntimeError, match="failed"):
        deploy_app.deploy(session, deploy_app.app_files(), *deploy_app.plan())
    assert not any(line.startswith("CREATE OR REPLACE") for line in session.log)


def test_dry_run_needs_no_snowflake(capsys, monkeypatch):
    monkeypatch.setattr("utils.forge_data.get_session", lambda: pytest.fail("dry run connected"))
    assert deploy_app.main(["--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "ui/views/explore.html" in out and "ADD LIVE VERSION FROM LAST" in out
