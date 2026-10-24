import Foundation
import CoreFoundation

enum ProxyClient: String {
    case nikki
    var title: String { "Nikki" }
    var appPath: String { Bundle.main.bundlePath }
}

struct MonitorSnapshot {
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

