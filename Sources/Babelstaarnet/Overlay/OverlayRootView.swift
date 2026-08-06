import SwiftUI

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
        .animation(.easeOut(duration: 0.14), value: state.hoverCard)
    }

    @ViewBuilder
    private func wordBubble(_ card: HoverCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text("Word bridge")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            EncouragedDanishWord(
                text: LearnerDisplayText.clean(card.word.sourceText),
                font: .system(
                    size: 13,
                    weight: .semibold,
                    design: .rounded
                ),
                opacity: KnowledgeTone.opacity(
                    for: card.wordKnowledgeLevel
                ),
                animationTrigger: card.showsControlsInWordBridge
                    ? state.knownAnimationID
                    : 0
            )
                .fixedSize(horizontal: false, vertical: true)

            if let wordEnglishMeaning = card.wordEnglishMeaning {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("EN")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)

                    Text(LearnerDisplayText.clean(wordEnglishMeaning))
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            .primary.opacity(
                                EnglishGlossTone.opacity(
                                    for: card.wordKnowledgeLevel
                                )
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SentenceBridgeText(
                text: LearnerDisplayText.clean(card.wordBridgeText),
                englishTokenIndexes:
                    card.wordBridgeEnglishTokenIndexes,
                knowledgeLevels: card.wordBridgeKnowledgeLevels,
                focusTokenIndexes: [],
                knownAnimationTrigger: 0
            )

            if let englishSupport = card.englishSupport {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.wordEnglishMeaning == nil ? "EN" : "More")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)

                    Text(LearnerDisplayText.clean(englishSupport))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if card.showsControlsInWordBridge {
                BridgeFeedbackControls(state: state, card: card)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: WordBubbleMetrics.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlassBubble(tint: .primary.opacity(0.05), cornerRadius: 12)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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
        .animation(.easeOut(duration: 0.14), value: state.hoverCard)
    }

    @ViewBuilder
    private func sentenceBubble(_ card: HoverCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text("Sentence bridge")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            SentenceBridgeText(
                text: LearnerDisplayText.clean(card.learningText),
                englishTokenIndexes: card.adaptiveEnglishTokenIndexes,
                knowledgeLevels: card.sentenceBridgeKnowledgeLevels,
                focusTokenIndexes: card.sentenceFocusTokenIndexes,
                knownAnimationTrigger: card.showsControlsInSentenceBridge
                    ? state.knownAnimationID
                    : 0
            )

            if card.showsEnglishSupportInSentenceBridge,
               let englishSupport = card.englishSupport {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("EN")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)

                    Text(LearnerDisplayText.clean(englishSupport))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if card.showsControlsInSentenceBridge {
                BridgeFeedbackControls(state: state, card: card)
            }
        }
        .padding(12)
        .frame(
            width: SentenceBubbleMetrics.width,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlassBubble(tint: .primary.opacity(0.04), cornerRadius: 14)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

}

private struct BridgeFeedbackControls: View {
    @ObservedObject var state: OverlayState
    let card: HoverCard

    var body: some View {
        Divider().opacity(0.45)

        HStack(spacing: 10) {
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

            Text(
                state.isPinned
                    ? "\(card.pinShortcutLabel)  Unpin"
                    : "\(card.pinShortcutLabel)  Pin"
            )

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .regular, design: .rounded))
        .foregroundStyle(.tertiary)
        .animation(
            .easeOut(duration: 0.12),
            value: state.feedbackConfirmation
        )
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
        InlineTokenLayout(spacing: 3, lineSpacing: 3) {
            ForEach(Array(displayUnits.enumerated()), id: \.offset) {
                _, unit in
                if let danish = unit.danish {
                    VStack(spacing: 1) {
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

                        if let english = unit.english {
                            Text(english)
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .medium,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(
                                    .primary.opacity(
                                        EnglishGlossTone.opacity(
                                            for: knowledgeLevels[
                                                unit.sourceIndex
                                            ] ?? 0
                                        )
                                    )
                                )
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.primary.opacity(0.035))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            .secondary.opacity(0.38),
                                            lineWidth: 0.55
                                        )
                                }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                } else if let english = unit.english {
                    Text(english)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.9))
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
            if englishIndexes.contains(index) {
                var english: [String] = []
                let start = index
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

            let sourceIndex = index
            var danish = tokens[index]
            index += 1
            var glossTokens: [String] = []
            while index < tokens.count,
                  englishIndexes.contains(index) {
                glossTokens.append(tokens[index])
                index += 1
            }
            var english = glossTokens.joined(separator: " ")
            if !english.isEmpty {
                let split = splitTrailingPunctuation(from: english)
                english = split.text
                danish += split.punctuation
            }
            result.append(
                BridgeDisplayUnit(
                    sourceIndex: sourceIndex,
                    danish: danish,
                    english: english.isEmpty ? nil : english
                )
            )
        }
        return result
    }

    private static func splitTrailingPunctuation(
        from value: String
    ) -> (text: String, punctuation: String) {
        var boundary = value.endIndex
        while boundary > value.startIndex {
            let candidate = value.index(before: boundary)
            let character = value[candidate]
            guard character.unicodeScalars.allSatisfy(
                CharacterSet.punctuationCharacters.contains
            ) else {
                break
            }
            boundary = candidate
        }
        return (
            String(value[..<boundary]),
            String(value[boundary...])
        )
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

enum KnowledgeTone {
    static func opacity(for level: Int) -> Double {
        switch min(max(level, 0), 5) {
        case 0: 1.00
        case 1: 0.95
        case 2: 0.90
        case 3: 0.85
        case 4: 0.80
        default: 0.74
        }
    }
}

private enum EnglishGlossTone {
    static func opacity(for level: Int) -> Double {
        switch min(max(level, 0), 2) {
        case 0: 0.94
        case 1: 0.84
        default: 0.74
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
