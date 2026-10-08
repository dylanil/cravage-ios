import SwiftUI

/// Small parts shared by the Paper screens. Each matches a shape that appears in more than one
/// approved mockup; a shape used once is built inline on its own screen.

/// The letter-spaced accent label above a heading ("CHECK THE CODE").
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .paperFont(.sans, 12, weight: .bold)
            .tracking(2)
            .foregroundStyle(Paper.accent)
            .accessibilityHidden(true)
    }
}

/// Eyebrow plus the serif heading that follows it, with the mockups' spacing.
struct PaperHeader: View {
    let eyebrow: String
    let title: String
    var size: CGFloat = 28
    /// The eyebrow carries the room's question rather than repeating the screen's name, so
    /// VoiceOver reads it before the title.
    var speaksEyebrow = false

    static func spokenLabel(eyebrow: String, title: String, speaksEyebrow: Bool) -> String {
        speaksEyebrow ? "\(eyebrow). \(title)" : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            Text(title)
                .paperFont(.serif, size)
                .tracking(-0.3)
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenLabel(eyebrow: eyebrow, title: title, speaksEyebrow: speaksEyebrow))
        .accessibilityAddTraits(.isHeader)
    }
}

/// The filled accent button that carries each screen's main action.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .paperFont(.sans, 17, weight: .semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: Paper.buttonHeight)
                .background(Paper.accentFill, in: RoundedRectangle(cornerRadius: Paper.corner))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// The outlined companion to `PrimaryButton`.
struct SecondaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .paperFont(.sans, 17, weight: .semibold)
                .foregroundStyle(Paper.ink)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: Paper.buttonHeight)
                .overlay(RoundedRectangle(cornerRadius: Paper.corner).strokeBorder(Paper.ink, lineWidth: 1.5))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A plain text action under the buttons: quiet by default, red where it ends the round.
struct QuietButton: View {
    let title: String
    var tint: Color = Paper.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .paperFont(.sans, 17)
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

/// The cream note card with a glyph down the left ("Look up and count the other phones.").
struct NoteCard<Glyph: View, Content: View>: View {
    @ViewBuilder var glyph: Glyph
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The glyph only decorates the note; VoiceOver reads the words.
            glyph.padding(.top, 2).accessibilityHidden(true)
            content
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Paper.card, in: RoundedRectangle(cornerRadius: Paper.corner))
        .overlay(RoundedRectangle(cornerRadius: Paper.corner).strokeBorder(Paper.hairline, lineWidth: 1))
    }
}

/// The party letter in its circle: filled once that party has done the thing the screen is about.
struct LetterBadge: View {
    let letter: String
    var filled: Bool

    var body: some View {
        Text(letter)
            .paperFont(.mono, 14)
            .foregroundStyle(filled ? Paper.onInk : Paper.muted)
            .frame(width: 32, height: 32)
            .background(filled ? Paper.ink : .clear, in: Circle())
            .overlay(filled ? nil : Circle().strokeBorder(Paper.hairline, lineWidth: 1.5))
            // One letter in a fixed circle: it grows to the largest standard size, not beyond.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// One person in a roster list: letter, name, an optional note ("Host", "You") and a trailing status.
struct PersonRow<Trailing: View>: View {
    let letter: String
    let name: String
    var note: String?
    var filled: Bool
    var showsRule = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            LetterBadge(letter: letter, filled: filled)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .paperFont(.serif, 20, weight: .regular)
                    .foregroundStyle(Paper.ink)
                if let note {
                    Text(note)
                        .paperFont(.sans, 14)
                        .foregroundStyle(Paper.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            if showsRule { Rectangle().fill(Paper.hairline).frame(height: 1) }
        }
    }
}

/// "Checked" in green, or a quiet word for anyone still doing it.
struct StatusTag: View {
    let text: String
    var done: Bool

    var body: some View {
        HStack(spacing: 4) {
            if done {
                Image(systemName: "checkmark")
                    .paperFont(.sans, 12, weight: .heavy)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .paperFont(.sans, 14, weight: .semibold)
        .foregroundStyle(done ? Paper.success : Paper.muted)
    }
}

/// The clock line under the buttons that says when a wait gives up.
struct DeadlineLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .paperFont(.sans, 13, weight: .regular)
                .accessibilityHidden(true)
            Text(text)
        }
        .paperFont(.sans, 13)
        .foregroundStyle(Paper.muted)
        .frame(maxWidth: .infinity)
    }
}

/// The bottom stack: actions sit on the page edge with the mockups' padding.
struct BottomStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, Paper.buttonGutter)
            .padding(.top, 12)
            .padding(.bottom, Paper.bottomInset)
    }
}

/// The screen's top bar: one leading action, matching the mockups' 44pt row.
struct PaperNavBar: View {
    var title: String?
    var showsChevron = false
    var action: (() -> Void)?

    var body: some View {
        HStack {
            if let title, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        if showsChevron {
                            Image(systemName: "chevron.left")
                                .paperFont(.sans, 17, weight: .semibold)
                                .accessibilityHidden(true)
                        }
                        Text(title)
                    }
                    .paperFont(.sans, 17)
                    .foregroundStyle(Paper.accent)
                }
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        // A top bar: it grows to the largest standard text size, not into the accessibility ones.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A rule with a letter-spaced caption under it, used to open a section ("CONFIRMED").
struct SectionHeading: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Paper.ink).frame(height: 1.5)
            Text(text.uppercased())
                .paperFont(.sans, 12, weight: .bold)
                .tracking(1.6)
                .foregroundStyle(Paper.ink)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A screen's scrolling body and its bottom actions. Normally the actions stay pinned under the
/// body; at accessibility text sizes they would fill most of the screen and hide what they act on
/// (on Check the code, the code itself), so there they scroll with the body instead.
struct ScrollingBody<Content: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 0) {
                    content
                    BottomStack { actions }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            VStack(spacing: 0) {
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
                BottomStack { actions }
            }
        }
    }
}
