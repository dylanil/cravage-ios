<!-- Provenance: produced 2026-09-12 by an independent agent session with no access to the planning session. Imported verbatim by the owner; only this header was added. Response: 2026-09-12-plan-review-response.md -->

# Cravage iOS plan review

## Verdict

**Revise before implementation. Keep the product scope, but do not freeze the transport or port the legacy protocol unchanged yet.**

The plan has strong scope control: local rounds, no developer backend, host-only one-off unlock, native UI, explicit dropout failure, a transport-independent state machine, and cross-language checks. Those are good foundations for a small owner-led app. The weak point is treating choices inherited from an educational demo, plus several Apple assumptions, as settled production facts.

This is a plan and selected-code review, not an audit of an iOS implementation. No iOS implementation was available or executed. Neither repository nor the deployed service was modified.

## Evidence checked

- Read the supplied plan attachment in full and recalled previous SMPC context.
- Found the local checkout behind its remote-tracking branch. Confirmed GitHub main at `06b70614b0d4fae763e931f0eab5cc47d231ce0b` and reviewed files from that exact commit in an isolated temporary directory, rather than pulling or changing the checkout.
- Ran its JavaScript numeric suite: **all 25 checks passed**.
- Ran isolated Python probes against its real mask derivation and offline transcript verifier. Results are described below; these are deliberately generated test fixtures, not real participant data.
- Checked Apple's current networking and App Store documentation.
- Did not run the browser server suites, build Swift, exercise StoreKit, or test physical-device connectivity. Those results cannot be inferred from this review.

## Must revise before protocol implementation

### 1. Reconsider Multipeer Connectivity for a new app

Apple's TN3213 explicitly says: "Xcode 27 deprecates the entire Multipeer Connectivity framework." It recommends migration to Network framework and confirms that Network framework also supports Apple peer-to-peer Wi-Fi. The note explains that its newer sample API targets iOS 26, while the older Network APIs can implement the same concepts.[9]

Deprecation does not mean removal, current failure, or automatic App Store rejection. It does mean the plan should not describe Multipeer as an unquestioned long-term foundation.

**Smallest plan change:** turn step 2 into a transport-choice spike, comparing Multipeer against Network framework on physical phones, including security setup and lifecycle behavior. Keep `RoundTransport`, the no-backend decision, and the 3-8 product scope. Do not let a framework change silently expand v1. If retaining Multipeer, record why and the migration exposure.

The abstraction isolates dependencies; it does not make CloudKit a drop-in replacement. Remote discovery, identity, admission, timing and human verification need another threat-model review even if the numerical engine is reused.

### 2. Unlimited inputs and finite masks do not support the intended privacy promise

The current implementation derives eight mask bytes, interprets them as a signed 64-bit integer, and adds/subtracts those masks over ordinary arbitrary-precision integers. There is no modular wraparound that makes the share distribution independent of an unbounded input.[2][3]

For three participants, the total masking offset is conservatively bounded by `2 * 2^63` fixed-point units. I computed the bound and used the plan's own pinned input, `9007199254740993`, in a genuine derived-mask fixture. Dividing that participant's public share by the scale reveals the input to within approximately **0.205%**, regardless of the two mask values. The fixture still passes the offline verifier.

This demonstrates approximate large-input leakage without collusion. It does not demonstrate exact recovery of ordinary salaries. The issue is that the plan explicitly accepts the leaking domain while moving to real-data privacy claims.

**Smallest plan change:** have the protocol review choose either a justified bounded input domain with quantified masking privacy, or a reviewed modular construction with explicit encoding and aggregate-overflow rules. Do not simply widen the masks while continuing to promise unlimited inputs. Do not preserve an unsafe property solely because a browser test pins it.

This is also the right point to revisit the requirement for a handwritten BigInt. Preserve exact arithmetic as a goal, but derive the implementation requirements from the approved domain, not the other way around. If custom BigInt remains, test against Python/JavaScript arbitrary-precision results far beyond Int64, including carry/borrow chains, huge divisors where relevant, signed rounding, and maximum accepted lengths. Int64-range fuzzing alone misses its reason for existing.

### 3. Specify the missing distributed-state transitions

The plan lists good local checks but leaves several cross-phone rules unspecified. A trusted relay's first-write-wins rule does not automatically become a globally consistent view when every phone receives independent messages.

Require explicit answers before coding:

- **Room confirmation barrier:** represent an actual state and event for each user's code check. Honest clients must not submit sensitive shares before their local confirmation and the protocol's required room acknowledgements. A label telling people to compare codes is not an enforced transition.
- **Peer binding on every phone:** the host sees invitation context, but each joiner also needs a specified, authenticated mapping from every transport peer to its roster verification key. Require proof of possession and reject duplicate keys/ambiguous bindings; do not trust display names or an unauthenticated self-asserted mapping.
- **Round-bound controls:** specify authentication, canonical encoding, sender authorization and round/roster binding for `confirm`, `abort`, lock, restart and other control messages. Do not leave confirmation digests as an unframed concatenation or an unsigned claimed party name.
- **Restart:** define how every connected peer replaces its signing identity, how new bindings and roster are established, and how late messages from the previous round are rejected. Fresh signing keys plus immutable admitted bindings require a deliberate rekey sequence.
- **Deadlines:** a connected phone that never sends its next message must not strand everyone forever. Define timeout/cancellation behavior and recovery for every waiting state.
- **Disagreement:** distinguish collecting confirmations, a confirmed matching result, a mismatch, and missing confirmations. Do not show a normal successful result with a subtly reduced agreement badge when conflicting views are known. Define what late conflict does to an already displayed/exported result.

Do not claim full Byzantine consensus from an acknowledgement exchange. The useful v1 goal is much narrower: an honest phone clearly distinguishes its locally checked candidate result from the agreement evidence it has actually received.

The short room fingerprint also needs review as an authentication ceremony, including truncation, collision assumptions, commitment ordering and human comparison. Replace the literal "identical iff same keys" claim with accurately scoped collision-resistance language. Bind the agreed question/units as well as the participants if differing labels must be detected.

### 4. Keep the old verifier as compatibility evidence, not the security definition

The legacy verifier reads its verification keys from the same file as the signatures, checks those signatures, sums the listed shares, and checks the stated average. It does not externally authenticate the room or prove that participants honestly formed their masked shares.[3]

My probes returned no failures for:

- A valid baseline transcript.
- That transcript with its format, scale and metric replaced.
- An entirely replaced set of signing keys, signed shares and result.

The complete replacement result is expected for a self-contained verifier with no trusted external anchor. It is not a broken ECDSA signature. It establishes the limit of the evidence: internal consistency is not proof of provenance.

A separate 5,000-digit share probe raised Python's integer-string conversion `ValueError`, rather than returning a normal verification result. The plan proposes accepting strings up to 16,384 characters, so the unchanged verifier is not valid acceptance coverage for the full proposed domain.

**Smallest plan change:** retain a pinned legacy verifier and compatible fixtures where useful, but add strict schema/domain validation and an explicitly specified iOS transcript contract. If the export should prove agreement by the room participants, include the relevant signed commitments and require comparison with independently retained room evidence. If it is only a share-integrity and arithmetic check, label it that way.

Pin the vendored reference to a commit and checksum. Comparing every CI run against mutable upstream main can break an unchanged iOS project and silently moves the acceptance standard. Review upstream updates deliberately.

For golden tests, distinguish deterministic keys/masks from signature generation: do not assume fresh ECDSA signing yields a byte-identical signature each time. Freeze signed verification fixtures separately from sign-and-verify round trips. A tampered-share test expecting only a signature failure must recompute the forged sum/average if it intends to exclude arithmetic failures.

## Must revise before device beta

### 5. Promote ordinary phone interruptions to acceptance tests

Apple documents that Multipeer stops discovery and disconnects sessions when the app backgrounds; returning to the foreground requires reestablishing closed sessions.[1]

Test app switching, locking, automatic screen lock, a call, host departure, cancellation, rapid restart, denial followed by granting permission, and a peer that stays connected but stops progressing. Handle result/export separately from an incomplete active round.

The plan's failure-on-dropout choice is reasonable. The missing part is a predictable user experience around normal phone behavior. Add concise foreground-use guidance and, if appropriate, disable auto-lock only during an active round and restore it afterwards. Do not add dropout recovery merely to avoid defining failure correctly.

Two simulators plus an iPhone are useful development equipment, not three-phone acceptance evidence. Apple specifically says the simulator does not support local network privacy.[5] Obtain three physical phones early and test eight before advertising eight as supported.

Do not treat leaving an infrastructure Wi-Fi network as proof of a dropped peer: peer-to-peer connectivity may still exist. Observe actual disconnect/failure events and use deliberate app termination or transport faults for deterministic dropout tests.

The plan maps every advertiser/browser start failure to permission denial. That is too broad. Apple documents that a local operation may initially fail before the user answers the permission prompt, and there is no universal API exposing local network permission state.[5] Preserve error distinctions, retry appropriately, and use an honest generic connection error when the cause is unknown.

### 6. Rewrite privacy copy against actual data flows

"No data leaves the room" is stronger than the transport establishes. Multipeer supports infrastructure Wi-Fi as well as peer-to-peer Wi-Fi; local connectivity does not enforce a physical room boundary.[1] Users can also intentionally export the transcript elsewhere.

"Nothing stored or sent" directly contradicts the proposed peer messages, remembered display name and temporary export file.

Prefer claims with explicit scope:

- "Your entered figure is processed on your phone; the app sends a masked share to the other participants."
- "Cravage does not operate a server that receives your round data."
- "Round history is not saved by the app. Your chosen name is saved on this phone. Exported transcripts can be retained and shared by their recipients."

Those statements still depend on implementation and the approved protocol limitations. Add rules for temporary-file cleanup, clearing round state, avoiding sensitive logs and crash annotations, and obscuring the app-switcher snapshot while sensitive input is visible. Do not promise forensic secure erasure in managed-memory code.

Put the small-group/collusion warning where people enter sensitive data, not only in Settings. The new wording must be re-derived: the existing SECURITY.md contains inconsistent collusion-threshold statements, including an N-2 assertion alongside a two-of-three example.[4] Do not reuse it verbatim as authoritative mathematics.

## Vibe-coding process changes

### Preserve the small scope; shorten the feedback loop

The pure core, state machine, native controls, device spike and cross-language tests are strong choices. Keep them. The plan does not need more permanent councils, dashboards or documents.

Make these limited adjustments:

1. Resolve the transport and numerical privacy decisions first.
2. Sketch the whole journey cheaply, but polish only enough screens to build the first end-to-end round. Approve detailed mockups feature by feature as real-device behavior becomes known.
3. Build the narrowest genuine vertical slice on three physical phones before completing every UI, export and store feature.
4. Add restart/error behavior, then commercial and export features in independently testable slices.
5. Before real sensitive-data beta, review the actual protocol, parser and identity-binding implementation independently of its author. A pre-code AI council cannot certify code that does not yet exist.
6. Before release, test the declared eight-device capacity, offline already-purchased launch, pending/cancelled purchases, restore, revocation, and poor connectivity. A size-picker padlock is not the sole place to enforce a host's entitlement.

For each coding task, require a narrow outcome, a reproducing or acceptance test, exact commands/results, an independent diff check for consequential changes, and a commit identifying the verified state. Do not let an agent resolve a failing security test by weakening its expected property without explicit review.

Frequent commits are good; pushing directly to main before the corresponding CI result is green should not be the default quality gate. A short feature branch and a focused second-agent review provide a useful stop point without creating a large-team process. Treat this as a proposed change to the owner's stated workflow, not an instruction to change repository settings now.

Scripted screenshots should be captures of the real app running deterministic test scenarios, not independently drawn imitations. That preserves reproducibility and prevents the Store listing drifting from the shipped UI. Clarify the blanket "never screen-grabbed" wording accordingly.

## Apple and release-paperwork corrections

- **Small Business Program is not automatic.** Apple says eligible developers must enroll. Add the application, Paid Apps agreement and verification of the reduced commission's effective date to setup.[11]
- **The personal phone name is not the default available value.** On iOS 16 and later, `UIDevice.name` returns a generic name by default; access to the user-assigned name requires an entitlement.[12] Prefer a short nickname prompt or generated editable alias. Do not build the join experience around several phones identifying themselves simply as "iPhone".
- **Free public-repository CI is broadly sound, but qualify it.** GitHub states that standard hosted runners are free and unlimited for public repositories.[13] Specify standard runner labels and practical concurrency/artifact limits rather than promising unrestricted resources. This does not establish that a public repo is the only possible zero-cash-cost development arrangement; public MIT can remain the owner's preference independently.
- **App Review access is not solved by a launch argument.** Apple requires full review access and any needed hardware/resources.[14] A simulator `-uiScenario` flag is a screenshot-test mechanism, not automatically something a reviewer can activate in the distributed app. Document a genuinely usable review route, with a video as supporting evidence. Do not claim that review approval is guaranteed. A finished real tool and an explicitly labeled demonstration of its workflow are different concepts.
- **Use real UI screenshots.** Apple's guideline 2.3.3 asks for screenshots showing the app in use.[14] Script the capture, not a separate invented rendering of what the app might look like.
- **Export compliance remains a gate, not an approved constant.** `ITSAppUsesNonExemptEncryption = NO` may ultimately be appropriate, but decide from the finished app's actual crypto and the applicable questionnaire, not just the fact that some primitives come from CryptoKit. This review does not make a legal classification.

## Commercial privacy decision missing from setup

The plan acknowledges that an individual developer's legal name is public, but EU distribution may require more. Apple says individual traders must provide an address or P.O. Box, phone number and email for display on the product page. Trader status is a self-assessment, not something this review determines.[10]

Decide distribution territories and the contact-details privacy implications before publication. A dedicated Gmail alone does not resolve this. Any paid mailbox/contact arrangement could also change the "only annual Apple fee" assumption.

## Suggested approval gate

Approve **setup and bounded discovery work**, not an unchanged full implementation. Before freezing CravageCore, require:

- A deliberate transport choice informed by current Apple guidance and physical-device evidence.
- An explicit numeric domain and defensible privacy guarantee.
- A complete room-confirmation, identity-binding, restart, timeout and disagreement specification.
- A transcript claim that matches what its verifier can actually establish.

The central distinction: **the product decisions can remain settled while incorrect technical assumptions remain revisable.**

## Sources

[1] https://developer.apple.com/documentation/multipeerconnectivity.md
[2] https://github.com/dylanil/SMPC/blob/06b70614b0d4fae763e931f0eab5cc47d231ce0b/public/static/smpc-core.js
[3] https://github.com/dylanil/SMPC/blob/06b70614b0d4fae763e931f0eab5cc47d231ce0b/verify_round.py
[4] https://github.com/dylanil/SMPC/blob/06b70614b0d4fae763e931f0eab5cc47d231ce0b/SECURITY.md
[5] https://developer.apple.com/tutorials/data/documentation/technotes/tn3179-understanding-local-network-privacy.md
[9] https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework.md
[10] https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
[11] https://developer.apple.com/app-store/small-business-program
[12] https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.device-information.user-assigned-device-name.md
[13] https://docs.github.com/en/actions/reference/runners/github-hosted-runners
[14] https://developer.apple.com/app-store/review/guidelines
