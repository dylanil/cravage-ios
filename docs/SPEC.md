<!-- Provenance: produced 2026-09-13 from the protocol council (docs/review/council/2026-09-13-protocol-council.md),
which reviewed docs/PLAN.md's technical design against its four gating questions. This is the spec
required before any protocol code (delivery step 1). The Limitations text at the end was walked
through with the owner in plain language and approved 2026-09-13; it is now folded into
README.md's Known limitations section (the in-app Limitations screen carries the same content once
the app target exists). -->

# Cravage protocol specification (v1)

Authoritative for `CravageCore` implementation. Where this document adds or corrects
`docs/PLAN.md`'s Technical Design section, this document governs; it does not reopen any decision
in PLAN.md's "Decisions (settled, do not reopen without the owner)" section.

## 1. Numeric domain and wraparound arithmetic

- Figures: fixed-point, scale 1,000,000 (six decimal places), signed, magnitude strictly less than
  10^18 fixed units (under 999,999,999,999.999999 in the user's units). Enforced by
  `FixedPoint.parseDecimalToFixed` before any masking.
- All share and sum arithmetic is Swift wrapping `Int64` (mod 2^64). No BigInt anywhere in the
  protocol path.
- **Why the cap exists (precise, so it is never "optimized away" later):** per-share secrecy comes
  from wraparound + uniform masks alone, and holds for *any* magnitude of input, bounded or not —
  a mask uniform over Z/2^64Z, added mod 2^64 to any fixed value, produces a share exactly uniform
  over Z/2^64Z (the one-time-pad property; exact, not asymptotic). The domain cap is a **separate,
  sum-correctness** requirement: masks cancel only when all N shares are summed, and the residual
  `(true sum) mod 2^64` recovers the exact signed true sum only if `|true sum| < 2^63`. With 8
  parties at the cap, `8 × 10^18 = 8.0×10^18` against a limit of `2^63 ≈ 9.223×10^18` — about 13.3%
  headroom. **Do not** raise the per-party cap or the max party count without re-checking
  `maxParties × cap < 2^63`; do not switch any wraparound addition to saturating/clamping
  arithmetic, which is not a bijection and breaks the uniform-share property entirely.
- **Required test**: a compile-time-or-test-time assertion tying `maxParties (8) × cap (10^18) <
  2^63`, so a future change to either constant fails loudly instead of silently corrupting sums.
- Residual, inherent, not fixable in software: N-1 colluding participants always recover the last
  party's exact figure (every pairwise mask is known to both members of its pair). Warned at figure
  entry, most strongly at N=3.

## 2. Transport and link security

- Apple Network framework, iOS 26 `NetworkListener`/`NetworkBrowser`/`NetworkConnection` interface,
  peer-to-peer Wi-Fi. Star topology: every joiner opens exactly one `NetworkConnection` to the
  host; the host forwards to all connections. Bonjour service `_cravage._tcp` (peer-to-peer),
  TXT record `{v, label, size, host}`.
- **Decision (was open as PLAN.md R8, now closed): signatures-only, no link-layer TLS.** In a star
  topology, hop-level TLS (joiner<->host, separately host<->joiner) cannot give end-to-end
  confidentiality — the host must decrypt to forward regardless — so it can only ever protect
  exactly the two hops it terminates on, not joiner-to-joiner. Checking what it would add on top of
  what's already planned: shares are never plaintext (masked before they're ever sent, so a passive
  sniffer sees the same uniform-looking bytes with or without TLS); every message is ECDSA-signed
  and bound to session+roster (an active MITM cannot forge or substitute content, TLS or not);
  nicknames/label/size are already broadcast in the cleartext Bonjour TXT record before any
  connection exists (TLS on the data connection can't retroactively un-leak that). A TLS
  implementation with no CA would need exactly the same trust-on-first-use bootstrap the design
  already does at the application layer (the human-compared room fingerprint) — building a second,
  parallel certificate-verification path duplicates that check for no additional guarantee, while
  adding real cost (per-round self-signed cert issuance, `NWProtocolTLS` wiring, a second trust
  bootstrap for an attacker to target). Conclusion: signatures-only is not a shortcut, it is the
  correct choice given the star topology.
- **Required**: ordinary connection-rate limiting on the host's inbound `NetworkListener` accepts,
  independent of the TLS decision — a flood of malformed connection attempts is a DoS concern
  signatures don't address either way.

## 3. State machine

States (unchanged from PLAN.md): `idle -> lobby -> confirming -> keyExchange -> sharing ->
collectingConfirmations -> complete(agreed | mismatch | partial) | failed(reason)`, plus a new
explicit transition below.

**What a joiner knows in `lobby`** (owner decision 2026-09-19, after the first three-phone round).
A joiner is sent `welcome` (nonce, room label, size) and then the roster only when the host locks
it. Before the lock its phone therefore knows the room it chose, its own nickname, and nothing
about anyone else; the host's own nickname is known only from the untrusted Bonjour advert. The
joiner's lobby screen must say so rather than list people, and the roster first appears on the
code-check screen, where every name is carried by a signed roster and every phone shows the same
code. Listing unverified names earlier would spend the user's confidence before the protocol has
earned it; doing it truthfully would need a new host-to-joiner lobby message, which is a protocol
change and not a screen change.

### Message/action taxonomy (revises `CanonicalMessage`'s action set)

`CanonicalMessage` action values: `pubkey | share | roomcode_confirm | result_confirm | control`.
The former single `confirm` action is split into two distinct, distinctly-signed artifacts that
must never share a verifier or a type:

- **`roomcode_confirm`** — pre-share barrier. Signature over `roster_hash ‖ room_label ‖ vks`
  (order fixed, letter order). Produced when the local user taps "I checked, the codes match."
  Gates entry into `keyExchange`/`sharing`: a share must not leave the phone until the local
  `roomcode_confirm` has been produced **and** a valid `roomcode_confirm` has been received from
  every other party.
- **`result_confirm`** — post-result barrier. Signature over `SHA-256(session_id ‖ roster_hash ‖
  shares in letter order)`. Produced after all N shares are received and verified. Gates
  `collectingConfirmations -> complete`.

These must not be implemented as the same message type with different payloads; keep them as
distinct cases so a future change to one cannot accidentally widen the other's verifier.

### Invariants (numbered to match PLAN.md's list; new items appended)

1. Roster/lock/abort/restart accepted only when signed by the host's per-round vk and bound to the
   current session id. *(unchanged)*
2. Joiner hello = **signing vk + mask key-agreement pubkey**, both covered by one signature over
   `(session id, host nonce)`. **Revised**: the mask (P-256 key-agreement) public key is now bound
   into the same signed hello as the identity key, not asserted separately or unsigned. Duplicate
   or ambiguous values of *either* key across the roster are rejected, not only the identity key.
   Names are never identity.
3. **Confirmation barrier**, restated precisely using the split message types above: no share
   leaves the phone until the local `roomcode_confirm` has been produced **and** valid
   `roomcode_confirm`s have arrived from every other party. (This invariant is about
   `roomcode_confirm` specifically — see `result_confirm` under invariant 7.)
4. First-write-wins per party for pubkey and share, **comparing canonical pre-signature content**,
   not raw envelope/signature bytes. **Revised**: because CryptoKit ECDSA is randomized, a resend
   of an unchanged, already-frozen share can produce a different valid signature; comparing raw
   bytes would make an honest phone's own harmless resend look like a conflicting share. Compare on
   the canonical signed content (sender, round id, generation, value) — identical content is a
   no-op regardless of signature bytes; different content for the same slot fails the round.
5. One distinct share per round identity: the figure is frozen into an immutable snapshot before
   async share generation; a changed figure requires a restart with fresh keys. **New, explicit
   idempotency guard**: once a share has been frozen and sent for a given round generation, a
   second send attempt for that same generation is a no-op regardless of cause (background
   suspend/resume race, expiring background task, duplicate timer) — this is independent of and in
   addition to the generation-counter check in invariant 10, which only covers cross-generation
   staleness.
6. Sum only when all N shares present and verified. *(unchanged)*
7. `result_confirm` (post-result signature, defined above) from every party; result screen
   distinguishes collecting / all N agree / mismatch (named) / missing. A mismatch is never shown
   as a success with a reduced badge. **New named transition**: `complete(agreed) -> disputed` is
   the sole permitted transition out of a completed state, triggered by a late-arriving conflicting
   `result_confirm`. An already-exported transcript file is not mutated; the on-device record and
   any subsequent display carry the disputed flag.
   **Revised by the owner, 2026-09-16, to match the implementation**: a disputed round produces no
   further transcript. `Transcript.make` refuses any record whose outcome is not clean agreement,
   so re-export is refused rather than flagged. Reason: `cravage-transcript-2` has no field for a
   dispute and its verifier is deliberately pinned, so a re-export would be byte-indistinguishable
   from a clean one and would overclaim agreement. Adding such a field would change the format and
   the pinned verifier in the SMPC repository; that is not done, and is the alternative if a
   disputed round ever needs an exportable artefact.
   **Copy rule (owner-agreed 2026-09-13, from the code review)**: a mismatch names the parties whose
   agreement differs from this phone's, which is not the same as naming who cheated. A dishonest
   relay can make two honest phones each name the other. The result screen says "did not agree
   with this phone", never that the named person misbehaved.
8. Every waiting state has a deadline; expiry fails the round with a reason. *(unchanged)*
9. Restart: host issues a signed restart with a new session id. **Clarified ordering**: the host
   applies the restart to its own local state (discard keys, generate fresh ones, reset generation)
   *before* broadcasting the control message — no privileged shortcut where the host's own pending
   work survives past a restart it itself issued. Messages carrying the old session id are rejected
   after restart.
10. Async results carry the round generation; stale results are dropped. **Clarified**: this is the
    safety net for a restart racing an in-flight send at the IO boundary (the sans-IO engine itself
    has no concurrency inside `handle()`) — a share can still physically leave a phone after a
    restart begins, and it is the **recipient's** session-id rejection (invariant 9), not any
    sender-side cancellation guarantee, that makes this safe. Double taps on any action produce one
    logical operation.
11. **New.** Entitlement (3 free, 4-8 unlocked) is enforced as a transition guard inside the state
    machine itself — refusing roster lock / admission of a 4th+ party without a verified StoreKit
    entitlement present in the coordinator's state — not only by a UI size-picker restriction that a
    modified client or direct event injection could bypass. This matches the threat model's own
    framing that the host holds "no other privilege": the entitlement check is protocol-level, not
    presentational.
12. **New.** Ghost-participant mitigation (see Limitations draft below for the copy): the Lobby and
    Confirm screens must display the count of *other* connected phones ("N-1 other phones
    connected") alongside the room fingerprint, and the confirm prompt must instruct the user to
    visually count that many other physical screens showing the identical code before confirming.
    This is a UX requirement on the Lobby/Confirm views, not a new state, but it is load-bearing:
    nothing in the cryptographic protocol can distinguish a real second phone from a host-fabricated
    key, so the human check is the only control and must be made concrete rather than left as a
    label.
13. **New.** Restart-differencing warning: when a restart is issued with a **smaller or changed**
    roster than the round it replaces, every remaining phone must show an explicit warning before
    the next figure entry ("Someone left before this restart — if figures don't change, comparing
    the two results can reveal what they entered"). This does not prevent the underlying math
    (subtracting two sums to isolate a dropped party's figure is inherent to any restart-with-
    same-figures scenario and cannot be patched cryptographically); it is a timing/copy control so
    the risk is surfaced when it is actually live, not only in a general Limitations paragraph read
    once before the first round.
    **Revised by the owner, 2026-09-13, after the code review.** A dishonest host can make a changed
    roster look unchanged (for example a key of its own under the departed person's nickname), so
    the warning is shown on **every** restart, whoever is in the new roster. When the roster visibly
    has fewer people or different names, the stronger copy is used. Copy approved by the owner
    2026-09-24, on being shown the screen as built; it had been recorded as approved on 2026-09-22,
    before that approval was actually given. "This is a restarted round. If the group has changed and people enter the same
    figures as last time, comparing the two results can reveal someone's figure." Also revised:
    a restart is an **offer**. Each joiner's phone asks the person before rejoining and sends
    nothing until they accept; an unanswered offer lapses with the host's restart lobby, and
    declining leaves the room.

### App lifecycle and input policy (owner decision 2026-09-22)

- On becoming inactive, conceal the whole window before the app-switcher snapshot. Temporary
  inactivity alone, including a permission prompt or Control Center, does not end a round.
- On entering the background, including phone lock, leave any unfinished round using the existing
  leave/disconnect path, clear local round state and show an interruption explanation on return.
  Cancel pending room creation and restart offers too. Do not resume automatically. A completed
  result remains available for sharing; this is not a background networking guarantee.
- This is an app/coordinator policy, not a wire change. A lobby can lose a joiner and keep waiting;
  once the roster is locked, the existing disconnect rule fails the round on the remaining phones.
- Decimal entry uses an ASCII full stop, never locale guessing. Commas and grouping separators are
  rejected with an explanation. Sign and decimal-point controls allow negative input even where
  the regional decimal keypad lacks a minus or full stop. Exact fixed-point rules are unchanged.
- Leaving or changing a figure is not promised to prevent restart differencing. A dropped person's
  figure can be recovered by comparing totals even though that person has left. Never add that
  reassurance to the warning.

## 4. Transcript honesty

- Exported only for a round whose parties all signed agreement to the same shares, and never
  again once that round is disputed (invariant 7).
- Format `cravage-transcript-2`. Fields: format id, session id, room label, ordered parties, scale
  `"1000000"`, modulus `"18446744073709551616"`, shares (signed decimal strings), share signatures,
  verifying keys, `result_confirm` signatures, sum, average. **Added by the owner, 2026-09-13**:
  `roomcode_confirm` signatures, which cover the roster hash, the label and the keys, so the room
  label is authenticated by the file (without them nothing in the file covered the label).
- **New required field**: `claim`, a fixed string asserted and checked byte-for-byte by both
  `TranscriptVerifier` (Swift) and `verify_round.py` (Python) as part of acceptance, so the honest
  scope of the transcript travels with the exported file itself and not only the app's UI chrome:

  > "This transcript shows that the listed keys signed the listed shares, that they sum and average
  > as stated, and that every listed key signed agreement to this exact set of shares. It does not
  > prove who the participants were, that separate devices or people were involved, or that any
  > input was truthful."

- Verifier checks (unchanged): every share signature verifies under its stated key; shares sum (mod
  2^64) to the stated sum; the stated average follows the app's rounding rule; every party's
  `result_confirm` verifies over the expected digest; **new**: the `claim` field is present and
  matches the pinned string exactly; **new (2026-09-13)**: every party's `roomcode_confirm` verifies
  over the digest of roster hash, label and keys.
- Two limitations that are inherent to this design and cannot be closed by a schema or verifier
  change (documented, not fixed): a verified transcript can be produced start-to-finish by a single
  device holding every private key (no external attestation exists to prevent this); the verifier
  never sees the masks, so it cannot check that a party's hidden figure was in-domain before
  masking — a modified client submitting an out-of-range hidden value can silently skew the whole
  group's average with no signature or verification failure.

## Overall verdict

**Go**, once the items in sections 1-4 above are what `CravageCore` and the app actually implement.
Nothing here reopens the transport/topology, numeric-domain, or product decisions already settled
in `docs/PLAN.md`; every change above is additive precision (message-type splitting, one new
invariant class, one new schema field, two new UX moments) rather than a redesign. See
`docs/review/council/2026-09-13-protocol-council.md` for the full independent reviews this spec is
drawn from.

## Limitations text (owner-approved 2026-09-13, shipped in README.md)

Short, in-app form (existing items from README's Known limitations are not repeated here except
where their wording changes; new items are marked **NEW**):

- Same room only; up to 8 people; everyone needs iOS 26+ with the app. *(unchanged, see README)*
- Figures up to 999,999,999,999.99; the maths hides figures perfectly only within a bounded range.
  *(unchanged)*
- If someone drops out mid-round, the round fails; the host restarts with one tap, same room and
  label. **NEW, sharper**: if a restart changes who's in the room and people re-enter the same
  figures as before, the difference between the two results can reveal the figure of whoever left —
  the app warns at the moment a restart drops someone, not only here. *(Behaviour revised by the
  owner 2026-09-13: the warning shows on every restart and each person chooses whether to rejoin;
  the shipped wording in README.md is updated to match.)*
- The maths cannot check honesty: signatures prove who sent a masked number, not that the figure
  was truthful. *(unchanged)*
- **NEW**: a room letter proves a distinct cryptographic key, not a distinct human or phone — the
  app cannot detect a host who fabricates extra "participants" entirely on their own device. Count
  the other phones in the room yourself; the app shows how many it expects.
- Collusion has a floor: if everyone else in the round conspires, they can recover your figure.
  *(unchanged)*
- The average itself can be revealing: small groups, prior knowledge, or repeated overlapping
  rounds. *(unchanged, now cross-referenced by the restart-differencing item above)*
- **NEW**: a verified transcript can be produced by a single device acting alone; it does not prove
  multiple phones or people took part.
- **NEW**: the app trusts each phone to keep its own figure in range before masking; a modified app
  could submit an out-of-range figure and skew everyone's average without any signature failure.
- **NEW**: anyone on the same Wi-Fi can see that a round is happening, its room name, host nickname
  and group size — not anyone's number.
- **NEW**: if a result is later found inconsistent, an already-shown or exported result may be
  marked disputed afterward; the exported file itself does not change, only the app's own record of
  it, and the app will not export that round again.
