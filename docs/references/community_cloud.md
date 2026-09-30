# Reference: Streamlit Community Cloud + Snowflake key-pair auth

| | |
|---|---|
| **Sources** | <https://docs.streamlit.io/deploy/streamlit-community-cloud/deploy-your-app/app-dependencies> |
| | <https://docs.streamlit.io/deploy/streamlit-community-cloud/deploy-your-app/file-organization> |
| | <https://docs.streamlit.io/deploy/streamlit-community-cloud/deploy-your-app/deploy> |
| | <https://docs.streamlit.io/develop/tutorials/databases/snowflake> |
| | <https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-connect> |
| | <https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-api> |
| | `snowflake-connector-python` **4.7.5** wheel source: `snowflake/connector/connection.py`, `snowflake/connector/auth/keypair.py` |
| **Fetched** | 2026-09-30 |
| **Used by** | C15: `forge_data.session_params()`, `app/requirements.txt`, root `.streamlit/`, `deploy/RUNBOOK.md` |

---

## 1. Dependency files: only one is used

Community Cloud recognises these files, in this order of precedence:

1. `uv.lock`
2. `Pipfile`
3. `environment.yml` (conda)
4. `requirements.txt` (pip)
5. `pyproject.toml`

> "any dependency file in your entrypoint file's directory taking precedence over any
> dependency file in the root of your repository." "If you include more than one...only the
> first file encountered will be used."

**Consequence for this repo:** `app/` must hold only `requirements.txt`. The SiS conda file
lives in `deploy/sis/environment.yml`, and `deploy/deploy_app.py` uploads it to the stage
root.

## 2. Working directory and config.toml

> "Streamlit Community Cloud copies all the files in your repository and executes
> `streamlit run` from its root directory."

`.streamlit/config.toml` must sit at the **repository root**, and only one is read. The app
keeps two identical copies:
- `app/.streamlit/config.toml`, for SiS and for local runs from `app/`
- `.streamlit/config.toml`, for Community Cloud and local runs from the root

A test keeps the two identical. Imports still resolve, because Streamlit puts the entrypoint
script's folder on `sys.path`, and `ui/view.py` finds its files through `Path(__file__)`.

## 3. Python version and secrets

- Both are set in the deploy dialog's **Advanced settings**. The Python default is 3.12;
  this app uses **3.11** (the same as CI and `deploy/sis/environment.yml`).
- Secrets: paste the contents of a `secrets.toml` into the "Secrets" field. The app reads
  them with `st.secrets`. Locally, Streamlit reads `.streamlit/secrets.toml` from the
  working directory (and `~/.streamlit/secrets.toml`).
- Streamlit's own Snowflake example uses `[connections.snowflake]` with `private_key_file`.
  That needs a file, and Community Cloud has none. This app builds its own Snowpark session
  from the same section (§4).

## 4. The connector's private-key parameters (4.7.5 source)

`connection.py`, the accepted types:
```
"private_key": (None, (type(None), bytes, str, RSAPrivateKey)),
"private_key_passphrase": (None, (type(None), bytes)),
"private_key_file": (None, (type(None), str)),
"private_key_file_pwd": (None, (type(None), str, bytes)),
```
`auth/keypair.py`:
- `str` → `base64.b64decode()`, then `load_der_private_key()`. **A PEM string is not
  accepted as-is.**
- `bytes` → `load_der_private_key()`, i.e. DER bytes.
- an `RSAPrivateKey` / `EllipticCurvePrivateKey` object → used directly.
- `private_key_file` → the file is opened and read as PEM.

**What the app does:** secrets hold the PEM text (a TOML multi-line string).
`forge_data.session_params()` loads it with
`cryptography.hazmat.primitives.serialization.load_pem_private_key`, re-serialises it as
PKCS#8 DER **bytes**, and passes `private_key=<bytes>`, `authenticator="SNOWFLAKE_JWT"`.
The bytes form works on every connector version.

Other `connect()` parameters in use:
- `login_timeout`: login timeout in seconds; the default is 60.
- `network_timeout`: none by default.
- `client_session_keep_alive`
- `session_parameters`: a dict of session parameters, e.g.
  `STATEMENT_TIMEOUT_IN_SECONDS` or `QUERY_TAG`.

## 5. Key pair (from Snowflake's key-pair guide)

```
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```
The public key body (without the header and footer lines) goes to
`ALTER USER … SET RSA_PUBLIC_KEY = '…'`. The private key goes only into Community Cloud's
secrets, never into the repo (`.gitignore` covers `*.p8`, `*.pem`, `rsa_key*`).

## 6. Sleeping apps

A Community Cloud app with no traffic goes to sleep, and a visitor then sees a "wake up"
button. `.github/workflows/keep_awake.yml` opens the public URL every 6 hours. Scheduled
workflows run **only from the default branch**, so the workflow must be on `main`.
