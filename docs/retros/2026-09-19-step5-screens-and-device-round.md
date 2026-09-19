# Retro 2026-09-19 - step 5 screens, and the first round on real phones

Public-safe record. Scope: `fc32eae..7700c5a` (12 commits). Delivery step 5 built, and verified on
three physical iPhones for the first time.

## Went well

- The nine Paper screens landed in five slices, each with its acceptance test written first, taking
  the app from a single placeholder to a complete round path (`07034e8`, `c7b40d4`, `a81868b`,
  `52523d7`, `2b45bdd`).
- A full round **and** a restart ran on three physical phones through the app's own
  NetworkTransport: room advertising, discovery, admission, the code check on every phone, figure
  entry, the same average everywhere, and rejoin after restart. The connectivity spike was deleted
  the same day, the condition CLAUDE.md had set for it (`de19daa`).
- The independent review found eight defects after the suite was green, including a forbidden
  honesty claim on Home and a transcript being written to disk on every re-render (`5523da3`).
  Second session running in which the fresh review outperformed the author's own tests.
- The mutation gate twice reported drift instead of falsely reporting a guard as caught
  (`3b17e75`, `de19daa`); in both cases a later edit had moved the line the mutation anchors to.

## Went badly

- Two defects reached the phones that 46 passing tests could not see. Screens never re-rendered,
  because `RoundEngine` is a plain class and reading it from a view registered nothing with
  Observation (`a970bfc`); and a restart could not be accepted, because the router reached a stub
  screen whose only button left the room (`27141a1`). Root cause for both: the tests asserted which
  screen the state calls for, never that the screen worked.
- A placeholder was routed as if it were a screen. Root cause: "not built yet" was treated as a
  renderable state rather than a compile error.
- Copy approved in a mockup shipped a claim CLAUDE.md forbids ("a number nobody sees"), while the
  mockups README asserted the copy already followed the honesty rules. Root cause: approval of a
  look was read as approval of the claims inside it.
- Two of four decisions put to the owner came back "not sure I understand", and a third as
  "spurious". Root cause: the items were described rather than shown with a concrete example, and
  were listed at equal weight regardless of impact.
- A claim was stated as fact and then withdrawn: that installing the app would prove the
  local-network permission prompt. It cannot, because nothing calls the Network framework until a
  round starts.
- `plutil -extract <key> json <file>` rewrites the file in place; it corrupted a built app's
  Info.plist and invalidated its code signature. `-o -` is the reading form.

## Missing gates

- **Placeholder screens.** Rule in CLAUDE.md: a screen that is not built is not routed, so the
  exhaustive switch refuses to compile. Check: `Tools/check_no_placeholder_screens.sh`, in CI.
- **Honesty copy.** Rule already in CLAUDE.md, now restated to cover copy arriving from an approved
  mockup. Check: `Tools/check_honesty_copy.sh`, in CI, greps the app's strings for the banned class.
- **Frozen screens.** `LiveEngineTests` pins both directions of the observation seam, with a
  mutation entry; the day `RoundEngine` becomes observable, a named test says so.
- **Mutation drift.** No new check; the gate already reports it. Rule added to CLAUDE.md: run the
  gate after the code has settled, or the run is wasted.
- **Tests passing is not a screen working.** Rule in CLAUDE.md. No automated check is possible; the
  device walk is the gate.
- **Decisions put to the owner.** No automated check possible; the fallback is the plain-English
  memory note, which now carries "show a concrete before and after, and triage by impact".

## Skills

- **Write:** none as a skill. The build-install-launch loop, run by hand six times, became
  `Tools/install_to_phones.sh`: mechanical, no judgement, so a script rather than a skill.
- **Edit:** none. `fresh-review` fired as written and produced the session's most valuable findings.
- **Audit:** none missing; `fresh-review` and `retro` both fired at the right moments.
- **Prune:** the CLAUDE.md paragraph describing `Spike/`, now that the directory is gone.

## Handoff

- **Owner, awaiting decision:** the restart-warning wording is still SPEC 13's draft, marked not
  approved. The paywall copy and its price are still placeholders.
- **Agent, next:** settings and the in-app Limitations screen; then the StoreKit paywall (delivery
  step 8); then dark mode for the Paper look, which has never been designed.
- **Owner and agent, together:** the eight-phone session, required before the app may advertise
  "up to 8 people".
- **Approved, not yet implemented:** nothing outstanding from earlier sessions; the restart warning
  and rejoin offer, listed this way in the 2026-09-14 retro, are now built.
- **Untested on hardware:** eight phones; local-network denial; a host whose listener fails; the
  release build's no-test-hooks assertion; transcript export through the share sheet.
- **Not fixed, deliberately:** `ResultView`'s use of the export gate is tested only through
  `OutcomeCopy`, since the view is not exercised by the suite; `Transcript.make`'s own refusal to
  produce a transcript for a non-agreed round is the backstop.
