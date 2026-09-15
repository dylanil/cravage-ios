# Codebase review - 2026-09-15

Reviewed commit: `356bdb90bd3796d96be272a7df0904b7a77ce6b9`.
Scope: all CravageCore source, app coordinator and transport, relevant tests and CI, against
PLAN.md, SPEC.md, WIRE.md, the coding guardrails and the latest retro. Separate read-only
reviewers inspected standards and spec conformance. Findings below are confirmed by source
inspection, not runtime reproductions. Application code was not changed during this review.

The core arithmetic, mask derivation, signature binding, confirmation barrier and fresh-key
restart design look coherent on inspection. No arithmetic or plaintext-disclosure defect was
identified. This is a code review, not a security certification or device acceptance run.

## Standards

### S1 [P1] Delayed disconnect can fail a newly joined room

`Cravage/Transport/NetworkTransport.swift:222-227` removes a connection, awaits its outbox drain,
then emits `peerDisconnected` without checking the transport generation. A joiner can leave and
join a new room during that await. Both host connections use `PeerID.host`, so the old callback
is indistinguishable from a failure of the new connection and fails the new round.
The receive-loop cleanup at lines 201-204 has the same gap after its identity check.

Required regression: hold the old close operation, leave and join another room, then release
that old close. The new round must remain active. Recheck generation after asynchronous cleanup
before emitting a lifecycle event. Governing rule: stale async work must not mutate a new round.

### S2 [P2] Repeated Join reconnects despite the engine rejecting the action

`Cravage/Round/RoundCoordinator.swift:58-61` calls `connect` whenever the resulting engine state
is lobby/joiner, even if the join action was rejected. A second Join while awaiting admission
therefore replaces the existing socket. If the first welcome already established the session,
the welcome from the replacement socket is rejected and no fresh hello is sent.

Required regression: complete the first welcome, tap Join again, and assert exactly one
transport connection and successful admission. Gate the transport side effect on an accepted
transition. Governing rule: two Join taps produce one logical operation.

### S3 [P2] Mutation gate counts build failures as detected regressions

`Tools/check_mutations.py:18-21,43-51` equates every nonzero `swift test` exit with a caught
mutation and discards stdout/stderr. A compile error or infrastructure failure after a mutation
therefore prints `caught` even if no test executed. The passing baseline does not prove that each
mutated build compiled or reached its tests.

Required regression for the harness: distinguish a passing suite, an actual assertion failure,
and a compile failure. Require a successful mutated build and evidence of the failing test;
retain diagnostics. This finding does not assert that a current listed mutation fails to compile.

No broad smell-driven refactor is justified by this pass. The main technical debt is lifecycle
acceptance coverage: the existing fake transport does not reproduce asynchronous socket
replacement and delayed closure.

## Spec

### P1 [P2] Disputed rounds can still produce a clean transcript

`CravageCore/Sources/CravageCore/RoundEngine.swift:715` changes only the phase when a late
conflicting result confirmation arrives. The completed `RoundRecord` retains its original
signatures and has no dispute state. `Transcript.make(from:)` at `Transcript.swift:41` can
therefore still produce the original verified transcript from that record.

SPEC invariant 7 requires the on-device record and subsequent re-export to carry the dispute;
already-exported files remain unchanged. The current late-conflict test checks phase and sum,
not export. Add a regression that completes a round, injects a late conflict through `received`,
then checks export. Preserve dispute state in the record and make export honor it; at minimum,
refuse to produce a clean agreement transcript from a disputed record. A format extension needs
to remain compatible with the deliberately pinned external verifier.

### P2 [P2] Joiners lack an incoming-message work budget

`CravageCore/Sources/CravageCore/RoundEngine.swift:551-566` applies the 64-message limit only to
hosts. A malicious host can repeatedly send a valid envelope to a joiner. Each delivery reaches
signature verification before the later session/phase rejection, including after completion or
failure. Framing bounds individual message sizes but does not bound repeated messages; delivery
runs through the main-actor coordinator.

PLAN's message-domain requirements explicitly bound repeated-valid-message floods and require
responsive cancellation. Add a joiner flood regression, with a budget that allows legitimate
relayed traffic from all eight parties. Disconnect excessive input before expensive verification.

## Verification and limits

- The exact reviewed commit has successful GitHub CI:
  https://github.com/dylanil/cravage-ios/actions/runs/34814727946.
- Local verifier checksum check: passed, pinned SMPC `bf7273489807ac72910e59e12896d9da2c0c162f`.
- Local public-safety lint on the existing index: passed.
- Local Swift tests and simulator tests could not start: the toolchain reports an unaccepted
  Xcode license. No claim of fresh local suite execution or runtime reproduction is made.
- CI currently tests the app in Debug and builds Release; it does not execute Release tests or
  assert the planned exclusion of test hooks. This remains an acceptance gap.
- Real NetworkTransport device paths remain untested per the handoff. Three-phone and later
  eight-phone acceptance are still required.
- SwiftUI screens, StoreKit purchase flow and app transcript sharing are planned delivery work.
  Their absence is not counted as a newly discovered defect.

## Follow-up

S3 follow-up: the harness now requires a successful build and a named failing XCTest case,
retains evidence, and mutates an isolated source copy. Its compiler-failure regression failed
against the original harness; all seven harness tests pass after the change. CI also runs those
tests and uploads mutation evidence. Implementation: `703f957`.
An independent fresh review found no high or medium issues and one weak baseline-stop assertion.
That assertion now checks that no mutated build was attempted; it fails when the early return
is removed in an isolated copy and passes with the guard intact.
The other four findings remain open. Each fix needs a
failing regression first and the normal fresh review and CI gates.
Coordinate ownership with the active implementation session before editing the
transport, coordinator or engine. Codex initialization uses CLAUDE.md as the shared rules source
and thin .agents skill entries pointing to the canonical .claude skills.
