# Cravage support

Cravage is made by Dylan Liew. Questions, bugs and suggestions are welcome.

- Email: cravage.support@gmail.com
- Report a bug or request a feature: [GitHub issues](https://github.com/dylanil/cravage-ios/issues)

## Why Cravage?

**What is it for?**
Finding a group's average when nobody wants to say their own number. How many steps you really
walk, or how many hours you lose to doomscrolling each night. What something is worth, from a used
car to a business, with every estimate made before anyone can anchor on someone else's. And
benchmarking: see how you compare with a peer group, on response times, conversion rates or hours
worked, without anyone showing their own number.

**Why not tell one trusted person?**
That person learns every figure and has to be trusted with them for good. In practice people round,
shade or opt out, and the average gets worse. With Cravage, nobody collects the figures.

**Why not an anonymous survey?**
Whoever runs a survey sees every answer, so "anonymous" means trusting them, and in a small group
answers are often easy to match to people. Cravage does not operate a server that receives your
round data, and every phone in the room checks the result.

**Why not just encrypt the data?**
Encryption protects figures on their way to someone, but that someone holds the key: they decrypt
every figure to add them up, so you are trusting them again. Cravage never decrypts anyone's
figure, because it never needs to. Each phone masks its own figure, and only the total can be
recovered, by adding up every masked number.

**How does it work?**
Each phone adds random amounts to its figure before sending it. The amounts are agreed in pairs
between phones and cancel out exactly when everything is added up. Each phone sees only masked
numbers, yet the total, and so the average, comes out exact. The technique is known as secure
aggregation. Phones connect peer-to-peer over Wi-Fi, with no server; the host's phone passes the
masked numbers along.

**Can I check the result?**
Every phone signs the masked numbers it received and the result. You can export a transcript and
check its arithmetic and signatures with the open-source checker.

**Why does everyone need to be in the same room?**
You count the phones and compare the room code by eye. That is how you catch a host who invents
extra participants or splits the group into two rooms.

**What doesn't it protect?**
The average itself can reveal something, especially in a small group. If everyone else works
together, they can work out your figure. And nobody can check that a figure was honest. The
Limitations screen in the app has the full list.

## Common questions

**Why does the round need at least 3 people?**
With only 2, each person could work out the other's figure from the average. Three is the minimum,
but it is still small: if the other two compare their figures, they can work out yours. The
Limitations screen in the app lists what the maths does and does not protect.

**Why can't I see the room on my phone?**
Every phone needs Wi-Fi turned on, and the app needs Local Network permission: Settings, Privacy
and Security, Local Network, Cravage. If the phones still can't see each other, join them all to the
same Wi-Fi network and try again.

**Someone left and the round failed. What now?**
The host taps Restart. The room and its label are kept; everyone re-enters their figure.

**Is my figure really private?**
Your figure is processed on your phone; the app sends a masked share to the other participants.
See the [privacy policy](privacy-policy.md) and the Limitations screen in the app for exactly what
is and is not protected.

**The codes didn't match. What does that mean?**
Every phone in a round should show the same room code. If someone's phone shows a different one,
they tap "The codes don't match" and the round stops on every phone. That can be a misread, or a
sign that a second room was set up. Only take part again when every phone shows the same code.
