import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if let hoverCard = state.hoverCard {
                hoverBubble(hoverCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: state.screenFrame.width,
            height: state.screenFrame.height
        )
        .animation(.easeOut(duration: 0.14), value: state.hoverCard)
    }

    @ViewBuilder
    private func hoverBubble(_ card: HoverCard) -> some View {
        let width: CGFloat = 300
        let height: CGFloat = card.explanationMode == .none ? 70 : 134
        if let globalCenter = OverlayLayout.hoverCenter(
            wordFrame: card.word.frame,
            estimatedSize: CGSize(width: width, height: height),
            screenFrame: card.word.screenFrame,
            obstacles: sourceFrames(for: card.word)
        ) {
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
                            .background(
                                .quaternary,
                                in: Capsule()
                            )
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if card.explanationMode != .none {
                    Divider().opacity(0.65)

                    Text(card.definition)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: width, alignment: .leading)
            .liquidGlassBubble(tint: .primary.opacity(0.04), cornerRadius: 14)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .position(localPoint(globalCenter))
        }
    }

    private func localPoint(_ globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - state.screenFrame.minX,
            y: state.screenFrame.maxY - globalPoint.y
        )
    }

    private func sourceFrames(for word: WordRegion) -> [CGRect] {
        if let line = state.regions.first(where: {
            $0.words.contains(where: { $0.id == word.id })
        }) {
            return [line.frame]
        }
        return [word.frame]
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
