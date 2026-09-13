# Retro 2026-09-13 - paperwork session

Public-safe record. Scope: the App Store paperwork, the support address, the public-safety lint,
and coordination with the concurrent build session. Companion to `2026-09-13-council-and-spike.md`.

## Went well

- The App Store listing copy, keywords and purchase text were checked against Apple's field limits
  by script before commit, and the privacy and support pages went live on GitHub Pages the same day.
- The first push collision between two sessions was resolved by fetch, inspect, rebase; the other
  session's seven commits were read before anything was rebased onto them.
- The lint's false positive on the public support address was caught locally, before it blocked
  a push.

## Went badly

- Pushed without fetching first, so the push was rejected. Root cause: one-session habits in a
  two-session repository. The other session hit the mirror image the same evening.
- The lint flagged its own denylist line and turned CI red; two in-place edits then missed because
  the working copy uses CRLF line endings. Root cause: exact-match scripting on a CRLF tree; whole-
  file rewrites are the reliable path here.
- One commit was staged with `git add -A` after the stage-by-name rule had landed from the other
  session but before this session had read it. Nothing unwanted was committed.

## Gates

- Team ID: the lint now scans the index (`git grep --cached`) and fails on an Apple team
  identifier in any project file, with a negative test proving it fires. Closes the check the
  council-and-spike retro asked for.
- Concurrent sessions: fetch and fast-forward before every commit (CLAUDE.md); git's own
  non-fast-forward rejection is the check, and force is never used.
- Skills on every machine: `retro` and `review-council` now live in the repo under
  `.claude/skills/` as the canonical copies, so a fresh clone has them.

## Handoff

- Owner: on the developer-account approval email, the App Store Connect walkthrough from
  `docs/APP_STORE.md`. Decide whether the Xcode team ID may ever be committed; the lint now says no
  by default, and an ignored xcconfig is the intended home.
- Build session: delivery step 3, `CravageCore`, per the council-and-spike retro's handoff.
- Approved, not yet implemented: the version-2 transcript mode (with the `claim` field) in the
  upstream verifier.
