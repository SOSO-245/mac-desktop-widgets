import Foundation
import SQLite3

enum ProxyClient: String, CaseIterable {
    case flclash, shadowrocket
    var title: String { self == .flclash ? "FlClash" : "Shadowrocket" }
    var appPath: String { "/Applications/\(title).app" }
    var other: ProxyClient { self == .flclash ? .shadowrocket : .flclash }
}

struct MonitorSnapshot {
    var client: ProxyClient = .flclash
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
    var connectionState = "正在连接 FlClash"
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

struct ActiveSubscription {
    let id: String
    let name: String
    let usedBytes: Double?
    let totalBytes: Double?
    let expiresAt: Date?
    let updatedAt: Date?
    let currentGroup: String?
    let selected: [String: String]

    static func decode(configuration: [String: Any]) -> ActiveSubscription? {
        // Never fall back to the first profile; it may be inactive or deleted.
        guard let id = identifier(configuration["currentProfileId"]),
              let profiles = configuration["profiles"] as? [[String: Any]],
              let profile = profiles.first(where: { identifier($0["id"]) == id }) else { return nil }
        let info = profile["subscriptionInfo"] as? [String: Any] ?? [:]
        let upload = nonnegative(info["upload"])
        let download = nonnegative(info["download"])
        let used = upload.flatMap { up in download.flatMap { down -> Double? in
            let sum = up + down
            return sum.isFinite ? sum : nil
        } }
        let total = nonnegative(info["total"]).flatMap { $0 > 0 ? $0 : nil }
        let expiry = nonnegative(info["expire"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        let rawDate = profile["lastUpdateDate"] as? String
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var updated = rawDate.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        if updated == nil, let rawDate {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = .current
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            updated = local.date(from: rawDate)
        }
        if let timestamp = profile["updatedAtUnix"] as? Double, timestamp.isFinite, timestamp > 0 {
            updated = Date(timeIntervalSince1970: timestamp)
        }
        return ActiveSubscription(id: id, name: (profile["label"] as? String) ?? "当前套餐",
                                  usedBytes: used, totalBytes: total, expiresAt: expiry,
                                  updatedAt: updated, currentGroup: profile["currentGroupName"] as? String,
                                  selected: profile["selectedMap"] as? [String: String] ?? [:])
    }

    private static func identifier(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
    private static func nonnegative(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
}

enum FlClashPreferences {
    static func read() throws -> [String: Any] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.follow.clash.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
        guard let values = plist as? [String: Any], let text = values["flutter.config"] as? String,
              let bytes = text.data(using: .utf8),
              let config = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.follow.clash/database.sqlite")
        return try addingDatabaseProfile(to: config, database: database)
    }

    static func addingDatabaseProfile(to configuration: [String: Any], database: URL) throws -> [String: Any] {
        // Old versions embed profiles. New versions keep only the selected ID here.
        if configuration["profiles"] != nil { return configuration }
        var config = configuration
        config["profiles"] = [[String: Any]]()
        guard let rawID = configuration["currentProfileId"],
              let id = Int64(String(describing: rawID)) else { return config }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?
        // Never select subscription URLs, passwords or node secrets.
        let sql = "SELECT id,label,current_group_name,last_update_date,subscription_info,selected_map FROM profiles WHERE id=? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return config }
        guard result == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                  sqlite3_column_bytes(statement, column) <= 1_048_576,
                  let value = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: value)
        }
        func object(_ column: Int32) -> Any? {
            guard let bytes = text(column)?.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: bytes)
        }
        var profile: [String: Any] = ["id": String(sqlite3_column_int64(statement, 0)),
                                     "label": text(1) ?? "当前套餐"]
        profile["currentGroupName"] = text(2)
        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
            profile["updatedAtUnix"] = Double(sqlite3_column_int64(statement, 3))
        }
        profile["subscriptionInfo"] = object(4)
        profile["selectedMap"] = object(5)
        config["profiles"] = [profile]
        return config
    }
}

enum FlClashAuthorization {
    static func apply(to request: URLRequest, secret: String) throws -> URLRequest {
        guard let url = request.url, ["http", "ws"].contains(url.scheme ?? ""),
              url.host == "127.0.0.1", url.port == 9090,
              url.user == nil, url.password == nil,
              secret.utf8.count <= 4096, !secret.contains("\r"), !secret.contains("\n") else {
            throw URLError(.badURL)
        }
        var request = request
        if !secret.isEmpty { request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization") }
        return request
    }
}
