# Connectivity spike findings, 2026-09-13

Delivery step 2 (`docs/PLAN.md`): prove three phones can find each other, connect through a host,
get admitted, and pass messages, using the iOS 26 `NetworkListener`/`NetworkBrowser`/
`NetworkConnection` interface. Records discovery time, permission-prompt behaviour, backgrounding
and lock behaviour, and disconnect signals. Code: `Spike/` (throwaway).

**Status: closed 2026-09-13** after two rounds, first with two physical iPhones, then three, all on
iOS 26. `Spike/` stays in the tree for now in case another round is wanted; it is deleted once
CravageCore's real transport replaces it. Raw logs were captured via the app's own on-screen log
(timestamped, copy-pasted from each device) - not reproduced verbatim here, only the events they
show.

## Session 1 (host + one joiner)

- Host started a room; joiner discovered it, connected, sent hello, was admitted, and exchanged
  chat messages both ways. Core discovery/connect/admit/relay mechanics work on real hardware.
- Host's log showed two near-simultaneous "incoming connection" attempts for the single joiner's
  hello, one of which failed immediately with `ECONNREFUSED` while the other proceeded normally
  (became ready, sent hello, got admitted, worked for the rest of the session). Read as two
  candidate paths racing for the same connection attempt, with the loser cleanly discarded - not a
  defect, and not evidence of a real second peer.
- **Host backgrounded → room died in ~6 seconds.** Host's app went to background at 17:30:52; by
  17:30:58 the listener itself failed (`-65569 DefunctConnection`) and the existing connection to
  the joiner failed (`ECONNABORTED`/"socket is not connected"). Consistent with iOS aggressively
  killing a backgrounded app's ability to *accept new inbound connections* almost immediately.
  Confirms PLAN.md's existing requirement that the host's app must disable the idle timer and stay
  foregrounded for the duration of a round - this was already a plan decision, this test supplies
  the magnitude (single-digit seconds, not minutes) and the concrete failure signature to detect it
  by (a `NetworkListener` reaching `.failed`).
- **Joiner backgrounded/locked → connection survived.** The joiner locked/unlocked (no failure) and
  was fully backgrounded for ~26 seconds and resumed with chat still flowing immediately after.
  Real asymmetry versus the host: an already-established outbound connection gets meaningfully more
  background grace than a listener waiting for new inbound connections. Implication for the state
  machine: a joiner briefly backgrounding mid-round is not automatically a dropout on the timescale
  observed here; the host's own foregrounding requirement is the harder constraint.
- **Detecting a dead peer can lag far behind the actual failure.** The host's listener/connection
  failed at 17:30:58. The joiner's own `NetworkConnection` did not report `.failed` until 17:31:36 -
  38 seconds later - despite the joiner attempting to send chat messages in between (which the UI
  logged as sent immediately, with no confirmation of actual delivery; the underlying send did not
  throw until the stack noticed the peer was gone). Confirms PLAN.md's requirement that every
  waiting state needs its own explicit deadline rather than relying on the transport to notice and
  report a dropped peer promptly - 38 seconds is well outside what a user would tolerate waiting
  silently.
- Local-network-permission system prompt (TN3179): both phones showed it and Allow was tapped on
  both. Exact timing not captured precisely, but most likely at the point of tapping "Host a room"
  or "Join a room" (i.e. when the listener/browser actually starts) rather than at launch. Worth
  logging this explicitly in a later round - TN3179 notes the prompt can be denied silently before
  the user answers, so the real app needs to handle a denial distinctly from other connection
  failures; this round only observed the allow path.
- Fix applied during this session: the host's `NetworkListener` had no explicit
  `newConnectionLimit`, which is a plausible cause of otherwise-unexplained "cannot add handler"
  console noise seen mid-session; set to 8 (the product's max party count) going forward
  (`268f2f5`).

## Session 2 (host + two joiners, three phones)

- **Relay through the host confirmed working joiner-to-joiner**, not just host-to-joiner: messages
  from each of the two joiners reached the other joiner via the host, matching the star-topology
  design.
- **A live connection tolerated a brief Wi-Fi drop and recovered on its own**, no reconnect needed
  (joiner's Wi-Fi was toggled off and back on; chat kept flowing once it returned). This is a real
  resilience data point - not everything that looks like a network interruption actually needs the
  round-restart machinery; only a full app kill or a backgrounded host proved fatal in these tests.
- **A genuine spike-code bug, now fixed**: force-quitting the app on a joiner and reopening it (a
  fresh launch, so a new random identity) produced a confusing stuck state - the host logged "wants
  to join" three times for the same rejoining phone (the user tapped the room repeatedly since
  nothing appeared to happen) and never admitted it, while separately the host kept failing to
  relay to the *original*, long-dead connection on every subsequent message. Root cause: the
  cleanup code that removes a peer from `hostConnections`/`admittedPeers`/`pendingRequests` once
  their connection ends was written after the message-receive loop inside the same `do` block, so a
  *thrown* failure (the normal way a dead connection surfaces) skipped straight to `catch` and never
  reached it - cleanup only ran on a clean, non-throwing disconnect, which is the rare case here.
  Fixed by moving cleanup outside the do/catch so it runs unconditionally, and by having the host
  recognize a reconnect from an already-admitted identity and immediately re-admit it rather than
  piling up duplicate pending requests.
- Force-quitting a peer's app was detected by the host almost instantly (same second) via a proper
  TCP reset, in clear contrast to session 1's 38-second lag for a silent background failure -
  disconnect-detection speed depends heavily on *how* a peer leaves, not just *that* they left.
- **Discovery time, with the host already advertising: 43 ms and 89 ms** from the joiner starting
  to browse to the room appearing in its list (the two joiners' logs: 18:10:18.871 -> .914 and
  18:06:45.290 -> .379). Connect-to-ready after the tap was 100-500 ms. No discovery-time concern
  for the product.

## Clean-checkout build on the Mac (the other step-2 deliverable)

Fresh `git clone` of `origin/main` at `e396056` into a temporary directory on the development Mac,
no private files, no caches, on 2026-09-13:

- Toolchain: Xcode 26.6 (17F113), Swift 6.3.3, Python 3.9.6 with `cryptography` 50.0.1.
- `swift test --package-path CravageCore`: 1 test (the placeholder), 0 failures.
- `Tools/check_verifier_sync.sh`: `verify_round.py` matches the pinned SMPC commit `06b7061`.
- `Tools/check_public_safe.sh`: clean.
- The Python transcript acceptance cannot run yet (no golden transcript until step 3 produces one).
- `Spike/ConnectivitySpike.xcodeproj` built unsigned for the device SDK (`-sdk iphoneos`) and for
  the simulator SDK from the tree; three physical iPhones ran it via Xcode with automatic signing
  under the free Personal Team.

## Not tested (carried forward)

- Rejoin after the round-2 fix (force-quit, reopen, rejoin the same live room): the fix compiled
  and is pushed but has not been exercised on phones.
- The local-network permission *denial* path (TN3179): only the allow path was observed.
- Eight phones: PLAN.md step 10, with the real app, before advertising "up to 8".
