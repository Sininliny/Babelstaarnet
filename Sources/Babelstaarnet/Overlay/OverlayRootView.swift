import SwiftUI

/// When a bubble is allowed to animate.
///
/// The fade belongs to the bubble arriving and leaving. It was keyed to the
/// whole card instead, so moving the pointer from one word to the next put the
/// two cards in the same animated transaction and SwiftUI cross-faded their
/// text: for 140 ms the bubble drew one word's explanation over the next one's,
/// in a panel that was being moved and resized in the same instant. On a line
/// of prose that is every word, and the result was an unreadable pile of two
/// vocabularies rather than a translation.
///
/// Reading is a stream of replacements, not a sequence of arrivals. Changing
/// which word is answered therefore has to be instant; only the bubble itself
/// coming and going is worth animating.
enum BubbleTransition {
    static let appearance = Animation.easeOut(duration: 0.14)
}

struct WordBubbleView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Group {
            if let hoverCard = state.hoverCard {
                wordBubble(hoverCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Color.clear
            }
        }
        .animation(BubbleTransition.appearance, value: state.hoverCard == nil)
    }

    @ViewBuilder
    private func wordBubble(_ card: HoverCard) -> some View {
        // Hovering a word is a request for its meaning. The meaning is
        // therefore the first thing in the bubble, at the largest size, with no
        // header to read past. Danish stays directly underneath so the learner
        // can see which word was actually read.
        let danishLeads = card.wordEnglishMeaning == nil

        VStack(alignment: .leading, spacing: 6) {
            // The controls sit above the answer and never leave. They used to
            // be earned by settling on a word and dropped again the moment the
            // machine saw any input, which made them flicker under a reader who
            // had not moved. A fixed row cannot flicker, and keeping it out of
            // the answer's own column — above it, behind a rule — is what stops
            // it from being read as part of the meaning.
            BridgeFeedbackControls(state: state, card: card)
            Divider()

            if let wordEnglishMeaning = card.wordEnglishMeaning {
                Text(LearnerDisplayText.clean(wordEnglishMeaning))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                EncouragedDanishWord(
                    text: LearnerDisplayText.clean(card.word.sourceText),
                    font: .system(
                        size: danishLeads ? 15 : 11,
                        weight: danishLeads ? .semibold : .medium,
                        design: .rounded
                    ),
                    opacity: KnowledgeTone.opacity(
                        for: card.wordKnowledgeLevel
                    ),
                    animationTrigger: state.knownAnimationID
                )
                .fixedSize(horizontal: false, vertical: true)

                if card.speaksOnHover {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                if card.showsAllEnglish {
                    AllEnglishIndicator()
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            if !card.wordBridgeText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                SentenceBridgeText(
                    text: LearnerDisplayText.clean(card.wordBridgeText),
                    englishTokenIndexes:
                        card.wordBridgeEnglishTokenIndexes,
                    knowledgeLevels: card.wordBridgeKnowledgeLevels,
                    focusTokenIndexes: [],
                    knownAnimationTrigger: 0
                )
            }

            if let englishSupport = card.englishSupport {
                Text(LearnerDisplayText.clean(englishSupport))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: WordBubbleMetrics.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // Answering a different word is a replacement, never an interpolation,
        // whatever transaction the change happens to arrive in.
        .contentTransition(.identity)
        .liquidGlassBubble(tint: .primary.opacity(0.05), cornerRadius: 12)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct AllEnglishIndicator: View {
    var body: some View {
        Text("All English")
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(.primary.opacity(0.06))
            }
    }
}

struct SentenceBridgeBubbleView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Group {
            if let hoverCard = state.hoverCard {
                sentenceBubble(hoverCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                Color.clear
            }
        }
        .animation(BubbleTransition.appearance, value: state.hoverCard == nil)
    }

    @ViewBuilder
    private func sentenceBubble(_ card: HoverCard) -> some View {
        // No header. The sentence is the content, and a label above it only
        // adds a line to read before the text the learner came for.
        VStack(alignment: .leading, spacing: 7) {
            SentenceBridgeText(
                text: LearnerDisplayText.clean(card.learningText),
                englishTokenIndexes: card.adaptiveEnglishTokenIndexes,
                knowledgeLevels: card.sentenceBridgeKnowledgeLevels,
                focusTokenIndexes: card.sentenceFocusTokenIndexes,
                knownAnimationTrigger: card.showsEnglishSupportInSentenceBridge
                    ? state.knownAnimationID
                    : 0
            )

            if card.showsEnglishSupportInSentenceBridge,
               card.wordKnowledgeLevel == 3,
               let wordEnglishMeaning = card.wordEnglishMeaning {
                Text(LearnerDisplayText.clean(wordEnglishMeaning))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if card.showsEnglishSupportInSentenceBridge,
               let englishSupport = card.englishSupport {
                Text(LearnerDisplayText.clean(englishSupport))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // No controls here — they live permanently in the word panel. The
            // confirmation still does, because the shortcuts stay live even
            // when the word panel is switched off and there is no button
            // anywhere to answer back.
            BridgeConfirmation(state: state)
        }
        .padding(12)
        .frame(
            width: SentenceBubbleMetrics.width,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.identity)
        .liquidGlassBubble(tint: .primary.opacity(0.04), cornerRadius: 14)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

}

/// Acting on the bubble always answers back, including where no button exists
/// to answer with — the shortcuts stay live whether or not the word panel that
/// carries the buttons is switched on.
private struct BridgeConfirmation: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        if let confirmation = state.feedbackConfirmation {
            Label(
                confirmation == .markedKnown
                    ? "Marked known"
                    : "English restored",
                systemImage: "checkmark"
            )
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
    }
}

private struct BridgeFeedbackControls: View {
    @ObservedObject var state: OverlayState
    let card: HoverCard

    var body: some View {
        // The narrow word bubble cannot fit four controls on one line, and a
        // button that wraps mid-label reads as a layout accident.
        InlineTokenLayout(spacing: 6, lineSpacing: 5) {
            Button {
                state.onKnown()
            } label: {
                if state.feedbackConfirmation == .markedKnown {
                    Label("Marked known", systemImage: "checkmark")
                } else {
                    Text("\(card.knownShortcutLabel)  Knew")
                }
            }

            Button {
                state.onDontKnow()
            } label: {
                if state.feedbackConfirmation == .englishRestored {
                    Label("English restored", systemImage: "checkmark")
                } else {
                    Text("\(card.dontKnowShortcutLabel)  Don’t know")
                }
            }

            // The label stays put and the capsule carries the state instead.
            // Swapping "All English" for "Less English" made the button wider
            // exactly when it was pressed, which was enough to wrap the row
            // onto a second line and jump the bubble 24 points taller on a
            // mode toggle.
            Button {
                state.onShowAllEnglish()
            } label: {
                Text("\(card.showAllEnglishShortcutLabel)  All English")
            }
            .buttonStyle(BridgeFeedbackButtonStyle(isOn: card.showsAllEnglish))
            .help(
                card.showsAllEnglish
                    ? "Return to adaptive support"
                    : "Translate every word on this line"
            )

            Button {
                state.onTogglePin()
            } label: {
                Text(
                    state.isPinned
                        ? "\(card.pinShortcutLabel)  Unpin"
                        : "\(card.pinShortcutLabel)  Pin"
                )
            }
            .help(state.isPinned ? "Let the bubble follow the pointer" : "Keep this bubble open")
        }
        .buttonStyle(BridgeFeedbackButtonStyle())
        .font(.system(size: 10, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .animation(
            .easeOut(duration: 0.12),
            value: state.feedbackConfirmation
        )
    }
}

/// A capsule filled at 4.5% of the foreground colour disappeared completely on
/// a Liquid Glass panel, which is already a light wash over whatever is behind
/// it: the row read as four pieces of grey text with nothing to say they could
/// be clicked. The hierarchical fills resolve against the material the bubble
/// is actually drawn on rather than against an assumed background, which is
/// what keeps the capsule visible over a dark page and a light one alike.
private struct BridgeFeedbackButtonStyle: ButtonStyle {
    /// Set on a control that is currently switched on, so its state shows in
    /// the capsule rather than in a label whose width would change with it.
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(fill(pressed: configuration.isPressed))
            }
            .contentShape(Capsule())
    }

    private func fill(pressed: Bool) -> HierarchicalShapeStyle {
        if pressed {
            return .secondary
        }
        return isOn ? .tertiary : .quaternary
    }
}

private enum LearnerDisplayText {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2026}", with: ".")
            .replacingOccurrences(
                of: #"\.{2,}"#,
                with: ".",
                options: .regularExpression
            )
    }
}

private struct SentenceBridgeText: View {
    let text: String
    let englishTokenIndexes: [Int]
    let knowledgeLevels: [Int: Int]
    let focusTokenIndexes: [Int]
    let knownAnimationTrigger: Int

    var body: some View {
        // One line of running text, set at one size. English words stand in
        // the sentence rather than under it, so they are typed like the words
        // beside them — a substitution the reader reads, not a note they
        // consult. A faint tint is the only thing marking which words were
        // swapped, so the swap stays visible without costing legibility.
        InlineTokenLayout(spacing: 4, lineSpacing: 4) {
            ForEach(Array(displayUnits.enumerated()), id: \.offset) {
                _, unit in
                if let danish = unit.danish {
                    EncouragedDanishWord(
                        text: danish,
                        font: .system(size: 12, design: .rounded),
                        opacity: KnowledgeTone.opacity(
                            for: knowledgeLevels[unit.sourceIndex] ?? 0
                        ),
                        animationTrigger: focusTokenIndexes.contains(
                            unit.sourceIndex
                        )
                            ? knownAnimationTrigger
                            : 0
                    )
                    .fixedSize(horizontal: true, vertical: true)
                } else if let english = unit.english {
                    Text(english)
                        .font(
                            .system(
                                size: 12,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.primary.opacity(0.07))
                        }
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var displayUnits: [BridgeDisplayUnit] {
        InterlinearBridgePresentation.units(
            text: text,
            englishTokenIndexes: englishTokenIndexes
        )
    }
}

struct BridgeDisplayUnit: Equatable {
    let sourceIndex: Int
    let danish: String?
    let english: String?
}

enum InterlinearBridgePresentation {
    /// Splits the bridge into the run of words it is read as.
    ///
    /// English stands in place of the Danish it replaced rather than beneath
    /// it, so there is nothing to pair: every token belongs to one language or
    /// the other and the line reads straight through. Consecutive English
    /// tokens are grouped, because one Danish word is often several English
    /// ones — "refleksionsperioden" is "the period of reflection" — and those
    /// four words are one substitution, not four.
    static func units(
        text: String,
        englishTokenIndexes: [Int]
    ) -> [BridgeDisplayUnit] {
        let tokens = text
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        let englishIndexes = Set(englishTokenIndexes)
        var result: [BridgeDisplayUnit] = []
        var index = 0
        while index < tokens.count {
            let start = index
            if englishIndexes.contains(index) {
                var english: [String] = []
                while index < tokens.count,
                      englishIndexes.contains(index) {
                    english.append(tokens[index])
                    index += 1
                }
                result.append(
                    BridgeDisplayUnit(
                        sourceIndex: start,
                        danish: nil,
                        english: english.joined(separator: " ")
                    )
                )
                continue
            }
            result.append(
                BridgeDisplayUnit(
                    sourceIndex: start,
                    danish: tokens[index],
                    english: nil
                )
            )
            index += 1
        }
        return result
    }
}

private struct KnownWordAnimationValues {
    var scale: CGFloat = 1
    var lift: CGFloat = 0
    var glow: Double = 0
}

private struct EncouragedDanishWord: View {
    let text: String
    let font: Font
    let opacity: Double
    let animationTrigger: Int

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary.opacity(opacity))
            .keyframeAnimator(
                initialValue: KnownWordAnimationValues(),
                trigger: animationTrigger
            ) { content, value in
                content
                    .scaleEffect(value.scale)
                    .offset(y: value.lift)
                    .shadow(
                        color: Color.accentColor.opacity(value.glow),
                        radius: 7
                    )
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.08, duration: 0.16)
                    CubicKeyframe(1, duration: 0.34)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-2.5, duration: 0.16)
                    CubicKeyframe(0, duration: 0.34)
                }
                KeyframeTrack(\.glow) {
                    CubicKeyframe(0.28, duration: 0.14)
                    CubicKeyframe(0, duration: 0.36)
                }
            }
    }
}

/// Danish is the text being read, so confidence is expressed inside a single
/// perceptual step. A wider ramp made well-known words the hardest ones to read
/// on a translucent panel — it charged legibility for a signal the learner was
/// not meant to be studying anyway.
enum KnowledgeTone {
    static func opacity(for level: Int) -> Double {
        switch min(max(level, 0), 5) {
        case 0: 1.00
        case 1: 0.98
        case 2: 0.96
        case 3: 0.94
        case 4: 0.92
        default: 0.90
        }
    }
}

/// English is the scaffolding, so this is where fading belongs and where it can
/// afford a range wide enough to notice without anyone being told about it.
private enum EnglishGlossTone {
    static func opacity(for level: Int) -> Double {
        switch min(max(level, 0), 3) {
        case 0: 0.95
        case 1: 0.82
        case 2: 0.68
        default: 0.55
        }
    }
}

private struct InlineTokenLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        measure(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let measurement = measure(
            proposal: ProposedViewSize(
                width: bounds.width,
                height: proposal.height
            ),
            subviews: subviews
        )
        for (index, origin) in measurement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + origin.x,
                    y: bounds.minY + origin.y
                ),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func measure(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint]) {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return (
            CGSize(
                width: proposal.width ?? usedWidth,
                height: subviews.isEmpty ? 0 : y + rowHeight
            ),
            origins
        )
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassBubble(
        tint: Color,
        cornerRadius: CGFloat
    ) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.tint(tint),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
        } else {
            materialBubble(cornerRadius: cornerRadius)
        }
#else
        materialBubble(cornerRadius: cornerRadius)
#endif
    }

    private func materialBubble(cornerRadius: CGFloat) -> some View {
        background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(.white.opacity(0.28), lineWidth: 0.7)
        }
    }
}
