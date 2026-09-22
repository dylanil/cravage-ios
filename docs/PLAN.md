# Cravage for iOS - approved plan (revision 2, 2026-09-13)

Revision 2 incorporates an independent plan review (docs/review/2026-09-12-plan-review.md) and a
coding-guardrails note (docs/review/2026-09-12-coding-guardrails.md). The owner agreed every
recommendation in the response (docs/review/2026-09-12-plan-review-response.md). Product decisions
are unchanged; the transport, the numeric domain, the state-machine specification, the privacy copy
and the acceptance discipline changed.

## Context

Cravage ("Get the average, not the secrets") is today a browser demo plus a Python relay at
fl-wg-smpc.fly.dev (repo github.com/dylanil/SMPC, public, MIT). A group computes its average without
anyone revealing their figure: pairwise ECDH+HKDF masks that cancel in the sum, ECDSA-signed shares,
exact fixed-point arithmetic, and a downloadable transcript anyone can verify offline.

The owner is repurposing it as a real, paid, ad-free iPhone app: one-off purchase, no subscription,
no running costs beyond the Apple Developer Program fee. Every decision below is the owner's, reached
through a grilling interview on 2026-09-12 and the review response on 2026-09-13.

## Decisions (settled, do not reopen without the owner)

Product
- Real tool, not a demo. No "test figures only" framing (App Store guidelines 2.1/2.2).
- Same-room only. Phones talk directly over Apple's **Network framework** (peer-to-peer Wi-Fi opt-in),
  NOT Multipeer Connectivity, which Apple's TN3213 says "Xcode 27 deprecates the entire" framework.
  **Minimum iOS 26**, using the iOS 26 interface (NetworkListener, NetworkBrowser, NetworkConnection).
  Excludes iPhone XS/XR and un-updated phones; accepted. Topology is a **star**: every joiner connects
  to the host, the host forwards messages. The host learns nothing (shares masked, everything signed,
  confirmation step catches selective forwarding). Product cap stays 8 participants including host.
  Remote participants are version two (CloudKit candidate); the crypto does not change for that, but
  discovery, identity, admission and timing need their own threat review then.
- Everyone in a round needs an iPhone with the app. Accepted.
- No aggregator role. Host creates the room (size 3-8, label), admits each joiner, otherwise holds
  nothing privileged. Proof-of-work, invite tokens and bearer tokens dropped. Per-share signatures,
  exact arithmetic and the transcript kept.
- **Bounded input domain with wraparound arithmetic.** Figures are capped at plus or minus
  999,999,999,999.999999 (under a trillion in any unit; fixed-point magnitude < 10^18). Shares and
  sums are computed modulo 2^64 (Swift wrapping Int64/UInt64). With 8 participants the true sum is
  below 2^63 so it is recovered exactly, and every share is uniformly distributed regardless of the
  figure. Reason: 64-bit masks cannot hide unbounded inputs (the reviewer showed the web demo's
  pinned nine-quadrillion value leaks to 0.2% from its own share); the web demo's "no cap" rule was
  an abuse-prevention stance for a demo, this cap is what makes the privacy claim true. Consequence:
  **no BigInt**; Int64 arithmetic only. The transcript becomes `cravage-transcript-2` (explicit
  modulus field) and `verify_round.py` in the SMPC repo gets a small extension to accept v2
  (approved, not yet implemented). The web vector `parseDecimalToFixed("9007199254740993")` is now a
  deliberate rejection (out of domain); all other parse/format/mask vectors still apply.
- Join flow: host taps New Room; nearby phones see it and tap Join; host admits each; once full,
  every screen shows the same room code and **each person taps "I checked, the codes match" before
  their phone will send a share** (enforced state, not a label). Display name: a nickname prompt on
  first launch ("What should people in the room call you?"), remembered, editable in Settings;
  blank = random two-word name. (The phone's own name is unavailable since iOS 16 without an Apple
  entitlement.)
- Dropout in v1: round fails cleanly with one-tap restart keeping room and label. Every waiting state
  has a timeout so a connected-but-silent phone cannot strand the room. Recovery is v2.
- Purchase: host pays. Exactly 3 participants free; one-off non-consumable unlock for 4-8 at $0.99
  (99p). Family Sharing off. Paywall on the group-size picker; **entitlement also enforced in the
  coordinator at room creation/start**, never only in the UI. Restore in Settings.
- Name Cravage. Subtitle "Group average, kept private". Keywords: average, salary, anonymous,
  private, group, poll, benchmark, secret, bonus, compare.
- v1 features: create room, join, admit, room code + confirmation step, nickname, enter figure
  (exact decimals, explicit full-stop separator, negatives, 2dp display, trillion cap), run round,
  per-phone verification, agreement display, share transcript, unlock + restore, settings, about,
  limitations, user-initiated diagnostics copy (allowlisted: app version, OS, protocol stage, error
  code), "run again". Not in v1: history, remote, dropout recovery, practice/solo mode (prepared
  fallback if App Review pushes back), iPad, Android, accounts.
- Visual: system light/dark, orange accent, Apple font, standard controls, monospace only for figures
  and the room code. Apple-native with brand moments. Mockups first on a design canvas the owner
  approves, covering the unattractive states too (empty discovery, waiting for admission, declined,
  full room, unsupported version, permission problem, malformed message, timeout, partial
  agreement, disagreement, restart), then Swift screens built to match. Subtraction pass after the
  real flow works. One uncoached-person comprehension test before TestFlight.
- Routine defaults: category Utilities, age 4+, standard EULA, English only, no analytics or
  crash-reporting SDK, custom join screen.

Money, accounts, territories
- Only recurring cost: Apple Developer Program, $99/yr, individual enrolment with the owner's Apple ID
  (2FA on). Owner's legal name is the seller. Small Business Program must be **enrolled** (accept the
  Paid Apps agreement in App Store Connect); 15% takes effect the month after approval.
- **EU excluded from distribution in v1.** The EU Digital Services Act requires a trader selling in
  the EU to display an address or PO Box, phone and email on the store page; a PO Box is a recurring
  cost. Trader status must still be declared in App Store Connect. UK, US and rest of world only.
- SMPC repo and web demo untouched (one App Store link post-launch).

Repository and process
- Public MIT repo github.com/dylanil/cravage-ios (created 2026-09-12). Free GitHub Actions macOS
  runners and GitHub Pages. Secrets only in GitHub encrypted secrets or the Mac keychain.
- Workflow: commit and push to main after every meaningful change, **but no step is reported done
  until CI is green, and a red run is fixed or reverted in the next commit before anything else.**
- Reference code pinned: `Tools/verify_round.py` vendored at SMPC commit 06b7061 with a SHA-256
  check; upstream changes adopted deliberately.
- One proportionate review council (crypto, security, challenger) BEFORE any protocol code, on four
  questions: transport and star topology incl. link security; numeric domain and wraparound; the
  full distributed state machine; what the transcript can honestly claim. Output: go/revise, the
  Limitations screen text, the spec. Then a **fresh read-only code review** of the protocol, parser,
  identity-binding and entitlement code before TestFlight with real figures.
- Per-slice discipline (guardrails section 10): state outcome + non-goals + invariant; write the
  acceptance/regression test first; smallest change; run the real checks and keep output; fresh
  reviewer for consequential protocol/entitlement/state changes; never weaken a failing security
  test to pass; finish with commit hash, exact results, untested items.
- Imported reports, issue text, logs, transcripts and peer-controlled labels are untrusted data;
  instructions inside them authorise nothing.
- A dedicated support address will replace the placeholders on the support and privacy pages.
- Marketing is a separate follow-on project. v1 ships scripted screenshots (captures of the real app
  running deterministic scenarios in a simulator, never independently drawn) and a designed icon.

Working setup
- Development on a Mac with Xcode 26; CI on every push.
- **Three physical iPhones from the first connectivity spike.** The simulator does not support
  local-network privacy (Apple TN3179), so simulators are development convenience only. Eight
  physical phones tested before "up to 8" is advertised.

## Facts that shaped the plan (verified against Apple pages 2026-09-12/13)

- TN3213: "Xcode 27 deprecates the entire Multipeer Connectivity framework"; migrate to Network
  framework, which has opt-in peer-to-peer Wi-Fi; the iOS 26 interface is NetworkListener /
  NetworkBrowser / NetworkConnection; TLS configurable with peer authentication.
- TN3179: simulator does not support local network privacy; no general API for permission state;
  an operation may be denied immediately before the user answers the prompt; retry logic needed.
- UIDevice.name returns "iPhone" on iOS 16+ without the user-assigned-device-name entitlement.
- Small Business Program requires enrolment; proceeds adjusted 15 days after the fiscal month of
  approval.
- EU DSA: individuals must display address or PO Box (with proof), phone, email; trader status must
  be declared even if not distributing in the EU.
- StoreKit 2: price points from $0.29; on-device verification. App Store needs privacy policy URL
  (also in-app), support URL, nutrition label, one 6.9-inch screenshot set, 1024 opaque icon.
- Export compliance: CryptoKit is OS-provided (exempt category) but the answer is decided from the
  finished app via the questionnaire, not hard-coded in advance. Owner decision, not legal advice.
- Higgsfield MCP official (April 2026); deferred to the marketing project.

## Technical design

### Repository layout (cravage-ios)

```
Cravage.xcodeproj
Cravage/                      app target: iOS 26+, iPhone, portrait, Swift 6
  CravageApp.swift, AppModel.swift (@MainActor @Observable root)
  Round/RoundCoordinator.swift        drives CravageCore.RoundEngine over a RoundTransport; owns the
                                      round generation id; drops stale async results
  Transport/RoundTransport.swift      protocol + TransportEvent + Envelope (no crypto)
  Transport/NetworkTransport.swift    the only file that imports Network (listener/browser/connections)
  Transport/PeerBinding.swift         connection <-> verifying-key binding, proof of possession
  Store/StoreManager.swift, Store/Cravage.storekit
  Export/TranscriptExporter.swift     JSON to tmp file + ShareLink; tmp file deleted after share
  Diagnostics/Diagnostics.swift       allowlisted, user-initiated copy only
  Settings/SettingsStore.swift        UserDefaults: nickname only (never figures)
  Views/ Home, NewRoom, Join, Lobby, Confirm, EnterFigure, Waiting, Result, Failed, Paywall,
         Settings, Limitations
  Resources/ Assets.xcassets, PrivacyInfo.xcprivacy, Info.plist
CravageCore/                  local Swift package, pure Swift + CryptoKit + Foundation
  Sources/CravageCore/ FixedPoint, ShareString, CanonicalMessage, PartyLabel,
    Crypto/SigningIdentity, Crypto/MaskKeyPair,
    Protocol/Roster, Envelope, RoomFingerprint, RoundEngine, RoundState,
    Transcript/Transcript, TranscriptVerifier
  Tests/CravageCoreTests/ ContractVector, FixedPoint, Roster, RoundEngine (InMemoryBus),
    TranscriptGolden, TranscriptVerifier, MessageDomain (fuzz/limits)
CravageTests/  StoreManagerTests (SKTestSession), CoordinatorTests (real coordinator + fake transport)
CravageUITests/ScreenshotTests.swift
Tools/verify_round.py (pinned), Tools/check_verifier_sync.sh, Tools/screenshots.sh
docs/ PLAN.md, privacy-policy.md, support.md, review/, retros/
.github/workflows/ci.yml, CLAUDE.md, README.md, LICENSE
```

CravageCore never imports UIKit, SwiftUI, Network or StoreKit. No duplicate protocol types or
numeric rules across targets. Release configuration cannot activate test-only transports,
verification bypasses or seeded states (compile-time exclusion, tested).

### CravageCore

- FixedPoint: exact ports of parseDecimalToFixed / formatFixed / formatAverageFixed from
  `public/static/smpc-core.js` lines 13-98, on Int64, plus the domain check: magnitude must be
  below 10^18 fixed units, otherwise a typed out-of-domain error with a plain message ("figures up
  to 999,999,999,999.99"). Never `Double` as an intermediate. Owner decision 2026-09-19, reaffirmed
  2026-09-22: accept an ASCII full stop only; reject commas and grouping separators with an inline
  explanation, since a comma can mean a decimal point or thousands separator. The figure screen
  supplies explicit Change sign and Decimal point controls alongside the regional decimal keypad.
- ShareString: ASCII `^-?[0-9]+$`, at most 20 digits (Int64 range), checked before parsing.
- Wraparound arithmetic: share = x &+ Σ maskSign(me, o) &* r(me, o) on Int64 (wrapping operators);
  result sum = wrapping sum of all N shares, then exact because |Σx| < 8 × 10^18 < 2^63.
- Crypto via CryptoKit: P256.Signing (x963 65-byte vk base64; raw r||s signature base64) and
  P256.KeyAgreement + HKDF-SHA256 (empty salt, info "SMPC mask " + lo + hi, 8 bytes big-endian ->
  Int64 bitPattern). Matches WebCrypto raw and verify_round.py lines 84-92. Pinned mask vector
  5107112043798890199 still holds.
- CanonicalMessage: "<action>|<session>|<party>|<content>", action pubkey|share|confirm|control.
  Every message on the wire is signed under the sender's round vk and carries session + roster hash;
  control messages (roster, lock, abort, restart) are signed by the host.
- PartyLabel: letters A..H by bytewise sort of vks; every phone recomputes; letters carry no
  privilege.
- RoomFingerprint = SHA-256 over a length-prefixed encoding of session, label, size and the sorted
  vks; first 5 bytes as Crockford base32, XXXX-XXXX. Claim: matching codes mean matching rooms
  except with negligible probability (40 bits); binds the label so differing questions are detected.
- RoundEngine (sans-IO, `handle(Event) -> [Effect]`), states: idle, lobby, confirming, keyExchange,
  sharing, collectingConfirmations, complete(agreed | mismatch | partial), failed(reason).
  Invariants, all unit-tested through the real message route:
  1. Roster/lock/abort/restart accepted only when signed by the host vk and bound to this session.
  2. Joiner hello = vk + signature over (session, host nonce): proof of possession. Duplicate or
     ambiguous vks rejected. Names are never identity.
  3. Confirmation barrier: no share leaves the phone until the local user has confirmed the code
     AND signed confirmations from all N-1 others have arrived.
  4. First-write-wins per party for pubkey and share; identical repeat no-op; different content
     fails the round.
  5. **One distinct share per round identity (sender side).** The figure is frozen into an
     immutable snapshot before async share generation; changing the figure requires a restart with
     fresh keys and masks. Tested on the sending path, not only the receiver.
  6. Sum only when all N shares present and verified. Result = wrapping sum.
  7. Post-result confirm = signature over SHA-256(session, roster hash, shares in letter order).
     Result screen distinguishes: collecting, all N agree, mismatch (named), missing. A mismatch is
     shown as a failure of agreement, never as a success with a smaller badge. A late conflict after
     display marks the result and any exported transcript as disputed.
  8. Every waiting state has a deadline (lobby idle, confirmation, key exchange, shares,
     confirmations); expiry fails the round with a reason.
  9. Restart: host issues a signed restart with a new session code; every phone discards keys,
     generates fresh ones, re-runs hello/roster; messages carrying the old session are rejected.
  10. Async results carry the round generation; stale results are dropped. Double taps on New Room,
      Join, Start, Submit, Buy, Restore, Restart produce one logical operation.
- Message domain limits (before decode and before any crypto): envelope byte cap, JSON depth cap,
  unknown fields ignored, unsupported protocol version rejected with a clear "update the app" state,
  bounded pending-invitation and message queues, repeated-valid-message floods bounded.
- Transcript v2: format "cravage-transcript-2", fields session, label, parties, scale "1000000",
  modulus "18446744073709551616", shares, share_sigs, vks, confirms, sum, average. Labelled honestly
  as a share-integrity and arithmetic check plus the participants' signed agreement; it does not
  prove who the participants were. TranscriptVerifier is the Swift twin; verify_round.py gains v2.

### Transport (Network framework, iOS 26 interface)

`protocol RoundTransport` unchanged in shape: AsyncStream of TransportEvent; startHosting /
stopHosting / startBrowsing / stopBrowsing / requestJoin / admit / decline / send / broadcast /
disconnect. `NetworkTransport`: host runs a NetworkListener advertising a Bonjour service
("_cravage._tcp", peer-to-peer included) with TXT record {v, label, size, host}; joiners run a
NetworkBrowser and open one NetworkConnection to the host; the host forwards envelopes to all
connections (star). Link security is a council question: TLS with per-round identities bound to
the vk, or application-layer signatures only (shares are uniform, but labels and names are
metadata). Info.plist: NSLocalNetworkUsageDescription ("Cravage finds other phones nearby to run a
round. It has no server and sends nothing over the internet.") and NSBonjourServices. Permission
denial is distinguished from other failures via the documented signals (Bonjour policy-denied
error; connection waiting with localNetworkDenied) and otherwise reported as an honest generic
connection error with retry. Backgrounding: the app keeps the screen awake during an active round
(idle timer disabled, restored after) and treats a lost connection as a dropout; foreground-use
guidance shown in the lobby. Product cap 8 enforced by the host.

### Threat model (for the council; Limitations screen derives from it)

| Attacker | Can do | Control | Residual |
|---|---|---|---|
| Anyone in Wi-Fi range | See label/host nickname/size; request to join | Admit gate; confirmation barrier | Label and names visible nearby; a wrongly admitted stranger is a participant |
| Active MITM on a link | Substitute keys | Signed messages under roster vks; fingerprint binds roster, label and keys; barrier | Only as strong as people comparing codes |
| Misbehaving host (relay) | Admit a stranger; drop or delay; forward selectively | No privileged data; signed control; confirm digests detect selective forwarding | Denial of service; chooses the room |
| Misbehaving participant | Any in-domain figure; different shares to different phones; malformed messages | Domain check; signatures; FWW; confirm; limits | Honesty of inputs unprovable |
| Colluding participants | N-1 recover the last figure | None (inherent) | Warning at N=3 shown at the figure entry |
| Observer of output | Infer from small groups or repeats | None | Stated |

### Privacy and data handling rules

Claims use explicit scope: "Your figure is processed on your phone; the app sends a masked share to
the other participants." "Cravage does not operate a server that receives your round data."
"Round history is not saved. Your nickname is saved on this phone. Exported transcripts can be kept
and shared by whoever receives them." Never "no data leaves the room" or "nothing stored or sent".
Rules: figures live only in memory and are cleared at round end; temp export file deleted after the
share sheet closes; no figures, keys, masks, names or labels in logs, diagnostics or crash
annotations; app-switcher snapshot obscured while a figure is on screen; collusion warning at the
point of entry. SECURITY.md's collusion wording is re-derived, not copied (it is internally
inconsistent).

### Tests

Contract pins carried from SMPC (tests.py lines 72-98, tests_numeric.js): canonical message
"share|ABCDEF|A|123"; signed-64 of 80 00.. = -9223372036854775808; the two SHA-256 pins; mask
5107112043798890199 symmetric; parseDecimal -12.345678 / 1.2345678 / 0.0000005 / -0.0000005 and the
rejections (1e6, 12abc, 1,000, Infinity, blank, Arabic-Indic digits); formatFixed(12345000) =
"12.35", formatFixed(-1) = "0"; formatAverage(1000000, 3) = "0.33", (6000000, 3) = "2"; maskSign.
Deliberate divergences, each pinned as such: 9007199254740993 rejected (domain); in-domain
boundary vectors added (999,999,999,999.999999 accepted, one micro-unit more rejected; 8 maximal
figures sum exactly).

Other suites: FixedPoint round trips and rounding boundaries; wrapping arithmetic vs a Python
oracle for random in-domain figures and random masks (masks cancel, sum exact, shares uniform
sanity); signing tamper/wrong key; roster and fingerprint permutation invariance and label
binding; RoundEngine over InMemoryBus for N=3 and N=8 incl. every invariant above as a negative
test (bad signature through the normal route, conflicting share, replay across restart, roster
from non-host, unknown letter, equivocation -> mismatch, silent peer -> timeout, double taps ->
one operation, changed figure -> no second share); MessageDomain fuzz (oversized, deep JSON,
unknown fields, bad versions, floods); TranscriptGolden with deterministic keys and figures
10/20/30 (shares pinned once via Python; signatures verified not pinned; forged share recomputes
its sum so only the signature fails); Python acceptance in CI against verify_round.py v2;
CoordinatorTests proving entitlement is enforced at room creation through the coordinator with a
fake store, and that a release build has no test hooks; StoreManager state machine (verified,
unverified, pending, cancelled, failed, duplicate updates, restore, offline cold start with
purchase, revocation, change during a round = current round continues, next room re-checks).

### CI

macOS runner, standard labels, two jobs: `swift test --package-path CravageCore` plus Python v2
transcript acceptance plus the pinned-verifier check; `xcodebuild test` on a simulator (debug and
release configurations), no signing. Clean-checkout build proven: the documented commands work with
no private files. TestFlight builds record commit and configuration.

### Screens

Home; New Room (label, size 3-8 with lock glyphs); Join (empty, browsing, requesting, declined,
full, unsupported version, permission problem); Lobby (host: admit/decline, roster, Start; joiner:
roster, waiting; timeout countdown); Confirm (code, "I checked, the codes match", waiting for
others); Enter Figure (cap and collusion note inline, locale-aware keypad, inline errors);
Waiting (k of N, who is outstanding, cancel, deadline); Failed sheet (reason, restart/leave);
Result (average, N, label, "all N signatures verified", agreement state, show shares, export, run
again, leave, disputed banner if a late conflict arrives); Paywall; Settings (nickname, restore,
privacy policy, diagnostics copy, about, limitations); Limitations. Every waiting state answers:
what is happening, what can I do, when does it stop waiting.

### App Store paperwork

Info.plist keys as above; portrait only; category Utilities. PrivacyInfo.xcprivacy: no tracking,
no collected data, UserDefaults reason CA92.1. Nutrition label: Data Not Collected. Privacy policy
and support on GitHub Pages. Age 4+. One IAP, Family Sharing off. Territories: all except the EU.
Trader status declared. Export compliance answered via the questionnaire from the finished app.
Review note: explains the 3-free/4-8-paid gate, that a round needs 3 phones, with a video of a real
round; practice mode is the prepared fallback. Screenshots: `Tools/screenshots.sh` boots a 6.9-inch
simulator and captures the real app in deterministic seeded scenarios (launch argument, compiled
out of release).

## Delivery sequence

0. Setup (owner present). Xcode, Apple ID, tools, phone pairing, developer enrolment, Small
   Business Program enrolment once approved, trader status declaration. Repo skeleton (done
   2026-09-12). Support address. Three physical iPhones lined up for the spike.
1. Council on the four questions -> spec (docs/SPEC.md) + Limitations text. No protocol code before.
   (Done 2026-09-13: docs/review/council/2026-09-13-protocol-council.md, docs/SPEC.md; Limitations
   text owner-approved and in README.)
2. Transport spike (throwaway): Network framework iOS 26 interface, host/join/admit/forward on
   three physical phones, then as many as available towards 8. Measures discovery time, permission
   prompt behaviour, backgrounding and lock behaviour, disconnect signals. Records the link-security
   choice. Also verifies Xcode 26 / macOS 26 toolchain and the clean-checkout build on the Mac.
   (Done 2026-09-13 on three iPhones: docs/review/2026-09-13-connectivity-spike-findings.md. Eight
   phones deferred to step 10.)
3. CravageCore with tests, all pins and negative tests green, Python v2 acceptance green in CI
   (verify_round.py v2 extension lands in the SMPC repo in the same step).
   (CravageCore committed and CI green 2026-09-13, f9166a1 through ffe8155: FixedPoint,
   wraparound and crypto, roster and fingerprint, envelope, RoundEngine, transcript v2; fresh
   read-only review done and its fixes committed. Wire bytes in docs/WIRE.md. Python v2
   acceptance runs in CI against the pinned verify_round.py (SMPC bf72734). Review findings M2 and L5 and the
   transcript label resolved by the owner and committed in 650b845: warn on every restart, ask
   before rejoining, room code signatures in the transcript. Warning copy approved; the misleading
   extra reassurance about leaving or changing a figure was removed by owner decision 2026-09-22.)
4. Mockups on a design canvas: the whole journey sketched cheaply; the screens for the first
   end-to-end round polished and approved; remaining screens approved feature by feature as device
   behaviour becomes known.
   (Drafted 2026-09-13, design/mockups/, published as a private design canvas. 2026-09-14 the owner
   chose look C "Paper" from three Home directions: editorial serif headings, hairline rules,
   numbered steps and drawn illustrations over standard iOS controls; monospace still only for
   figures and the room code. Nine first-round screens restyled in it; sixteen states sketched;
   remaining unbuilt screens retain draft status. The unlock price is already agreed at $0.99/99p;
   the actual purchase screen must obtain localized pricing from StoreKit.)
5. Vertical slice on three phones: NetworkTransport + Home/New Room/Join/Lobby/Confirm/Enter
   Figure/Waiting/Result, real round end to end. Fresh read-only review of the protocol, parser and
   binding code.
   (Groundwork committed 2026-09-13, 9b6f3f2: XcodeGen project with the team ID in an ignored
   xcconfig, NetworkTransport, RoundCoordinator with entitlement at creation, coordinator tests on
   the simulator. Screens and restart/rejoin are now built. The owner verified a first round, a new
   round and a restarted round on three phones on 2026-09-19. See that session's retro.)
6. Restart, timeouts, failure and disagreement states; interruption acceptance tests (app switch,
   lock, call, host leaves, cancel, rapid restart, permission denied then granted, silent peer).
   Owner decision 2026-09-22: keep automatic locking enabled. Inactive screens receive an opaque
   window cover; backgrounding or locking leaves an unfinished round (including a pending restart
   offer) and clears its local state. Returning never resumes it. A completed result is retained
   so sharing can leave the app. The lifecycle regressions are automated; physical-device lock,
   switcher, call and permission-prompt acceptance remains outstanding.
7. Transcript v2 export; Python acceptance; temp-file cleanup.
8. Unlock: StoreManager state machine, Paywall, coordinator enforcement, local StoreKit tests,
   sandbox once enrolment clears.
9. Polish: Settings, Limitations, diagnostics copy, privacy policy and support live, icon,
   accessibility pass on a device, subtraction pass, README Known limitations, uncoached-person test.
10. TestFlight (owner present): external link, a real 4-plus phone round, an 8-phone round before
    "up to 8" is advertised; fix findings.
11. Store listing and submission (owner present): scripted screenshots, metadata, nutrition label,
    export questionnaire, territories, review note and video, submit; respond to review.
12. Post-launch: App Store link on the SMPC web home page; hand off to the marketing project.

## Verification

- `swift test --package-path CravageCore` green on the Mac and CI; every invariant has a negative
  test through the real message route.
- `python3 Tools/verify_round.py --transcript golden.json` (v2) passes in CI; pinned-verifier check
  passes.
- `xcodebuild test` debug and release; release has no test hooks (asserted).
- Device: three physical phones from step 2; interruption matrix in step 6; eight phones in step 10;
  permission denied path; disputed-result path with a deliberately misbehaving test build.
- Purchase: sandbox buy, restore on a second device, offline cold start, gate through the
  coordinator.
- Store: screenshots regenerated by script on UI change; submission accepted.

## Risks and open items

- R1 Export compliance decided from the finished app via the questionnaire (owner).
- R2 Network framework peer-to-peer reliability and star behaviour with 8 phones: step-2 spike.
- R3 App name availability: reserve immediately after enrolment.
- R4 App Review with one device: video and note; practice mode fallback.
- R5 iOS 26 minimum excludes some phones; accepted, revisit if TestFlight friends are blocked.
- R6 verify_round.py v2 extension: done 2026-09-14, SMPC pull request 1 merged (bf72734), re-vendored and
  pinned; CI runs it against the Swift-produced transcript.
- R8 Link security choice: resolved 2026-09-13, signatures-only, no link-layer TLS (docs/SPEC.md
  §2 has the reasoning).
