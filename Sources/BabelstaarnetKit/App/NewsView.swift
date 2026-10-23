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
                Text("Fresh Danish, with English to help you read. Select any Danish word for its meaning, pronunciation or Word Book.").foregroundStyle(.secondary)
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
                Toggle("English support", isOn: Binding(get: { news.reader.showEnglish }, set: { news.reader.setEnglish($0) }))
                    .help("On by default. Turn it off to try Danish first; Show English is always available.")
                    .toggleStyle(.switch)
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
    init(news: NewsService, card: NewsCard) { self.news = news; self.reader = news.reader; self.card = card }
    private var article: NewsArticle { card.article }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DR · " + article.publishedDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            Text("DANISH · SELECT A WORD FOR HELP").font(.caption2).foregroundStyle(.secondary)
            source(article.title, headline: true)
            if reader.isVisible(article) { english(part: 0) }
            if !article.summary.isEmpty {
                source(article.summary, headline: false)
                if reader.isVisible(article) { english(part: 1) }
            } else {
                Text("Headline only · DR did not include an excerpt.").font(.caption).foregroundStyle(.secondary)
            }
            if !reader.isVisible(article) {
                Button("Show English") { Task { await reader.prepare(article, requested: true) } }
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
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .task(id: NewsReadingSupport.key(article) + (reader.showEnglish ? ":en" : ":da")) { await reader.prepare(article) }
    }
    @ViewBuilder private var readingActions: some View {
        Button("Listen to headline", systemImage: "speaker.wave.2") { reader.speak?(article.title) }.disabled(reader.speak == nil)
        Button(article.summary.isEmpty ? "Simpler headline · local AI" : "Simpler excerpt · local AI") { Task { await news.simplify(article) } }
    }
    @ViewBuilder private func english(part: Int) -> some View {
        if let value = reader.meaning(article), value.parts.indices.contains(part) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ENGLISH · ON THIS DEVICE").font(.caption2).foregroundStyle(.secondary)
                Text(value.parts[part]).textSelection(.enabled)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        } else if part == 0 {
            VStack(alignment: .leading, spacing: 5) {
                Text(reader.state(article) ?? "Preparing English on this device…").font(.caption).foregroundStyle(.secondary)
                Button("Try English again") { Task { await reader.prepare(article, requested: true) } }.font(.caption)
            }
        }
    }
    private func source(_ text: String, headline: Bool) -> some View {
        InlineTokenLayout(spacing: 4, lineSpacing: 5) {
            ForEach(Array(NewsReadingSupport.pieces(text).enumerated()), id: \.offset) { _, piece in
                if let word = NewsReadingSupport.word(piece) {
                    Button { Task { await reader.lookup(word, article: article) } } label: {
                        Text(piece).font(headline ? .title3.weight(.semibold) : .body)
                            .padding(.horizontal, 1).padding(.vertical, 2)
                            .background(card.matches.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 3))
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
            Toggle("Daily news digest · while this app runs", isOn: Binding(get: { news.preferences.notify }, set: { value in
                if !value { set(notify: false); UNUserNotificationCenter.current().removeAllPendingNotificationRequests(); return }
                Task {
                    let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true
                    if news.preferences.enabled && news.preferences.background { set(notify: allowed) }
                }
            })).disabled(!news.preferences.enabled || !news.preferences.background)
            Picker("Digest time", selection: Binding(get: { news.preferences.digestHour }, set: { set(hour: $0) })) {
                ForEach(9..<21, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
            }.frame(maxWidth: 220)
            Text("At most one daily digest. Quiet hours 21:00–09:00; no notification while reading. Turning news off also turns background refresh and notifications off.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
