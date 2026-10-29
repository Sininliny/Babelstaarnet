import AppKit
import BabelNews
import SwiftUI
import Translation
import UserNotifications

struct NewsView: View {
    @ObservedObject var news: NewsService
    @ObservedObject var translator: NewsTranslationQueue
    @ObservedObject var reader: NewsReadingSupport
    init(news: NewsService, translator: NewsTranslationQueue) { self.news = news; self.translator = translator; reader = news.reader }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Read something new").font(.title.bold())
                    Spacer()
                    SettingsLink { Label("News settings", systemImage: "gearshape") }.font(.caption)
                }
                Text("Read in Danish. Your help language replaces difficult words. Your familiar Danish stays, with just a little new everyday vocabulary. Select any word for help.").foregroundStyle(.secondary)
                if !news.preferences.enabled {
                    Toggle("DR news (internet)", isOn: Binding(get: { news.preferences.enabled }, set: { value in
                        news.configure(enabled: value, background: false, notify: false, topic: news.preferences.topic, hour: news.preferences.digestHour)
                        Task { await news.refresh() }
                    }))
                    Text(NewsService.disclosure).font(.caption).foregroundStyle(.secondary)
                } else {
                    DisclosureGroup("DR news · internet is on · privacy details") { Text(NewsService.disclosure).font(.caption).foregroundStyle(.secondary) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { topic; buttons }
                    VStack(alignment: .leading) { topic; buttons }
                }
                Text(news.status).font(.caption).foregroundStyle(.secondary)
                ForEach(news.cards) { card in NewsReadingCardView(news: news, card: card) }
                if news.cards.isEmpty && !news.busy { Text("No suitable new content yet. Try a different topic or come back later.").foregroundStyle(.secondary) }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        .translationTask(translator.configuration) { await translator.process(using: $0) }
        .task { news.pageVisible = true; await news.refresh() }
        .onDisappear { news.pageVisible = false; news.reader.cancel() }
    }
    private var topic: some View {
        Picker("Topic", selection: Binding(get: { news.preferences.topic }, set: { value in
            news.configure(enabled: news.preferences.enabled, background: news.preferences.background, notify: news.preferences.notify, topic: value, hour: news.preferences.digestHour)
            Task { await news.refresh(manual: true) }
        })) { ForEach(0..<NewsService.topics.count, id: \.self) { Text(NewsService.topics[$0]).tag($0) } }.frame(maxWidth: 230)
    }
    private var buttons: some View {
        HStack {
            Button(news.busy ? "Fetching…" : "Refresh") { Task { await news.refresh(manual: true) } }.disabled(!news.preferences.enabled || news.busy)
            Button("Another group") { news.nextGroup() }
            if news.hasUpdates { Button("Show new content") { news.acceptUpdates() } }
        }
    }
}

struct NewsReadingCardView: View {
    @ObservedObject var news: NewsService
    @ObservedObject var reader: NewsReadingSupport
    let card: NewsCard
    let compact: Bool
    init(news: NewsService, card: NewsCard, compact: Bool = false, reader: NewsReadingSupport? = nil) { self.news = news; self.reader = reader ?? news.reader; self.card = card; self.compact = compact }
    private var article: NewsArticle { card.article }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { Text("DR · " + article.publishedDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            Text("YOUR DANISH · HELP WHERE NEEDED").font(.caption2).foregroundStyle(.secondary)
            source(article.title, headline: !compact)
            if !article.summary.isEmpty {
                source(article.summary, headline: false)
            } else if !compact {
                Text("Headline only · DR did not include an excerpt.").font(.caption).foregroundStyle(.secondary)
            }
            if let state = reader.wordState(article) { Text(state).font(.caption).foregroundStyle(.secondary) }
            if reader.isVisible(article) {
                english(part: 0)
                if !article.summary.isEmpty { english(part: 1) }
                Button("Back to reading") { reader.hideTranslation(article) }.font(.caption)
            } else {
                Button("Help with this sentence") { Task { await reader.prepare(article, requested: true) } }.font(.caption)
            }
            if let word = reader.selected, word.articleKey == NewsReadingSupport.key(article) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.word).font(.headline)
                    if !word.meaning.isEmpty { Text(word.meaning).textSelection(.enabled) }
                    Text(word.status).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Listen to word", systemImage: "speaker.wave.2") { reader.speak?(word.word) }.disabled(reader.speak == nil)
                        Button(word.saved ? "Saved to Word Book" : "Save word", systemImage: word.saved ? "checkmark" : "plus") { reader.saveSelection(article: article) }.disabled(word.saved || word.meaning.isEmpty || reader.saveWord == nil)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if let text = news.simplifiedText(for: article) {
                Text("Simpler Danish · on-device AI · compare with the DR text above").font(.caption).foregroundStyle(.secondary)
                source(text, headline: false)
            }
            if let state = news.simplificationState(for: article) { Text(state).font(.caption).foregroundStyle(.secondary) }
            if !card.matches.isEmpty { Text("From your recent words: " + card.matches.joined(separator: " · ")).font(.caption).foregroundStyle(Color.accentColor) }
            if !compact {
            ViewThatFits(in: .horizontal) {
                HStack { readingActions }
                VStack(alignment: .leading) { readingActions }
            }
            HStack {
                Button("Full story · browser / internet") {
                    if article.valid, let url = URL(string: article.url) { NSWorkspace.shared.open(url); news.markSeen(article) }
                }
                Button("Already seen") { news.markSeen(article) }
            }.font(.caption)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .task(id: NewsReadingSupport.key(article)) { await reader.prepare(article) }
    }
    @ViewBuilder private var readingActions: some View {
        Button("Listen to headline", systemImage: "speaker.wave.2") { reader.speak?(article.title) }.disabled(reader.speak == nil)
        Button(article.summary.isEmpty ? "Simpler headline · local AI" : "Simpler excerpt · local AI") { Task { await news.simplify(article) } }
    }
    @ViewBuilder private func english(part: Int) -> some View {
        if let value = reader.meaning(article), value.parts.indices.contains(part) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SENTENCE HELP · ENGLISH · ON THIS DEVICE").font(.caption2).foregroundStyle(.secondary)
                Text(value.parts[part]).textSelection(.enabled)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        } else if part == 0 {
            VStack(alignment: .leading, spacing: 5) {
                Text(reader.state(article) ?? "Preparing sentence help on this device…").font(.caption).foregroundStyle(.secondary)
                Button("Try sentence help again") { Task { await reader.prepare(article, requested: true) } }.font(.caption)
            }
        }
    }
    private func source(_ text: String, headline: Bool) -> some View {
        InlineTokenLayout(spacing: 4, lineSpacing: 5) {
            ForEach(Array(NewsReadingSupport.pieces(text).enumerated()), id: \.offset) { _, piece in
                if let word = NewsReadingSupport.word(piece) {
                    Button { Task { await reader.lookup(word, article: article, context: text) } } label: {
                        let display = reader.presentation(piece, article: article)
                        Text(display.text).font(headline ? .title3.weight(.semibold) : .body)
                            .foregroundStyle(display.mode == 2 ? Color.accentColor : Color.primary)
                            .underline(display.mode == 2)
                            .padding(.horizontal, 3).padding(.vertical, 3)
                            .background(display.mode == 1 ? Color.secondary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 3))
                    }.buttonStyle(.plain).help("Meaning of " + word).accessibilityLabel("Look up Danish word " + word)
                } else { Text(piece).font(headline ? .title3.weight(.semibold) : .body) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NewsSettings: View {
    @ObservedObject var news: NewsService
    private func set(_ enabled: Bool? = nil, background: Bool? = nil, notify: Bool? = nil, hour: Int? = nil) {
        news.configure(enabled: enabled ?? news.preferences.enabled, background: background ?? news.preferences.background,
            notify: notify ?? news.preferences.notify, topic: news.preferences.topic, hour: hour ?? news.preferences.digestHour)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("News recommendations (internet)", isOn: Binding(get: { news.preferences.enabled }, set: { value in set(value); Task { await news.refresh() } }))
            Text(NewsService.disclosure).font(.caption).foregroundStyle(.secondary)
            Toggle("Background refresh", isOn: Binding(get: { news.preferences.background }, set: { set(background: $0) })).disabled(!news.preferences.enabled)
            Divider()
            Toggle("Scheduled adapted news cards", isOn: Binding(get: { news.popupPreferences.enabled }, set: { news.configurePopups(enabled: $0, interval: news.popupPreferences.intervalMinutes) }))
                .disabled(!news.preferences.enabled || !news.preferences.background)
            Picker("Show a card every", selection: Binding(get: { news.popupPreferences.intervalMinutes }, set: { news.configurePopups(enabled: news.popupPreferences.enabled, interval: $0) })) {
                Text("1 hour").tag(60); Text("2 hours").tag(120); Text("4 hours").tag(240)
            }.frame(maxWidth: 250)
            Text("While the app runs · 09:00–21:00 · at most 3 cards a day. No catch-up queue, sound or focus stealing. Reading takes priority. Enable background refresh above to schedule cards.").font(.caption).foregroundStyle(.secondary)
            Text("Each card uses installed local AI to simplify DR text, with your help language for difficult words and a little new Danish. No local AI means no scheduled cards; the original remains in Word Book.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Try a card now") { Task { await news.refresh(manual: true); await news.tickPopup(preview: true) } }.disabled(!news.preferences.enabled)
                if news.popupsPaused { Button("Resume news cards") { news.pausePopupsForToday(false) } }
            }
            Text(news.popupsPaused ? "News cards are paused for today." : news.popupStatus).font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Daily headline notification · alternative to cards", isOn: Binding(get: { news.preferences.notify }, set: { value in
                if !value { set(notify: false); UNUserNotificationCenter.current().removeAllPendingNotificationRequests(); return }
                Task {
                    let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true
                    if news.preferences.enabled && news.preferences.background { set(notify: allowed) }
                }
            })).disabled(!news.preferences.enabled || !news.preferences.background)
            Picker("Digest time", selection: Binding(get: { news.preferences.digestHour }, set: { set(hour: $0) })) {
                ForEach(9..<21, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
            }.frame(maxWidth: 220)
            Text("Enabling this notification turns scheduled cards off. At most one daily digest. Quiet hours 21:00–09:00; no notification while reading. Turning news off also turns background refresh and notifications off.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
