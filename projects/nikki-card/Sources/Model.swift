import Foundation
import CoreFoundation

enum ProxyClient: String, Codable {
    case nikki
    var title: String { "Nikki" }
    var appPath: String { Bundle.main.bundlePath }
}

enum TrafficScope: String, CaseIterable, Codable {
    case all, proxyOnly
    var title: String { self == .all ? "代理＋直连" : "仅代理" }
    static func load() -> TrafficScope {
        TrafficScope(rawValue: UserDefaults.standard.string(forKey: "nikkiTrafficScope") ?? "") ?? .all
    }
}

struct MonitorSnapshot: Codable {
    // Optional storage keeps previous widget cache snapshots decodable.
    var trafficScopeSelection: TrafficScope?
    var trafficScope: TrafficScope {
        get { trafficScopeSelection ?? .all }
        set { trafficScopeSelection = newValue }
    }
    var trafficLabel: String { trafficScope.title }
    var trafficHint: String {
        trafficScope == .all ? "Nikki 核心处理的代理与直连流量，不包含绕过核心的流量。"
            : "按每秒活动连接采样，排除直连与拒绝连接；短连接可能漏计，为近似速率，不是套餐计费用量。"
    }

    var client: ProxyClient = .nikki
    var routeIdentity = ""
    var profileName: String?
    var usedBytes: Double?
    var totalBytes: Double?
    var expiresAt: Date?
    var subscriptionUpdatedAt: Date?
    var nodeName: String?
    var metadataIssue: String?
    var groupName: String?
    var latencyMS: Int?
    var latencyIsLive = false
    var latencyKind = "最近测速"
    var uploadBps: Double?
    var downloadBps: Double?
    var connectionCount: Int?
    var connectionState = "等待连接 Nikki"
    var isConnected = false
    var isRunning = false
    var sampledAt: Date?
    var speedHistory: [Double] = []
    var uploadSpeedHistory: [Double] = []
}

enum SubscriptionCountdown {
    static func text(expiry: Date?, now: Date = Date()) -> String {
        guard let expiry else { return "到期时间未知" }
        let seconds = expiry.timeIntervalSince(now)
        guard seconds.isFinite else { return "到期时间未知" }
        guard seconds > 0 else { return "套餐已到期" }
        if seconds >= 86400 { return "距到期 \(Int(seconds / 86400)) 天" }
        if seconds >= 3600 { return "距到期 \(Int(seconds / 3600)) 小时" }
        return "距到期 \(max(1,Int(ceil(seconds / 60)))) 分钟"
    }
}


enum ConnectionMetrics {
    static func count(_ payload:[String:Any]?) -> Int? {
        (payload?["connections"] as? [[String:Any]])?.count
    }
}
