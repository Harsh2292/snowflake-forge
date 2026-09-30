"""CoCo's helper for running repo SQL files through the SQL tool (B08m, 2026-09-30).

Load it in CoCo's Python REPL (the `coco` tool bridge must exist there):

    exec(open(r'e:\\DevStuff\\snowflake-forge\\sql\\replay_helper.py', encoding='utf-8').read())
    CONN = 'QURFOQP-XU04029'                      # the event account's VS Code connection
    run_file('sql/01_setup/01_database.sql', 'ACCOUNTADMIN', CONN)
    q("CALL SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS('SUPPLY_CHAIN_FORGE')", 'FORGE_ADMIN', CONN)
    fetch_json("CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL')", 'FORGE_ADMIN', CONN)

Why it exists (docs/references/snowflake_execution_notes.md, runs/C16_run.md):
- One tool call = one session: USE ROLE / USE SCHEMA only hold inside the same call, so a file
  is sent as ONE call, with the role and warehouse prepended.
- The Windows tool bridge garbles non-ASCII text. Full-line comments with non-ASCII are dropped;
  any statement that still holds non-ASCII is sent base64-encoded and decoded server-side
  (EXECUTE IMMEDIATE inside an anonymous block, same session, so USE state still applies).
  Results that may hold non-ASCII are fetched base64-encoded too (fetch_json).
- A call returns only its LAST statement's result: use run_each() for run files (99_run.sql)
  when every CALL's output matters, or q() one step at a time.
- The REPL can time out on long calls while the query keeps running: poll QUERY_HISTORY.
- The REPL can restart and lose state: re-run the exec() line above.
"""
import base64, json, os, re

ROOT = r'e:\DevStuff\snowflake-forge'


def statements(path):
    """Split a SQL file into statements, respecting '...' strings, $$ blocks and comments."""
    text = open(os.path.join(ROOT, path), encoding='utf-8').read()
    # Drop full-line comments (they carry most of the non-ASCII); keep code lines as they are.
    text = '\n'.join(l for l in text.split('\n') if not l.lstrip().startswith('--'))
    out, cur, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith('$$', i):
            j = text.find('$$', i + 2)
            j = n if j < 0 else j + 2
            cur.append(text[i:j]); i = j; continue
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == '\\': j += 2; continue
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'": j += 2; continue
                    break
                j += 1
            cur.append(text[i:j + 1]); i = j + 1; continue
        if text.startswith('--', i):
            j = text.find('\n', i); j = n if j < 0 else j
            cur.append(text[i:j]); i = j; continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            cur.append(text[i:j]); i = j; continue
        if c == ';':
            s = ''.join(cur).strip()
            if re.sub(r'--[^\n]*', '', s).strip(): out.append(s)
            cur = []; i += 1; continue
        cur.append(c); i += 1
    s = ''.join(cur).strip()
    if re.sub(r'--[^\n]*', '', s).strip(): out.append(s)
    return out


def _safe(stmt):
    """ASCII statements go as they are; others are base64-wrapped and decoded server-side."""
    if all(ord(ch) < 128 for ch in stmt):
        return stmt
    b = base64.b64encode(stmt.encode('utf-8')).decode()
    return ("EXECUTE IMMEDIATE $$ DECLARE s VARCHAR DEFAULT BASE64_DECODE_STRING('" + b + "'); "
            "BEGIN EXECUTE IMMEDIATE :s; RETURN 'ok'; END; $$")


def q(sql, role, conn, wh='FORGE_WH', timeout=1200, desc=None):
    """Run one statement (or a ;-chain) as ROLE on WH. Returns the tool's text output."""
    full = f'USE ROLE {role}; USE WAREHOUSE {wh};\n' + sql
    return str(coco.tool('sql_execute', {'sql': full, 'connection': conn, 'timeout_seconds': timeout,
                                         'description': desc or f'{role}: {sql[:60]}'}))


def run_file(path, role, conn, wh='FORGE_WH', timeout=1200):
    """Send a whole DDL file as ONE call (USE statements in the file hold for the whole file)."""
    body = ';\n'.join(_safe(s) for s in statements(path)) + ';'
    r = q(body, role, conn, wh, timeout, desc=f'replay {path} as {role}')
    print(path, '->', r[:300].replace('\n', ' '))
    return r


def run_each(path, role, conn, wh='FORGE_WH', timeout=1200):
    """One call per statement (for run files whose every result matters)."""
    res = []
    for k, s in enumerate(statements(path)):
        r = q(_safe(s), role, conn, wh, timeout, desc=f'{path} step {k + 1} as {role}')
        print(f'{path} [{k + 1}]', s[:70].replace('\n', ' '), '->', r[:200].replace('\n', ' '))
        res.append(r)
    return res


def fetch_json(sql, role, conn, wh='FORGE_WH'):
    """Run a statement returning one VARIANT/JSON value; fetch it base64 (non-ASCII safe)."""
    r = q(sql + ';\nSELECT BASE64_ENCODE(TO_JSON($1)) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))',
          role, conn, wh)
    m = re.findall(r'[A-Za-z0-9+/=\n]{40,}', r)
    return json.loads(base64.b64decode(max(m, key=len).replace('\n', '')).decode('utf-8'))
