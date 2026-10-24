import AppKit
import Combine
import Foundation


enum CardSize: String, CaseIterable {
    case small, medium, large
    var title: String { switch self { case .small: return "小号"; case .medium: return "中号"; case .large: return "大号" } }
    var dimensions: CGSize { switch self {
    case .small: return CGSize(width: 220, height: 164)
    case .medium: return CGSize(width: 344, height: 164)
    case .large: return CGSize(width: 344, height: 344)
    } }
}

struct ProbeSite: Identifiable {
    let id: String
    let url: String
    let mark: String
    static func icon(_ id: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "SiteIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 15, height: 15)
        image.isTemplate = false
        return image
    }
    static let all: [ProbeSite] = [
        .init(id: "Google", url: "https://www.google.com/", mark: "G"),
        .init(id: "GitHub", url: "https://github.com/", mark: "GH"),
        .init(id: "YouTube", url: "https://www.youtube.com/", mark: "▶"),
        .init(id: "ChatGPT", url: "https://chatgpt.com/", mark: "◎"),
        .init(id: "Claude", url: "https://claude.ai/", mark: "✳"),
        .init(id: "bilibili", url: "https://www.bilibili.com/", mark: "B")
    ]
}

struct SiteReading {
    var milliseconds: Int?
    var status = "待检测"
    var httpCode: Int?
    var checkedAt: Date?
    var busy = false
    var reachable: Bool { milliseconds != nil }
    func refreshing(at now:Date = Date()) -> SiteReading {
        guard let checkedAt, (0...120).contains(now.timeIntervalSince(checkedAt)) else { return SiteReading(busy:true) }
        var value = self; value.busy = true; return value
    }
    static func decode(output: String, exitCode: Int32, at date: Date = Date()) -> SiteReading {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        let code = parts.first.flatMap { Int($0) } ?? 0
        let seconds = parts.count > 1 ? Double(parts[1]) : nil
        let ms = seconds.flatMap { $0.isFinite && $0 > 0 && $0 < 60 ? max(1, Int(($0 * 1000).rounded())) : nil }
        if exitCode != 0 {
            return SiteReading(status: exitCode == 28 ? "超时" : [35, 60].contains(exitCode) ? "TLS 错误" : "连接失败", checkedAt: date)
        }
        guard (100...599).contains(code), let ms else { return SiteReading(status: "无响应", checkedAt: date) }
        let status = (200..<400).contains(code) ? "响应" : [401, 403, 429, 451].contains(code) ? "受限" : "HTTP \(code)"
        return SiteReading(milliseconds: ms, status: status, httpCode: code, checkedAt: date)
    }
}


@MainActor
final class SiteLatencyMonitor: ObservableObject {
    @Published private(set) var readings: [String: SiteReading] = [:]
    @Published private(set) var routeLabel = "Nikki 策略组测速"
    weak var monitor: MonitorCoordinator?
    private var large = false, connected = false
    private var menuSite = "Google", identity = ""
    private var timer: Task<Void,Never>?, round: Task<Void,Never>?
    private var generation = UUID()
    func configure(large: Bool, menuSite: String, snapshot: MonitorSnapshot) {
        let key = snapshot.routeIdentity + "|\(snapshot.isConnected)|\(large)|\(menuSite)"
        self.large = large; self.menuSite = menuSite; self.connected = snapshot.isConnected
        guard key != identity else { return }
        identity = key; stop(); refresh()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:60_000_000_000) } catch { return }
                self?.refresh()
            }
        }
    }
    func stop() { generation = UUID(); round?.cancel(); timer?.cancel(); round = nil; timer = nil; readings = [:] }
    func refresh(siteID: String? = nil) {
        guard round == nil, connected, let monitor, let api = monitor.api else { return }
        let token = generation
        let sites = ProbeSite.all.filter { siteID != nil ? $0.id == siteID : large || $0.id == menuSite }
        let mapped = ["Google":"Google", "GitHub":"GitHub", "YouTube":"YouTube", "ChatGPT":"AI", "Claude":"AI", "bilibili":"DIRECT"]
        let routes = Dictionary(uniqueKeysWithValues: sites.map { site -> (String,String) in
            let proposed = mapped[site.id] ?? monitor.settings.group
            return (site.id, monitor.proxies[proposed] != nil ? proposed : monitor.settings.group)
        })
        routeLabel = "Nikki · 按同名策略组检测，AI 共用 AI 组，bilibili 直连"
        round = Task {
            // Sequential requests avoid router load spikes. No selector is changed.
            for site in sites {
                guard generation == token, !Task.isCancelled else { return }
                readings[site.id] = (readings[site.id] ?? SiteReading()).refreshing()
                do {
                    let value = try await api.json(["proxies",routes[site.id]!,"delay"], query:[URLQueryItem(name:"url",value:site.url), URLQueryItem(name:"timeout",value:"8000")])
                    guard generation == token, !Task.isCancelled else { return }
                    if let ms = NikkiData.number(value["delay"]), ms > 0, ms < 60000 {
                        readings[site.id] = SiteReading(milliseconds:Int(ms),status:"响应 · \(routes[site.id]!)",checkedAt:Date())
                    } else { readings[site.id] = SiteReading(status:"无有效延迟",checkedAt:Date()) }
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    // Mihomo does not expose the site's HTTP status: never infer unlock/access status.
                    let timeout = (error as? URLError)?.code == .timedOut
                    readings[site.id] = SiteReading(status:timeout ? "超时" : "检测失败",checkedAt:Date())
                }
            }
            if generation == token { round = nil }
        }
    }
}
