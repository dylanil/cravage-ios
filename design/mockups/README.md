# Screen mockups (delivery step 4)

Static mockups for the owner to approve before the app screens are built. `gen_mockups.py` writes
every artboard (`*.dc.html`) and the layout (`canvas.json`); edit it and re-run rather than editing
the generated files:

    python3 design/mockups/gen_mockups.py design/mockups

Two pages:

- **First round (polished):** Home, New room, Join, Lobby (host and joiner), Check the code,
  Enter figure, Waiting for shares, Result (agreed).
- **Other states (sketches):** nothing nearby, requesting, declined, full, old app, local-network
  permission off, connection lost, timeout, restart offer, restart warning, partial agreement,
  disagreement, disputed, paywall, settings, limitations.

Visual rules come from `docs/PLAN.md` (system font, standard iOS controls, orange accent,
monospace only for figures and the room code). Copy follows CLAUDE.md's honesty rules and the
SPEC 7 copy rule. Strings marked "Copy not yet approved" or "Draft copy" need the owner's sign-off;
the unlock price is a placeholder. Status: approved, not yet implemented - awaiting owner review.
