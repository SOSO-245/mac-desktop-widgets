import Foundation

/// The app requests refresh only for its currently matched HTTP subscription.
/// An attempt is persisted before the request, so failures/relaunches cannot loop.
enum SubscriptionRefreshPolicy {
    static let intervals = [0, 1800, 3600, 10800, 21600, 43200]
    static func interval(_ value: Int?) -> Int { value.flatMap { intervals.contains($0) ? $0 : nil } ?? 3600 }
    static func title(_ seconds: Int) -> String {
        seconds == 0 ? "关闭" : (seconds < 3600 ? "每 30 分钟" : "每 \(seconds / 3600) 小时")
    }
    static func due(now: Date, updated: Date?, attempted: Date?, interval: Int, manual: Bool = false) -> Bool {
        if let attempted, now.timeIntervalSince(attempted) < (manual ? 10 : 600) { return false }
        if manual { return true }
        guard interval > 0 else { return false }
        // Future upstream timestamps are ignored rather than suppressing refresh forever.
        let valid = [updated, attempted].compactMap { $0 }.filter { $0 <= now }
        return valid.max().map { now.timeIntervalSince($0) >= Double(interval) } ?? true
    }
    static func key(endpoint: String, provider: String) -> String {
        "subscriptionRefresh.attempt." + Data((endpoint + "|" + provider).utf8).base64EncodedString()
    }
}
