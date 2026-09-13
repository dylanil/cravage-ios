# Cravage wire format (v1, implementation notes)

This note records the concrete encodings `CravageCore` chose while implementing `docs/SPEC.md`.
SPEC governs what must be signed and checked; this file says how the bytes look, so a second
implementation (for example the transcript verifier) can match them. Source of truth in code:
`Envelope.swift`, `Wire.swift`, `Roster.swift`. Python twins of the hashes live in
`Tools/gen_core_fixtures.py` and are pinned by `Fixtures/core_vectors.json`.

## Envelope

One JSON object per message, at most 8192 bytes, JSON nesting at most 6, unknown fields ignored:

| Field | Value |
|---|---|
| `v` | protocol version, integer `1`. Any other value is reported as "update the app". |
| `session` | bound session, see below |
| `action` | `pubkey`, `share`, `roomcode_confirm`, `result_confirm` or `control` |
| `party` | see the action table |
| `sender` | the sender's P-256 verifying key, X9.63 uncompressed (65 bytes), base64 |
| `content` | see the action table |
| `sig` | ECDSA P-256 SHA-256 signature, raw r then s (64 bytes), base64 |

The signature covers the UTF-8 bytes of `action|session|party|content`.

**Bound session.** Before the roster locks, `session` is the 32-character lowercase hex session
id. After it locks, `session` is `<session hex>.<roster hash hex>` (32, a dot, 64 lowercase hex).
This is how every post-lock message is bound to both the session and the roster hash.

## Actions

| Action | Sender | `party` | `content` |
|---|---|---|---|
| `pubkey` (hello) | joiner or host | the sender's verifying key, base64 | `<mask key base64>\|<host nonce hex>\|<nickname>` |
| `control` | host only | `host` | JSON object, see below |
| `roomcode_confirm` | any party | letter A..H | lowercase hex of the roomcode digest |
| `share` | any party | letter A..H | the share as a canonical signed decimal Int64 (`^-?[0-9]+$`, no leading zeros, no `-0`) |
| `result_confirm` | any party | letter A..H | lowercase hex of the result digest |

The nickname is the last hello field, so it may contain `|`. The hello signature binds the
identity key, the mask key, the nickname, the session and the host nonce in one signature.

Control objects (sorted keys):

- `{"type":"welcome","nonce":..,"label":..,"size":..}`: first message to a new connection.
- `{"type":"roster","entries":[{"vk":..,"mask":..,"nick":..,"sig":..}, ...]}`: the lock. Each
  entry carries that party's own hello signature, which every phone re-verifies.
- `{"type":"decline"}`
- `{"type":"abort","reason":"peer_left|timeout|conflict|roster_mismatch|host_left"}`
- `{"type":"restart","session":..,"nonce":..,"label":..,"size":..,"host":..}`: signed by the
  old host key under the old session; `host` is the new round's host verifying key. A joiner
  treats it as an offer and sends its new hello only after the person accepts.

## Hashes

All hashes are SHA-256 over a length-prefixed encoding: each field is a 4-byte big-endian length
followed by its bytes; single-byte counts are written as one raw byte. Strings are UTF-8.

- **Roster hash**: `"cravage-roster-1"`, session hex, count byte, then per party in letter order:
  verifying key (65 bytes), mask key (65 bytes), nickname.
- **Room fingerprint**: `"cravage-fingerprint-1"`, session hex, label, count byte, roster hash.
  The first 5 bytes as Crockford base32 (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`), shown `XXXX-XXXX`.
- **Roomcode digest**: `"cravage-roomcode-confirm-1"`, roster hash, label, count byte, then each
  verifying key in letter order.
- **Result digest**: `"cravage-result-confirm-1"`, session hex, roster hash, count byte, then each
  share string in letter order.

Letters A..H are assigned by bytewise order of the verifying keys' X9.63 bytes.

## Mask and share

Pair mask for letters lo < hi: P-256 ECDH shared secret, HKDF-SHA256, empty salt, info
`"SMPC mask " + lo + hi`, 8 bytes read big-endian as a signed Int64. A party's share is its
figure plus each pair mask where its letter is lower, minus each where it is higher, all with
wrapping Int64 arithmetic. The wrapping sum of all shares is the exact sum of the figures.

## Transcript v2

`cravage-transcript-2` is one JSON object with sorted keys: `format`, `session` (the bound session,
exactly as signed), `label`, `parties` (the letters in order), `scale` `"1000000"`, `modulus`
`"18446744073709551616"`, `shares`, `share_sigs`, `vks`, `confirms` (the `result_confirm`
signatures), `roomcode_confirms` (the `roomcode_confirm` signatures), `sum`, `average` and `claim`
(the pinned SPEC section 4 sentence). A verifier checks: format, scale, modulus and claim exactly;
letters A.. in order and assigned by bytewise key order; every share canonical and its signature
valid; the wrapping sum and the two-place average; every room code signature over the roomcode
digest of roster hash, label and keys (this is what authenticates the label); every agreement
signature over the result digest recomputed from the listed shares.

Not covered, by construction: the roster hash itself cannot be recomputed (the file carries
neither mask keys nor nicknames), so the file shows that everyone signed the same roster hash,
not which mask keys or nicknames it contained.
Implementations: `TranscriptVerifier` (Swift) and `Tools/check_transcript_v2.py` (Python, interim
until the version-2 mode lands in the SMPC repository's `verify_round.py`).
