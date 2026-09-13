# App Store paperwork

Everything App Store Connect will ask for, drafted so the submission is copy and paste. Field
limits are Apple's. Items marked *decision* need the owner's confirmation before entry; items marked
*later* depend on the finished app.

## App record

| Field | Value |
|---|---|
| Name (30) | Cravage |
| Subtitle (30) | Group average, kept private |
| Bundle ID | `com.dylanliew.cravage` (*decision*: permanent once the first build is uploaded) |
| SKU | `cravage-ios` |
| Primary language | English (UK) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content rights | Does not contain, show or access third-party content |
| Age rating | 4+ (see questionnaire below) |
| Copyright | 2026 Dylan Liew |
| Version | 1.0 |
| Price | Free (the unlock is an in-app purchase) |

## Listing copy

**Promotional text (170):**

Find your group's average without anyone saying their number. Phones in the same room, no server,
no account, nothing saved.

**Description (4000):**

Cravage lets a group of people in the same room find their average without anyone revealing their
own figure. Salaries, bonuses, valuations, rents, hours, anything you would rather not say out loud.

HOW IT WORKS
One person opens a room and says what is being averaged. Everyone else joins from their own
iPhone. Each phone shows the same short room code, and everyone confirms it matches before anything
is sent. Then each person types their figure, and the average appears on every phone at once.

WHAT MAKES IT PRIVATE
Your figure never leaves your phone in readable form. Every pair of phones agrees a secret random
number, and each person sends only their figure plus those secrets. When all the masked numbers are
added together, the secrets cancel out and only the true total remains. Every phone does that
addition itself and checks a digital signature on every masked number, so nobody, including the
person who opened the room, has to be trusted.

NO SERVER, NO ACCOUNT
Phones talk directly to each other over Wi-Fi. Cravage has no server, no sign-up, no analytics and
no adverts. It saves your nickname and nothing else. Round results are never stored.

CHECK IT YOURSELF
Any round can be exported as a transcript that shows the masked numbers, the signatures and the
result. The same open-source verifier that checks the web version checks the phone's transcript,
on any computer.

PRICING
Groups of exactly three are free, always. A one-off purchase lets the person opening the room run
groups of four to eight. Only that person pays; joining is always free. There is no subscription.

GOOD TO KNOW
Everyone needs an iPhone with Cravage installed, within Wi-Fi range of each other. The maths hides
figures up to a trillion in any unit. If everyone else in a group conspires, they can work out the
remaining person's figure; that is inherent to the technique, and the app says so where you enter
your number. Three is the smallest group where the maths protects everyone.

Cravage is open source. The code, the plan and an independent review of its design are published
at github.com/dylanil/cravage-ios.

**Keywords (100, comma separated, no spaces):**

average,salary,anonymous,private,group,poll,benchmark,secret,bonus,compare,team,survey,confidential

**What's New (version 1.0):**

First release.

**Support URL:** https://dylanil.github.io/cravage-ios/support

**Marketing URL:** https://dylanil.github.io/cravage-ios/

**Privacy Policy URL:** https://dylanil.github.io/cravage-ios/privacy-policy

## App Review information

**Contact:** the dedicated support address (EMAIL-TBD) and a phone number (*decision*: Apple
requires one for review contact; it is not shown publicly).

**Sign-in required:** No. Demo account: not applicable.

**Notes to the reviewer:**

Cravage computes a group average across several iPhones in the same room, so a complete round needs
at least three devices running the app within Wi-Fi range. We have attached a short video of a real
three-phone round. With a single device you can exercise everything up to the point where other
participants would join: creating a room, the group-size picker and its one-off unlock (groups of
exactly three are free; four to eight require the purchase, which only the room's host makes),
Settings, Restore Purchases, the privacy policy and limitations screens, and the Join screen's
"looking for rooms" state. The app has no server, no account and collects no data. Local Network
permission is requested only to find other phones running Cravage.

**Attachment (*later*):** 30 to 60 second screen recording of three phones completing a round,
including the room-code confirmation and the result appearing on all three.

## App Privacy (nutrition label)

Answer **"Data Not Collected"** for every category. Rationale, in Apple's terms: nothing is sent to
the developer or any third party. The nickname stays on the device. Masked shares travel only to
other phones in the room. Purchases are processed by Apple under Apple's own label. There are no
third-party SDKs. Tracking: No.

The privacy policy page says the same in plain words, and the label and the policy must agree.

## Age rating questionnaire

Every question answered **None / No**: no violence, no sexual content or nudity, no profanity or
crude humour, no alcohol, tobacco or drug references, no horror or fear themes, no mature or
suggestive themes, no gambling, no contests, no unrestricted web access, no user-generated content
in Apple's sense (nicknames and room labels are shown only to phones in the same room and are never
published), no medical or treatment information. Made for Kids: No. Expected rating: 4+.

## In-app purchase

| Field | Value |
|---|---|
| Type | Non-consumable |
| Reference name | Unlock groups of 4 to 8 |
| Product ID | `unlock_8` |
| Price | USD 0.99 tier (Apple sets local equivalents; UK shows 99p) |
| Display name (30) | Larger groups |
| Description (45) | Host rooms of 4 to 8 people. One-off. |
| Family Sharing | Off |
| Review screenshot (*later*) | The paywall screen from a simulator |
| Review notes | Unlocks the group-size picker for 4 to 8 participants for the host. Groups of exactly 3 remain free. |

Also required before the first purchase can be tested in the sandbox: accept the Paid Apps agreement
and complete banking and tax forms under Agreements, Tax, and Banking.

## Export compliance

Apple asks two questions at upload. Draft answers, *decision* for the owner from the finished app:

- Does your app use encryption? **Yes.**
- Does it qualify for an exemption? **Yes**: the app uses only the encryption provided by Apple's
  operating system (CryptoKit: P-256 key agreement and signatures, HKDF-SHA256, and the OS
  transport security), for digital signatures and for deriving one-time masking values; it
  implements no proprietary encryption and the source is public. Under this answer Apple requires no
  documentation. A US annual self-classification report may still apply to exempt encryption; the
  owner decides whether to file one. This is not legal advice.

If the owner prefers, the same answers go in Info.plist as `ITSAppUsesNonExemptEncryption = NO` so
App Store Connect stops asking at each upload.

## Territories and trader status

- **Availability:** all territories except the 27 EU member states (Austria, Belgium, Bulgaria,
  Croatia, Cyprus, Czechia, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland,
  Italy, Latvia, Lithuania, Luxembourg, Malta, Netherlands, Poland, Portugal, Romania, Slovakia,
  Slovenia, Spain, Sweden). Reason: the EU Digital Services Act requires a trader to display a postal
  address and phone number on the product page.
- **Trader status declaration:** required regardless of territories. Answer as the owner's
  situation dictates (selling a paid unlock as an individual is ordinarily trader activity); with
  the EU excluded, no contact details are displayed.

## Small Business Program

Enrol once the developer account is approved: App Store Connect, Agreements, Tax, and Banking,
accept the Paid Apps agreement, then apply at developer.apple.com/app-store/small-business-program.
Commission drops from 30% to 15% from the month after approval.

## Assets (*later*, produced by script from the real app)

- App icon 1024x1024 PNG, no transparency.
- iPhone 6.9-inch screenshots, 1320x2868 portrait, three to six of: Home, Lobby with room code,
  Enter Figure, Result, Paywall. Light and dark variants optional.
- App preview video optional (15 to 30 seconds); the review video above is separate and is
  attached in the review notes, not published.

## Checklist order at submission time

1. Developer account approved; Paid Apps agreement, banking, tax done; Small Business enrolled.
2. App record created with the fields above; name reserved.
3. In-app purchase created and set to Ready to Submit with its screenshot.
4. Build uploaded from Xcode; export compliance answered.
5. Listing copy, keywords, URLs, screenshots, age rating, privacy label, territories entered.
6. Review notes and video attached; contact details entered.
7. Submit for review. Typical turnaround is one to three days.
