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
- **Home: other looks:** two alternative directions for Home (Night, Paper) to compare with the
  warm-glow look used on the first page.

Visual rules come from `docs/PLAN.md` (standard iOS controls, orange accent, monospace only for
figures and the room code). Look A, "Warm glow", adds a cream ground with an orange glow, rounded
display type and drawn illustrations, after the owner found the first draft too plain. Copy follows CLAUDE.md's honesty rules and the
SPEC 7 copy rule. Strings marked "Copy not yet approved" or "Draft copy" need the owner's sign-off;
the unlock price is a placeholder. Status: drafted and awaiting owner review; not approved and not
implemented.
