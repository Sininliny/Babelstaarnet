import BabelCore
import LanguageDanish
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

/// The mark on the page saying which word the panels are answering about.
///
/// It is the same accent rule the sentence panel already draws under the word
/// it is pointing at, moved onto the page: one idiom for "this one", in the
/// only colour either panel uses to say it. Drawn over whatever the reader
/// happens to be reading rather than on a panel of known colour, it carries its
/// own glow — enough to survive a dark page, not enough to read as a highlight.
struct WordFocusMarkerView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        Group {
            if state.hoverCard != nil {
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(height: WordFocusMarker.thickness)
                    .shadow(
                        color: Color.accentColor.opacity(0.5),
                        radius: 3
                    )
                    .padding(.horizontal, WordFocusMarker.glow)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(BubbleTransition.appearance, value: state.hoverCard == nil)
    }
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

                Spacer(minLength: 0)

                // A word the profile counts as known has no English to show —
                // withholding it is the whole point of counting it as known.
                // The panel still has to answer: pointing at a familiar word
                // was returning a box containing three buttons and the word
                // itself, sitting on top of the line being read. Saying which
                // state the word is in is an answer, and the control above it
                // already offers the way back. It sits at the far edge of the
                // row, away from the Danish, so it reads as the word's state
                // rather than as the word's meaning.
                if card.wordEnglishMeaning == nil, card.wordIsKnown {
                    Text("Known")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
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
                knownAnimationTrigger: card.sentencePanelStandsAlone
                    ? state.knownAnimationID
                    : 0
            )

            if card.sentencePanelStandsAlone,
               card.wordKnowledgeLevel == 3,
               let wordEnglishMeaning = card.wordEnglishMeaning {
                Text(LearnerDisplayText.clean(wordEnglishMeaning))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if card.sentencePanelStandsAlone,
               let englishSupport = card.englishSupport {
                Text(LearnerDisplayText.clean(englishSupport))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // No controls here — they live permanently in the word panel, and
            // Knew and Don't know are about the word, not the sentence. The
            // confirmation appears here only when the word panel is switched
            // off: the shortcuts stay live in that configuration and there is
            // no button anywhere else to answer back. With both panels on it
            // was saying "Marked known" under a sentence while the word panel
            // was already confirming the same press.
            if card.sentencePanelStandsAlone {
                BridgeConfirmation(state: state)
            }
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
        // The narrow word bubble cannot always fit the controls on one line,
        // and a button that wraps mid-label reads as a layout accident.
        InlineTokenLayout(spacing: 6, lineSpacing: 5) {
            // No control ever changes width. The confirmation replaces the
            // shortcut key with a tick inside a slot that holds both at once,
            // so the button is the same size whether or not it is confirming:
            // swapping the whole label for "Marked known" more than doubled
            // this button and wrapped the row onto a second line, so acting on
            // the bubble resized it.
            Button {
                state.onKnown()
            } label: {
                BridgeControlLabel(
                    shortcut: card.knownShortcutLabel,
                    title: "Knew",
                    isConfirming: state.feedbackConfirmation == .markedKnown
                )
            }
            .buttonStyle(
                BridgeFeedbackButtonStyle(
                    isOn: state.feedbackConfirmation == .markedKnown
                )
            )

            Button {
                state.onDontKnow()
            } label: {
                BridgeControlLabel(
                    shortcut: card.dontKnowShortcutLabel,
                    title: "Don’t know",
                    isConfirming:
                        state.feedbackConfirmation == .englishRestored
                )
            }
            .buttonStyle(
                BridgeFeedbackButtonStyle(
                    isOn: state.feedbackConfirmation == .englishRestored
                )
            )

            Button {
                state.onTogglePin()
            } label: {
                BridgeControlLabel(
                    shortcut: card.pinShortcutLabel,
                    title: "Pin"
                )
            }
            .buttonStyle(BridgeFeedbackButtonStyle(isOn: state.isPinned))
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
/// A control's shortcut key and its name, with the key able to become a tick
/// without the control changing size.
///
/// Both the key and the tick are always laid out, one of them invisible, so the
/// slot they share is as wide as the wider of the two whatever the state is. A
/// row of four of these in a 280-point panel has no room to absorb a control
/// that grows when it is used.
private struct BridgeControlLabel: View {
    let shortcut: String
    let title: String
    var isConfirming = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Text(shortcut)
                    .opacity(isConfirming ? 0 : 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(isConfirming ? 1 : 0)
            }
            Text(title)
        }
    }
}

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
        InlineTokenLayout(spacing: 5, lineSpacing: 5) {
            ForEach(Array(displayUnits.enumerated()), id: \.offset) {
                _, unit in
                if let danish = unit.danish {
                    EncouragedDanishWord(
                        text: danish,
                        font: .system(size: 12, design: .rounded),
                        opacity: KnowledgeTone.opacity(
                            for: knowledgeLevels[unit.sourceIndex] ?? 0
                        ),
                        animationTrigger: unit.isFocus
                            ? knownAnimationTrigger
                            : 0
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .pointedAt(unit.isFocus)
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
                        .background {
                            // The tint is painted outside the token's own box.
                            // Padding it inside made every substituted run six
                            // points wider than the words beside it, so a line
                            // of running text was set with two different word
                            // spaces: the eye read a row of chips rather than a
                            // sentence, and the wider the reader's English, the
                            // more of the line was chips.
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.primary.opacity(marksSwaps ? 0.06 : 0))
                                .padding(.horizontal, -3)
                                .padding(.vertical, -1.5)
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        .pointedAt(unit.isFocus)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Whether marking the swapped words is worth anything on this line.
    ///
    /// The tint means "this word was swapped for you". Said about nearly every
    /// word — which is where every reader starts, and where they stay for a
    /// long while — it stops being a mark and becomes the background: a line of
    /// highlighter with two Danish words floating outside it, harder to read
    /// than the plain sentence underneath. So the mark is drawn only while
    /// substitutions are still the exception on the line, and it leaves the
    /// design on its own as the profile fills in and the Danish comes back.
    private var marksSwaps: Bool {
        let tokens = text.split(whereSeparator: \Character.isWhitespace).count
        guard tokens > 0 else {
            return false
        }
        return Double(englishTokenIndexes.count) / Double(tokens) <= 0.66
    }

    private var displayUnits: [BridgeDisplayUnit] {
        InterlinearBridgePresentation.units(
            text: text,
            englishTokenIndexes: englishTokenIndexes,
            focusTokenIndexes: focusTokenIndexes
        )
    }
}

struct BridgeDisplayUnit: Equatable {
    let sourceIndex: Int
    let danish: String?
    let english: String?
    /// Whether this unit is the word the pointer is resting on.
    let isFocus: Bool

    init(
        sourceIndex: Int,
        danish: String?,
        english: String?,
        isFocus: Bool = false
    ) {
        self.sourceIndex = sourceIndex
        self.danish = danish
        self.english = english
        self.isFocus = isFocus
    }
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
        englishTokenIndexes: [Int],
        focusTokenIndexes: [Int] = []
    ) -> [BridgeDisplayUnit] {
        let tokens = text
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        let englishIndexes = Set(englishTokenIndexes)
        let focusIndexes = Set(focusTokenIndexes)
        var result: [BridgeDisplayUnit] = []
        var index = 0
        while index < tokens.count {
            let start = index
            if englishIndexes.contains(index) {
                // A run also ends where the pointed-at word's English begins or
                // ends. Grouping adjacent English is about reading one Danish
                // word's answer as one thing, and the word being asked about is
                // exactly that: run it together with its neighbours and the
                // answer to the reader's question disappears into the middle of
                // a line with nothing marking it.
                let isFocus = focusIndexes.contains(index)
                var english: [String] = []
                while index < tokens.count,
                      englishIndexes.contains(index),
                      focusIndexes.contains(index) == isFocus {
                    english.append(tokens[index])
                    index += 1
                }
                result.append(
                    BridgeDisplayUnit(
                        sourceIndex: start,
                        danish: nil,
                        english: english.joined(separator: " "),
                        isFocus: isFocus
                    )
                )
                continue
            }
            result.append(
                BridgeDisplayUnit(
                    sourceIndex: start,
                    danish: tokens[index],
                    english: nil,
                    isFocus: focusIndexes.contains(index)
                )
            )
            index += 1
        }
        return result
    }
}

private extension View {
    /// Marks the word the pointer is resting on.
    ///
    /// The two panels answer the same question and had nothing tying them
    /// together: the sentence below repeated the word among thirty others, or
    /// replaced it with English somewhere in the middle of a line, and the
    /// reader had to find it before the answer meant anything. A rule under the
    /// word is enough to say "this one", and it is the only mark in the bubble
    /// that uses the accent colour, so nothing else competes with it.
    @ViewBuilder
    func pointedAt(_ isFocused: Bool) -> some View {
        if isFocused {
            overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.62))
                    .frame(height: 1.5)
                    .padding(.horizontal, -1)
                    .offset(y: 2.5)
            }
        } else {
            self
        }
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

    /// Words are placed on a shared baseline, not on a shared top edge.
    ///
    /// Aligning tops is only the same thing while every token is the same
    /// height, and they are not: a tinted English run and a plain Danish word
    /// measure differently, so the sentence was set with its words sitting a
    /// point or two above and below one another. At twelve points that is not
    /// subtle — it is the difference between a line of text and a row of
    /// separate labels — and it fell on exactly the words the reader was being
    /// asked to read as one sentence.
    private func measure(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint]) {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let baselines = subviews.indices.map { index in
            let dimensions = subviews[index].dimensions(in: .unspecified)
            let baseline = dimensions[.firstTextBaseline]
            // A subview with no text reports its own height here, which is the
            // right thing to sit on the baseline anyway.
            return baseline.isFinite ? baseline : sizes[index].height
        }

        var origins: [CGPoint] = Array(
            repeating: .zero,
            count: subviews.count
        )
        var row: [Int] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0

        func placeRow() {
            guard let baseline = row.map({ baselines[$0] }).max() else {
                return
            }
            for index in row {
                origins[index].y = y + baseline - baselines[index]
            }
            let depth = row
                .map { sizes[$0].height - baselines[$0] }
                .max() ?? 0
            y += baseline + depth
            row = []
        }

        for index in subviews.indices {
            let size = sizes[index]
            if x > 0, x + size.width > availableWidth {
                placeRow()
                y += lineSpacing
                x = 0
            }
            origins[index].x = x
            row.append(index)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }
        placeRow()

        return (
            CGSize(
                width: proposal.width ?? usedWidth,
                height: subviews.isEmpty ? 0 : y
            ),
            origins
        )
    }
}

/// How solid the ground under the bubble text is.
///
/// A panel that has to be read is read over whatever the page behind it
/// happens to be, and the hardest case is the ordinary one: a white article
/// under a system running in dark appearance. There the material alone put
/// grey text on grey, with the page's own black text showing through the panel
/// and interleaving with the sentence — two texts occupying the same rectangle.
///
/// So the text is given its own ground, painted inside the material rather than
/// instead of it: the glass still frames the panel and still belongs to the
/// desktop, while the words sit on the panel's own background colour, which is
/// dark under dark appearance and light under light. This is the one number to
/// turn if the panels ever want more of the page showing through them.
private enum BubbleGround {
    static let opacity: Double = 0.62
}

private extension View {
    func liquidGlassBubble(
        tint: Color,
        cornerRadius: CGFloat
    ) -> some View {
        background {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(BubbleGround.opacity)
            )
        }
        .bubbleMaterial(tint: tint, cornerRadius: cornerRadius)
    }

    @ViewBuilder
    private func bubbleMaterial(
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
        // Regular rather than ultra-thin: this panel carries the text the
        // reader came for, and ultra-thin is a wash for chrome sitting over
        // content, not a surface to set a sentence on.
        background(
            .regularMaterial,
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
