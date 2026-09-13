# Cravage for iOS

**Get the average, not the secrets.**

Cravage lets a group of people in the same room find their average - salary, bonus, valuation,
anything - without anyone revealing their own figure. Phones talk directly to each other over
Wi-Fi. Cravage has no server, no accounts, and saves no round data.

*Status: plan approved and reviewed, implementation starting. Not yet on the App Store.*

The web demo, which shares the same maths: [dylanil/SMPC](https://github.com/dylanil/SMPC).

## How it works, in one paragraph

Every pair of phones agrees a secret random number that only those two know. Each person adds
their pair-secrets to their figure (adding for one side of each pair, subtracting for the other)
and sends only that masked number. When all the masked numbers are added up, every secret appears
once with a plus and once with a minus, so they cancel and only the true total remains. Every phone
does that addition itself and checks a digital signature on every masked number, so nobody has to
trust the host. Before any masked number is sent, everyone confirms that the room code on their
screen matches everyone else's.

## Pricing

Free for groups of exactly 3. A one-off unlock (no subscription) lets the host run rooms of 4 to 8.
Only the host pays; joining is always free. No adverts, ever.

## Known limitations

These are known and, in most cases, intentional. They are listed here so they are explicit rather
than discovered. The in-app Limitations screen carries the same list in shorter form.

- **Same room only.** Phones must be within Wi-Fi range of each other. Remote participants are
  planned for a later version.
- **Up to 8 people.** A product decision for this version; tested on real phones before release.
- **Everyone needs an iPhone running iOS 26 or later with the app.** iPhone 11 and newer. There is
  no Android or web participant in this version.
- **Figures up to 999,999,999,999.99.** The masking maths hides figures perfectly only within a
  bounded range, so the app enforces one. Anything under a trillion in any unit is fine.
- **If someone drops out mid-round, the round fails.** The host restarts it with one tap; the room
  and label are kept. Every waiting step has a time limit. If the group is smaller after a restart
  and people re-enter the same figures as before, comparing the two results can reveal exactly what
  the person who left had entered - the app warns about this the moment a restart drops someone.
  Recovering an average from a partial group is planned for a later version.
- **The maths cannot check honesty.** Signatures prove who sent a masked number, not that the
  figure behind it was truthful.
- **Collusion has a floor.** If everyone else in the round conspires, they can recover your figure.
  This is inherent to the technique; the app warns about it where you enter your figure, and most
  strongly for groups of 3.
- **The average itself can be revealing.** Small groups, prior knowledge, or repeated overlapping
  rounds can leak information through the result.
- **A letter (A, B, C...) proves a matching digital signature, not a real second phone.** Nothing
  stops a dishonest host from inventing extra "participants" entirely on their own device and
  showing a lone real participant what looks like a normal room. The confirmation screen shows how
  many other phones are expected; count that many real phones in the room yourself before
  confirming - the app cannot do this check for you.
- **Room label and nicknames are visible to nearby phones** while a room is open.
- **Not sold in the EU** in this version, because EU rules would require publishing a postal
  address and phone number on the store page.
- **The exported transcript proves internal consistency**: that the signatures verify, the
  arithmetic adds up, and every listed key signed agreement to the result. It does not prove who
  the participants were, or even that separate phones or people were involved - one device holding
  every key could produce a transcript that verifies perfectly.
- **A modified app could submit an out-of-range figure undetected.** Each phone checks its own
  figure against the trillion cap before masking; nothing in the round detects a modified app that
  skips this, and it would skew everyone's average with no signature or verification failure.
- **A dispute found after the fact doesn't rewrite an already-saved file.** If a conflict surfaces
  after a result was shown or exported, the app marks its own record disputed from then on; a file
  already exported earlier is unchanged.

## Repository layout

- `CravageCore/` - the protocol maths, crypto, round state machine and transcript (pure Swift).
- `Cravage/` - the iPhone app (SwiftUI, Network framework, StoreKit 2).
- `Tools/` - the web app's transcript verifier, pinned to a specific commit, plus the screenshot
  script.
- `docs/` - the plan, privacy policy, support page and the review record, published with GitHub
  Pages.

## Verifying a round yourself

Export a transcript from the Result screen, then on any computer with Python 3:

```bash
pip install cryptography
python3 Tools/verify_round.py --transcript cravage-transcript-XXXXXX.json
```

That is the same verifier the web demo uses, so the phone and the browser are held to one standard.

## Licence

MIT. Copyright (c) 2026 Dylan Liew.
