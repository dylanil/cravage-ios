# Retro 2026-09-24 - reviewing incoming work, and step 9's first slice

Public-safe record. Scope: `d213f28..e3c5e28`. Three commits came from another session (Codex);
five from this one. No hardware session: the phones were away.

## Went well

- Another session's three commits were checked by running them here rather than reading the badge:
  81 app tests, 143 core tests, four lints, and `xcodegen` proving the project file was still
  generated rather than hand-edited. The verdict was sound, and it was sound with evidence.
- That work caught a real error in copy written by this session: the restart warning had said
  leaving the round avoids differencing. It does not - leaving is exactly the case where comparing
  two totals reveals the departed figure. Cross-agent review has now found defects in both
  directions.
- The public-safety lint caught a genuine leak this session introduced (a test room named with an
  owner-personal marker). The gate worked; the author did not.
- Settings, the Limitations screen and support diagnostics landed with the privacy promise made
  checkable: four tests drive a real round with distinctive names, a distinctive room name and a
  distinctive figure, and assert none of them - nor the room code, nor the roster hash - reach the
  report, with a mutation entry that swaps a count for the room name (`9af7f5c`).

## Went badly

- **A repeated correction.** The owner was asked to approve the restart-warning wording without
  being shown it, and replied "What's the restart warning wording?". The 2026-09-19 retro recorded
  the same root cause - describing a decision rather than showing it - and set the fix. It was not
  applied to the first decision raised afterwards.
- The public-safety lint was run before the new files were staged. It reads the git index, so it
  judged a state that did not contain the work it existed to judge, passed, and CI went red on the
  next push (`b0e0d91`). Root cause: a check whose scope silently excluded the thing being checked.
- The owner was told step 8 could not start until they created a product in App Store Connect.
  That was wrong: Xcode's local StoreKit configuration tests the whole purchase flow without an
  account. A blocker was asserted onto the owner without being verified. Caught by this session,
  after the owner had accepted it.
- `Tools/install_to_phones.sh`, written in the last retro, listed two simulators as phones and
  reported them as install failures. Root cause: `devicectl` reports `deviceType` "iPhone" for
  simulators too, and the script was never run against a real device list before being committed.
- A document asserted an owner approval that had not been given (the restart-warning copy, dated
  two days before the owner saw it). Surfaced and corrected (`957877b`), but it was written by an
  agent and passed review.

## Missing gates

- **Copy decisions.** Rule: a decision about user-visible words is raised by quoting the exact
  string as the screen shows it, never by describing it. No automated check is possible; the
  fallback is the plain-English memory note, which now carries the copy case explicitly. This is
  the second time this root cause has appeared, so it is recorded as repeated rather than new.
- **Lint scope.** Fixed in the check itself: `Tools/check_public_safe.sh` now scans files that are
  not in the index yet, so a new file carrying a marker fails before it can be added.
- **Asserted blockers.** Rule: before telling the owner that work is blocked on them, verify the
  dependency exists. No automated check; recorded here and in memory.
- **Scripts that talk to hardware.** Rule: a tool that enumerates devices is run against the real
  list before it is committed. No automated check possible.

## Skills

- **Write:** `review-incoming` (project), for checking commits another session pushed. The process
  has now been run twice by hand and its non-obvious steps - verify locally rather than on CI, check
  nothing was weakened, read document claims as claims - were re-derived both times.
- **Edit:** none.
- **Audit:** `fresh-review` did not fire this session and did not need to; the incoming work
  carried its own independent review, which is the same gate reached by another route.
- **Prune:** none. The previous retro's handoff is superseded by the one below, not stale within it.

## Handoff

- **Agent, next:** produce two or three distinct options each for the **app icon** (none exists in
  the project at all) and for **dark mode** of the Paper look (never designed). The owner has asked
  for options; the decision is theirs once shown, side by side, as with the Home looks.
- **Agent, also available:** delivery step 8, the purchase unlock. It needs nothing from the owner:
  Xcode's local StoreKit configuration exercises buy, restore and entitlement enforcement without
  an App Store Connect product, which is needed only before TestFlight.
- **Owner, parked:** the interruption acceptance test on three phones - Control Centre mid-round
  (survives), app switcher from the figure screen (paper cover, no figure), lock (round ends on all
  three). The build is already installed on the three phones. Parked because the owner is away.
- **Owner and agent, later:** TestFlight, an eight-phone round, the store listing, screenshots and
  submission (steps 10 and 11).
- **Decided this session:** the unlock is a single 99p/$0.99 purchase, not tiered by group size;
  the app never prints that price itself and must show StoreKit's localized price. The restart
  warning wording and the twelfth Limitations item are both owner-approved.
- **Untested on hardware:** the interruption and privacy-cover behaviour; eight phones; local
  network denial; a host whose listener fails; transcript export through a real share sheet.
