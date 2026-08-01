import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Group {
            if let hoverCard = state.hoverCard {
                hoverBubble(hoverCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.14), value: state.hoverCard)
    }

    @ViewBuilder
    private func hoverBubble(_ card: HoverCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.word.sourceText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if card.translationMode == .english {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Text(card.word.translatedText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                if let badgeTitle = card.explanationMode.badgeTitle {
                    Text(badgeTitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Spacer(minLength: 0)

                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if card.explanationMode != .none {
                Divider().opacity(0.65)

                if card.explanationMode == .adaptive {
                    Text(card.definition)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(card.definition)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let englishSupport = card.englishSupport {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("EN")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)

                        Text(englishSupport)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if card.explanationMode == .adaptive {
                    Divider().opacity(0.45)

                    HStack(spacing: 10) {
                        Button("1  Knew") {
                            state.onKnown()
                        }

                        Button(
                            card.englishIsExpanded
                                ? "2  Explained"
                                : "2  Don’t know"
                        ) {
                            state.onDontKnow()
                        }
                        .disabled(card.englishIsExpanded)

                        Text(state.isPinned ? "3  Unpin" : "3  Pin")

                        Spacer(minLength: 0)

                        if let familiarityLabel = card.familiarityLabel {
                            Text(familiarityLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(
                            systemName: state.isOptionHeld
                                ? "pin.fill"
                                : "option"
                        )
                        Text(
                            state.isOptionHeld
                                ? "Held open while Option is down"
                                : (state.isPinned
                                    ? "Pinned · press 3 to release"
                                    : state.isStationaryHeld
                                        ? "Held only while there is no input"
                                        : "Stay still, hold Option, or press 3")
                        )
                    }
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(
            width: HoverBubbleMetrics.width,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlassBubble(tint: .primary.opacity(0.04), cornerRadius: 14)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
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
