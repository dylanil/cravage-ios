# Screen review follow-up, 2026-09-22

Review baseline: `d213f28`. The owner authorized all seven fixes, choosing to end an unfinished
round on phone lock/backgrounding instead of suppressing automatic locking.

## Changes

1. Removed the restart warning's false reassurance that leaving or changing a figure prevents
   differencing. The actual warning remains; leaving can itself expose a dropped person's figure
   when others compare totals.
2. Screen actions capture the displayed round generation. Admission, start, code confirmation,
   submission, restart, rejoin, acknowledgement and exit no longer fetch a newer generation when
   an old callback executes. Backing out of pending room creation also cancels its store answer.
3. Reconciled PLAN, SPEC, README and the mockup generator/output with the actual lobby, full-stop
   decimal rule, Waiting copy, restart wording and current implementation status. Corrected the
   previous handoff's already-decided price, without rewriting its historical findings.
4. Added a synchronous UIKit whole-window privacy cover on scene deactivation, retained through
   background/foreground until activation. It covers presented content too and dismisses editing.
5. Added text-only Change sign and Decimal point controls alongside the decimal keypad. No locale
   guessing, numeric conversion or change to the exact core parser.
6. Result and Failed now display a restart refusal. With fewer than three connected phones the
   instruction is to leave and create a new room, not to rejoin a terminal room.
7. Backgrounding exits unfinished rounds, cancels restart offers and pending creation, clears
   local round state and routes to an interruption explanation. Existing disconnect behavior ends
   a locked round on other phones. Temporary inactivity alone does not fail a round. Completed
   results are retained for transcript sharing. No protocol or wire changes.

## Evidence at implementation

- Each new behavior was exercised red before green: retained callbacks, rendered restart refusal,
  negative decimal entry, background exit and pixel-level snapshot concealment.
- 74 simulator app tests and 143 core tests passed. The Release simulator build passed.
- Core mutation gate: all 21 caught. The expanded app mutation gate and independent post-commit
  review are running; the completion addendum must record their outcomes, not infer them.
- Honesty-copy, placeholder-screen and public-safety checks passed before staging. Recheck the
  staged public-safety lint before committing. No hardware test is claimed for these changes.

## Next-session handoff

First run the changed build on three physical phones:

- Lock the host and each joiner during code confirmation, figure entry and waiting. Confirm the
  unfinished round stops, returning shows the explanation, and a fresh room works afterwards.
- Inspect the app switcher after typing a private fixture figure, including a regional comma
  keyboard. No figure should be visible. Test Control Center, an incoming call and the local-network
  prompt separately: transient inactivity covers the screen; actual backgrounding ends the round.
- Enter negative figures with the sign and full-stop controls. Check readability with the keyboard
  open, larger text sizes and VoiceOver.
- Complete a round, let one phone leave, and tap Run again. Check the visible explanation and the
  fresh-room route. Repeat normal restart/rejoin while all three stay connected.
- Export an agreed transcript using the real share sheet, leave the app to save/share, and verify
  the file with the pinned Python verifier. Test later-dispute export restrictions on the device.

Remaining product work: Settings and the in-app Limitations screen; StoreKit unlock/restore and
localized price ($0.99/99p target already decided); dark appearance; accessibility and uncoached
walkthrough; automated real-app screenshot capture (the referenced `Tools/screenshots.sh` does not
exist yet); local-network denial/recovery and listener failure; 4-plus and eight-phone acceptance;
TestFlight and store submission. Mockup HTML is design documentation, not device evidence.
