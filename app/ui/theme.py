"""Design tokens and page CSS for the two themes (design C).

Streamlit can't switch its own theme from code, so the app's light/dark switch works by
re-injecting this CSS with the other token set. Custom HTML and charts read the same
tokens, so everything flips together.
"""

LIGHT = {
    "page": "#EDF1F6", "surface": "#FFFFFF", "raised": "#F6F8FB",
    "ink": "#16233B", "ink2": "#4A5870", "muted": "#667285", "line": "#DCE3EC",
    "blue": "#1F63C4", "bar": "#2A78D6", "bar_muted": "#BED2EC", "src": "#8C96A5",
    "sel": "#E4EEFB", "good": "#0A8A0A", "critical": "#C2362F", "onblue": "#FFFFFF", "track": "#C9D3E0",
    "shadow": "0 1px 2px rgba(22,35,59,0.06), 0 10px 28px rgba(22,35,59,0.09)",
}

DARK = {
    "page": "#121821", "surface": "#1B2330", "raised": "#222B39",
    "ink": "#EAF0F8", "ink2": "#AAB6C7", "muted": "#8492A6", "line": "#2A3546",
    "blue": "#6AAEFF", "bar": "#3987E5", "bar_muted": "#2C4466", "src": "#6B788C",
    "sel": "#1C3151", "good": "#34C759", "critical": "#FF6B61", "onblue": "#0E1624", "track": "#34507A",
    "shadow": "inset 0 1px 0 rgba(255,255,255,0.05), 0 14px 34px rgba(0,0,0,0.38)",
}

FONT_STACK = "'Instrument Sans', system-ui, -apple-system, 'Segoe UI', sans-serif"

# Fonts may load from any HTTPS domain under the SiS content security policy; external
# stylesheets may not, hence @font-face instead of a Google Fonts <link>.
FONT_FACES = "".join(
    f"@font-face{{font-family:'Instrument Sans';font-style:normal;font-weight:{weight};font-display:swap;"
    f"src:url(https://fonts.gstatic.com/s/instrumentsans/v4/{file}) format('truetype');}}"
    for weight, file in [
        (400, "pximypc9vsFDm051Uf6KVwgkfoSxQ0GsQv8ToedPibnr-yp2JGEJOH9npSTF-Qf1.ttf"),
        (500, "pximypc9vsFDm051Uf6KVwgkfoSxQ0GsQv8ToedPibnr-yp2JGEJOH9npST3-Qf1.ttf"),
        (600, "pximypc9vsFDm051Uf6KVwgkfoSxQ0GsQv8ToedPibnr-yp2JGEJOH9npSQb_gf1.ttf"),
        (700, "pximypc9vsFDm051Uf6KVwgkfoSxQ0GsQv8ToedPibnr-yp2JGEJOH9npSQi_gf1.ttf"),
    ]
)


def tokens(dark: bool) -> dict:
    return DARK if dark else LIGHT


def page_css(t: dict, active_nav: str, active_keys: list[str]) -> str:
    """The whole-page stylesheet. `active_nav` / `active_keys` get the selected styling."""
    active_rules = "".join(
        f".st-key-{key} button{{background:{t['sel']} !important;color:{t['ink']} !important;"
        f"font-weight:600 !important;border-color:{t['blue']} !important;}}"
        for key in [f"nav_{active_nav}", *active_keys]
    )
    return f"""<style>
{FONT_FACES}
html, body, .stApp, .stApp :is(h1, h2, h3, h4, h5, h6, p, div, span, label, li, td, th, button, input, textarea):not([data-testid="stIconMaterial"]) {{
  font-family: {FONT_STACK}; }}
html, body, .stApp {{ background: {t['page']}; color: {t['ink']}; }}
/* Streamlit's fixed top bar is invisible here but still sat over our menu and swallowed clicks */
[data-testid="stHeader"] {{ background: transparent; pointer-events: none; height: 0; }}
[data-testid="stToolbar"] {{ display: none; }}
.block-container {{ padding: 1.25rem 2.75rem 4rem; max-width: none; }}
/* HTML views sit flush on the page */
.stApp iframe {{ border: 0; background: transparent; width: calc(100% + 32px) !important; margin-left: -16px; }}
.stApp p, .stApp li, .stApp label, .stApp span, .stApp h1, .stApp h2, .stApp h3 {{ color: inherit; }}
[data-testid="stMarkdownContainer"] p {{ margin-bottom: 0; }}
hr {{ border-color: {t['line']}; }}

/* Buttons: secondary = quiet outline, primary = governed blue */
.stApp [data-testid^="stBaseButton"] {{ border-radius: 14px; font-weight: 600; min-height: 44px;
  transition: background-color .2s ease, border-color .2s ease, color .2s ease; }}
.stApp [data-testid="stBaseButton-secondary"] {{ background: {t['surface']}; color: {t['ink']}; border: 1px solid {t['line']}; }}
.stApp [data-testid="stBaseButton-secondary"]:hover {{ border-color: {t['blue']}; color: {t['blue']}; }}
.stApp [data-testid="stBaseButton-primary"] {{ background: {t['blue']}; color: {t['onblue']}; border: 0; padding: 0 22px; }}
.stApp [data-testid="stBaseButton-primary"]:hover {{ filter: brightness(1.08); color: {t['onblue']}; }}
.stApp [data-testid="stBaseButton-secondary"]:disabled {{ background: transparent; color: {t['muted']};
  border: 1px dashed {t['line']}; text-decoration: line-through; opacity: 1; }}
.stApp button:focus-visible {{ outline: 2px solid {t['bar']}; outline-offset: 3px; }}

/* Header navigation */
.stApp [class*="st-key-nav_"] button {{ border-radius: 999px; min-height: 40px; padding: 4px 14px;
  background: transparent; border: 1px solid transparent; color: {t['ink2']}; font-weight: 500; white-space: nowrap; }}
.stApp [class*="st-key-nav_"] button:hover {{ background: {t['raised']}; color: {t['ink']}; border-color: {t['line']}; }}
/* Header and "next" columns size to their labels. Fixed column shares let a bold, selected
   pill spill onto its neighbour at 1366 px and wrapped the longest "next" label. The header
   row never wraps; the brand column gives way first. */
.stApp [data-testid="stColumn"]:has([class*="st-key-nav_"], .st-key-dark),
.stApp [data-testid="stColumn"]:has([class*="st-key-next_"]) {{ flex: 0 0 auto !important; width: auto !important; min-width: 0; }}
.stApp [data-testid="stColumn"]:has(.sf-brand) {{ flex: 1 1 0 !important; width: auto !important; min-width: 0; overflow-x: clip; }}
.stApp [data-testid="stHorizontalBlock"]:has(> [data-testid="stColumn"] .st-key-nav_problem) {{ justify-content: space-between; flex-wrap: nowrap; }}
.stApp [data-testid="stColumn"]:has([class*="st-key-nav_"]) [data-testid="stHorizontalBlock"] {{ gap: 4px; flex-wrap: nowrap; }}
.stApp [data-testid="stHorizontalBlock"]:has(> [data-testid="stColumn"] [class*="st-key-next_"]) {{ justify-content: flex-end; }}
.stApp [data-testid="stHorizontalBlock"]:has(> [data-testid="stColumn"] [class*="st-key-next_"]) > [data-testid="stColumn"]:not(:has([class*="st-key-next_"])) {{ display: none; }}
.stApp [class*="st-key-next_"] button {{ white-space: nowrap; }}
@media (max-width: 1400px) {{
  .block-container {{ padding-left: 2rem; padding-right: 2rem; }}
  .stApp [class*="st-key-nav_"] button {{ padding: 4px 11px; }}
  .stApp [class*="st-key-nav_"] button p {{ font-size: 15px; }}
}}
{active_rules}

/* Ask: the eight question cards */
.stApp [class*="st-key-qcard_"] button {{ min-height: 104px; height: 100%; justify-content: flex-start; align-items: flex-start;
  text-align: left; white-space: normal; padding: 18px 20px; border-radius: 20px; border: 2px solid transparent;
  background: {t['surface']}; box-shadow: {t['shadow']}; font-size: 16px; font-weight: 500; line-height: 1.45;
  transition: border-color .2s ease, transform .2s ease; }}
.stApp [class*="st-key-qcard_"] button:hover {{ border-color: {t['blue']}; color: {t['ink']}; transform: translateY(-2px); }}
.stApp [class*="st-key-qcard_"] button > div {{ justify-content: flex-start; width: 100%; }}
.stApp [class*="st-key-qcard_"] button p {{ text-align: left; }}

/* Widgets that Streamlit themes itself */
.stApp [data-testid="stExpander"] details {{ background: {t['surface']}; border: 1px solid {t['line']}; border-radius: 16px; }}
.stApp [data-testid="stExpander"] summary {{ color: {t['ink']}; }}
.stApp [data-testid="stChatMessage"] {{ background: {t['surface']}; border-radius: 18px; padding: 16px 18px; box-shadow: {t['shadow']}; }}
.stApp [data-testid="stChatInput"] {{ background: {t['surface']}; border: 1px solid {t['line']}; border-radius: 22px;
  box-shadow: {t['shadow']}; padding: 6px 8px 6px 14px; max-width: 1080px; margin: 0 auto; }}
.stApp [data-testid="stChatInput"]:focus-within {{ border-color: {t['blue']}; }}
.stApp [data-testid="stChatInput"] textarea {{ color: {t['ink']}; font-size: 16px; }}
.stApp [data-testid="stChatInputSubmitButton"] {{ background: {t['blue']}; color: {t['onblue']}; border-radius: 14px; }}
.stApp [data-testid="stBottom"] > div, .stApp [data-testid="stBottomBlockContainer"] {{ background: {t['page']}; }}
.stApp [data-testid="stBaseButton-pills"] {{ background: {t['surface']}; color: {t['ink']}; border: 1px solid {t['line']}; border-radius: 999px; min-height: 36px; font-weight: 500; }}
.stApp [data-testid="stBaseButton-pillsActive"] {{ background: {t['blue']}; color: {t['onblue']}; border-radius: 999px; min-height: 36px; }}
.stApp [data-testid="stCode"] pre, .stApp [data-testid="stCode"] code {{ background: {t['raised']}; color: {t['ink']}; }}
.stApp [data-testid="stWidgetLabel"] p {{ color: {t['ink2']}; font-weight: 600; }}
.stApp [data-testid="stCaptionContainer"] {{ color: {t['muted']}; }}

/* Our own HTML blocks */
.sf-card {{ background: {t['surface']}; border-radius: 24px; padding: 24px; box-shadow: {t['shadow']}; color: {t['ink']}; }}
.sf-h1 {{ font-size: 42px; line-height: 1.08; font-weight: 600; letter-spacing: -0.025em; margin: 0; color: {t['ink']}; }}
.sf-lede {{ font-size: 18px; line-height: 1.5; color: {t['ink2']}; margin: 10px 0 0; max-width: 760px; }}
.sf-h2 {{ font-size: 22px; font-weight: 600; letter-spacing: -0.01em; margin: 0; color: {t['ink']}; }}
.sf-muted {{ color: {t['muted']}; }}
.sf-ink2 {{ color: {t['ink2']}; }}
.sf-blue {{ color: {t['blue']}; }}
.sf-chip {{ display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px; border-radius: 999px; font-size: 14px;
  font-weight: 500; background: {t['raised']}; color: {t['ink']}; border: 1px solid {t['line']}; margin: 0 6px 6px 0; }}
.sf-chip.off {{ background: transparent; color: {t['muted']}; border-style: dashed; }}
.sf-banner {{ display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 18px 24px;
  border-radius: 18px; background: {t['sel']}; color: {t['ink']}; font-size: 17px; font-weight: 500; }}
.sf-table {{ width: 100%; border-collapse: collapse; font-size: 15px; color: {t['ink']}; }}
.sf-table th {{ text-align: left; padding: 10px 8px; font-weight: 600; color: {t['ink2']}; border-bottom: 1px solid {t['line']}; }}
.sf-table td {{ padding: 9px 8px; border-bottom: 1px solid {t['line']}; }}
.sf-table .num {{ text-align: right; font-variant-numeric: tabular-nums; }}
.sf-tag {{ display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 12px; font-weight: 600;
  border: 1px solid {t['line']}; color: {t['ink2']}; }}
.sf-brand {{ display: flex; align-items: center; gap: 12px; font-size: 20px; font-weight: 600; letter-spacing: -0.01em;
  color: {t['ink']}; white-space: nowrap; }}
@media (prefers-reduced-motion: reduce) {{ .stApp [data-testid^="stBaseButton"] {{ transition: none; }} }}
</style>"""

