"""Deploy the app to Streamlit in Snowflake (warehouse runtime), or redeploy it after a change.

Uploads every file under app/, plus deploy/sis/environment.yml, to a stage, keeping its
folders (utils/, ui/, ui/screens/, ui/views/, .streamlit/), then creates or replaces SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO and
makes it live. Run by CoCo (build step B15), from the repo root:

    set SNOWFLAKE_CONNECTION_NAME=<connection>        # same connection as pytest -m live
    python deploy/deploy_app.py                       # deploy or redeploy
    python deploy/deploy_app.py --dry-run             # files and SQL only, no connection
    python deploy/deploy_app.py --grant-usage PLANNER_ROLE BUYER_ROLE

Snowflake docs (fetched 2026-09-27): FROM copies the files once at create time, so a
redeploy is CREATE OR REPLACE; the app isn't live until ADD LIVE VERSION FROM LAST.
A replaced object loses its grants, so --grant-usage roles are granted again every time.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "app"
sys.path.insert(0, str(APP_DIR))

from utils import config  # noqa: E402  contract §1 names

STAGE = f"{config.DATABASE}.APP.FORGE_STAGE"
STAGE_PATH = f"@{STAGE}/app"
APP_OWNER_ROLE = "FORGE_ADMIN"  # owns the app; the persona procedures grant it USAGE (§5.4)
MAIN_FILE = "streamlit_app.py"
TITLE = "Supply Chain Forge"
REQUIRED = {MAIN_FILE, "environment.yml"}  # SiS warehouse runtime reads environment.yml
# SiS's conda file lives outside app/, so Community Cloud installs from app/requirements.txt
# (C15). It is uploaded to the stage root under its usual name.
EXTRA_FILES = {Path("environment.yml"): ROOT / "deploy" / "sis" / "environment.yml"}

# Local-only: pip dependencies (SiS uses environment.yml), bytecode, secrets and keys.
# Matched case-insensitively (review #18, 1 Oct: ".PEM" or ".Env" slipped through before).
SKIP_NAMES = {"requirements.txt", "secrets.toml", ".env", "credentials.json", "connections.toml"}
SKIP_DIRS = {"__pycache__", ".git"}
SKIP_SUFFIXES = {".pyc", ".p8", ".pem", ".key", ".p12", ".pfx", ".crt", ".env"}
SKIP_PREFIXES = ("rsa_key", ".env")

IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")


def app_files(app_dir: Path = APP_DIR) -> list[Path]:
    """Every file to upload, as its path on the stage (relative to app/)."""
    files = []
    for path in sorted(app_dir.rglob("*")):
        rel = path.relative_to(app_dir)
        name, suffix = path.name.lower(), path.suffix.lower()
        if (path.is_file() and not SKIP_DIRS & {part.lower() for part in rel.parts}
                and name not in SKIP_NAMES and suffix not in SKIP_SUFFIXES and not name.startswith(SKIP_PREFIXES)):
            files.append(rel)
    return files + [rel for rel, source in EXTRA_FILES.items() if source.is_file()]


def local_path(rel: Path) -> Path:
    return EXTRA_FILES.get(rel, APP_DIR / rel)


def stage_folder(rel: Path) -> str:
    parent = rel.parent.as_posix()
    return STAGE_PATH if parent == "." else f"{STAGE_PATH}/{parent}"


def plan(role: str = APP_OWNER_ROLE, grant_usage=()) -> tuple[list[str], list[str]]:
    """SQL run before the upload, and SQL run after it."""
    for name in [role, *grant_usage]:
        if not IDENTIFIER.match(name):
            raise ValueError(f"Not a valid role name: {name!r}")
    before = [
        f"USE ROLE {role}",
        f"USE WAREHOUSE {config.WAREHOUSE}",
        f"CREATE STAGE IF NOT EXISTS {STAGE}",
        f"REMOVE {STAGE_PATH}/",  # files deleted from app/ must not linger on the stage
    ]
    after = [
        f"CREATE OR REPLACE STREAMLIT {config.STREAMLIT_APP}\n"
        f"  FROM '{STAGE_PATH}'\n"
        f"  MAIN_FILE = '{MAIN_FILE}'\n"
        f"  QUERY_WAREHOUSE = {config.WAREHOUSE}\n"
        f"  TITLE = '{TITLE}'",
        f"ALTER STREAMLIT {config.STREAMLIT_APP} ADD LIVE VERSION FROM LAST",
        *[f"GRANT USAGE ON STREAMLIT {config.STREAMLIT_APP} TO ROLE {r}" for r in grant_usage],
    ]
    return before, after


def deploy(session, files: list[Path], before: list[str], after: list[str]) -> None:
    for sql in before:
        print(f"  {sql.splitlines()[0]}")
        session.sql(sql).collect()
    for rel in files:
        results = session.file.put(local_path(rel).as_posix(), stage_folder(rel),
                                   auto_compress=False, overwrite=True)
        status = results[0].status if results else "NO RESULT"
        if status.upper() not in ("UPLOADED", "SKIPPED"):
            raise RuntimeError(f"Upload of {rel.as_posix()} failed: {status}")
        print(f"  PUT {rel.as_posix()}")
    for sql in after:
        print(f"  {sql.splitlines()[0]}")
        session.sql(sql).collect()
    described = session.sql(f"DESCRIBE STREAMLIT {config.STREAMLIT_APP}").collect()
    if not described:
        raise RuntimeError(f"{config.STREAMLIT_APP} was not created")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Deploy the app to Streamlit in Snowflake.")
    parser.add_argument("--dry-run", action="store_true", help="print files and SQL; don't connect")
    parser.add_argument("--role", default=APP_OWNER_ROLE, help=f"role that owns the app (default {APP_OWNER_ROLE})")
    parser.add_argument("--grant-usage", nargs="*", default=[], metavar="ROLE",
                        help="roles that may open the app (granted again after every deploy)")
    args = parser.parse_args(argv)

    files = app_files()
    missing = REQUIRED - {f.as_posix() for f in files}
    if missing:
        print(f"Missing from app/: {', '.join(sorted(missing))}", file=sys.stderr)
        return 1
    before, after = plan(args.role, args.grant_usage)

    if args.dry_run:
        print(f"{len(files)} files -> {STAGE_PATH}")
        for rel in files:
            print(f"  {rel.as_posix():40} -> {stage_folder(rel)}")
        print("\nSQL:")
        for sql in [*before, "-- PUT each file above (AUTO_COMPRESS=FALSE, OVERWRITE=TRUE)", *after]:
            print(f"{sql};" if not sql.startswith("--") else sql)
        return 0

    from utils import forge_data  # imports Snowpark only when actually deploying
    print(f"Deploying {len(files)} files to {config.STREAMLIT_APP}")
    deploy(forge_data.get_session(), files, before, after)
    print(f"\nDone. {config.STREAMLIT_APP} is live: Snowsight > Projects > Streamlit > FORGE_DEMO.")
    print("Viewers of an open session see the new version after a rerun (press R).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
