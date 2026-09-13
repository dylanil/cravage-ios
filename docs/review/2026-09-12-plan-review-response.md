# Response to the plan review of 2026-09-12

*Written 2026-09-13 by the implementing agent (Claude Code) for the owner, who agreed every
recommendation below the same day. The review it answers is `2026-09-12-plan-review.md`; the
companion guardrails note is `2026-09-12-coding-guardrails.md`. Both were produced by an
independent agent session with no access to this session's context.*

## Verdict on the review

Accepted in substance. Every factual claim that bears weight was checked against Apple's own
documentation before acting on it, and all of them held:

| Claim | Checked against | Result |
|---|---|---|
| Multipeer Connectivity deprecated | Apple TN3213 | Confirmed verbatim: "Xcode 27 deprecates the entire Multipeer Connectivity framework." Migrate to Network framework, which has opt-in peer-to-peer Wi-Fi. |
| Device name unavailable | UIDevice.name reference | Confirmed: iOS 16+ returns "iPhone" without an entitlement. |
| Simulator ignores local-network privacy | Apple TN3179 | Confirmed, plus: no API for permission state; operations may be denied before the prompt is answered. |
| Small Business Program needs enrolment | Apple programme page | Confirmed: accept the Paid Apps agreement; 15% applies from the month after approval. |
| EU trader contact details | App Store Connect help | Confirmed: individuals display address or PO Box (with proof), phone, email; trader status must be declared regardless. |
| Finite masks leak unbounded inputs | The maths | Confirmed. 64-bit masks hide figures only up to about 9.2 trillion in fixed-point units; the web demo's pinned nine-quadrillion vector leaks to 0.2% from its own share. |

## Decisions taken (owner agreed 2026-09-13)

1. **Transport:** Network framework, iOS 26 interface, iOS 26 minimum, star topology through the
   host. Multipeer is out. The 8-participant cap stays as a product decision.
2. **Numeric domain:** figures capped at magnitude below 10^18 fixed units (999,999,999,999.999999);
   shares and sums in wrapping Int64 arithmetic; no BigInt. Transcript becomes version 2 with an
   explicit modulus; the SMPC verifier gains a v2 mode (approved, not yet implemented).
3. **EU:** excluded from distribution in version one rather than publishing an address.
4. **App Review access:** review note plus video of a real round; a labelled practice mode is the
   prepared fallback, not a v1 feature.
5. **Nickname prompt** on first launch replaces "default to the phone's name".
6. **Workflow:** keep committing to main, but nothing is reported done until CI is green and any
   red run is fixed or reverted before other work.
7. **Council remit:** one council on four questions (transport and link security, numeric domain,
   full distributed state machine, transcript claims), then a fresh read-only code review of the
   protocol, parser, binding and entitlement code before TestFlight.
8. **Publish** both review documents with provenance headers, alongside this response.

## Specification points adopted from the review and the guardrails

Confirmation barrier as an enforced state; proof of key possession at hello; signed and
round-bound control messages; explicit restart rekey sequence; deadlines on every waiting state;
disagreement shown as a failure of agreement never as a smaller success badge; fingerprint claim
scoped to collision resistance and bound to the label; one distinct share per round identity with
the figure frozen before asynchronous work; round-generation tagging of asynchronous results;
entitlement enforced in the coordinator; message limits before decoding and before crypto;
release builds compiled without test hooks; interruption acceptance tests (backgrounding, lock,
call, host departure, cancel, rapid restart, permission denied then granted, silent peer); three
physical phones from the first spike and eight before advertising eight; allowlisted user-initiated
diagnostics; privacy copy rewritten with explicit scope; the verifier pinned to a commit and
checksum and labelled as internal-consistency evidence.

## Where the response differs from the review

- The plan never claimed remote participation would be a drop-in; it claimed the crypto would not
  change, which still holds. Remote discovery, identity and timing get their own review in v2.
- "Approve setup and bounded discovery only" is already the delivery order: the council and the
  device spike precede any protocol code. The plan now says so explicitly.
- Feature branches with a merge gate were proposed; the owner's standing rule requires explicit
  approval for every merge, so the equivalent "main, but green before done" rule was adopted.
