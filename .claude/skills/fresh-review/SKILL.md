---
name: fresh-review
description: Launch the fresh read-only reviewer CLAUDE.md requires after a protocol, entitlement, state-machine or transport slice is committed. Use right after the commit and before reporting the slice done; then fix findings test-first and record them in a commit.
---

# Fresh read-only review

CLAUDE.md requires an independent reviewer for protocol, entitlement, state-machine and transport
changes. Both reviews in the 2026-09-14 session found real defects the author's own tests missed
(a lifetime connection budget read as a cap; tests passing without testing their names).

## 1. Brief (background agent, general-purpose)

Give the agent only what a stranger needs, never the conversation:

- READ-ONLY: no edits, commits or pushes; it may run `swift test --package-path CravageCore`.
- The commit hashes and the files under review, plus the governing docs: `docs/SPEC.md` sections,
  `docs/PLAN.md` sections, `docs/WIRE.md`, and any findings document the code learned from.
- For Apple API use: check against the SDK's `.swiftinterface` **and** the doc comments in
  `Network.framework/Headers` (or the relevant framework headers), not memory.
- A numbered hunt list specific to the change (invariants, bypasses, lifecycle, limits, privacy,
  concurrency), always ending with: tests that do not test what their names claim, and important
  untested behaviour.
- Output: severity, trigger sequence, file:line, CONFIRMED or PLAUSIBLE; what is sound; a word cap.

## 2. Act on the report

- Fix every critical, high and medium finding, and the lows that are cheap, each with a regression
  test written first; revert each fix once to see its test fail.
- Add an entry to `Tools/mutations.json` for every guard a new test claims to protect, and run
  `python3 Tools/check_mutations.py`.
- Findings that change SPEC behaviour or product copy go to the owner as a decision, in plain words.
- One commit for the fixes, naming each finding and saying which were not fixed and why.
