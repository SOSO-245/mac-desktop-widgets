import SwiftUI
import WidgetKit
import AppIntents

enum Bridge {
    static let session:URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration:configuration)
    }()
    static func fetch(refresh:Bool = false) async -> Snapshot {
        let key = "home-energy-snapshot"
        var previous = UserDefaults.standard.data(forKey:key).flatMap { try? JSONDecoder().decode(Snapshot.self,from:$0) } ?? Snapshot()
        do {
            let url = URL(string:"http://127.0.0.1:18763/v1/" + (refresh ? "refresh" : "snapshot"))!
            var request = URLRequest(url:url); request.timeoutInterval = refresh ? 18 : 4; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data,response) = try await session.data(for:request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let s = try JSONDecoder().decode(Snapshot.self,from:data)
            UserDefaults.standard.set(data,forKey:key)
            UserDefaults.standard.removeObject(forKey:"bridge-error")
            return s
        } catch {
            let problem = error as NSError
            UserDefaults.standard.set("\(problem.domain) \(problem.code)",forKey:"bridge-error")
            previous.title = "家庭概览"
            previous.connectionIssue = "等待家庭概览连接"
            return previous
        }
    }
}

struct RefreshEnergyIntent:AppIntent {
    static var title:LocalizedStringResource = "刷新家庭概览"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        _ = await Bridge.fetch(refresh:true)
        WidgetCenter.shared.reloadTimelines(ofKind:"HomeEnergyWidget")
        return .result()
    }
}

struct EnergyEntry:TimelineEntry { let date:Date; let snapshot:Snapshot }
struct EnergyProvider:TimelineProvider {
    func placeholder(in context:Context) -> EnergyEntry { EnergyEntry(date:Date(),snapshot:Snapshot()) }
    func getSnapshot(in context:Context,completion:@escaping(EnergyEntry)->Void) {
        if context.isPreview { completion(EnergyEntry(date:Date(),snapshot:.sample)); return }
        Task { completion(EnergyEntry(date:Date(),snapshot:await Bridge.fetch())) }
    }
    func getTimeline(in context:Context,completion:@escaping(Timeline<EnergyEntry>)->Void) {
        Task {
            let now = Date(), s = await Bridge.fetch()
            // A future entry invalidates the live badge without pretending to poll.
            var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:s.timezone) ?? .current
            let midnight = calendar.startOfDay(for:now).addingTimeInterval(86400)
            let entries = [EnergyEntry(date:now,snapshot:s),EnergyEntry(date:now.addingTimeInterval(180),snapshot:s),EnergyEntry(date:midnight,snapshot:s)]
            completion(Timeline(entries:entries.sorted { $0.date < $1.date },policy:.after(now.addingTimeInterval(900))))
        }
    }
}

struct EnergyWidgetView:View {
    let entry:EnergyEntry
    @Environment(\.widgetFamily) var family
    var body:some View {
        EnergyCard(snapshot:entry.snapshot,size:family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium),refresh:AnyView(
            Button(intent:RefreshEnergyIntent()) { Image(systemName:"arrow.clockwise").font(.system(size:10,weight:.semibold)) }.buttonStyle(.plain).accessibilityLabel("刷新 HA 数据")
        ),managementURL:URL(string:"homeenergy://settings"),websiteURL:URL(string:"homeenergy://website"),overviewURL:URL(string:"homeenergy://overview"),now:entry.date)
        .containerBackground(for:.widget) { EnergyBackground() }
        .widgetURL(URL(string:"homeenergy://overview"))
    }
}

@main struct HomeEnergyWidget:Widget {
    let kind = "HomeEnergyWidget"
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:EnergyProvider()) { EnergyWidgetView(entry:$0) }
            .configurationDisplayName("家庭概览")
            .description("家庭概览的桌面入口。点击主体查看完整概览，点击左上标题打开 HA 网页；大号包含车库、环境和 NAS。")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
            .contentMarginsDisabled()
            .containerBackgroundRemovable(false)
    }
}
