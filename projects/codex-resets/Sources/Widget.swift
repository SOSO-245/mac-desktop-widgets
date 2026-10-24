import SwiftUI
import WidgetKit
import AppIntents

struct RefreshResetsIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新重置公告"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        _ = await ResetClient.load(force: true)
        WidgetCenter.shared.reloadTimelines(ofKind: resetsWidgetKind)
        return .result()
    }
}
struct ResetEntry: TimelineEntry { let date: Date; let snapshot: ResetSnapshot }
struct ResetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResetEntry { ResetEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (ResetEntry) -> Void) {
        if context.isPreview { completion(ResetEntry(date: Date(), snapshot: .sample)); return }
        Task { completion(ResetEntry(date: Date(), snapshot: await ResetClient.load())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ResetEntry>) -> Void) {
        Task {
            let snapshot = await ResetClient.load()
            let now = Date()
            let dates = ResetTimelineDates.dates(now: now, snapshot: snapshot, showClock: context.family != .systemSmall)
            let entries = dates.map { ResetEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}
struct ResetWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ResetEntry
    private var size: CardSize { family == .systemSmall ? .small : family == .systemLarge ? .large : .medium }
    var body: some View {
        ResetCard(snapshot: entry.snapshot, size: size, now: entry.date, refresh: AnyView(
            Button(intent: RefreshResetsIntent()) { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)).frame(width: 17, height: 17) }
                .buttonStyle(.plain).accessibilityLabel("刷新重置公告")
        ))
        .containerBackground(for: .widget) { ResetBackground() }
        .widgetURL(ResetNavigation.widgetURL)
    }
}
@main
struct CodexResetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: resetsWidgetKind, provider: ResetProvider()) { ResetWidgetView(entry: $0) }
            .configurationDisplayName("Codex 重置")
            .description("追踪 Codex Resets 的重置公告、计划倒计时和历史。非个人账户额度。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
            .containerBackgroundRemovable(false)
    }
}
