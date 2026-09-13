# Connectivity spike findings, 2026-09-13 (in progress)

Delivery step 2 (`docs/PLAN.md`): prove three phones can find each other, connect through a host,
get admitted, and pass messages, using the iOS 26 `NetworkListener`/`NetworkBrowser`/
`NetworkConnection` interface. Records discovery time, permission-prompt behaviour, backgrounding
and lock behaviour, and disconnect signals. Code: `Spike/` (throwaway, deleted once this step is
done).

Two physical iPhones so far (a third pending a Lightning-to-USB-C cable). Both on iOS 26. Raw logs
captured via the app's own on-screen log (timestamped, copy-pasted from each device) - not
reproduced verbatim here, only the events they show.

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

## Open for the next session

- Third phone (needs a Lightning-to-USB-C cable) - repeat with three concurrent joiners once
  available, and scale toward eight before release per PLAN.md.
- Confirm whether the local-network permission prompt appeared and on which device/timing.
- Rough discovery-time number: the joiner's browser reached `ready` within ~70ms of starting, but
  the exact moment the host's room appeared in its list was not logged (only "looking" and the
  human's subsequent tap, ~10s later, which includes reaction time) - worth adding an explicit log
  line for a cleaner number, low priority.
