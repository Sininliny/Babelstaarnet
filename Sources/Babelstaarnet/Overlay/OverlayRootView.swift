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

            Text(LearnerDisplayText.clean(card.word.sourceText))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            SentenceBridgeText(
                text: LearnerDisplayText.clean(card.wordBridgeText),
                englishTokenIndexes:
                    card.wordBridgeEnglishTokenIndexes
            )

            if let englishSupport = card.englishSupport {
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
                englishTokenIndexes: card.adaptiveEnglishTokenIndexes
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
            Button("\(card.knownShortcutLabel)  Knew") {
                state.onKnown()
            }

            Button("\(card.dontKnowShortcutLabel)  Don’t know") {
                state.onDontKnow()
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

    var body: some View {
        let englishIndexes = Set(englishTokenIndexes)
        InlineTokenLayout(spacing: 3, lineSpacing: 3) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                if englishIndexes.contains(index) {
                    Text(token)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    .secondary.opacity(0.45),
                                    lineWidth: 0.6
                                )
                        }
                } else {
                    Text(token)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tokens: [String] {
        text.split(whereSeparator: \Character.isWhitespace).map(String.init)
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
