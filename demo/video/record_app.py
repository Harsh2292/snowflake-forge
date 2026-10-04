"""Record the app scenes of the demo video from the live link, with a visible cursor.

Writes raw.webm plus marks.json (scene start/end seconds within the recording).
"""
import json
import re
import shutil
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

URL = "https://supply-chain-forge.streamlit.app/~/+/"
HERE = Path(__file__).parent
VID = HERE / "rec"
W, H = 1920, 1080
marks = {}
T0 = [0.0]
pos = [W / 2, H / 2]

CURSOR_JS = """
() => {
  if (document.getElementById('demo-cursor')) return;
  const c = document.createElement('div');
  c.id = 'demo-cursor';
  c.innerHTML = '<svg width="28" height="28" viewBox="0 0 24 24"><path d="M4 2 L4 20 L9 15 L12.5 22 L15.5 20.6 L12 13.8 L19 13.8 Z" fill="#111" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  Object.assign(c.style, {position:'fixed', left:'0px', top:'0px', zIndex: 2147483647, pointerEvents:'none',
    transition:'transform 0.6s cubic-bezier(.3,.7,.3,1)', transform:'translate(960px,540px)'});
  document.body.appendChild(c);
}
"""


def now():
    return time.monotonic() - T0[0]


def mark(name):
    marks[name] = round(now(), 2)
    print(f"  mark {name} {marks[name]}")


def settle(page, extra=1200):
    page.wait_for_timeout(800)
    for _ in range(180):
        if not page.locator('[data-testid="stStatusWidget"]').count():
            break
        page.wait_for_timeout(500)
    page.wait_for_timeout(extra)
    page.evaluate(CURSOR_JS)


def move(page, x, y, dur=0.6):
    page.evaluate(f"() => {{ const c = document.getElementById('demo-cursor'); if (c) {{ c.style.transition = 'transform {dur}s cubic-bezier(.3,.7,.3,1)'; c.style.transform = 'translate({x}px,{y}px)'; }} }}")
    page.mouse.move(x, y, steps=max(2, int(dur * 30)))
    pos[:] = [x, y]
    page.wait_for_timeout(int(dur * 1000))


def find(page, text, exact=False, nth=0):
    for f in page.frames:
        loc = f.get_by_text(text, exact=exact)
        if loc.count() > nth:
            return loc.nth(nth)
    return None


def to(page, loc, dx=0.5, dy=0.5, dur=0.6):
    loc.scroll_into_view_if_needed(timeout=5000)
    b = loc.bounding_box()
    move(page, b["x"] + b["width"] * dx, b["y"] + b["height"] * dy, dur)


def nav(page, label):
    btn = page.get_by_role("button", name=re.compile(re.escape(label))).first
    to(page, btn, dur=0.5)
    btn.click()
    settle(page)
    page.evaluate("""() => { for (const el of document.querySelectorAll('*')) { if (el.scrollHeight > el.clientHeight + 50 && getComputedStyle(el).overflowY.match(/auto|scroll/)) el.scrollTop = 0; } }""")


def wheel(page, dy, steps=10, pause=120):
    for _ in range(steps):
        page.mouse.wheel(0, dy / steps)
        page.wait_for_timeout(pause)


with sync_playwright() as p:
    if VID.exists():
        shutil.rmtree(VID)
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": W, "height": H}, record_video_dir=str(VID),
                        record_video_size={"width": W, "height": H}, color_scheme="light")
    page = ctx.new_page()
    T0[0] = time.monotonic()
    page.goto(URL, wait_until="domcontentloaded", timeout=180_000)
    page.get_by_role("button", name=re.compile("The problem")).first.wait_for(timeout=300_000)
    settle(page, 4000)
    # warm every screen so nothing loads on camera
    for label in ["The fix", "Same for everyone", "Ask", "Explore metrics", "Data health", "The problem"]:
        nav(page, label)
    page.wait_for_timeout(1500)

    # Scene 1: the problem
    mark("s1_start")
    page.wait_for_timeout(2500)
    for t in ["ERP", "WMS", "TMS", "SRM"]:
        loc = find(page, t, exact=True)
        if loc:
            to(page, loc, dur=0.9)
            page.wait_for_timeout(900)
    for t in ["68.2%", "87.5%"]:
        loc = find(page, t, exact=True)
        if loc:
            to(page, loc, dur=1.0)
            page.wait_for_timeout(2500)
    page.wait_for_timeout(2500)
    mark("s1_end")

    # Scene 2: the fix
    mark("s2_start")
    nav(page, "The fix")
    page.wait_for_timeout(1500)
    for t in ["Source", "Governed", "Semantic", "Conversation"]:
        loc = find(page, t, exact=True)
        if loc:
            to(page, loc, dur=0.9)
            page.wait_for_timeout(1300)
    move(page, 960, 760, 0.8)
    wheel(page, 520, steps=14, pause=110)
    page.wait_for_timeout(4500)
    mark("s2_end")

    # Scene 4a: same for everyone
    mark("s4a_start")
    nav(page, "Same for everyone")
    page.wait_for_timeout(1200)
    for i in range(3):
        loc = find(page, "0.875369", exact=True, nth=i)
        if loc:
            to(page, loc, dur=0.8)
            page.wait_for_timeout(1000)
    loc = find(page, "What this team can see", nth=1)
    if loc:
        to(page, loc, dur=0.8)
        page.wait_for_timeout(1200)
    loc = find(page, "Fill Rate", exact=True)
    if loc:
        to(page, loc, dur=0.9)
        page.wait_for_timeout(400)
        loc.click()
        settle(page, 600)
        for i in range(3):
            l2 = find(page, "Matches", nth=i)
            if l2:
                to(page, l2, dur=0.6)
                page.wait_for_timeout(500)
    page.wait_for_timeout(2500)
    mark("s4a_end")

    # Scene 4b: ask
    mark("s4b_start")
    nav(page, "Ask")
    newc = page.get_by_role("button", name=re.compile("New conversation"))
    if newc.count():
        to(page, newc.first, dur=0.6)
        newc.first.click()
        settle(page)
    sug = page.get_by_role("button", name=re.compile("on-time delivery rate by region"))
    if sug.count():
        to(page, sug.first, dur=0.9)
        page.wait_for_timeout(300)
        sug.first.click()
    else:
        box = page.get_by_role("textbox").last
        box.fill("What is on-time delivery rate by region?")
        box.press("Enter")
    settle(page, 3500)
    mark("s4b_instant_done")
    box = page.get_by_role("textbox").last
    to(page, box, dx=0.3, dur=0.8)
    box.click()
    box.press_sequentially("List the top 5 suppliers in EMEA with the shortest lead times", delay=45)
    page.wait_for_timeout(500)
    box.press("Enter")
    mark("s4b_asked")
    page.wait_for_timeout(4000)
    mark("s4b_thinking")
    for _ in range(240):  # up to 2 minutes for the agent
        if not page.locator('[data-testid="stStatusWidget"]').count() and \
                any(f.get_by_text("Supply Chain Agent").count() for f in page.frames):
            break
        page.wait_for_timeout(500)
    settle(page, 1500)
    mark("s4b_answered")
    page.wait_for_timeout(5000)
    sql = None
    for f in reversed(page.frames):
        t = f.get_by_role("tab", name="SQL")
        if t.count():
            sql = t.last
            break
    if sql:
        to(page, sql, dur=0.8)
        sql.click()
        page.wait_for_timeout(4000)
    mark("s4b_end")

    # Scene 5: data health
    mark("s5_start")
    nav(page, "Data health")
    page.wait_for_timeout(2500)
    move(page, 960, 700, 0.8)
    wheel(page, 900, steps=30, pause=180)
    page.wait_for_timeout(1500)
    wheel(page, 1500, steps=30, pause=150)
    page.wait_for_timeout(2500)
    mark("s5_end")

    # Scene 6 tail: back to the problem screen
    mark("s6_start")
    nav(page, "The problem")
    move(page, 1300, 300, 0.8)
    page.wait_for_timeout(9000)
    mark("s6_end")

    video = page.video.path()
    ctx.close()
    b.close()
    shutil.copy(video, HERE / "raw.webm")
    (HERE / "marks.json").write_text(json.dumps(marks, indent=1))
    print("saved raw.webm", marks)
