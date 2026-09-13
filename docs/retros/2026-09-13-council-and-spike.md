# Retro 2026-09-13 - council and connectivity spike

Public-safe record. Scope: delivery steps 1 and 2 of `docs/PLAN.md` - the protocol council and
`docs/SPEC.md`, the owner-approved Limitations text, the three-phone Network framework spike, and
the clean-checkout build. Eight pushes to `main`, all green. Private material is in agent memory.

## Went well

- The council was three separate agent sessions given cold excerpts, with no view of each other
  or of the planning conversation. The two question-scoped reviewers confirmed the design; the
  adversarial one found two no-collusion attacks (host-fabricated participants; restart
  differencing) that neither scoped reviewer saw. The guardrail "multiple personas agreeing is not
  independent corroboration" paid for itself on its first use.
- The Limitations text was approved in one pass because each item was explained in plain
  language, with what it means and what it does not, before any decision was asked for.
- The iOS 26 `NetworkListener`/`NetworkBrowser`/`NetworkConnection` API is newer than the model's
  training. Instead of guessing, the session read the SDK's own `.swiftinterface`, wrote against
  the real signatures, and compiled for the device SDK before the owner spent any phone time. One
  compile error was caught that way; nothing later failed to build on a phone.
- A timestamped on-screen log with a Copy button turned owner-run device tests into precise
  evidence. Three logs from three phones (one emailed by that phone's user) gave discovery times,
  the backgrounding asymmetry, disconnect-detection timing and the relay proof without anyone
  reading an Xcode console.
- The documented build and test commands were proven from a fresh clone on the development Mac,
  with no private files.

## Went badly

- A basic control-flow bug in the spike: peer cleanup was placed after a throwing receive loop
  inside the same `do` block, so it never ran when a connection failed - the common case. Symptoms
  on phones: phantom "admitted" peers, relay failures on every message, a rejoining phone piling
  up duplicate never-admitted requests. Root cause: throwaway code got throwaway discipline, but
  its bugs cost three people's device time. There was no test with a throwing stream.
- A speculative fix shipped on console noise: the listener's connection limit was raised because
  a "cannot add handler" log line looked like a limit problem. Harmless and probably right, but the
  commit message stated it as a cause without a reproduction.
- The `retro` and `review-council` skills recorded by the previous retro do not exist on the Mac:
  the private notes were carried across, the skills were not. The council was run from PLAN.md and
  the guardrails instead; its procedure is now written down in the council record, so it can be
  reconstructed.
- Xcode wrote the developer team ID into the tracked spike project file when signing was set up.
  Caught only by reading `git status` before the last commit. Root cause: the public-safety lint
  looks for prose markers and does not scan `.pbxproj` at all.
- Another session pushed to `main` mid-session. Noticed only because the clean-checkout clone was
  one commit ahead of the local tree. No conflict, by luck.
- The physical setup steps (menus, trust prompts, cables) were explained at the wrong level of
  detail until the private notes were in place, which happened mid-session.

## Gates

- Failure-path cleanup: in any code that owns a connection, task or stream that can throw, cleanup
  lives after the `do`/`catch` or in `defer`, and a unit test injects a throwing stream. Check:
  `CravageCore`'s `RoundEngine` gets a "transport error thrown mid-state" negative test, and the
  real `NetworkTransport` gets one before its first device run. Rule now; check lands in step 3.
- Speculative changes: a change made without a reproduction says "speculative" in the commit
  message and in the findings, and gets a named follow-up. Check: the fresh reviewer reads commit
  messages for causal claims. Rule only.
- Team ID: `CLAUDE.md` now says stage by name and keep the team ID out of the tree. Check to add
  next session: the public-safety lint scans index content (what will actually be committed, via
  `git grep --cached`) and includes `*.pbxproj` and `*.xcconfig` with a `DEVELOPMENT_TEAM =`
  pattern; then move the team into an ignored xcconfig so the working tree is clean too. Rule now;
  check next session.
- Concurrent sessions: `CLAUDE.md` now says fetch and fast-forward before every commit. Check:
  `git status -sb` shows "behind" when it matters. Rule only.

## Handoff

- Next: step 3, `CravageCore`. Start from `docs/SPEC.md` sections 1, 3 and 4 and PLAN.md's test
  list; first slice is `FixedPoint` with the pinned SMPC vectors, tests first. SPEC additions that
  step 3 must implement, beyond PLAN.md's original list: the `roomcode_confirm` / `result_confirm`
  split, the mask public key inside the signed hello with duplicate rejection, first-write-wins on
  canonical content, the same-generation send guard, the `complete(agreed) -> disputed`
  transition, the `maxParties x cap < 2^63` assertion, and the transcript `claim` field. The
  `verify_round.py` v2 extension in the SMPC repo (PLAN.md R6) must check `claim` too.
- Deadline values for `RoundEngine`: the transport reported a dead peer after 38 seconds in one
  case and within a second in another. Per-state deadlines must be shorter than the slow case so a
  silent peer fails the round on the engine's clock, not the transport's.
- Steps 4 and 5 must include SPEC invariants 12 and 13: the "N-1 other phones connected" count on
  the Lobby and Confirm screens, and the warning shown when a restart shrinks the roster. The
  mockups need those states.
- Owner: bring the `retro` and `review-council` skills to the Mac by the same route as the private
  notes, or ask the agent to recreate them from `docs/review/council/`. Nothing skill-shaped
  exists on the Mac today.
- Owner: decide whether the team ID may be committed. Until then it stays as an unstaged change in
  `Spike/ConnectivitySpike.xcodeproj/project.pbxproj`; see the gate above.
- `Spike/` stays in the tree. Carried forward untested (all in the findings doc): rejoin after the
  cleanup fix, the local-network permission denial path, and eight phones at step 10.
- Three iPhones on iOS 26 are set up and trusted for Xcode. Free Personal Team builds expire after
  seven days; re-run from Xcode when needed.
- `docs/APP_STORE.md` arrived from another session and was only skimmed here. Its items marked
  *decision* (bundle ID, review contact number, export-compliance answer) are the owner's.
