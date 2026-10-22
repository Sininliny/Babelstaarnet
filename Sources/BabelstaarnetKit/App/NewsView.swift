import AppKit
import BabelNews
import SwiftUI
import UserNotifications

struct NewsView: View {
    @ObservedObject var news: NewsService
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Read something new").font(.title.bold())
                Text("DR news · optional internet feature. Recent learning helps choose fresh content on this Mac.").foregroundStyle(.secondary)
                NewsSettings(news: news)
                HStack {
                    Picker("Topic", selection: Binding(get: { news.preferences.topic }, set: { value in
                        news.configure(enabled: news.preferences.enabled, background: news.preferences.background, notify: news.preferences.notify, topic: value, hour: news.preferences.digestHour)
                        Task { await news.refresh(manual: true) }
                    })) { ForEach(0..<NewsService.topics.count, id: \.self) { Text(NewsService.topics[$0]).tag($0) } }.frame(maxWidth: 240)
                    Button(news.busy ? "Fetching…" : "Refresh") { Task { await news.refresh(manual: true) } }.disabled(!news.preferences.enabled || news.busy)
                    Button("Another group") { news.nextGroup() }
                }
                Text(news.status).font(.caption).foregroundStyle(.secondary)
                ForEach(news.cards) { card in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.article.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text("DR · " + card.article.publishedDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if !card.article.summary.isEmpty { Text(card.article.summary).textSelection(.enabled) }
                        if !card.matches.isEmpty { Text("Title / summary includes: " + card.matches.joined(separator: " · ")).font(.caption).foregroundStyle(Color.accentColor) }
                        HStack {
                            Button("Read original · browser / internet") {
                                if card.article.valid, let url = URL(string: card.article.url) { NSWorkspace.shared.open(url); news.markSeen(card.article) }
                            }
                            Button("Already seen") { news.markSeen(card.article) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
                if news.cards.isEmpty && !news.busy { Text("No suitable new content yet. Try a different topic or come back later.").foregroundStyle(.secondary) }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.task { await news.refresh() }
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
