# Retro 2026-09-14 - CravageCore, transport groundwork, mockups

Public-safe record. Scope: f9166a1..0512dc0 (23 commits, CI green on every push) and SMPC pull
request 1 (merged as bf72734). Delivery step 3 done, step 4 look chosen, step 5 groundwork.

## Went well
- Every CravageCore slice was cross-checked outside Swift: 6000 parse and 6002 format cases against the real JavaScript (0 mismatches); Python-generated vectors for masks, signatures, rosters and a golden transcript; the pinned SMPC verifier now accepts the app's transcript in CI and rejects a tampered one (0bf6c99).
- Both fresh read-only reviews paid off. The engine review (6b34bdf) found an unattributable lobby lockout and an overfillable restart; the transport review (9b6f3f2) found that `newConnectionLimit` is a lifetime budget, which would have locked hosts out after sixteen connections. All fixed with regression tests that went red on revert (ffe8155, 8c39ed5).
- Owner decisions were asked in plain terms and landed the same day: warn on every restart, ask before rejoining, authenticate the room label in the transcript (650b845).
- Showing three Home looks side by side got a one-word decision ("Paper") after a single draft had read as plain (4b9473b, 0512dc0).

## Went badly
- Tests that passed without testing their names: one of mine (a "ghost nickname" test that built no ghost), three found by the engine review, two by the transport review. Root cause: no step checked that a named guarantee fails when its guard is removed.
- An Apple API read from its Swift signature only: `newConnectionLimit` looked like a cap. Root cause: the header doc comment, which says it decrements, was not read.
- Explanations named things instead of explaining them; the owner asked what "the transcript checker" and "checking the room code as per the spec" meant. Root cause: summaries and canvas notes reused internal names.
- The first mockups followed the plan's style line literally with no alternates, and were judged plain. Root cause: the design skill's "put alternates beside the deliverable" was skipped because the plan named a style.
- A mockups README was committed saying "approved" before any approval (fixed in 97cc494). Root cause: status wording copied from the CLAUDE.md phrase without checking it applied.
- Tool friction: zsh did not split an argument variable (ran via bash); a Write failed on a file patched since its last read; Swift 6 flagged NSLock in async test code and non-Sendable closures (fixed in 22ec604).

## Gates
- Tests that do not test their names: rule in CLAUDE.md (a test named for a guarantee gets a `Tools/mutations.json` entry); check `Tools/check_mutations.py`, a CI job that breaks 16 guards one at a time and requires a failing suite. All 16 caught locally.
- Apple API semantics: rule in CLAUDE.md (read framework header doc comments, not only the signature); the `fresh-review` skill tells the reviewer to check headers. No automated check is possible; the review is the backstop.
- Plain explanations and visual alternates: no automated check possible; fallbacks are agent memory notes (plain-English explanations; visual choices).
- Status words: rule already in CLAUDE.md ("approved, not yet implemented"); no automated check; noted here.

## Skills
- Write: `fresh-review` (project), from the reviewer brief written by hand twice this session.
- Edit: none. Audit: `code-review` (global) did not fire and was not needed; the reviews needed spec-specific hunt lists. Prune: the working-setup memory bullet saying skills were missing on the Mac (they are in `.claude/skills/`).

## Handoff
- Owner: say when the three iPhones are free for the device session (NetworkTransport has never run on a phone).
- Agent, next: confirm with the owner that the nine Paper screens in `design/mockups/` are the build reference, then build them in SwiftUI against `RoundCoordinator`; add dark mode for the Paper look, which is not yet designed.
- Approved, not yet implemented: restart warning and rejoin offer in the UI; the "did not agree with this phone" copy rule; screens in the Paper look.
- Awaiting values or approval: unlock price placeholder; restart-warning copy (drafted in SPEC 13); the "Error code R-12" draft string in the connection-lost sketch.
- Untested: every NetworkTransport path on devices, including whether cancelling a joiner's blocked receive closes its connection; local-network denial; the release-build no-test-hooks assertion.
- Still unstaged by design: the team ID in `Spike/ConnectivitySpike.xcodeproj`; `Spike/` is deleted after the first real three-phone round.
