<!-- Provenance: three independent agent sessions, each given a cold excerpt of the plan's technical
design (no access to this conversation or to each other's output), run 2026-09-13 per the retro
handoff in docs/retros/2026-09-13.md ("run the council on the four questions in docs/PLAN.md to
produce docs/SPEC.md and the Limitations text"). Raw outputs below are verbatim. Synthesis and
verdict at the end are this session's, not any reviewer's. Owner has not yet reviewed this file. -->

# Cravage protocol council, 2026-09-13

Per `docs/PLAN.md`: "One proportionate review council (crypto, security, challenger) BEFORE any
protocol code, on four questions: transport and star topology incl. link security; numeric domain
and wraparound; the full distributed state machine; what the transcript can honestly claim. Output:
go/revise, the Limitations screen text, the spec."

Method: three separate agent sessions, run in parallel, each with no visibility into this
conversation or the other two sessions. Each was handed a cold, self-contained excerpt of the
design (no planning narrative, no "here's what to conclude"). This mirrors the independence
discipline in `docs/review/2026-09-12-plan-review.md` and the explicit guardrail in
`docs/review/2026-09-12-coding-guardrails.md` #10: "Multiple personas agreeing is not independent
corroboration."

- Reviewer 1: cryptography — numeric domain/wraparound, transcript honesty.
- Reviewer 2: protocol/security engineering — transport/link security, state machine.
- Reviewer 3: adversarial challenger — all four areas, hunting across boundaries the other two
  reviewed narrowly.

No code exists yet (repository is still the skeleton from `b58628c`); this is a design-only review.

---

## Reviewer 1 (crypto: numeric domain, transcript honesty)

# Independent design review: numeric domain and transcript claims (Cravage iOS, pre-implementation)

I read `docs/PLAN.md` and the prior review pair (`docs/review/2026-09-12-plan-review.md` / `-response.md`) for grounding only — my verdicts below are my own independent analysis, not a restatement of what's already agreed.

## Question 1: Numeric domain and wraparound arithmetic

**Verdict: GO, with caveat (documentation/test, not a math change).**

The design brief frames the 10^18 cap as the thing that makes a single share "hide" the input. That framing is a slight misdiagnosis of *why* the fix works, and I want to correct it precisely, because a future maintainer reasoning from the wrong mental model could weaken the real protection later.

**The actual mechanism (modular one-time pad):** Each mask is 8 bytes of HKDF-SHA256 output interpreted as a signed `Int64`. That interpretation is a *bijection* between the 2^64 possible byte patterns and the 2^64 residues mod 2^64 — so if the HKDF output is (computationally) uniform over 64 bits, the mask is uniform over the *entire* group Z/2^64Z, not a sub-range. Now take any share `y = x + m (mod 2^64)` where `m` is uniform over Z/2^64Z and independent of `x`. For *every* fixed value of `x` — regardless of magnitude, distribution, or whether the attacker knows `x`'s prior — `y` is exactly uniform over Z/2^64Z. This is literally the one-time-pad proof (Shannon), and it is exact, not asymptotic: convolving a uniform distribution with anything (including a bounded or even unbounded `x`) yields uniform. Summing more independent uniform masks (N=3 has two: `x ± m_AB ± m_AC`) preserves uniformity regardless of party count or label position — one uniform independent term is already sufficient, so N=3 has no *extra* single-share weakness relative to N=8.

**So what does the cap actually do?** It's a *correctness* bound, not a secrecy bound. The masks cancel only when *all* N shares are summed; the residual is `(true sum) mod 2^64`, and recovering the exact signed integer from that residue requires `|true sum| < 2^63`. Check the arithmetic: 2^63 = 9,223,372,036,854,775,808 ≈ 9.223×10^18. Worst case, 8 parties each at the cap: 8×10^18 = 8.0×10^18. Margin ≈ 1.223×10^18, i.e. **~13.3% headroom** — correct and safe, but not enormous. This also explains the earlier bug cleanly: `docs/review/2026-09-12-plan-review.md` line 36 says the JS-demo path used "ordinary arbitrary-precision integers... no modular wraparound." That's a missing-reduction bug, not a "masks too small for the input" bug — an unbounded `x` added *without* mod reduction simply isn't a one-time pad at all. Adding *only* a cap without wraparound would not have fixed it; adding wraparound is what restores perfect per-share secrecy, and the cap is what's needed on top so the *sum* still comes out exactly right.

**Caveats to lock in before coding:**
- Comment/spec language should say explicitly: "the domain cap exists so the wrapped sum decodes to the exact true sum; per-share secrecy comes from wraparound + uniform masks and holds regardless of the cap." This prevents a future "let's raise the cap for user convenience, the masks still look random" change that quietly erodes the sum-correctness margin, and prevents a future "let's switch to saturating arithmetic for extra safety" change that would *break* secrecy (saturating/clamped arithmetic is not a bijection and is not a one-time pad).
- Add a regression test/assertion tying `maxParties × cap < 2^63` together, so a later entitlement change (e.g. "support 10 people") fails loudly at compile/test time instead of silently corrupting averages.
- Real residual risk is **collusion**, not bias: with N=3, any 2 colluding parties jointly hold every pairwise mask in the graph (each of the 3 masks is known to both members of its pair), so 2-of-3 collusion always recovers the third party's exact figure. This is inherent to any pairwise-mask/secure-aggregation scheme and is already correctly captured in the plan's threat table ("Colluding participants... N-1 recover the last figure... Residual: Warning at N=3"). No change needed to the math; keep the entry-time warning.

## Question 2: What the transcript can honestly claim

**Verdict: GO, with caveat (two Limitations-copy additions).**

The field set (session id, room label, ordered parties, scale, modulus, shares+signatures, keys, per-party confirmation signatures, sum, average) is well-scoped: it contains *no* field that overclaims — no timestamp, no location, no device attestation — so there's nothing in the schema itself implying something the crypto doesn't back. The verifier's four checks (signatures valid under stated keys; shares sum to stated sum mod 2^64; average follows the rounding rule; confirmation signatures verify over the expected digest) map exactly onto the intended claim: "these keys signed these shares, they sum/average as stated, and every key signed agreement to that exact set." That already matches the prior review's own recommendation ("If it is only a share-integrity and arithmetic check, label it that way") and CLAUDE.md's existing prohibition on claiming "participant identity beyond the host's eyes."

Two gaps are real and worth stating explicitly rather than leaving implicit under "doesn't prove who took part":

1. **Single-device fabrication.** Because verifying keys are self-generated per round with no external attestation (no App Attestation/DeviceCheck, no PKI), one device running a script can generate all N keypairs, compute all ECDH shared secrets locally (it holds every private key), sign N shares and N confirmations, and produce a transcript that verifies *perfectly*. This is a stronger and more specific claim than "doesn't prove identity" — it means the transcript doesn't even prove *multiple devices or people were involved at all*. I'd make this its own Limitations bullet rather than leaving it folded into the identity disclaimer, since a reader could otherwise assume "well, at least several distinct phones did something."
2. **Range is unverifiable after the fact.** The verifier never sees the masks, so it cannot check that any individual party's hidden figure was within the 10^18 domain cap — the cap is enforced only by each phone's own local input validation before masking. A modified client could submit a share implying an out-of-range hidden value; this doesn't just corrupt its own figure (already covered by "honesty of inputs unprovable" in the threat table) — it can *silently wrap the group sum into a wrong average for everyone else*, with no signature failure and no verifier-detectable anomaly. This consequence (corruption of the shared result, not just of one party's own honesty) is distinct enough from the existing "misbehaving participant" line that it deserves its own explicit sentence rather than being assumed to be covered by it. I don't think this warrants new cryptography (a ZK range proof is disproportionate to this app's threat model and scope); it's a copy fix, not a protocol fix.

**Smallest concrete change:** add two sentences to the Limitations screen / SPEC transcript section:
- "A verified transcript can be produced start-to-finish by a single device; it does not prove multiple phones or people took part."
- "The app relies on each phone to keep its own figure in range before masking; a modified app submitting a hidden out-of-range figure can skew everyone's average without any signature or verification failure."

No field additions, no cap change, no verifier logic change needed for either question — both are copy/documentation/test items to fold into the SPEC.md the plan says the council output should produce.

---

## Reviewer 2 (protocol/security engineering: transport, state machine)

# Independent Review: Transport/Topology and State Machine

Reviewed cold, against the excerpt only. No code exists yet; this gates protocol implementation.

## 1. Transport, star topology, link security

**Verdict: go — decide against link-layer TLS, close the open question in favor of signatures-only.**

Reasoning: in a star topology the host must terminate and re-forward every message, so "TLS per hop" only ever protects joiner<->host and host<->joiner separately — it never gives joiner<->joiner confidentiality, and the host sees cleartext at the relay point either way. Given that, ask what a passive eavesdropper on either hop actually gains without TLS:

- **Shares**: never plaintext — they're masked by ECDH+HKDF secrets an outside eavesdropper doesn't have. A passive sniffer sees the same "random-looking" bytes whether or not TLS wraps them. TLS buys zero confidentiality here that the mask doesn't already provide.
- **Integrity/forgery**: every message is ECDSA-signed under the sender's round key and bound to session+roster. An active MITM cannot forge or substitute content without the private key, TLS or not. TLS buys no integrity property signatures don't already give.
- **Metadata** (nicknames, room label, size): already broadcast in cleartext via the Bonjour TXT record before any connection exists. TLS on the data connection can't retroactively un-leak what advertising already leaked.

What TLS *would* need to bootstrap trust (a per-round-identity-bound cert with no CA) is exactly the same trust-on-first-use problem the design already solves at the app layer: humans visually compare a fingerprint that binds roster+label+keys. Building a second, parallel TLS-cert verification path duplicates that human check for no new guarantee, and adds real cost (self-signed cert issuance/rotation per round, NWProtocolTLS wiring, and a second place attackers can attack the trust bootstrap). Recommend explicitly closing this as **signatures-only, no transport TLS**, and writing down *why* in the plan so it's not re-litigated: because the star topology makes hop-only TLS incapable of the one thing it'd be good for (E2E confidentiality), and everything it *can* do is already covered by masking + signing.

Residual gaps regardless of the TLS decision, worth a Limitations line: connection-establishment/DoS resistance (a flood of malformed connection attempts against the host) isn't solved by app-layer signing and should be handled with ordinary connection-rate limits in `NetworkTransport`, independent of TLS.

## 2. State machine

**Confirmation-ordering question: the state list separates the two barriers correctly; invariant #3's prose does not, and should be fixed.**

The state enumeration (`confirming` before `keyExchange`/`sharing`; `collectingConfirmations` after `sharing`) is structurally correct: there really are two distinct signed artifacts —
- a **pre-share** signal, gating entry into `keyExchange`/`sharing`, that the human visually confirmed the room fingerprint (should be a signature over roster hash + room label + keys, not over any share data), and
- a **post-result** signal, gating `collectingConfirmations` → `complete`, that is a signature over SHA-256(session id, roster hash, shares concatenated) — this is invariant #7's artifact.

Invariant #3 as written calls both simply "confirmation messages," which is exactly the ambiguity the prompt flagged and exactly the kind of thing that produces a real bug: an implementer could accidentally wire the same message type/signature verifier to both gates, at which point "everyone confirmed the room code" and "everyone agrees on the result" become indistinguishable in code even though they mean very different things (one is "the humans looked at the code," the other is "the math came out consistent"). **Smallest concrete fix**: rename them in the spec now, before code exists — e.g. `RoomCodeConfirm(sig over roster_hash‖room_label‖vks)` for the pre-share barrier, `ResultConfirm(sig over SHA-256(session_id‖roster_hash‖shares))` for the post-share barrier — and state invariant #3 in terms of `RoomCodeConfirm` explicitly, not "confirmation messages" generically. This is a revise, not a blocker, since the underlying state diagram already has the right shape.

**Other findings against the invariant list:**

- **Restart vs. in-flight share race**: because `handle()` is a pure serial function, there's no true data race inside the engine — the real ordering question is at the IO boundary, between an inbound `RestartReceived` event and an outbound `SendShare` effect from a prior turn actually reaching the socket. The design doesn't say this out loud. The actual safety net is invariant #9 (recipients reject old-session-id messages), not any guarantee on the sender side that a send can be preempted. Recommend making this explicit in the spec: "a share may still physically leave a phone after restart begins; recipients' session-id rejection, not sender-side cancellation, is what makes this safe." Also worth stating the generation check (invariant #10) covers the sender's own late-arriving async result, which it does.
- **Host-initiated restart while host itself has a pending share**: the host is a participant too, and the spec doesn't say whether the host applies restart to its own local round state before or after broadcasting the control message to others. If broadcast happens first and local state update second, there's a window where the host could still emit/accept its own stale share. Recommend an explicit rule: host updates its own generation/keys first (as if receiving its own signed restart message through the same event path), *then* broadcasts — no privileged shortcut for the host's own state.
- **Entitlement gate is missing from the invariant list entirely.** The threat model claims the host has "no OTHER privilege," which implicitly requires the 3-free/4-8-paid gate to be enforced by the RoundEngine's transition guard (e.g., refusing the `lobby -> confirming` roster lock, or refusing to admit a 4th joiner) without a valid entitlement receipt present — not merely by graying out a number in a UI picker that a modified client or direct event injection could bypass. As given, none of invariants 1-10 mention this. **Revise: add an explicit invariant** — "roster lock / admission beyond 3 parties is refused inside the state machine's transition guard absent a verified StoreKit entitlement, independent of any UI restriction" — since this is a monetization-and-protocol boundary, not just a screen.
- **Post-complete "disputed" transition isn't in the named state list.** Invariant #7 requires a `complete(agreed)` result to become retroactively "disputed" if a conflicting `ResultConfirm` arrives late, but the state enumeration shows `complete(...)` as if terminal. Recommend adding `complete(agreed) -> disputed` as an explicit, sole permitted transition out of a "terminal" state, and note that an already-*exported* transcript file can't be edited — only the on-device record and any future export/display can carry the disputed flag; the spec should say so rather than implying the export itself gets fixed.

No other gaps found in first-write-wins, duplicate-vk rejection, double-tap idempotency, or the deadline-on-every-waiting-state rule — those read as sound and complete as stated.

## For the Limitations screen

- "Anyone on the same Wi-Fi can see that a Cravage round is happening, the room name, host nickname, and group size — not anyone's number." (holds regardless of the TLS decision)
- "If the round result is later found inconsistent, a result already shown or exported may be marked disputed after the fact — the exported file itself won't change, but the app's record of it will."
- "A modified or compromised device pretending to be the host could try to admit an unintended participant; the room-code check is what catches that, so compare it carefully."

---

## Reviewer 3 (adversarial challenger, all four areas)

# Red-Team Review: Cravage Protocol Design (Independent Take)

## 1. Ghost-participant / no physical-identity binding — **breaks the core privacy promise**

**Attack:** Nothing in the design binds a roster "letter" to a *distinct, real, physically-present phone*. Verifying keys are fresh per round, freely generated, with no proof-of-work, invite tokens, or device attestation (all explicitly dropped). A host — or anyone with a modified client — can mint N-1 "ghost" identities itself: generate their keypairs, sign their hellos, admit them, set their figures to 0, and produce their post-result confirmation signatures, all locally. It then tells a single real victim "you're in a 3-person room with B and C." The victim's phone runs the full protocol correctly — signed hellos, confirmation barrier, matching room fingerprint, "all N signatures verified" — and the sum equals the victim's raw figure. Every cryptographic invariant in the spec holds; the break is that "N distinct people" was never actually enforced, only "N distinct keys," which the same attacker fully controls.

**Does the design stop it?** No. The threat table only covers "a wrongly admitted *stranger*" (an unwanted extra real participant), not a host fabricating phantom participants that never existed. The confirmation ceremony ("look around, count phones, read the code aloud") is a social convention, not a state-machine rule; nothing in Enter Figure / Confirm / Lobby prompts the user to affirmatively count connected devices against the declared size.

**Fix:** Add an explicit UI+copy requirement (not just a state): the Lobby/Confirm screen must show "N-1 other phones connected" and instruct the user to visually count that many *other physical screens* showing the identical fingerprint before tapping confirm, and the Limitations screen must state plainly that the app cannot verify a letter corresponds to a distinct human — only that it corresponds to a distinct key the display-order implies came from another device. This is a copy/UX gap, not a crypto one, but it's the most exploitable hole in the whole design and isn't currently named anywhere in the Limitations text as drafted.

## 2. Two-round differencing via the built-in restart flow — **breaks the core privacy promise, no collusion needed**

**Attack:** v1's own dropout-restart feature keeps the same room/label and re-runs the round. If a round with roster {A,B,C,D} restarts (e.g., a genuine dropout) as {A,B,C} because D failed to reconnect, and A, B, C re-enter the *same* figures (extremely likely for something like salary within the same sitting), then **any single participant** — not a colluding set, just one honest-looking party who was present both times — can compute sum1 − sum2 = D's exact figure. This requires zero collusion, zero cryptanalysis, and is triggered by the app's own designed failure-recovery path, which is far more likely to occur in practice than an incidental "repeated round."

**Does the design stop it?** Only a generic acknowledgment exists: "observer of output... infer from small groups or repeated rounds — stated as a limitation, no technical mitigation." That line doesn't connect to the *specific, designed* restart-with-changed-roster flow, which is the realistic trigger, not a hypothetical.

**Fix:** This is mathematically inherent (can't be patched cryptographically), so the fix is copy + UX timing: when a restart drops a participant, show an explicit warning *at that moment* ("Someone left before this restart — if figures don't change, comparing the two results can reveal what they entered") rather than relying on a generic Limitations paragraph read once, if ever, before the round.

## 3. Transcript "verified" badge travels without its own caveat — **misuse / honesty-copy gap**

A participant (or a solo scripted client, per the prompt's own suggestion) can fabricate an entire N-party round alone and produce a transcript that verifies perfectly — the verifier can only ever attest to internal consistency, never provenance, and the design says as much. The gap: the Result screen shows the reassuring phrase "all N signatures verified," and the exported transcript JSON itself carries no caveat — only the app UI does. Anyone who screenshots the result or hands the JSON to a third party (HR, a journalist, a group chat) strips away the one place the disclaimer lives.

**Fix (cheap, concrete):** add a fixed, verifier-checked disclaimer string to the `cravage-transcript-2` schema itself (e.g., a `claim` field reading something like "signed shares are internally consistent; this does not prove who took part or that inputs were honest"), and have `TranscriptVerifier`/`verify_round.py` assert its presence and exact wording. That way the caveat travels with the artifact, not just the app chrome.

## 4. Mask-key distinctness isn't clearly specified — **partial gap, likely low exploitability**

The design specifies duplicate/ambiguous-key rejection for the round *identity/signing* key at hello-time, but doesn't say whether the separate P-256 key-agreement (mask) public key is (a) bound inside that same signed hello, or (b) checked for uniqueness across the roster the same way. P-256 has cofactor 1, so classic small-subgroup attacks don't apply, but nothing currently stops a malicious party from publishing a mask public key equal to another party's, or swapping it in later unsigned, which the stated invariants don't visibly cover.

**Fix:** require the mask key-agreement public key to be included in and covered by the same signed hello as the identity key, and explicitly reject duplicates across the roster, exactly as already done for identity keys.

## 5. Same-generation duplicate-signature race — **correctness/DoS, not privacy**

The design guards cross-generation staleness (a generation counter dropping late async results) but "one distinct share per round identity" is tested "on the sending path," which suggests generation-counter filtering rather than an explicit idempotency lock. ECDSA over CryptoKit is randomized (not RFC6979-deterministic), so two concurrent completions of the *same* generation's share-signing (e.g., a background-suspend/resume race, or a background-task expiration handler firing alongside the original continuation) would sign the identical frozen figure but produce two different valid signature byte strings. If first-write-wins compares raw envelope bytes rather than the canonical signed content, an honest phone could self-inflict a "conflicting share" failure on its own round from a harmless resend.

**Fix:** make first-write-wins compare on the canonical pre-signature content when the sender is unchanged, not on full envelope/signature bytes, and add an explicit "share already frozen+sent for this generation, second attempt is a no-op" guard independent of the generation counter.

## 6. Host-failure single point of failure, sharper at N=3 — **DoS only**

Only the host can issue signed restart/roster/abort messages. If the host's phone drops (backgrounds, crashes, walks out of range) mid-round, there's no host-failover or re-election described — the room is unrecoverable except by standing up an entirely new Bonjour advertisement. This is a star-topology property at any N, but proportionally worse at the minimum N=3 (losing 1 of 3 is losing the coordinator with much higher relative likelihood, and it's noted as a test case in delivery step 6 but the *outcome UX* isn't specified). Low severity, worth a copy/UX note (host device should stay foregrounded, plugged in, screen-locked-off) rather than a protocol redesign.

## Checked and found sound

- Wraparound-arithmetic magnitude bound and the domain cap: correctly closes the original 0.2%-leakage bug for ≤8 parties.
- Selective-forwarding by a dishonest host across an *honest, real* roster: the post-result confirmation digest genuinely catches divergent views, since signatures can't be forged even by the relay.
- Entitlement client-side bypass via a modified client: real, but inherent to any server-less, account-less design — a business risk to accept explicitly, not a security gap the protocol can close.

## Overall verdict: **revise**

Must-fix before protocol code:
1. Add an explicit, prominent "count the phones, don't just trust the letter count" instruction at the confirmation ceremony, and name the ghost-participant risk in Limitations (item 1).
2. Add a restart-time warning when the roster shrinks/changes, naming the differencing risk concretely, not just generically (item 2).
3. Embed a fixed, verifier-checked disclaimer field inside the transcript schema itself (item 3).
4. Specify mask-key binding/distinctness inside the signed hello (item 4).
5. Specify same-generation idempotency for share-sending independent of the generation counter, and canonical-content comparison for first-write-wins (item 5).

Items 1-3 are copy/spec changes, not redesigns; items 4-5 are small, precise state-machine/schema additions. None require reworking the crypto or topology choices already made.

---

## Synthesis (this session)

**Overall verdict: revise (small, precise), then go.** Nothing here reopens a product decision or the crypto/transport/topology choices in `docs/PLAN.md`'s settled section. All three reviewers independently confirmed the numeric-domain fix (cap + wraparound) actually closes the previously-found leak, and reviewer 2's transport analysis gives a reasoned basis to close the one item that was still explicitly open (R8, link security) as signatures-only. The list below is what's folded into `docs/SPEC.md`; none of it requires new cryptographic primitives.

The two most consequential findings — **ghost-participant fabrication** and **restart differencing** — were found only by the challenger, precisely because the other two reviewers were scoped to their own question pairs. Both break the core privacy promise in realistic, no-collusion scenarios, and neither was previously named anywhere in the plan's threat table. This is exactly the failure mode the multi-agent council process (rather than one reviewer, or one session wearing multiple hats) is meant to catch, and it did.

**Folded into `docs/SPEC.md` (spec-level, no owner sign-off needed to draft, but code must match):**
- Numeric domain: corrected rationale (secrecy from wraparound+uniform masks regardless of magnitude; cap is for sum-correctness only), `maxParties × cap < 2^63` as an enforced invariant/test.
- Transport: signatures-only, no link-layer TLS, with the reasoning on record; connection-rate limiting on the host's inbound connections as an ordinary DoS control.
- State machine: `RoomCodeConfirm` / `ResultConfirm` as distinct named, distinctly-signed message types; entitlement enforced as a transition-guard invariant, not a UI-only gate; `complete(agreed) -> disputed` as a named transition; host applies restart to its own state before broadcasting; recipient-side session rejection named as the actual restart-race safety net (not sender cancellation); mask key-agreement public key bound into the same signed hello as the identity key, duplicates rejected across the roster; first-write-wins compares canonical pre-signature content (not raw signature bytes) so a randomized-ECDSA resend of an unchanged share cannot self-collide.
- Transcript: a fixed, verifier-checked `claim` field carrying the honest-scope disclaimer, so it travels with the exported file itself, not only the app's UI chrome.

**Needs the owner (per CLAUDE.md: "The Limitations text is council-approved; change it only with the owner") — drafted, not yet final:**
- Ghost-participant risk: a new Lobby/Confirm requirement to display "N-1 other phones connected" and instruct visually counting distinct physical devices, plus a Limitations bullet that a roster letter is a distinct key, not a verified distinct human.
- Restart-differencing risk: an explicit warning shown at the moment a restart drops a participant, plus a Limitations bullet naming the specific mechanism (not just the generic "repeated rounds" line already drafted).
- Two additional Limitations bullets from reviewer 1 (single-device fabrication; unverifiable out-of-range shares silently skewing the group average) and three from reviewer 2 (Wi-Fi metadata visibility; disputed-after-export; host-impersonation admission risk).

See `docs/SPEC.md` for the consolidated spec and the full draft Limitations text.
