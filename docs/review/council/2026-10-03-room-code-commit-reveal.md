# Council 2026-10-03 - room-code commit-reveal

Proposal: close the room-code collision (a dishonest host controls both rooms, so matching a
40-bit displayed code is a birthday bound, not a target bound) by "seal first, then dice": every
party commits to a fresh random value, reveals only after holding every commitment, and the code
covers all revealed values. Source: the codebase review of 2026-10-03.

## Roster and opinions

All seven: support with changes.

- **Crypto.** Standard short-authenticated-string commit-reveal; host reduced to 2^-40 per
  attempt. Full 32-byte commitment, 32-byte `r` from the system generator, every code input fixed
  before any honest reveal, code is one tagged hash, never truncated commitments.
- **Protocol.** Commitment rides in the signed hello, so `rosterHash` covers it; one new signed,
  roster-bound reveal message and one new stage with a deadline. Combine reveals by hashing in
  letter order, never XOR. `confirmRoomCode` must refuse until the code exists.
- **Security.** Tried partition, mirroring, relay equivocation, withholding and ghost-only rooms.
  First four stopped (withholding becomes a visible restart, not a better chance); ghost-only room
  untouched and still rests on counting phones.
- **QA.** Current tests check binding, not collision resistance against an input-choosing host.
  CI-safe acceptance via a test-only narrow code width; engine negative tests through the real
  route, each with a mutation entry; matrix 3..8 parties with restart and timeout in the new stage.
- **UX.** Same code, same comparison. Show "Making the room code..." with the button disabled
  rather than a blank confirmable code; non-accusing failure copy; "The codes don't match" should
  end the round with an explanation instead of a silent leave.
- **Claims.** Wrong today: PLAN's "negligible probability (40 bits)", the PLAN threat table, the
  `RoomFingerprint` doc comment, the "count the phones" Limitations line (false assurance until
  the fix), README "nobody has to trust the host", APP_STORE "nobody ... has to be trusted"
  (overclaims even after the fix), SPEC's fingerprint-as-TLS note. Privacy policy must list the
  new value.
- **Challenger.** Longer code needs 80 to 128 bits (16 to 26 characters): unusable aloud.
  Host-only seal, host-independent session id and copy-only all fail because ghosts are the host.
  Proposed the hello placement.

## Debates

1. **Commitment in the hello vs a separate commit step after lock** (protocol and challenger vs
   security and crypto). Resolved for the hello. The label is fixed by the host-signed welcome
   before a joiner says hello; a joiner accepts one roster per session; restart regenerates keys.
   Binding to `rosterHash` and letter adds nothing because `rosterHash` covers the commitments.
   Security conceded with two conditions made invariants: exactly one roster per session per
   joiner (the existing `roster == nil` guard, now security-critical, needs a test and mutation
   entry), and `r` created with the keys in `beginSession`, never carried across a restart.
   Protocol added the label to the commitment preimage.
2. **Transcript v2 vs v3** (challenger vs QA, protocol, security, crypto). Resolved for v2 in
   this fix, v3 as a separate slice. The commitments are inside `rosterHash`, which v2's
   `roomcode_confirm` already signs, so the confirmed record fixes every code input; v2 loses only
   recomputing the code. Checked by the manager: `Tools/verify_round.py` treats the roster hash
   as opaque and reads no hello content, so the pin is untouched. A v3 that recomputes the code
   must also carry the hellos and recompute `rosterHash`, which closes a separate existing gap.

## Recommendation: GO, with conditions

1. Hello content gains `commit = SHA256(tag | session | vk | label | r)`, `r` 32 bytes, fresh per
   session. New signed, roster-bound `roomcode_reveal`, sent only after the roster verifies.
2. New stage between lock and confirming, with a deadline; code shown only after every reveal
   opens its commitment; mismatch, conflicting repeat or missing reveal fails the round visibly;
   no automatic retry.
3. Code = one tagged SHA-256 over roster hash, label, size and reveals in letter order, cut to 40
   bits. `confirmRoomCode` refused, in the engine, until the code exists.
4. Tests first, each guard with a mutation entry; narrow-width collision test in CI; full PoC
   stays private and is rerun against the new derivation.
5. Same commits: PLAN, SPEC, WIRE, doc comment, README, privacy policy. Limitations and APP_STORE
   wording go for sign-off.
6. Ends with `fresh-review`.

Framing note: the fix restores the meaning of "count the phones"; it does nothing for a room
padded with ghosts on the host's phone.

## Decision

2026-10-03: GO as recommended. Transcript v3 is a later, separate slice; this fix stays on
`cravage-transcript-2` with the verifier pin untouched. App Store and README trust wording:
the most accurate wording was approved (final text in the claims commit). No interim
Limitations caveat: no build goes to anyone before the fix lands. "The codes don't match" ends the
round with an explanation, included in this fix.
