# Contributing to Cravage for iOS

Read `docs/PLAN.md` (the approved plan) and `docs/SPEC.md` (the protocol spec; it governs
`CravageCore` and adds to the plan's technical design) before substantive work.

## What this is

Cravage for iOS: a native iPhone app where a group in the same room computes its average without
anyone revealing their figure. Pairwise ECDH+HKDF masks that cancel in the sum, ECDSA-signed shares,
exact fixed-point arithmetic with wraparound, exportable transcript. Phones talk directly over
Apple's Network framework (peer-to-peer Wi-Fi, star topology through the host); there is no server,
no account, no analytics, no third-party code. The web version lives at
https://github.com/dylanil/SMPC and shares the crypto with this app.

## Layout

- `CravageCore/` - local Swift package: FixedPoint, crypto, roster, RoundEngine (sans-IO state
  machine), Transcript. Pure Swift + CryptoKit + Foundation. **Must never import UIKit, SwiftUI,
  Network or StoreKit.** `swift test --package-path CravageCore` runs on the Mac and CI without a
  simulator.
- `Cravage/` - the app target (iOS 26+, iPhone, portrait): SwiftUI views, `NetworkTransport` (the
  only file that imports Network), StoreKit 2, settings, transcript export, diagnostics.
  `Cravage.xcodeproj` is generated from `project.yml`: edit the yml and run `xcodegen generate`,
  never edit the project in Xcode's settings panes. Signing reads the git-ignored
  `Config/Local.xcconfig` (team ID); see `Config/Local.xcconfig.example`.
- `CravageTests/` - coordinator tests on a simulator with a fake transport, clock and store.
- `Cravage/UI/Paper.swift` is the reference for the look.
- `Tools/verify_round.py` - vendored from SMPC and **pinned to a commit and SHA-256** by
  `Tools/check_verifier_sync.sh`. Upstream changes are adopted deliberately, never silently.
- `docs/` - GitHub Pages: privacy policy, support, plan, spec, wire format, App Store paperwork and
  the review record (`docs/review/`, council records in `docs/review/council/`).

## Protocol invariants (load-bearing)

- Figures are capped at magnitude < 10^18 fixed units (999,999,999,999.999999). Shares and sums use
  wrapping Int64 arithmetic (mod 2^64); with at most 8 parties the true sum is exact. **No BigInt,
  never `Double`**, never widen the domain to avoid a test.
- Parse/format rules are exact ports of `smpc-core.js` (`parseDecimalToFixed`, `formatFixed`,
  `formatAverageFixed`); the SMPC vectors are pinned except the deliberate out-of-domain rejection.
- Mask: P-256 ECDH, HKDF-SHA256, empty salt, info `"SMPC mask " + lo + hi`, 8 bytes big-endian as
  signed Int64. Lower letter adds, higher subtracts. Letters A..H by bytewise sort of vks.
- Every wire message is signed under the sender's round key and bound to the session and roster
  hash; control messages are host-signed. Joiners prove possession of their key at hello.
- Confirmation barrier: no share leaves a phone before the user confirms the room code and signed
  confirmations from all others have arrived.
- Sealed room code (SPEC 14): each party seals a fresh random value in its signed hello and reveals
  it only after the roster locks; the code covers every value and exists only once all have
  opened; one roster per session. A 40-bit code over inputs the host chooses is a birthday bound,
  not a target bound.
- **One distinct share per round identity.** Freeze the figure before async share generation; a
  changed figure means a restart with fresh keys. First-write-wins on receipt.
- Fresh keys every round and restart; old-session messages rejected; every waiting state has a
  deadline; async results carry a round generation and stale ones are dropped.
- Entitlement (3 free, 4-8 unlocked) is enforced in the coordinator at room creation, not only in
  the picker.
- Transcript format `cravage-transcript-2` with an explicit modulus; labelled as a share-integrity
  and arithmetic check plus signed agreement, never as proof of who took part.

## Honesty copy

Allowed: "Your figure is processed on your phone; the app sends a masked share to the other
participants." "Cravage does not operate a server that receives your round data." "Round history is
not saved; your nickname is saved on this phone; exported transcripts can be kept by whoever
receives them." Forbidden: "no data leaves the room", "nothing stored or sent", any claim against
collusion, input honesty, participant identity beyond the host's eyes, or that the average is safe
to share. The Limitations text is council-approved and changes only with the maintainer.

## Rules every change follows

- No em dashes or en dashes anywhere. Use " - " or "-". Unicode math minus only in equations.
- Figures, keys, masks, names and labels never appear in logs, diagnostics or crash annotations.
- A test named for a guarantee gets an entry in `Tools/mutations.json`;
  `python3 Tools/check_mutations.py` must show every listed guard is caught when removed. CI checks
  per push only the guards whose file changed, and every guard nightly.
- A screen that is not built is not routed: its case stays unhandled so the exhaustive switch
  refuses to compile. `Tools/check_no_placeholder_screens.sh` fails if a placeholder is reachable.
- Every user-visible string passes `Tools/check_honesty_copy.sh`.
- Keep `README.md`'s "Known limitations" current in the same commit as any capability change.
- Images are captures of the real app in deterministic scenarios (`Tools/screenshots.sh`).
- A skipped test is not a tested claim.
- Signing material and the Apple team ID never enter the repository; `Tools/check_public_safe.sh`
  (CI and a pre-commit hook from `Tools/install_hooks.sh`) checks for it.

## Verification

- `swift test --package-path CravageCore` - contract pins, engine negative tests through the real
  message route, transcript golden test, message-domain fuzz.
- `Tools/transcript_acceptance.sh <file>` - the pinned `verify_round.py --transcript` accepts a
  Swift-produced v2 transcript and rejects a tampered one. `Tools/check_verifier_sync.sh` - pin
  intact.
- `xcodebuild test -project Cravage.xcodeproj -scheme Cravage -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  CODE_SIGNING_ALLOWED=NO` on a simulator, plus a Release build; release has no test hooks.
- Device: Network framework cannot run on CI and the simulator ignores local-network privacy; test
  on three physical phones, eight before advertising eight. `Tools/install_to_phones.sh` builds the
  last commit and installs and launches it on every paired iPhone.
- TestFlight: raise `CFBundleVersion` in `project.yml`, then `Tools/upload_testflight.sh` archives
  HEAD from a clean copy, checks it and uploads it.
