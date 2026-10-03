"""Fill the CoCo CLI Hackathon submission template for Supply Chain Forge.

Usage: python build_deck.py template.pptx shots_dir out.pptx
"""
import copy
import sys
from pathlib import Path

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Inches, Pt

TEMPLATE, SHOTS, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])

FONT = "Arial"
INK = RGBColor(0x0B, 0x12, 0x20)
INK2 = RGBColor(0x33, 0x41, 0x55)
MUTED = RGBColor(0x5B, 0x6B, 0x82)
BLUE = RGBColor(0x1A, 0x5F, 0xD6)
CYAN = RGBColor(0x00, 0x9C, 0xDE)
TINT = RGBColor(0xEE, 0xF4, 0xFD)
TINT2 = RGBColor(0xE3, 0xEC, 0xFB)
LINE = RGBColor(0xD5, 0xDF, 0xEE)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
GREEN = RGBColor(0x1E, 0x8E, 0x4E)
GREY = RGBColor(0x6B, 0x72, 0x80)
NAVY = RGBColor(0x0E, 0x2A, 0x5C)

LIVE = "supply-chain-forge.streamlit.app"
REPO = "github.com/Harsh2292/snowflake-forge"

prs = Presentation(str(TEMPLATE))
slides = list(prs.slides)
title_slide, guide_slide, blank_a, blank_b, extra_slide, thanks_slide = slides


# ── helpers ──────────────────────────────────────────────────────────────

def text(slide, x, y, w, h, paras, size=12, color=INK, bold=False, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, spacing=0, name=None):
    """paras: a string, or a list of paragraphs; each paragraph a string or a list of
    (text, {bold, color, size, italic}) runs."""
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        box.name = name
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        if spacing:
            p.space_after = Pt(spacing)
        runs = [(para, {})] if isinstance(para, str) else para
        for t, o in runs:
            r = p.add_run()
            r.text = t
            f = r.font
            f.name = FONT
            f.size = Pt(o.get("size", size))
            f.bold = o.get("bold", bold)
            f.italic = o.get("italic", False)
            f.color.rgb = o.get("color", color)
    return box


def box(slide, x, y, w, h, fill=TINT, line=None, radius=0.12, name=None, shadow=False):
    shp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        shp.name = name
    shp.adjustments[0] = min(0.5, radius / min(w, h))
    shp.fill.solid()
    shp.fill.fore_color.rgb = fill
    if line is None:
        shp.line.fill.background()
    else:
        shp.line.color.rgb = line
        shp.line.width = Pt(0.75)
    if not shadow:
        sp_pr = shp._element.spPr
        sp_pr.append(etree.SubElement(sp_pr, qn("a:effectLst")))
    shp.text_frame.text = ""
    return shp


def label_in(shp, paras, size=11, color=INK, bold=False, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, margin=0.06):
    tf = shp.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = Inches(margin)
    tf.margin_top = tf.margin_bottom = Inches(0.03)
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        runs = [(para, {})] if isinstance(para, str) else para
        for t, o in runs:
            r = p.add_run()
            r.text = t
            f = r.font
            f.name = FONT
            f.size = Pt(o.get("size", size))
            f.bold = o.get("bold", bold)
            f.color.rgb = o.get("color", color)


def arrow(slide, x1, y1, x2, y2, color=MUTED, width=1.25, dash=False):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = color
    c.line.width = Pt(width)
    ln = c.line._get_or_add_ln()
    if dash:
        d = etree.SubElement(ln, qn("a:prstDash"))
        d.set("val", "dash")
    tail = etree.SubElement(ln, qn("a:tailEnd"))
    tail.set("type", "triangle")
    tail.set("w", "med")
    tail.set("len", "med")
    return c


def title(slide, t, sub=None):
    text(slide, 0.45, 0.68, 9.1, 0.42, t, size=22, bold=True, color=INK, name="Title")
    if sub:
        text(slide, 0.45, 1.1, 9.1, 0.3, sub, size=11.5, color=MUTED, name="Subtitle")


def new_content_slide(source):
    """A new slide with the template's header picture (same image part)."""
    pic = next(s for s in source.shapes if s.shape_type == 13)
    s = prs.slides.add_slide(source.slide_layout)
    for ph in list(s.placeholders):
        ph._element.getparent().remove(ph._element)
    blob = pic.image.blob
    import io
    s.shapes.add_picture(io.BytesIO(blob), 0, 0, prs.slide_width, prs.slide_height)
    return s


def move_slide(slide, index):
    lst = prs.slides._sldIdLst
    el = next(e for e in lst if prs.slides.get(int(e.get("id"))) is slide) if False else None
    for e in list(lst):
        if prs.slides._sldIdLst.index(e) >= 0 and prs.part.related_part(e.get(qn("r:id"))) is slide.part:
            el = e
    lst.remove(el)
    lst.insert(index, el)


def delete_slide(slide):
    lst = prs.slides._sldIdLst
    for e in list(lst):
        if prs.part.related_part(e.get(qn("r:id"))) is slide.part:
            prs.part.drop_rel(e.get(qn("r:id")))
            lst.remove(e)


def add_shot(slide, name, x, y, w, crop_bottom=0.0, crop_top=0.0):
    pic = slide.shapes.add_picture(str(SHOTS / f"{name}.png"), Inches(x), Inches(y), width=Inches(w))
    pic.crop_bottom = crop_bottom
    pic.crop_top = crop_top
    # keep the aspect after cropping
    pic.height = int(pic.height * (1 - crop_bottom - crop_top)) if False else pic.height
    ln = pic.line
    ln.color.rgb = LINE
    ln.width = Pt(0.75)
    return pic


# ── 1. Title slide: fill the four fields ─────────────────────────────────

fields = {
    "Team Name :": "Supply Chain Forge",
    "Team Leader Name :": "Harsh Patel",
    "Team Size :": "1",
    "Problem Statement :": "Supply Chain Ontology and Governed Conversational Analytics",
}
for shp in title_slide.shapes:
    key = shp.text_frame.text.strip() if shp.has_text_frame else None
    if key in fields:
        p = shp.text_frame.paragraphs[0]
        r = copy.deepcopy(p.runs[-1]._r)
        p.runs[-1]._r.addnext(r)
        p.runs[-1].text = " " + fields[key]
        p.runs[-1].font.bold = True
        p.runs[-1].font.color.rgb = NAVY

# ── 2. Problem brief ─────────────────────────────────────────────────────

s = blank_a
title(s, "Problem brief: four systems, four versions of the truth")
rows = [
    ("The business problem",
     "Supply chain data sits in four systems (ERP, WMS, TMS, SRM) that name and date things their own way. "
     "Ask “What is our on-time delivery rate?” and each team gets a different answer."),
    ("Who it is for",
     "Production planners, procurement leads (buyers) and logistics coordinators, plus the leaders "
     "who need one number they can act on."),
    ("Pain today → with Supply Chain Forge",
     "Teams reconcile spreadsheets and argue about whose number is right. Now every metric is defined "
     "once in a Snowflake semantic view, and people, dashboards and the AI agent all read that one definition."),
    ("Industry context",
     "Manufacturing and distribution: 12 plants in APAC, EMEA and AMER, 150 suppliers, 1,200 parts, "
     "~725K orders and ~780K shipments over 10 years, with SAP-style source tables and real-world defects."),
]
y = 1.3
for (head, body), step in zip(rows, [1.02, 0.84, 1.02, 1.0]):
    text(s, 0.45, y, 5.55, 0.22, head, size=11.5, bold=True, color=BLUE)
    text(s, 0.45, y + 0.24, 5.55, 0.62, body, size=10.5, color=INK2)
    y += step

card = box(s, 6.35, 1.3, 3.2, 3.85, fill=TINT, name="Stat card")
text(s, 6.6, 1.45, 2.8, 0.5, "Leadership asks: “What is our on-time delivery rate?”",
     size=11, bold=True, color=INK)
text(s, 6.6, 2.05, 2.8, 0.2, "Planning says", size=10, color=MUTED)
text(s, 6.6, 2.25, 2.8, 0.55, "68.2%", size=32, bold=True, color=GREY)
text(s, 6.6, 2.8, 2.8, 0.2, "using the ERP order date", size=9.5, color=MUTED)
text(s, 6.6, 3.15, 2.8, 0.2, "Logistics says", size=10, color=MUTED)
text(s, 6.6, 3.35, 2.8, 0.55, "87.5%", size=32, bold=True, color=BLUE)
text(s, 6.6, 3.9, 2.8, 0.2, "using the carrier’s promised date", size=9.5, color=MUTED)
text(s, 6.6, 4.3, 2.8, 0.7,
     [[("Same shipments, 19.3 points apart.", {"bold": True})],
      "Supply Chain Forge makes 87.5% the one governed answer, for every team."],
     size=10, color=INK2, spacing=2)

# ── 3. Architecture ──────────────────────────────────────────────────────

s = blank_b
title(s, "Architecture: one governed layer, built and run in Snowflake")

# Lane labels
lane_y = 1.2
for x, w, t in [(0.45, 1.45, "Data sources"), (2.15, 1.55, "Cleaned"), (3.95, 1.55, "Governed"),
                (5.75, 1.6, "Ontology"), (7.6, 1.95, "Consumers")]:
    text(s, x, lane_y, w, 0.2, t.upper(), size=8.5, bold=True, color=MUTED)

# Sources
src = [("ERP", "orders, customers, FX"), ("WMS", "inventory, usage"), ("TMS", "shipments, carriers"),
       ("SRM", "suppliers, parts, contracts")]
sy = 1.45
for i, (n, d) in enumerate(src):
    b = box(s, 0.45, sy + i * 0.6, 1.45, 0.5, fill=WHITE, line=LINE)
    label_in(b, [[(n, {"bold": True, "size": 10})], [(d, {"size": 7.5, "color": MUTED})]])
text(s, 0.45, 3.9, 1.45, 0.45, "Structured tables, SAP-style names, 19 kinds of defects",
     size=7.5, color=MUTED)

mid = sy + 1.5 * 0.6 + 0.25  # vertical centre of the source stack
b = box(s, 2.15, 1.6, 1.55, 1.95, fill=TINT)
label_in(b, [[("CONFORMED", {"bold": True, "size": 10})],
             [("10 incremental dynamic tables", {"size": 8, "color": INK2})],
             [("dedupe, code maps, FX to USD, test and orphan removal, dq_flags", {"size": 7.5, "color": MUTED})]])
b = box(s, 3.95, 1.6, 1.55, 1.95, fill=TINT)
label_in(b, [[("GOVERNED", {"bold": True, "size": 10})],
             [("9 business-named views", {"size": 8, "color": INK2})],
             [("masking policies per role, sensitivity tags, persona procedures", {"size": 7.5, "color": MUTED})]])
b = box(s, 5.75, 1.6, 1.6, 1.95, fill=BLUE)
label_in(b, [[("SUPPLY_CHAIN_SV", {"bold": True, "size": 9.5, "color": WHITE})],
             [("semantic view", {"size": 8, "color": WHITE})],
             [("10 entities, 12 relationships, 4 canonical + 15 metrics, 14 verified queries",
               {"size": 7.5, "color": WHITE})]])

for x1, x2 in [(1.9, 2.15), (3.7, 3.95), (5.5, 5.75)]:
    arrow(s, x1, 2.575, x2, 2.575)

# Consumers
cons = [("Cortex Agent", "Analyst + data_health tool"), ("Streamlit app", "router: instant (~1 s) or agent"),
        ("3 personas", "same number, different masking")]
for i, (n, d) in enumerate(cons):
    yy = 1.6 + i * 0.68
    b = box(s, 7.6, yy, 1.95, 0.56, fill=WHITE, line=LINE)
    label_in(b, [[(n, {"bold": True, "size": 9.5})], [(d, {"size": 7.5, "color": MUTED})]])
    arrow(s, 7.35, 2.575, 7.6, yy + 0.28)

# Data quality band under the pipeline
b = box(s, 2.15, 3.7, 5.2, 0.42, fill=WHITE, line=LINE)
label_in(b, [[("77 Data Metric Functions + SP_DATA_HEALTH", {"bold": True, "size": 8.5}),
              ("  check every layer for freshness and defects", {"size": 8, "color": MUTED})]])
text(s, 7.6, 3.75, 1.95, 0.4, "Input: plain-English questions (unstructured)", size=7.5, color=MUTED)

# CoCo CLI skills strip
text(s, 0.45, 4.3, 9.1, 0.2, "BUILT WITH COCO CLI SKILLS, EACH OWNING ONE LAYER", size=8.5, bold=True, color=MUTED)
skills = [("sql-author", "schemas, DDL"), ("dynamic-tables", "CONFORMED"), ("data-governance", "masking, tags"),
          ("agent-studio", "semantic view, agent"), ("data-quality", "DMFs, health"), ("lineage", "validation")]
sw, gap = 1.4, 0.14
for i, (n, d) in enumerate(skills):
    x = 0.45 + i * (sw + gap)
    b = box(s, x, 4.52, sw, 0.5, fill=NAVY)
    label_in(b, [[(n, {"bold": True, "size": 8.5, "color": WHITE})], [(d, {"size": 7, "color": TINT2})]])
    if i < len(skills) - 1:
        arrow(s, x + sw, 4.77, x + sw + gap, 4.77, color=MUTED, width=1)

# ── 4. Impact ────────────────────────────────────────────────────────────

s = new_content_slide(blank_a)
title(s, "Impact: one trusted number, answered in seconds")
stats = [
    ("0.000000", "difference between Planner, Buyer and Logistics on all 4 metrics (6 decimal places)"),
    ("19.3 pts", "of cross-team disagreement on on-time delivery removed (68.2% vs 87.5%)"),
    ("~1 s", "instant governed answers with no LLM call; agent answers ~12 s at p50"),
    ("28 / 30", "agent evaluation questions correct, incl. multi-part, Hindi and refusals"),
]
cw = 2.1
for i, (big, small) in enumerate(stats):
    x = 0.45 + i * (cw + 0.2)
    box(s, x, 1.3, cw, 1.4, fill=TINT)
    text(s, x + 0.15, 1.42, cw - 0.3, 0.5, big, size=24, bold=True, color=BLUE)
    text(s, x + 0.15, 1.95, cw - 0.3, 0.7, small, size=10, color=INK2)

cols = [
    ("Measurable outcomes", [
        "One definition per metric replaces per-team SQL and spreadsheet reconciliation",
        "93/93 data-quality self-checks pass; 77 DMFs watch every load",
        "Masking enforced by Snowflake policies, not by the app",
    ]),
    ("Scalability", [
        "Incremental dynamic tables and an XS warehouse handle ~6M source rows",
        "Rebuilt from the repo into a new account with no hand fix, data byte-identical",
        "A nightly task appends each new business day automatically",
    ]),
    ("Beyond the demo", [
        "Swap the generator for real SAP and WMS connectors; layers stay the same",
        "Add a metric or synonym to the semantic view: the agent and app pick it up",
        "Same pattern fits finance, sales or HR data that disagree across systems",
    ]),
]
colw = 2.95
for i, (head, items) in enumerate(cols):
    x = 0.45 + i * (colw + 0.13)
    text(s, x, 3.0, colw, 0.25, head, size=12, bold=True, color=INK)
    paras = []
    for it in items:
        paras.append([("•  ", {"color": BLUE, "bold": True}), (it, {})])
    text(s, x, 3.35, colw, 1.95, paras, size=10.5, color=INK2, spacing=7)

# ── 5. Demo: Input -> Processing -> Output ───────────────────────────────

s = extra_slide
for shp in list(s.shapes):
    if shp.has_text_frame and shp.text_frame.text.strip() == "Additional Slide":
        shp._element.getparent().remove(shp._element)
title(s, "The working prototype: live on Snowflake")
flow = [("Input", "A plain-English question, e.g. “What is on-time delivery by region?”"),
        ("Processing", "The router runs governed semantic-view SQL or asks the Cortex Agent; masking applies per role"),
        ("Output", "A governed answer with its chart, SQL, metric definition and the path that answered")]
fx = 0.45
for i, (h, d) in enumerate(flow):
    b = box(s, fx + i * 3.08, 1.22, 2.85, 0.78, fill=TINT)
    label_in(b, [[(h, {"bold": True, "size": 10.5, "color": BLUE})], [(d, {"size": 8.5, "color": INK2})]],
             align=PP_ALIGN.LEFT, margin=0.12)
    if i < 2:
        arrow(s, fx + i * 3.08 + 2.85, 1.61, fx + (i + 1) * 3.08, 1.61)

shots = [("1-problem", "1  The problem: two numbers"), ("3-same-for-everyone", "2  Same for everyone"),
         ("4-ask", "3  Ask: instant governed answer"), ("5-data-health", "4  Data health: 35/35 passing")]
pw = 2.15
for i, (name, cap) in enumerate(shots):
    x = 0.45 + i * (pw + 0.17)
    add_shot(s, name, x, 2.25, pw)
    text(s, x, 3.82, pw, 0.22, cap, size=9, bold=True, color=INK)
text(s, 0.45, 4.35, 9.1, 0.6,
     [[("Try it: ", {"bold": True}), (LIVE, {"bold": True, "color": BLUE}),
       ("   ·   Code and docs: ", {"bold": True}), (REPO, {"color": BLUE})],
      "Public link on Streamlit Community Cloud, reading Snowflake live through a key-pair service user "
      "with a read-only role, rate limits and a Cortex budget."],
     size=9.5, color=INK2, spacing=3)

# ── 6. How CoCo CLI built it ─────────────────────────────────────────────

s = new_content_slide(blank_a)
title(s, "How it was built: CoCo CLI plus a frozen contract")
steps = [
    ("1", "Contract first", "docs/CONTRACT.md fixes every object name, metric, valid pairing and masking rule"),
    ("2", "CoCo builds Snowflake", "Schemas, CONFORMED dynamic tables, masking, semantic view, Cortex Agent, DMFs, cost caps"),
    ("3", "Handoff lock", "Generator, quality and eval SQL written outside Snowflake; CoCo runs it and records each run"),
    ("4", "Proof captured", "Real Snowflake output saved as artifacts; ~1,000 tests replay it in CI"),
]
for i, (n, h, d) in enumerate(steps):
    yy = 1.3 + i * 0.8
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(0.45), Inches(yy), Inches(0.46), Inches(0.46))
    c.fill.solid(); c.fill.fore_color.rgb = BLUE; c.line.fill.background()
    label_in(c, [[(n, {"bold": True, "size": 12, "color": WHITE})]])
    text(s, 1.1, yy - 0.02, 4.2, 0.25, h, size=11.5, bold=True, color=INK)
    text(s, 1.1, yy + 0.24, 4.2, 0.55, d, size=9.5, color=INK2)

box(s, 5.65, 1.3, 3.9, 2.95, fill=TINT)
text(s, 5.9, 1.45, 3.4, 0.25, "What CoCo CLI delivered", size=11.5, bold=True, color=INK)
facts = ["4 source schemas, ~6M rows of messy data",
         "10 dynamic tables that clean it incrementally",
         "9 governed views, masking policies for 3 roles",
         "1 semantic view: 19 metrics, 14 verified queries",
         "1 Cortex Agent with a custom data_health tool",
         "77 Data Metric Functions, alerts and cost caps",
         "Full replay into a new account with no hand fix"]
text(s, 5.9, 1.9, 3.45, 2.9, [[("✓  ", {"bold": True, "color": GREEN}), (f, {})] for f in facts],
     size=10, color=INK2, spacing=8)

b = box(s, 0.45, 4.5, 9.1, 0.55, fill=NAVY)
label_in(b, [[("Two AI agents, one frozen contract: ", {"bold": True, "color": WHITE, "size": 10.5}),
              ("CoCo CLI built and ran everything in Snowflake; Claude Code built the app, tests and docs; "
               "a human coordinated both.", {"color": TINT2, "size": 10})]], align=PP_ALIGN.LEFT, margin=0.2)

# ── Thank-you slide: add the links ───────────────────────────────────────

text(thanks_slide, 0.5, 5.0, 9.0, 0.3, f"{LIVE}   ·   {REPO}", size=12, bold=True, color=WHITE,
     align=PP_ALIGN.CENTER)

# ── Order: title, problem, architecture, impact, demo, how built, thanks ─

delete_slide(guide_slide)
order = [title_slide, blank_a, blank_b]
lst = prs.slides._sldIdLst
by_part = {prs.part.related_part(e.get(qn("r:id"))): e for e in lst}
all_slides = list(prs.slides)
impact, built = all_slides[-2], all_slides[-1]
final = [title_slide, blank_a, blank_b, impact, extra_slide, built, thanks_slide]
for e in list(lst):
    lst.remove(e)
for sl in final:
    lst.append(by_part[sl.part])

prs.save(str(OUT))
print("saved", OUT)
