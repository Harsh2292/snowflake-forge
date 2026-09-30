"""C15: the repo is public, so no key, secret or account name may ever be committed.

Runs in CI inside `pytest -q`. Scans every file git tracks or would track (untracked files
not ignored), and proves on planted examples that each check really catches its case.
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]

# A PEM private-key block with a body (a header on its own, as in docs, is fine).
PEM_KEY = re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----\s*[A-Za-z0-9+/=]{40,}")
# A real account hostname: <something>.snowflakecomputing.com
ACCOUNT_HOST = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.snowflakecomputing\.com", re.I)
# account = "<value>" in TOML / config style, where the value isn't a placeholder
ACCOUNT_VALUE = re.compile(r"""^\s*account\s*=\s*["']([^"']*)["']""", re.I | re.M)
KEY_SUFFIXES = {".p8", ".pem", ".key", ".p12", ".pfx"}
SECRET_NAMES = {"secrets.toml", "connections.toml", ".env", "credentials.json"}


def _placeholder(value: str) -> bool:
    return not value.strip() or "<" in value or value.lower() in {"xxx", "your-account", "account"}


def scan(paths, root: Path) -> list[str]:
    """Findings as 'path: problem' lines, empty when clean."""
    findings = []
    for rel in paths:
        path = root / rel
        if path.name in SECRET_NAMES:
            findings.append(f"{rel}: secrets file")
        if path.suffix.lower() in KEY_SUFFIXES or path.name.startswith("rsa_key"):
            findings.append(f"{rel}: key file")
        if not path.is_file() or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue  # binary: images and the like
        if PEM_KEY.search(text):
            findings.append(f"{rel}: private key block")
        if ACCOUNT_HOST.search(text):
            findings.append(f"{rel}: Snowflake account hostname")
        for value in ACCOUNT_VALUE.findall(text):
            if not _placeholder(value):
                findings.append(f"{rel}: account identifier")
    return findings


def _git(*args) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


@pytest.fixture(scope="module")
def repo_files():
    if shutil.which("git") is None or _git("rev-parse", "--git-dir").returncode != 0:
        pytest.skip("not a git checkout")
    out = _git("ls-files", "-co", "--exclude-standard").stdout
    return [line for line in out.splitlines() if line]


def test_no_key_secret_or_account_name_in_the_repo(repo_files):
    assert scan(repo_files, ROOT) == []


@pytest.mark.parametrize("path", [".streamlit/secrets.toml", "app/.streamlit/secrets.toml", "rsa_key.p8",
                                  "rsa_key.pub", "deploy/app_key.pem"])
def test_secrets_and_keys_are_git_ignored(repo_files, path):
    assert _git("check-ignore", "-q", path).returncode == 0, f"{path} is not git-ignored"


def test_the_secrets_example_is_only_a_shape():
    example = ROOT / ".streamlit" / "secrets.toml.example"
    import tomllib
    data = tomllib.loads(example.read_text(encoding="utf-8"))
    snowflake = data["connections"]["snowflake"]
    assert _placeholder(snowflake["account"]) and "<" in snowflake["private_key"]
    assert scan([example.relative_to(ROOT)], ROOT) == []


# ── Deliberate breaks: each check must catch its case ───────────────────────

def _pem() -> str:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                             serialization.NoEncryption()).decode()


def test_catches_a_pasted_private_key(tmp_path):
    (tmp_path / "notes.md").write_text(f"oops\n{_pem()}", encoding="utf-8")
    assert scan(["notes.md"], tmp_path) == ["notes.md: private key block"]


def test_catches_key_and_secrets_files(tmp_path):
    for name in ["rsa_key.p8", "secrets.toml"]:
        (tmp_path / name).write_text("x", encoding="utf-8")
    assert sorted(scan(["rsa_key.p8", "secrets.toml"], tmp_path)) == ["rsa_key.p8: key file",
                                                                       "secrets.toml: secrets file"]


def test_catches_an_account_hostname_and_identifier(tmp_path):
    host = "ab12345.central-india.azure" + ".snowflakecomputing.com"
    (tmp_path / "a.py").write_text(f'URL = "https://{host}"\n', encoding="utf-8")
    (tmp_path / "b.toml").write_text('account = "myorg-myaccount"\n', encoding="utf-8")
    assert scan(["a.py", "b.toml"], tmp_path) == ["a.py: Snowflake account hostname",
                                                  "b.toml: account identifier"]


def test_placeholders_and_bare_headers_pass(tmp_path):
    (tmp_path / "c.toml").write_text('account = "<orgname-accountname>"\n'
                                     'private_key = """\n-----BEGIN PRIVATE KEY-----\n<paste>\n"""\n',
                                     encoding="utf-8")
    assert scan(["c.toml"], tmp_path) == []
