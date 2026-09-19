# Screen mockups (delivery step 4)

Static mockups for the owner to approve before the app screens are built. `gen_mockups.py` writes
every artboard (`*.dc.html`) and the layout (`canvas.json`); edit it and re-run rather than editing
the generated files:

    python3 design/mockups/gen_mockups.py design/mockups

Three pages:

- **First round (polished):** Home, New room, Join, Lobby (host and joiner), Check the code,
  Enter figure, Waiting for shares, Result (agreed).
- **Other states (sketches):** nothing nearby, requesting, declined, full, old app, local-network
  permission off, connection lost, timeout, restart offer, restart warning, partial agreement,
  disagreement, disputed, paywall, settings, limitations.
- **Looks not chosen:** the Warm glow and Night Home directions, kept for reference.

Visual rules come from `docs/PLAN.md` (standard iOS controls, orange accent, monospace only for
figures and the room code). The owner chose look C, "Paper" (2026-09-14): editorial serif
headings, hairline rules, numbered steps and drawn illustrations. The first draft was judged too
plain; Warm glow and Night were the other two directions. Copy follows CLAUDE.md's honesty rules and the
SPEC 7 copy rule. Strings marked "Copy not yet approved" or "Draft copy" need the owner's sign-off;
the unlock price is a placeholder. Status: look chosen; the nine first-round screens are built in the app (delivery step 5), together with the restart offer, the restart warning and the round-ended screen. Where a screen and the protocol disagreed, the protocol won and the mockup was corrected: the joiner's lobby no longer lists people it cannot know about (see SPEC section 3).
