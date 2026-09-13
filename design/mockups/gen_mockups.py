#!/usr/bin/env python3
"""Writes the Cravage step-4 mockup artboards (.dc.html) and canvas.json into design/mockups/."""
import json
import os
import sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

BASE_CSS = """
body { margin: 0; background: #F2F2F7; color: #1C1C1E; font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif; -webkit-font-smoothing: antialiased; }
a { color: #C2410C; text-decoration: none; } a:hover { color: #9A3412; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-variant-numeric: tabular-nums; }
"""

SKETCH_CSS = """
body { margin: 0; background: #FAFAF7; color: #2B2B2B; font-family: "Patrick Hand", "Comic Sans MS", "Marker Felt", system-ui, sans-serif; }
a { color: #C2410C; } a:hover { color: #9A3412; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; }
"""

ORANGE = "#D9480F"      # filled buttons: white text passes AA for 17pt semibold
ORANGE_TEXT = "#C2410C"
TINT = "#FFF1E8"
SECONDARY = "#6C6C70"
SEPARATOR = "#D1D1D6"
GREEN = "#1F8A3B"
RED = "#C62828"

ICON = {
    "gear": '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h0a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v0a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path></svg>',
    "chev": '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 6 15 12 9 18"></polyline></svg>',
    "back": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 6 9 12 15 18"></polyline></svg>',
    "check": '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><polyline points="5 12.5 10 17 19 7"></polyline></svg>',
    "clock": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"></circle><polyline points="12 7 12 12 15 14"></polyline></svg>',
    "lock": '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"></rect><path d="M8 11V8a4 4 0 0 1 8 0v3"></path></svg>',
    "phone": '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2.5" width="10" height="19" rx="2.5"></rect><line x1="11" y1="18.5" x2="13" y2="18.5"></line></svg>',
    "warn": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg>',
    "spin": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"><path d="M12 3a9 9 0 1 0 9 9"></path></svg>',
}


def icon(name, color):
    return ICON[name] % color


def page(body, css=BASE_CSS, bg="#F2F2F7"):
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


def nav(title="", left="", right="", large=None):
    left_html = f'<div style="display: flex; align-items: center; gap: 2px; color: {ORANGE_TEXT}; font-size: 17px;">{left}</div>'
    right_html = f'<div style="display: flex; align-items: center; justify-content: flex-end; color: {ORANGE_TEXT}; font-size: 17px; font-weight: 600;">{right}</div>'
    bar = f"""<div style="height: 44px; margin-top: 54px; padding: 0 16px; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); align-items: center;">
  {left_html}
  <div style="text-align: center; font-size: 17px; font-weight: 600;">{title}</div>
  {right_html}
</div>"""
    if large:
        bar += f'<div style="padding: 4px 20px 8px; font-size: 34px; font-weight: 700; letter-spacing: 0.3px;">{large}</div>'
    return bar


def primary(label, disabled=False):
    bg = "#E5E5EA" if disabled else ORANGE
    fg = "#8E8E93" if disabled else "#FFFFFF"
    return f'<div style="height: 52px; border-radius: 14px; background: {bg}; color: {fg}; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'


def secondary(label, color=ORANGE_TEXT):
    return f'<div style="height: 52px; border-radius: 14px; background: {TINT}; color: {color}; display: flex; align-items: center; justify-content: center; font-size: 17px; font-weight: 600;">{label}</div>'


def plain(label, color=ORANGE_TEXT):
    return f'<div style="height: 44px; display: flex; align-items: center; justify-content: center; color: {color}; font-size: 17px;">{label}</div>'


def section(title, rows, footer=""):
    head = f'<div style="padding: 0 36px 6px; font-size: 13px; color: {SECONDARY}; text-transform: uppercase; letter-spacing: 0.4px;">{title}</div>' if title else ""
    inner = f'<div style="margin: 0 16px; background: #FFFFFF; border-radius: 12px; overflow: hidden; display: flex; flex-direction: column;">{"".join(rows)}</div>'
    foot = f'<div style="padding: 6px 36px 0; font-size: 13px; line-height: 18px; color: {SECONDARY}; text-wrap: pretty;">{footer}</div>' if footer else ""
    return f'<div style="display: flex; flex-direction: column; padding-top: 22px;">{head}{inner}{foot}</div>'


def row(main, sub="", trailing="", last=False, leading=""):
    border = "" if last else f"border-bottom: 0.5px solid {SEPARATOR};"
    sub_html = f'<div style="font-size: 14px; color: {SECONDARY}; margin-top: 2px;">{sub}</div>' if sub else ""
    lead = f'<div style="display: flex; align-items: center;">{leading}</div>' if leading else ""
    return f"""<div style="min-height: 52px; padding: 10px 16px; box-sizing: border-box; display: flex; align-items: center; gap: 12px; {border}">
  {lead}<div style="flex-grow: 1; display: flex; flex-direction: column;"><div style="font-size: 17px;">{main}</div>{sub_html}</div>
  <div style="display: flex; align-items: center; gap: 8px;">{trailing}</div>
</div>"""


def letter(ch, filled=True):
    bg = "#1C1C1E" if filled else "#E5E5EA"
    fg = "#FFFFFF" if filled else SECONDARY
    return f'<div class="mono" style="width: 30px; height: 30px; border-radius: 15px; background: {bg}; color: {fg}; display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: 600;">{ch}</div>'


def pill(text, fg, bg):
    return f'<div style="height: 26px; padding: 0 10px; border-radius: 13px; background: {bg}; color: {fg}; display: flex; align-items: center; gap: 4px; font-size: 13px; font-weight: 600;">{text}</div>'


def bottom(*items):
    return f'<div style="margin-top: auto; padding: 12px 20px 34px; display: flex; flex-direction: column; gap: 10px;">{"".join(items)}</div>'


def note(text, color=SECONDARY, size=13):
    return f'<div style="font-size: {size}px; line-height: {size + 5}px; color: {color}; text-align: center; text-wrap: pretty;">{text}</div>'


def deadline(text):
    return f'<div style="display: flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px; color: {SECONDARY};">{icon("clock", SECONDARY)}<span>{text}</span></div>'


screens = {}

# 1 Home
screens["Main"] = page(f"""
{nav(right=icon("gear", ORANGE_TEXT))}
<div style="padding: 60px 28px 0; display: flex; flex-direction: column; gap: 10px;">
  <div style="font-size: 44px; font-weight: 800; letter-spacing: -0.5px;">Cravage</div>
  <div style="font-size: 22px; line-height: 28px; color: #3A3A3C; text-wrap: pretty;">Work out a group average without anyone showing their number.</div>
</div>
<div style="padding: 36px 28px 0; display: flex; flex-direction: column; gap: 14px;">
  <div style="display: flex; align-items: center; gap: 12px;"><div class="mono" style="width: 28px; height: 28px; border-radius: 14px; background: {TINT}; color: {ORANGE_TEXT}; display: flex; align-items: center; justify-content: center; font-weight: 700;">1</div><div style="font-size: 16px;">Everyone opens the app in the same room</div></div>
  <div style="display: flex; align-items: center; gap: 12px;"><div class="mono" style="width: 28px; height: 28px; border-radius: 14px; background: {TINT}; color: {ORANGE_TEXT}; display: flex; align-items: center; justify-content: center; font-weight: 700;">2</div><div style="font-size: 16px;">You check your screens show the same code</div></div>
  <div style="display: flex; align-items: center; gap: 12px;"><div class="mono" style="width: 28px; height: 28px; border-radius: 14px; background: {TINT}; color: {ORANGE_TEXT}; display: flex; align-items: center; justify-content: center; font-weight: 700;">3</div><div style="font-size: 16px;">Each phone sends a masked share; only the average comes out</div></div>
</div>
{bottom(primary("New room"), secondary("Join a room"), note('You appear as <strong style="color: #1C1C1E;">Dee</strong>. <a>Change</a>', size=15))}
""")

# 2 New room
seg = "".join(
    f'<div class="mono" style="height: 40px; border-radius: 9px; display: flex; align-items: center; justify-content: center; gap: 3px; font-size: 16px; font-weight: 600; {"background: #FFFFFF; box-shadow: 0 1px 3px rgba(0,0,0,0.14); color: #1C1C1E;" if n == 3 else "color: " + SECONDARY + ";"}">{n}{"" if n == 3 else icon("lock", SECONDARY)}</div>'
    for n in range(3, 9))
screens["NewRoom"] = page(f"""
{nav("New room", left="Cancel")}
{section("What are you averaging?", [row('<span style="color: #1C1C1E;">Annual bonus</span>', last=True)], "Everyone in the room sees this. Nearby phones can see it too, with your nickname and the group size, but never anyone's number.")}
<div style="display: flex; flex-direction: column; padding-top: 26px;">
  <div style="padding: 0 36px 6px; font-size: 13px; color: {SECONDARY}; text-transform: uppercase; letter-spacing: 0.4px;">How many people, including you</div>
  <div style="margin: 0 16px; padding: 3px; background: #E5E5EA; border-radius: 12px; display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 2px;">{seg}</div>
  <div style="padding: 8px 36px 0; font-size: 13px; line-height: 18px; color: {SECONDARY};">3 people is free. 4 to 8 people is a one-off unlock.</div>
</div>
{bottom(primary("Open room"))}
""")

# 3 Join
screens["Join"] = page(f"""
{nav("Join a room", left=icon("back", ORANGE_TEXT) + "Back")}
{section("Rooms nearby", [
    row("Annual bonus", "Host: Sam &#183; 3 people", icon("chev", "#C7C7CC")),
    row("Team lunch budget", "Host: Morgan &#183; 5 people", icon("chev", "#C7C7CC")),
    row(f'<span style="color: {SECONDARY};">Looking for more&#8230;</span>', trailing=icon("spin", SECONDARY), last=True),
], "Rooms appear when you are close to the host's phone and the host has the app open.")}
{bottom(note('Joining as <strong style="color: #1C1C1E;">Dee</strong>', size=15))}
""")

# 4 Lobby, host
screens["LobbyHost"] = page(f"""
{nav("Annual bonus", left="Close")}
<div style="padding: 18px 20px 0; display: flex; align-items: center; gap: 10px;">
  <div style="font-size: 28px; font-weight: 700;">2 of 3</div><div style="font-size: 17px; color: {SECONDARY};">in the room</div>
</div>
{section("Asking to join", [row("Priya", "Only admit someone you can see in the room",
    '<div style="height: 34px; padding: 0 12px; border-radius: 17px; background: #F2F2F7; color: #1C1C1E; display: flex; align-items: center; font-size: 15px;">Decline</div><div style="height: 34px; padding: 0 14px; border-radius: 17px; background: ' + ORANGE + '; color: #FFFFFF; display: flex; align-items: center; font-size: 15px; font-weight: 600;">Admit</div>', last=True)])}
{section("In the room", [row("Sam", "You, host", pill("This phone", SECONDARY, "#F2F2F7")), row("Alex", last=True, trailing=pill(icon("phone", GREEN) + "Connected", GREEN, "#E8F5EC"))],
    "1 other phone connected. Keep the app open on every phone until the round ends.")}
{bottom(primary("Start round", disabled=True), note("Start needs 3 people. Admit Priya to begin."), deadline("Room closes in 14:12 if the round has not started"))}
""")

# 5 Lobby, joiner
screens["LobbyJoiner"] = page(f"""
{nav("Annual bonus", left="Leave")}
<div style="padding: 60px 28px 0; display: flex; flex-direction: column; align-items: center; gap: 14px;">
  <div style="width: 64px; height: 64px; border-radius: 32px; background: {TINT}; display: flex; align-items: center; justify-content: center;">{icon("spin", ORANGE_TEXT)}</div>
  <div style="font-size: 22px; font-weight: 700; text-align: center;">Waiting for Sam to start</div>
  <div style="font-size: 16px; line-height: 22px; color: {SECONDARY}; text-align: center; text-wrap: pretty;">You are in. Keep the app open; the round begins when the room is full.</div>
</div>
{section("In the room", [row("Sam", "Host"), row("Alex"), row("Dee", "You", last=True)])}
{bottom(deadline("Stops waiting in 14:05"))}
""")

# 6 Confirm code
screens["ConfirmCode"] = page(f"""
{nav("Check the code")}
<div style="padding: 20px 24px 0; display: flex; flex-direction: column; align-items: center; gap: 10px;">
  <div style="font-size: 15px; color: {SECONDARY};">Annual bonus &#183; 3 people</div>
  <div class="mono" style="font-size: 46px; font-weight: 700; letter-spacing: 3px; color: #1C1C1E;">K7QM-3XRD</div>
  <div style="margin-top: 6px; padding: 14px 16px; border-radius: 14px; background: #FFFFFF; display: flex; gap: 12px; align-items: flex-start;">
    <div style="padding-top: 1px;">{icon("phone", ORANGE_TEXT)}</div>
    <div style="font-size: 16px; line-height: 22px; text-wrap: pretty;">Look at the <strong>2 other phones</strong> in the room. Each must show exactly this code. If there are more or fewer phones, or a code differs, do not continue.</div>
  </div>
</div>
{section("Confirmed", [
    row("Sam", "Host", pill(icon("check", GREEN) + "Checked", GREEN, "#E8F5EC"), leading=letter("A")),
    row("Alex", "", pill("Checking", SECONDARY, "#F2F2F7"), leading=letter("B", False)),
    row("Dee", "You", "", last=True, leading=letter("C", False)),
])}
{bottom(primary("I checked, the codes match"), plain("The codes don't match", RED), deadline("Stops waiting in 2:48"))}
""")

# 7 Enter figure
screens["EnterFigure"] = page(f"""
{nav("Your figure", left="Leave")}
<div style="padding: 18px 20px 0; font-size: 15px; color: {SECONDARY};">Annual bonus</div>
<div style="margin: 10px 16px 0; padding: 18px 16px; background: #FFFFFF; border-radius: 14px; border: 2px solid {ORANGE}; display: flex; align-items: baseline; gap: 6px;">
  <div class="mono" style="font-size: 40px; font-weight: 600; color: #1C1C1E;">42500.50</div>
  <div style="width: 2px; height: 40px; background: {ORANGE}; align-self: center;"></div>
</div>
<div style="padding: 8px 32px 0; font-size: 13px; line-height: 18px; color: {SECONDARY};">Up to 999,999,999,999.99. Use your decimal mark; leave out thousands separators.</div>
<div style="margin: 22px 16px 0; padding: 14px 16px; background: #FFFFFF; border-radius: 14px; display: flex; flex-direction: column; gap: 10px;">
  <div style="font-size: 15px; line-height: 21px; text-wrap: pretty;">Your figure is processed on your phone; the app sends a masked share to the other participants.</div>
  <div style="height: 0.5px; background: {SEPARATOR};"></div>
  <div style="font-size: 15px; line-height: 21px; color: #3A3A3C; text-wrap: pretty;">With 3 people, the other 2 could work out your figure if they shared theirs with each other.</div>
</div>
{bottom(primary("Send masked share"), note("Once sent, your figure can't be changed for this round."))}
""")

# 8 Waiting
screens["Waiting"] = page(f"""
{nav("Annual bonus", left="Cancel")}
<div style="padding: 36px 24px 0; display: flex; flex-direction: column; align-items: center; gap: 12px;">
  <div class="mono" style="font-size: 52px; font-weight: 700;">2<span style="color: #C7C7CC;"> / 3</span></div>
  <div style="font-size: 17px; color: {SECONDARY};">masked shares in</div>
  <div style="width: 240px; height: 6px; border-radius: 3px; background: #E5E5EA; overflow: hidden;"><div style="width: 66%; height: 6px; background: {ORANGE};"></div></div>
</div>
{section("", [
    row("Sam", "", pill(icon("check", GREEN) + "Sent", GREEN, "#E8F5EC"), leading=letter("A")),
    row("Alex", "Still entering a figure", icon("spin", SECONDARY), leading=letter("B", False)),
    row("Dee", "You", pill(icon("check", GREEN) + "Sent", GREEN, "#E8F5EC"), last=True, leading=letter("C")),
])}
{bottom(deadline("Stops waiting in 4:21; the round then fails and the host can restart"))}
""")

# 9 Result, agreed
screens["Result"] = page(f"""
{nav("Result", right="Done")}
<div style="padding: 36px 24px 0; display: flex; flex-direction: column; align-items: center; gap: 6px;">
  <div style="font-size: 17px; color: {SECONDARY};">Average annual bonus</div>
  <div class="mono" style="font-size: 54px; font-weight: 700; letter-spacing: -1px;">37,166.83</div>
  <div style="font-size: 15px; color: {SECONDARY};">from 3 people</div>
</div>
<div style="margin: 24px 16px 0; padding: 14px 16px; background: #E8F5EC; border-radius: 14px; display: flex; gap: 12px; align-items: center;">
  {icon("check", GREEN)}<div style="font-size: 15px; line-height: 21px; color: #14532D; text-wrap: pretty;">All 3 phones signed agreement to the same set of shares.</div>
</div>
{section("", [row("Show the shares", "", icon("chev", "#C7C7CC")), row("Share transcript", "A file anyone can check", icon("chev", "#C7C7CC"), last=True)],
    "The app can't check that the figures people entered were true. Round history is not saved.")}
{bottom(secondary("Run again"), plain("Leave room"))}
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
      "A transcript you already shared is unchanged; this phone now marks the result disputed."], ["OK"], ""),
    ("SketchPaywall", "Paywall", "Rooms for 4 to 8 people",
     ["One-off unlock for this Apple ID. The host pays; people joining don't.", "[PRICE]"], ["Unlock", "Restore purchase", "Not now"], ""),
    ("SketchSettings", "Settings", "Settings",
     ["Nickname: Dee", "Restore purchase", "Limitations", "Privacy policy", "Copy diagnostics (no figures or names)", "About"], ["Done"], ""),
    ("SketchLimitations", "Limitations", "What Cravage can't do",
     ["Same room only; up to 8 people.", "The maths can't check honesty.", "A room letter proves a key, not a person: count the phones.",
      "Colluding people can recover a figure.", "The average itself can be revealing.", "(Approved text, shortened here)"], ["Done"], ""),
]
for name, title, heading, lines, actions, tag in sketches:
    screens[name] = page("", css=SKETCH_CSS)  # placeholder, replaced below
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

canvas = {
    "pages": [{"id": "page-1", "name": "First round (polished)"}, {"id": "page-2", "name": "Other states (sketches)"}],
    "artboards": artboards,
    "annotations": [
        {"id": "brief-round", "page": "page-1", "x": 1880, "y": 1000, "w": 420,
         "text": "First end-to-end round, for approval.\n\nFollows PLAN.md Visual: system font, standard iOS controls, orange accent, monospace only for figures and the room code.\n\nFlow: Home > New room (host) or Join > Lobby > Check the code > Enter figure > Waiting > Result.\n\nLight mode shown; dark mode follows the system.\n\nFilled-button orange is darkened from system orange so white text stays readable."},
        {"id": "open-questions", "page": "page-1", "x": 1880, "y": 1420, "w": 420,
         "text": "Worth checking:\n- The Home three-step explainer: keep or cut?\n- Room code shown with a count of other phones (SPEC 12).\n- Collusion note sits on the figure screen (PLAN).\n- The unlock price is left as a placeholder."},
        {"id": "brief-states", "page": "page-2", "x": 0, "y": -150, "w": 620,
         "text": "Every other state, sketched cheaply. Approve these feature by feature as device behaviour becomes known (PLAN step 4). Tags mark new owner decisions and copy not yet approved."},
    ],
    "launch": {"view": "canvas", "page": "page-1"},
}
with open(os.path.join(OUT, "canvas.json"), "w", encoding="utf-8") as f:
    json.dump(canvas, f, indent=2)
print("wrote", len(screens), "artboards")
