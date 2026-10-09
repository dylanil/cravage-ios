# App Store paperwork

Everything App Store Connect will ask for, drafted so the submission is copy and paste. Field
limits are Apple's. Items marked *decision* need confirmation before entry; items marked
*later* depend on the finished app.

## App record

| Field | Value |
|---|---|
| Name (30) | Cravage |
| Subtitle (30) | Private peer-to-peer averages |
| Bundle ID | `com.dylanliew.cravage` (decided 2026-09-13; permanent once the first build is uploaded) |
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
no account, no round history saved.

**Description (4000):**

Cravage lets a group of people in the same room find their average without anyone revealing their
own figure. Daily steps, hours of doomscrolling, what a car or a business is worth, how your
numbers benchmark against a peer group: anything you would rather not say out loud, or not say first.

HOW IT WORKS
One person opens a room and says what is being averaged. Everyone else joins from their own
iPhone. Each phone shows the same short room code, and everyone confirms it matches before anything
is sent. Then each person types their figure, and the average appears on every phone at once.

WHAT MAKES IT PRIVATE
Cravage uses secure aggregation, so nobody has to be trusted with the figures: not a colleague, not
a survey company, not a server holding a decryption key.
Your figure is processed on your phone; the app sends a masked share to the other participants.
Every pair of phones agrees a secret random
number, and each person sends only their figure plus those secrets. When all the masked numbers are
added together, the secrets cancel out and only the true total remains. Every phone does that
addition itself and checks a digital signature on every masked number. The person who opened the
room passes the messages along but cannot read anyone's figure on their own, as long as everyone
checks the room code and counts the phones in the room; they can still stop a round, or add
participants that exist only on their own phone, and counting is what catches that.

NO SERVER, NO ACCOUNT
Cravage is peer-to-peer: phones talk directly to each other over Wi-Fi. Cravage has no server, no sign-up, no analytics and
no adverts. It saves your nickname and your light or dark setting on your phone. Round results are
not stored, unless you choose to share a transcript.

CHECK IT YOURSELF
Any round that every phone agreed on can be shared as a transcript that shows the masked numbers,
the signatures and the result. The same open-source verifier that checks the web version checks the phone's transcript,
on any computer.

PRICING
Groups of exactly three are free, always. A one-off purchase lets the person opening the room run
groups of four to eight. Only that person pays; joining is always free. There is no subscription.

GOOD TO KNOW
Everyone needs an iPhone with Cravage installed, within Wi-Fi range of each other. The maths hides
figures up to a trillion in any unit. If everyone else in a group conspires, they can work out the
remaining person's figure; that is inherent to the technique, and the app says so where you enter
your number. Three is the minimum, and the smallest group where no one else can work out your figure
alone; in a group of three, the other two together can.

Cravage is open source. The code, the plan and independent AI reviews of its design are published
at github.com/dylanil/cravage-ios.

**Keywords (100, comma separated, no spaces):**

average,aggregate,private,group,benchmark,secret,estimate,valuation,compare,team,survey,confidential

**What's New (version 1.0):**

First release.

**Support URL:** https://dylanil.github.io/cravage-ios/support

**Marketing URL:** https://dylanil.github.io/cravage-ios/

**Privacy Policy URL:** https://dylanil.github.io/cravage-ios/privacy-policy

## App Review information

**Contact:** cravage.support@gmail.com and the review-contact phone number (kept in the
private notes; Apple requires it for review contact and never shows it publicly).

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
| Reference name | Rooms for 4 to 8 people |
| Product ID | `com.dylanliew.cravage.unlock` (what `StoreManager.unlockProductID` asks for; permanent once created; created 2026-10-06) |
| Price | £0.99 with the United Kingdom as base country (Apple sets local equivalents) |
| Display name (30) | Rooms for 4 to 8 people (as in `Config/Cravage.storekit`) |
| Description (45) | Rooms for 4 to 8 people, for this Apple ID. |
| Family Sharing | Off |
| Review screenshot | New room with the padlocked sizes, from `Tools/screenshots.sh` (`02-newRoom.png`) |
| Review notes | Unlocks the group-size picker for 4 to 8 participants for the host. Groups of exactly 3 remain free. |

Also required before the first purchase can be tested in the sandbox: accept the Paid Apps agreement
and complete banking and tax forms under Agreements, Tax, and Banking.

## Export compliance

Answered 2026-10-06 for build 1.0 (1): "None of the algorithms mentioned above" (only the
encryption built into Apple's operating system), so exempt with no documentation. The reasoning:

- Does your app use encryption? **Yes.**
- Does it qualify for an exemption? **Yes**: the app uses only the encryption provided by Apple's
  operating system (CryptoKit: P-256 key agreement and signatures, HKDF-SHA256), for digital
  signatures and for deriving one-time masking values; connections between phones are plain TCP
  with no transport encryption of the app's own or the OS's (checked 2026-10-06); it
  implements no proprietary encryption and the source is public. Under this answer Apple requires no
  documentation. A US annual self-classification report may still apply to exempt encryption; the
  a decision is needed on whether to file one. This is not legal advice.

If preferred, the same answers go in Info.plist as `ITSAppUsesNonExemptEncryption = NO` so
App Store Connect stops asking at each upload.

## Territories and trader status

- **Availability:** all territories except the 27 EU member states (Austria, Belgium, Bulgaria,
  Croatia, Cyprus, Czechia, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland,
  Italy, Latvia, Lithuania, Luxembourg, Malta, Netherlands, Poland, Portugal, Romania, Slovakia,
  Slovenia, Spain, Sweden). Reason: the EU Digital Services Act requires a trader to display a postal
  address and phone number on the product page.
- **Trader status declaration:** made 2026-10-06 as "not a trader under the DSA or not
  distributing in the EU", so no contact details are displayed. This binds the availability above:
  the EU countries **must be unticked** when availability is set. Offering the app in the EU later
  means declaring as a trader first, with a postal address (a PO box is accepted), a phone number
  and an email shown on the product page.

## Small Business Program

Enrol once the developer account is approved: App Store Connect, Agreements, Tax, and Banking,
accept the Paid Apps agreement, then apply at developer.apple.com/app-store/small-business-program.
Commission drops from 30% to 15% from the month after approval.

## Assets (*later*, produced by script from the real app)

- App icon 1024x1024 PNG, no transparency.
- iPhone 6.9-inch screenshots, 1320x2868 portrait, from `Tools/screenshots.sh` (its `listing/`
  folder). Decision 2026-10-05: five screens, in order Home, Lobby, Check the code, Your
  figure (12 typed in), Result; a round called "Weekly screen time" with Alice (this phone), Bob
  and Carol entering 12, 6 and 8.5, so the average reads 8.83.
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
8. Once the app is live, open it from the App Store on a UK account, go to New room, pick 4, and
   check the button reads "Unlock for £0.99". TestFlight cannot show this: on iOS 26 it can give
   the app US dollar prices while Apple's payment sheet shows the local price, so a "$0.99" seen in
   TestFlight is not evidence either way. The app shows Apple's price string unchanged.
