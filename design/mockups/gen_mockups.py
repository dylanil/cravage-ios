#!/usr/bin/env python3
"""Writes the Cravage step-4 mockup artboards (.dc.html) and canvas.json.

    python3 design/mockups/gen_mockups.py design/mockups

Look C "Paper", chosen by the owner on 2026-09-14 from three Home directions: editorial serif
headings, hairline rules, numbered rhythm and drawn illustrations over standard iOS controls.
Monospace stays reserved for figures and the room code. The two Home looks not chosen (Warm glow,
Night) are kept on their own page for reference.
"""
import json
import os
import sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

# ---- Palette (warm glow) ---------------------------------------------------------------------
CREAM = "#FFF8F1"
INK = "#1F1A17"
MUTED = "#6F625A"
HAIR = "#EFE2D6"
CARD = "#FFFFFF"
ORANGE = "#F26B21"
ORANGE_DEEP = "#D9480F"
ORANGE_TEXT = "#C2410C"
CORAL = "#F58B6B"
AMBER = "#F6B24A"
TINT = "#FFEBDD"
GREEN = "#2F8F4E"
GREEN_TINT = "#E6F4EA"
RED = "#C62828"

DISPLAY = 'ui-rounded, "SF Pro Rounded", -apple-system, "Helvetica Neue", Arial, sans-serif'
TEXT = '-apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif'
MONO = 'ui-monospace, "SF Mono", Menlo, Consolas, monospace'

BASE_CSS = f"""
body {{ margin: 0; background: {CREAM}; color: {INK}; font-family: {TEXT}; -webkit-font-smoothing: antialiased; }}
a {{ color: {ORANGE_TEXT}; text-decoration: none; }} a:hover {{ color: #9A3412; }}
.mono {{ font-family: {MONO}; font-variant-numeric: tabular-nums; }}
.display {{ font-family: {DISPLAY}; }}
"""

SKETCH_CSS = """
body { margin: 0; background: #FAFAF7; color: #2B2B2B; font-family: "Patrick Hand", "Comic Sans MS", "Marker Felt", system-ui, sans-serif; }
a { color: #C2410C; } a:hover { color: #9A3412; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; }
"""

GLOW = f"radial-gradient(120% 60% at 50% -10%, #FFD2B0 0%, #FFE6D3 35%, {CREAM} 70%)"


def page(body, css=BASE_CSS, bg=f"{GLOW}, {CREAM}"):
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>{css}</style>
</helmet>
<div style="width: 390px; height: 844px; box-sizing: border-box; background: {bg}; display: flex; flex-direction: column; overflow: hidden; position: relative;">
{body}
</div>
</x-dc>
<script data-dc-script data-props='{{"$preview":{{"width":390,"height":844}}}}'>
class Component extends DCLogic {{}}
</script>
</body>
</html>
"""


# ---- Icons (stroke, 24 grid) -----------------------------------------------------------------
def svg(inner, size=20, color=INK, width=1.9):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{inner}</svg>')


def i_gear(c=INK): return svg('<circle cx="12" cy="12" r="3.2"></circle><path d="M12 2.8v2.4M12 18.8v2.4M4.2 12H2.8M21.2 12h-1.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"></path>', 22, c)
def i_back(c=ORANGE_TEXT): return svg('<polyline points="15 5 8 12 15 19"></polyline>', 22, c, 2.4)
def i_chev(c="#C9B8AA"): return svg('<polyline points="9 6 15 12 9 18"></polyline>', 16, c, 2.4)
def i_check(c=GREEN, s=16): return svg('<polyline points="5 12.5 10 17 19 7"></polyline>', s, c, 2.8)
def i_clock(c=MUTED): return svg('<circle cx="12" cy="12" r="9"></circle><polyline points="12 7 12 12 15.5 14"></polyline>', 15, c, 2)
def i_lock(c=MUTED): return svg('<rect x="5" y="11" width="14" height="10" rx="2.5"></rect><path d="M8 11V8a4 4 0 0 1 8 0v3"></path>', 12, c, 2.4)
def i_phone(c=ORANGE_TEXT, s=18): return svg('<rect x="7" y="2.5" width="10" height="19" rx="2.6"></rect><line x1="11" y1="18.3" x2="13" y2="18.3"></line>', s, c, 2)
def i_shield(c=ORANGE_TEXT): return svg('<path d="M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6z"></path><polyline points="9 12 11.2 14.2 15.5 9.8"></polyline>', 20, c, 2)
def i_people(c=ORANGE_TEXT): return svg('<circle cx="9" cy="8" r="3"></circle><path d="M3.5 19c.8-3 3-4.6 5.5-4.6s4.7 1.6 5.5 4.6"></path><circle cx="17" cy="9" r="2.4"></circle><path d="M15.5 14.6c2.3.1 4.1 1.6 4.8 4.1"></path>', 20, c, 2)
def i_file(c=ORANGE_TEXT): return svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"></path><polyline points="14 3 14 8 19 8"></polyline><line x1="9" y1="13" x2="15" y2="13"></line><line x1="9" y1="17" x2="13" y2="17"></line>', 20, c, 2)
def i_eye(c=ORANGE_TEXT): return svg('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"></path><circle cx="12" cy="12" r="2.8"></circle>', 20, c, 2)


# ---- Brand mark and illustrations ------------------------------------------------------------
def mark(size=64):
    """Three overlapping discs whose shared centre is the average."""
    return f"""<svg width="{size}" height="{size}" viewBox="0 0 64 64">
  <defs>
    <linearGradient id="mk1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{AMBER}"></stop><stop offset="1" stop-color="{ORANGE}"></stop></linearGradient>
    <linearGradient id="mk2" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{CORAL}"></stop><stop offset="1" stop-color="{ORANGE_DEEP}"></stop></linearGradient>
  </defs>
  <rect x="0" y="0" width="64" height="64" rx="16" fill="#FFFFFF"></rect>
  <circle cx="25" cy="26" r="14" fill="url(#mk1)" opacity="0.92"></circle>
  <circle cx="39" cy="26" r="14" fill="url(#mk2)" opacity="0.85"></circle>
  <circle cx="32" cy="38" r="14" fill="{ORANGE}" opacity="0.78"></circle>
  <circle cx="32" cy="30.5" r="4.2" fill="#FFFFFF"></circle>
</svg>"""


def ill_room(w=104, h=80):
    """Step 1: three phones around a table."""
    def phone(x, y, rot, tone):
        return (f'<g transform="translate({x} {y}) rotate({rot})">'
                f'<rect x="-9" y="-15" width="18" height="30" rx="4.5" fill="#FFFFFF" stroke="{INK}" stroke-width="1.6"></rect>'
                f'<rect x="-6" y="-11" width="12" height="17" rx="2" fill="{tone}"></rect>'
                f'<line x1="-2.5" y1="10.5" x2="2.5" y2="10.5" stroke="{INK}" stroke-width="1.4" stroke-linecap="round"></line></g>')
    return f"""<svg width="{w}" height="{h}" viewBox="0 0 104 80">
  <ellipse cx="52" cy="50" rx="40" ry="18" fill="{TINT}"></ellipse>
  <ellipse cx="52" cy="48" rx="40" ry="18" fill="none" stroke="#F3C9AA" stroke-width="1.4"></ellipse>
  {phone(22, 42, -16, AMBER)}
  {phone(52, 30, 0, ORANGE)}
  {phone(82, 42, 16, CORAL)}
</svg>"""


def ill_code(w=104, h=80):
    """Step 2: two phones showing the same code, joined by a check."""
    def phone(x):
        return (f'<g transform="translate({x} 40)">'
                f'<rect x="-15" y="-26" width="30" height="52" rx="7" fill="#FFFFFF" stroke="{INK}" stroke-width="1.6"></rect>'
                f'<rect x="-10" y="-12" width="20" height="5" rx="2.5" fill="{INK}"></rect>'
                f'<rect x="-10" y="-3" width="20" height="5" rx="2.5" fill="{INK}"></rect>'
                f'<rect x="-10" y="6" width="12" height="5" rx="2.5" fill="{ORANGE}"></rect></g>')
    return f"""<svg width="{w}" height="{h}" viewBox="0 0 104 80">
  {phone(26)}
  {phone(78)}
  <path d="M41 26 Q52 14 63 26" fill="none" stroke="{GREEN}" stroke-width="1.8" stroke-dasharray="3 3"></path>
  <circle cx="52" cy="17" r="9" fill="{GREEN}"></circle>
  <polyline points="47.5 17.2 50.8 20.3 56.5 14" fill="none" stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"></polyline>
</svg>"""


def ill_average(w=104, h=80):
    """Step 3: three masked shares flow together; only the average comes out."""
    def chip(y, tone):
        return (f'<g transform="translate(8 {y})"><rect width="34" height="16" rx="8" fill="{tone}"></rect>'
                f'<path d="M7 11 L12 5 M14 11 L19 5 M21 11 L26 5" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" opacity="0.85"></path></g>')
    return f"""<svg width="{w}" height="{h}" viewBox="0 0 104 80">
  {chip(10, AMBER)}
  {chip(32, ORANGE)}
  {chip(54, CORAL)}
  <path d="M44 18 C58 18 60 40 70 40 M44 40 L70 40 M44 62 C58 62 60 40 70 40" fill="none" stroke="#E9B895" stroke-width="1.8" stroke-linecap="round"></path>
  <circle cx="84" cy="40" r="15" fill="{ORANGE}"></circle>
  <circle cx="84" cy="40" r="15" fill="none" stroke="#FFFFFF" stroke-width="2" opacity="0.5"></circle>
  <line x1="77" y1="40" x2="91" y2="40" stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round"></line>
  <circle cx="84" cy="34" r="2" fill="#FFFFFF"></circle>
  <circle cx="84" cy="46" r="2" fill="#FFFFFF"></circle>
</svg>"""


# ---- Building blocks -------------------------------------------------------------------------
def nav(title="", left="", right=""):
    return f"""<div style="height: 44px; margin-top: 54px; padding: 0 16px; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); align-items: center;">
  <div style="display: flex; align-items: center; gap: 2px; color: {ORANGE_TEXT}; font-size: 17px;">{left}</div>
  <div style="text-align: center; font-size: 17px; font-weight: 600;">{title}</div>
  <div style="display: flex; align-items: center; justify-content: flex-end; color: {ORANGE_TEXT}; font-size: 17px; font-weight: 600;">{right}</div>
</div>"""


def primary(label, disabled=False):
    if disabled:
        return f'<div style="height: 56px; border-radius: 18px; background: #EDE3DA; color: #A8998D; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'
    return (f'<div style="height: 56px; border-radius: 18px; background: linear-gradient(180deg, #F47A34 0%, {ORANGE_DEEP} 100%); '
            f'box-shadow: 0 8px 20px rgba(217, 72, 15, 0.28), inset 0 1px 0 rgba(255,255,255,0.25); color: #FFFFFF; '
            f'display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>')


def secondary(label, color=ORANGE_TEXT):
    return f'<div style="height: 56px; border-radius: 18px; background: {CARD}; box-shadow: 0 1px 0 {HAIR}, 0 4px 14px rgba(120, 70, 30, 0.08); color: {color}; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'


def plain(label, color=ORANGE_TEXT):
    return f'<div style="height: 44px; display: flex; align-items: center; justify-content: center; color: {color}; font-size: 17px;">{label}</div>'


def card(inner, pad="6px 0", margin="0 16px"):
    return f'<div style="margin: {margin}; padding: {pad}; background: {CARD}; border-radius: 20px; box-shadow: 0 1px 0 {HAIR}, 0 10px 30px rgba(120, 70, 30, 0.07); display: flex; flex-direction: column;">{inner}</div>'


def label(text):
    return f'<div style="padding: 22px 32px 8px; font-size: 13px; font-weight: 600; color: {MUTED}; letter-spacing: 0.3px;">{text}</div>'


def foot(text):
    return f'<div style="padding: 8px 32px 0; font-size: 13px; line-height: 18px; color: {MUTED}; text-wrap: pretty;">{text}</div>'


def row(main, sub="", trailing="", last=False, leading=""):
    border = "" if last else f"border-bottom: 1px solid {HAIR};"
    sub_html = f'<div style="font-size: 14px; color: {MUTED}; margin-top: 2px;">{sub}</div>' if sub else ""
    lead = f'<div style="display: flex; align-items: center;">{leading}</div>' if leading else ""
    return f"""<div style="min-height: 56px; margin: 0 16px; padding: 10px 0; box-sizing: border-box; display: flex; align-items: center; gap: 12px; {border}">
  {lead}<div style="flex-grow: 1; display: flex; flex-direction: column;"><div style="font-size: 17px;">{main}</div>{sub_html}</div>
  <div style="display: flex; align-items: center; gap: 8px;">{trailing}</div>
</div>"""


def avatar(name, tone):
    return f'<div class="display" style="width: 36px; height: 36px; border-radius: 18px; background: {tone}; color: #FFFFFF; display: flex; align-items: center; justify-content: center; font-size: 16px; font-weight: 700;">{name[0]}</div>'


def letter(ch, filled=True):
    bg = INK if filled else "#F1E7DE"
    fg = "#FFFFFF" if filled else MUTED
    return f'<div class="mono" style="width: 32px; height: 32px; border-radius: 16px; background: {bg}; color: {fg}; display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: 700;">{ch}</div>'


def pill(text, fg, bg):
    return f'<div style="height: 28px; padding: 0 11px; border-radius: 14px; background: {bg}; color: {fg}; display: flex; align-items: center; gap: 5px; font-size: 13px; font-weight: 600;">{text}</div>'


def bottom(*items):
    return f'<div style="margin-top: auto; padding: 12px 20px 34px; display: flex; flex-direction: column; gap: 10px;">{"".join(items)}</div>'


def note(text, color=MUTED, size=13):
    return f'<div style="font-size: {size}px; line-height: {size + 5}px; color: {color}; text-align: center; text-wrap: pretty;">{text}</div>'


def deadline(text):
    return f'<div style="display: flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px; color: {MUTED};">{i_clock()}<span>{text}</span></div>'


def badge(icon_html, bg=TINT, size=40):
    return f'<div style="width: {size}px; height: {size}px; border-radius: {size // 2 - 6}px; background: {bg}; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">{icon_html}</div>'


def step(number, title, body, illustration):
    return f"""<div style="display: flex; align-items: center; gap: 14px; padding: 12px 14px; background: {CARD}; border-radius: 20px; box-shadow: 0 1px 0 {HAIR}, 0 10px 26px rgba(120, 70, 30, 0.07);">
  <div style="width: 104px; height: 80px; border-radius: 16px; background: #FFF4EA; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">{illustration}</div>
  <div style="display: flex; flex-direction: column; gap: 3px;">
    <div class="display" style="font-size: 13px; font-weight: 700; color: {ORANGE_TEXT}; letter-spacing: 0.4px;">STEP {number}</div>
    <div class="display" style="font-size: 17px; font-weight: 700; line-height: 21px;">{title}</div>
    <div style="font-size: 14px; line-height: 19px; color: {MUTED}; text-wrap: pretty;">{body}</div>
  </div>
</div>"""


STEPS = [
    ("1", "Gather in one room", "Everyone opens Cravage on their own phone.", ill_room()),
    ("2", "Match the code", "Each screen shows the same room code. Check it together.", ill_code()),
    ("3", "Only the average appears", "Each phone sends a masked share, not your figure.", ill_average()),
]

screens = {}

# ---- Look C "Paper" (owner's choice, 2026-09-14): editorial serif display, hairline rules, -----
# ---- numbered rhythm, drawn illustrations; monospace still only for figures and the room code --
PAPER_SERIF = 'ui-serif, "New York", Georgia, "Times New Roman", serif'
PAPER = "#FBF6EE"
RULE = "#E6DACB"
PAPER_CSS = BASE_CSS.replace(f"background: {CREAM};", f"background: {PAPER};") + f"\n.serif {{ font-family: {PAPER_SERIF}; }}\n"


def ppage(body):
    return page(body, css=PAPER_CSS, bg=PAPER)


def kicker(text):
    return f'<div style="font-size: 12px; font-weight: 700; letter-spacing: 2px; color: {ORANGE_TEXT};">{text}</div>'


def headline(kick, title, size=34):
    return f"""<div style="padding: 6px 26px 0; display: flex; flex-direction: column; gap: 8px;">
  {kicker(kick)}
  <div class="serif" style="font-size: {size}px; line-height: {size + 4}px; font-weight: 600; letter-spacing: -0.3px; text-wrap: pretty;">{title}</div>
</div>"""


def p_primary(label, disabled=False):
    bg, fg = ("#E9DFD3", "#A3968A") if disabled else (ORANGE_DEEP, "#FFFFFF")
    return f'<div style="height: 54px; border-radius: 14px; background: {bg}; color: {fg}; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'


def p_secondary(label, color=INK):
    return f'<div style="height: 54px; border-radius: 14px; border: 1.5px solid {INK}; box-sizing: border-box; color: {color}; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'


def p_section(text):
    return f'<div style="margin: 24px 26px 0; padding-top: 10px; border-top: 1.5px solid {INK}; font-size: 12px; font-weight: 700; letter-spacing: 1.6px; color: {INK};">{text}</div>'


def p_foot(text):
    return f'<div style="padding: 10px 26px 0; font-size: 14px; line-height: 20px; color: {MUTED}; text-wrap: pretty;">{text}</div>'


def p_row(main, sub="", trailing="", leading="", last=False, serif=True):
    border = "" if last else f"border-bottom: 1px solid {RULE};"
    cls = ' class="serif"' if serif else ""
    size = 20 if serif else 17
    sub_html = f'<div style="font-size: 14px; color: {MUTED}; margin-top: 2px;">{sub}</div>' if sub else ""
    lead = f'<div style="display: flex; align-items: center;">{leading}</div>' if leading else ""
    return f"""<div style="min-height: 58px; margin: 0 26px; padding: 10px 0; box-sizing: border-box; display: flex; align-items: center; gap: 14px; {border}">
  {lead}<div style="flex-grow: 1; display: flex; flex-direction: column;"><div{cls} style="font-size: {size}px;">{main}</div>{sub_html}</div>
  <div style="display: flex; align-items: center; gap: 8px;">{trailing}</div>
</div>"""


def p_initial(name):
    return f'<div class="serif" style="width: 36px; height: 36px; border-radius: 18px; border: 1.5px solid {INK}; box-sizing: border-box; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{name[0]}</div>'


def p_letter(ch, filled=True):
    style = f"background: {INK}; color: #FFFFFF;" if filled else f"border: 1.5px solid {RULE}; color: {MUTED};"
    return f'<div class="mono" style="width: 32px; height: 32px; border-radius: 16px; box-sizing: border-box; {style} display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: 700;">{ch}</div>'


def p_status(text, ok=True):
    color = GREEN if ok else MUTED
    icon = i_check(GREEN, 14) if ok else ""
    return f'<div style="display: flex; align-items: center; gap: 4px; font-size: 14px; font-weight: 600; color: {color};">{icon}{text}</div>'


def p_bottom(*items):
    return f'<div style="margin-top: auto; padding: 12px 22px 34px; display: flex; flex-direction: column; gap: 10px;">{"".join(items)}</div>'


def p_box(inner):
    return f'<div style="margin: 14px 26px 0; padding: 14px 16px; border: 1px solid {RULE}; border-radius: 14px; background: #FFFDF9; display: flex; gap: 12px; align-items: flex-start;">{inner}</div>'


paper_steps = "".join(
    f'<div style="display: flex; gap: 16px; padding: 16px 0; border-top: 1px solid {RULE};">'
    f'<div class="serif" style="font-size: 44px; line-height: 44px; color: {ORANGE_DEEP}; width: 34px;">{n}</div>'
    f'<div style="display: flex; flex-direction: column; gap: 4px; flex-grow: 1;"><div class="serif" style="font-size: 21px; font-weight: 600;">{t}</div>'
    f'<div style="font-size: 15px; line-height: 21px; color: {MUTED};">{b}</div></div>'
    f'<div style="display: flex; align-items: center;">{ill(72, 56)}</div></div>'
    for (n, t, b, _), ill in zip(STEPS, [ill_room, ill_code, ill_average]))

# 1 Home
screens["Main"] = ppage(f"""
{nav(right=i_gear())}
<div style="padding: 10px 26px 0; display: flex; flex-direction: column; gap: 8px;">
  {kicker("CRAVAGE")}
  <div class="serif" style="font-size: 38px; line-height: 42px; font-weight: 600; letter-spacing: -0.3px;">An average the whole room can check, without passing your figure around.</div>
</div>
<div style="padding: 18px 26px 0; display: flex; flex-direction: column;">{paper_steps}</div>
{p_bottom(p_primary("New room"), p_secondary("Join a room"), note(f'You appear as <strong style="color: {INK};">Dee</strong>. <a>Change</a>', size=15))}
""")

# 2 New room
sizes = "".join(
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 4px;">'
    f'<div class="serif" style="width: 44px; height: 44px; border-radius: 22px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; font-size: 20px; font-weight: 600; '
    f'{"background: " + INK + "; color: #FFFFFF;" if n == 3 else "border: 1.5px solid " + RULE + "; color: " + INK + ";"}">{n}</div>'
    f'<div style="height: 12px;">{"" if n == 3 else i_lock()}</div></div>'
    for n in range(3, 9))
screens["NewRoom"] = ppage(f"""
{nav("", left="Cancel")}
{headline("NEW ROOM", "What are you averaging?")}
<div style="margin: 18px 26px 0; padding-bottom: 8px; border-bottom: 2px solid {ORANGE_DEEP};">
  <div class="serif" style="font-size: 26px;">Annual bonus</div>
</div>
{p_foot("Everyone in the room sees this. Nearby phones can see it too, with your nickname and the group size, but never anyone's number.")}
{p_section("HOW MANY PEOPLE, INCLUDING YOU")}
<div style="margin: 14px 26px 0; display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 6px;">{sizes}</div>
{p_foot("3 people is free. 4 to 8 people is a one-off unlock.")}
{p_bottom(p_primary("Open room"))}
""")

# 3 Join
screens["Join"] = ppage(f"""
{nav("", left=i_back() + "Back")}
{headline("JOIN A ROOM", "Rooms nearby")}
<div style="margin-top: 18px; border-top: 1.5px solid {INK}; margin-left: 26px; margin-right: 26px;"></div>
{p_row("Annual bonus", "Host: Sam &#183; 3 people", i_chev(MUTED))}
{p_row("Team lunch budget", "Host: Morgan &#183; 5 people", i_chev(MUTED))}
<div style="margin: 0 26px; padding: 16px 0; display: flex; align-items: center; gap: 10px; color: {MUTED}; font-size: 15px;">
  <div style="width: 8px; height: 8px; border-radius: 4px; background: {ORANGE_DEEP}; box-shadow: 0 0 0 5px rgba(217,72,15,0.15);"></div>
  <span>Looking for more rooms&#8230;</span>
</div>
{p_foot("Rooms appear when you are close to the host's phone and the host has the app open.")}
{p_bottom(note(f'Joining as <strong style="color: {INK};">Dee</strong>', size=15))}
""")

# 4 Lobby, host
screens["LobbyHost"] = ppage(f"""
{nav("", left="Close")}
{headline("ANNUAL BONUS", "2 of 3 in the room", size=36)}
{p_section("ASKING TO JOIN")}
{p_row("Priya", "",
    f'<div style="height: 36px; padding: 0 13px; border-radius: 18px; border: 1.5px solid {INK}; box-sizing: border-box; display: flex; align-items: center; font-size: 15px;">Decline</div><div style="height: 36px; padding: 0 15px; border-radius: 18px; background: {ORANGE_DEEP}; color: #FFFFFF; display: flex; align-items: center; font-size: 15px; font-weight: 600;">Admit</div>',
    leading=p_initial("Priya"), last=True)}
{p_foot("Only admit someone you can see in the room.")}
{p_section("IN THE ROOM")}
{p_row("Sam", "You, host", p_status("This phone", ok=False), leading=p_initial("Sam"))}
{p_row("Alex", "", p_status("Connected"), leading=p_initial("Alex"), last=True)}
{p_foot("1 other phone connected. Keep the app open on every phone until the round ends.")}
{p_bottom(p_primary("Start round", disabled=True), note("Start needs 3 people. Admit Priya to begin."), deadline("Room closes in 14:12 if the round has not started"))}
""")

# 5 Lobby, joiner
screens["LobbyJoiner"] = ppage(f"""
{nav("", left="Leave")}
<div style="padding: 10px 26px 0; display: flex; flex-direction: column; gap: 10px;">
  <div style="display: flex; justify-content: flex-start;">{ill_room(150, 115)}</div>
  {kicker("ANNUAL BONUS")}
  <div class="serif" style="font-size: 32px; line-height: 36px; font-weight: 600;">Waiting for Sam to start</div>
  <div style="font-size: 16px; line-height: 22px; color: {MUTED}; text-wrap: pretty;">You are in. Keep the app open; the round begins when the room is full.</div>
</div>
{p_section("IN THE ROOM")}
{p_row("Sam", "Host", leading=p_initial("Sam"))}
{p_row("Dee", "You", leading=p_initial("Dee"), last=True)}
{p_foot("Everyone else appears when the host starts and every phone shows the room code.")}
{p_bottom(deadline("Stops waiting in 14:05"))}
""")

# 6 Check the code
screens["ConfirmCode"] = ppage(f"""
{nav("")}
{headline("CHECK THE CODE", "Is this on every phone?", size=28)}
<div style="margin: 18px 26px 0; padding: 18px 0 16px; border-top: 2px solid {INK}; border-bottom: 2px solid {INK}; display: flex; flex-direction: column; align-items: center; gap: 4px;">
  <div style="font-size: 13px; color: {MUTED};">Annual bonus &#183; 3 people</div>
  <div class="mono" style="font-size: 44px; font-weight: 700; letter-spacing: 3px;">K7QM<span style="color: {ORANGE_DEEP};">-</span>3XRD</div>
</div>
{p_box(f'<div style="padding-top: 2px;">{i_phone(ORANGE_TEXT, 20)}</div><div style="font-size: 15px; line-height: 21px; text-wrap: pretty;"><span class="serif" style="font-size: 17px; font-weight: 600;">Look up and count the other phones.</span> There should be exactly 2, each showing this code. If you count more or fewer, or a code differs, stop.</div>')}
{p_section("CONFIRMED")}
{p_row("Sam", "Host", p_status("Checked"), leading=p_letter("A"))}
{p_row("Alex", "", p_status("Checking", ok=False), leading=p_letter("B", False))}
{p_row("Dee", "You", "", leading=p_letter("C", False), last=True)}
{p_bottom(p_primary("I checked, the codes match"), plain("The codes don't match", RED), deadline("Stops waiting in 2:48"))}
""")

# 7 Enter figure
screens["EnterFigure"] = ppage(f"""
{nav("", left="Leave")}
{headline("ANNUAL BONUS", "Your figure")}
<div style="margin: 18px 26px 0; padding-bottom: 6px; border-bottom: 2px solid {ORANGE_DEEP}; display: flex; align-items: center; gap: 6px;">
  <div class="mono" style="font-size: 42px; font-weight: 600;">42500.50</div>
  <div style="width: 2px; height: 40px; background: {ORANGE_DEEP};"></div>
</div>
{p_foot("Up to 999,999,999,999.99. Use your decimal mark; leave out thousands separators.")}
{p_box(f'<div style="padding-top: 1px;">{i_shield()}</div><div style="font-size: 15px; line-height: 21px; text-wrap: pretty;">Your figure is processed on your phone; the app sends a masked share to the other participants.</div>')}
{p_box(f'<div style="padding-top: 1px;">{i_people()}</div><div style="font-size: 15px; line-height: 21px; color: #4A3B32; text-wrap: pretty;">With 3 people, the other 2 could work out your figure if they shared theirs with each other.</div>')}
{p_bottom(p_primary("Send masked share"), note("Once sent, your figure can't be changed for this round."))}
""")

# 8 Waiting
segments = "".join(
    f'<div style="height: 6px; border-radius: 3px; background: {c};"></div>' for c in [INK, "#E9DFD3", INK])
screens["Waiting"] = ppage(f"""
{nav("", left="Cancel")}
{headline("ANNUAL BONUS", "2 of 3 masked shares in", size=32)}
<div style="margin: 18px 26px 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 6px;">{segments}</div>
{p_section("PHONES")}
{p_row("Sam", "", p_status("Sent"), leading=p_letter("A"))}
{p_row("Alex", "Still entering a figure", p_status("Waiting", ok=False), leading=p_letter("B", False))}
{p_row("Dee", "You", p_status("Sent"), leading=p_letter("C"), last=True)}
{p_bottom(deadline("Stops waiting in 4:21; the round then fails and the host can restart"))}
""")

# 9 Result
screens["Result"] = ppage(f"""
{nav("", right="Done")}
<div style="padding: 6px 26px 0; display: flex; flex-direction: column; gap: 6px;">
  {kicker("RESULT")}
  <div class="serif" style="font-size: 26px; line-height: 30px; font-weight: 600;">Average annual bonus</div>
  <div style="padding: 10px 0 12px; border-bottom: 3px solid {ORANGE_DEEP};">
    <div class="mono" style="font-size: 52px; font-weight: 700; letter-spacing: -1px;">37,166.83</div>
  </div>
  <div style="font-size: 15px; color: {MUTED};">from 3 people</div>
</div>
<div style="margin: 16px 26px 0; display: flex; gap: 10px; align-items: center;">
  {i_check(GREEN, 18)}<div style="font-size: 15px; line-height: 21px; color: #1E5A32; text-wrap: pretty;">All 3 phones signed agreement to the same set of shares.</div>
</div>
{p_section("THIS ROUND")}
{p_row("Show the shares", "", i_chev(MUTED), serif=False)}
{p_row("Share transcript", "A file anyone can check", i_chev(MUTED), serif=False, last=True)}
{p_foot("The app can't check that the figures people entered were true. Round history is not saved.")}
{p_bottom(p_secondary("Run again"), plain("Leave room"))}
""")


# ---- Alternative Home looks the owner did not choose, kept for reference ---------------------------------------------------
NIGHT_CSS = BASE_CSS.replace(f"background: {CREAM}; color: {INK};", "background: #120E0C; color: #F7EFE8;")
screens["HomeNight"] = page(f"""
<div style="height: 44px; margin-top: 54px; padding: 0 16px; display: flex; align-items: center; justify-content: flex-end;">{i_gear("#E9D8CA")}</div>
<div style="padding: 12px 24px 0; display: flex; flex-direction: column; gap: 10px;">
  {mark(56)}
  <div class="display" style="font-size: 40px; font-weight: 800; letter-spacing: -0.6px; line-height: 44px; color: #FFF6EE;">Know the average.<br><span style="color: {ORANGE};">Keep your number.</span></div>
</div>
<div style="padding: 24px 16px 0; display: flex; flex-direction: column; gap: 10px;">
  {"".join(f'<div style="display: flex; align-items: center; gap: 14px; padding: 10px 12px; border-radius: 20px; background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08);"><div style="width: 88px; height: 68px; border-radius: 14px; background: #FFF4EA; display: flex; align-items: center; justify-content: center;">{ill(88, 68)}</div><div style="display: flex; flex-direction: column; gap: 2px;"><div class="display" style="font-size: 17px; font-weight: 700; color: #FFF6EE;">{t}</div><div style="font-size: 14px; line-height: 19px; color: #BFAEA1;">{b}</div></div></div>' for (_, t, b, _), ill in zip(STEPS, [ill_room, ill_code, ill_average]))}
</div>
<div style="margin-top: auto; padding: 12px 20px 34px; display: flex; flex-direction: column; gap: 10px;">
  {primary("New room")}
  <div style="height: 56px; border-radius: 18px; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14); color: #FFE2CF; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">Join a room</div>
</div>
""", css=NIGHT_CSS, bg="radial-gradient(90% 50% at 80% 0%, rgba(242,107,33,0.35) 0%, rgba(18,14,12,0) 60%), #120E0C")

# Alternative Home look A: Warm glow
screens["HomeWarm"] = page(f"""
{nav(right=i_gear())}
<div style="padding: 8px 24px 0; display: flex; align-items: center; gap: 14px;">
  <div style="border-radius: 16px; box-shadow: 0 10px 24px rgba(217, 72, 15, 0.22);">{mark(60)}</div>
  <div style="display: flex; flex-direction: column;">
    <div class="display" style="font-size: 36px; font-weight: 800; letter-spacing: -0.5px; line-height: 40px;">Cravage</div>
    <div style="font-size: 15px; color: {MUTED};">Group average, kept private</div>
  </div>
</div>
<div style="padding: 22px 16px 0; display: flex; flex-direction: column; gap: 10px;">
  {"".join(step(*s) for s in STEPS)}
</div>
{bottom(primary("New room"), secondary("Join a room"), note(f'You appear as <strong style="color: {INK};">Dee</strong>. <a>Change</a>', size=15))}
""")


# ---- Sketches: other states, deliberately low-fi ----------------------------------------------
def sketch(title, lines, actions, tag=""):
    body_lines = "".join(
        f'<div style="font-size: 19px; line-height: 25px; text-wrap: pretty;">{l}</div>' for l in lines)
    acts = "".join(
        f'<div style="height: 48px; border: 2px solid #2B2B2B; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 19px; {"background: #FDE3D2;" if i == 0 else ""}">{a}</div>'
        for i, a in enumerate(actions))
    tag_html = f'<div style="align-self: flex-start; padding: 2px 10px; border: 1.5px dashed {ORANGE_TEXT}; color: {ORANGE_TEXT}; border-radius: 8px; font-size: 15px;">{tag}</div>' if tag else ""
    return page(f"""
<div style="padding: 64px 26px 0; display: flex; flex-direction: column; gap: 16px;">
  {tag_html}
  <div style="font-size: 30px; line-height: 34px;">{title}</div>
  <div style="height: 2px; background: #2B2B2B; opacity: 0.5;"></div>
  {body_lines}
</div>
<div style="margin-top: auto; padding: 0 26px 40px; display: flex; flex-direction: column; gap: 12px;">{acts}</div>
""", css=SKETCH_CSS, bg="#FAFAF7")


sketches = [
    ("SketchJoinEmpty", "Join: nothing nearby", "No rooms nearby yet",
     ["Stand near the host and ask them to open the room.", "Still looking&#8230;"], ["Back"], ""),
    ("SketchRequesting", "Join: requesting", "Asking Sam to let you in",
     ["Sam sees your nickname, Dee, and decides.", "Stops waiting in 1:30."], ["Cancel request"], ""),
    ("SketchDeclined", "Join: declined", "Sam didn't admit you",
     ["If that's a mistake, ask Sam and try again."], ["Back to rooms"], ""),
    ("SketchRoomFull", "Join: full", "This room is full",
     ["Annual bonus already has 3 people."], ["Back to rooms"], ""),
    ("SketchUnsupported", "Join: old app", "Update Cravage to join",
     ["This room uses a newer version of the app than yours."], ["Open App Store", "Back"], ""),
    ("SketchPermission", "Permission off", "Cravage can't see phones nearby",
     ["Local Network access is turned off for Cravage.", "Settings &gt; Privacy &amp; Security &gt; Local Network &gt; Cravage."],
     ["Open Settings", "Try again"], ""),
    ("SketchConnectionLost", "Connection lost", "Lost the connection to Sam",
     ["The round has stopped. Nothing you entered was sent unmasked.", "Error code R-12 (copy for support)"], ["OK"], "Draft copy"),
    ("SketchTimeout", "Round failed: timeout", "The round stopped",
     ["Alex didn't send a share in time.", "Sam can restart with the same room and name."], ["Restart round (host)", "Leave"], ""),
    ("SketchRestartOffer", "Restart offer (joiner)", "Sam restarted the round",
     ["Annual bonus &#183; 3 people", "Rejoin to take part again. You will enter your figure again.", "Offer ends in 2:40."],
     ["Rejoin", "Leave room"], "New: owner decision"),
    ("SketchRestartWarning", "Before entering a figure after a restart", "This is a restarted round",
     ["If the group has changed and people enter the same figures as last time, comparing the two results can reveal someone's figure.",
      "Stronger version when fewer people rejoined: &#8220;1 person from the last round is not here.&#8221;"],
     ["I understand", "Leave room"], "Copy not yet approved"),
    ("SketchPartial", "Result: partial", "Average: 37,166.83 (not agreed)",
     ["Alex's phone didn't sign agreement in time.", "Treat this result with care. It can't be exported."], ["Leave room"], ""),
    ("SketchMismatch", "Result: disagreement", "Phones did not agree",
     ["Alex's phone did not agree with this phone about the shares.", "This does not mean Alex did anything wrong.",
      "No average is shown."], ["Restart round (host)", "Leave room"], "Copy rule: never name a cheat"),
    ("SketchDisputed", "Result: disputed later", "Result disputed",
     ["After the result appeared, a conflicting agreement arrived from Alex's phone.",
      "A transcript you already shared is unchanged; this phone now marks the result disputed.",
      "This round can't be exported again: the file has no way to say a result is disputed."], ["OK"], ""),
    ("SketchPaywall", "Paywall", "Rooms for 4 to 8 people",
     ["One-off unlock for this Apple ID. The host pays; people joining don't.", "[PRICE]"], ["Unlock", "Restore purchase", "Not now"], ""),
    ("SketchSettings", "Settings", "Settings",
     ["Nickname: Dee", "Restore purchase", "Limitations", "Privacy policy", "Copy diagnostics (no figures or names)", "About"], ["Done"], ""),
    ("SketchLimitations", "Limitations", "What Cravage can't do",
     ["Same room only; up to 8 people.", "The maths can't check honesty.", "A room letter proves a key, not a person: count the phones.",
      "Colluding people can recover a figure.", "The average itself can be revealing.", "(Approved text, shortened here)"], ["Done"], ""),
]
for name, _title, heading, lines, actions, tag in sketches:
    screens[name] = sketch(heading, lines, actions, tag)

for name, html in screens.items():
    with open(os.path.join(OUT, name + ".dc.html"), "w", encoding="utf-8") as f:
        f.write(html)

polished = [("Main", "1 Home"), ("NewRoom", "2 New room"), ("Join", "3 Join"), ("LobbyHost", "4 Lobby: host"),
            ("LobbyJoiner", "5 Lobby: joiner"), ("ConfirmCode", "6 Check the code"), ("EnterFigure", "7 Enter figure"),
            ("Waiting", "8 Waiting for shares"), ("Result", "9 Result: agreed")]
artboards = []
for i, (name, title) in enumerate(polished):
    artboards.append({"file": name + ".dc.html", "title": title, "x": (i % 5) * 470, "y": (i // 5) * 1000,
                      "w": 390, "h": 844, "page": "page-1"})
for i, (name, title, *_rest) in enumerate(sketches):
    artboards.append({"file": name + ".dc.html", "title": title, "x": (i % 6) * 470, "y": (i // 6) * 1000,
                      "w": 390, "h": 844, "page": "page-2"})
for i, (name, title) in enumerate([("HomeWarm", "Home look A: Warm glow"), ("HomeNight", "Home look B: Night")]):
    artboards.append({"file": name + ".dc.html", "title": title, "x": i * 470, "y": 0, "w": 390, "h": 844, "page": "page-3"})

canvas = {
    "pages": [{"id": "page-1", "name": "First round (polished)"}, {"id": "page-2", "name": "Other states (sketches)"},
              {"id": "page-3", "name": "Looks not chosen"}],
    "artboards": artboards,
    "annotations": [
        {"id": "brief-round", "page": "page-1", "x": 1880, "y": 1000, "w": 420,
         "text": "Look C, \"Paper\", chosen by the owner on 2026-09-14: editorial serif headings, hairline rules, numbered steps and drawn illustrations over standard iOS controls. Monospace only for figures and the room code.\n\nFlow: Home > New room (host) or Join > Lobby > Check the code > Enter figure > Waiting > Result.\n\nLight mode shown; dark mode follows the system."},
        {"id": "brief-looks", "page": "page-3", "x": 0, "y": -150, "w": 860,
         "text": "The two Home looks not chosen, kept for reference: A \"Warm glow\" and B \"Night\"."},
        {"id": "brief-states", "page": "page-2", "x": 0, "y": -150, "w": 620,
         "text": "Every other state, sketched cheaply. Approve these feature by feature as device behaviour becomes known (PLAN step 4). Tags mark new owner decisions and copy not yet approved."},
    ],
    "launch": {"view": "canvas", "page": "page-1"},
}
with open(os.path.join(OUT, "canvas.json"), "w", encoding="utf-8") as f:
    json.dump(canvas, f, indent=2)
print("wrote", len(screens), "artboards")
