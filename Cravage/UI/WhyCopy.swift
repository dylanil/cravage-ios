/// Why someone would use Cravage, as questions a host can hand across the table. Kept apart from
/// the view so the wording rules can be tested. Examples avoid pay (decided 2026-10-04): steps and
/// doomscrolling for fun, what something is worth for the commercial use.
enum WhyCopy {
    struct Item: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    static let items = [
        Item(question: "What is it for?",
             answer: "Finding a group's average when nobody wants to say their own number. How many steps you really "
                + "walk, or how many hours you lose to doomscrolling each night. What something is worth, from a used "
                + "car to a business, with every estimate made before anyone can anchor on someone else's. And "
                + "benchmarking: see how you compare with a peer group, on response times, conversion rates or hours "
                + "worked, without anyone showing their own number."),
        Item(question: "Why not tell one trusted person?",
             answer: "That person learns every figure and has to be trusted with them for good. In practice people round, "
                + "shade or opt out, and the average gets worse. With Cravage, nobody collects the figures."),
        Item(question: "Why not an anonymous survey?",
             answer: "Whoever runs a survey sees every answer, so \"anonymous\" means trusting them, and in a small group "
                + "answers are often easy to match to people. Cravage does not operate a server that receives your "
                + "round data, and every phone in the room checks the result."),
        Item(question: "Why not just encrypt the data?",
             answer: "Encryption protects figures on their way to someone, but that someone holds the key: they decrypt "
                + "every figure to add them up, so you are trusting them again. Cravage never decrypts anyone's "
                + "figure, because it never needs to. Each phone masks its own figure, and only the total can be "
                + "recovered, by adding up every masked number."),
        Item(question: "How does it work?",
             answer: "Each phone adds random amounts to its figure before sending it. The amounts are agreed in pairs "
                + "between phones and cancel out exactly when everything is added up. Each phone sees only masked "
                + "numbers, yet the total, and so the average, comes out exact. The technique is known as secure "
                + "aggregation. Phones connect peer-to-peer over Wi-Fi, with no server; the host's phone passes the "
                + "masked numbers along."),
        Item(question: "Can I check the result?",
             answer: "Every phone signs the masked numbers it received and the result. You can export a transcript and "
                + "check its arithmetic and signatures with the open-source checker."),
        Item(question: "Why does everyone need to be in the same room?",
             answer: "You count the phones and compare the room code by eye. That is how you catch a host who invents "
                + "extra participants or splits the group into two rooms."),
        Item(question: "What doesn't it protect?",
             answer: "The average itself can reveal something, especially in a small group. If everyone else works "
                + "together, they can work out your figure. And nobody can check that a figure was honest."),
    ]
}
