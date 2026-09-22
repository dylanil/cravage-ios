# Screen mockups (delivery step 4)

Static design artboards, not screenshots or proof of device behavior. `gen_mockups.py` writes
every artboard (`*.dc.html`) and the layout (`canvas.json`); edit it and re-run rather than editing
the generated files:

    python3 design/mockups/gen_mockups.py design/mockups

Three pages:

- **First round (polished):** Home, New room, Join, Lobby (host and joiner), Check the code,
  Enter figure, Waiting for shares, Result (agreed).
- **Other states (sketches):** nothing nearby, requesting, declined, full, old app, local-network
  permission off, connection lost, timeout, restart offer, restart warning, partial agreement,
  disagreement, disputed, paywall, settings, limitations, interruption, restart refusal.
- **Looks not chosen:** the Warm glow and Night Home directions, kept for reference.

Visual rules come from `docs/PLAN.md` (standard iOS controls, orange accent, monospace only for
figures and the room code). The owner chose look C, "Paper" (2026-09-14): editorial serif
headings, hairline rules, numbered steps and drawn illustrations. The first draft was judged too
plain; Warm glow and Night were the other two directions. Copy is checked against CLAUDE.md's honesty rules by
`Tools/check_honesty_copy.sh` in CI, after the fresh review of 2026-09-19 found the Home headline
claiming against collusion and input honesty; the SPEC 7 copy rule applies too. That lint scans app
strings, not these HTML files. Strings marked "Copy not yet approved" or "Draft copy" still need
sign-off. The unlock price was agreed at $0.99/99p; StoreKit must supply the localized purchase price.

Status: the first-round, restart and round-ended screens are built. On 2026-09-22 the generator and
generated files were reconciled with the actual lobby: the joiner has asked to join, cannot know
admission or list the roster yet, and sees the advertised host as unverified. Decimal copy now
specifies a full stop, with sign and decimal-point controls; Waiting says "No share yet" without
guessing what the person is doing. Interruption and restart-refusal sketches record the new policy.
Settings, Limitations and the paywall remain design sketches, not implemented capabilities.
