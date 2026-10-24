import Foundation
import SQLite3

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private func profile(id: Any, label: String = "示例套餐", upload: Any = 120,
                     download: Any = 380, total: Any = 2000) -> [String: Any] {
    ["id": id, "label": label,
     "subscriptionInfo": ["upload": upload, "download": download, "total": total, "expire": 1_900_000_000],
     "lastUpdateDate": "2026-10-23T08:09:10.123456",
     "currentGroupName": "示例选择组", "selectedMap": ["示例选择组": "示例节点"]]
}

private func active(_ profile: [String: Any], currentID: Any = "active") -> ActiveSubscription? {
    ActiveSubscription.decode(configuration: ["currentProfileId": currentID, "profiles": [profile]])
}

@main
private enum ModelTests {
    static func main() throws {
        var passed = 0
        func run(_ name: String, _ operation: () throws -> Void) throws {
            try operation()
            passed += 1
            print("PASS \(name)")
        }

        try run("Current profile ID selects the active subscription, never array order") {
            let profiles = [profile(id: "inactive", label: "未激活套餐", upload: 1, download: 2),
                            profile(id: "active", label: "激活套餐", upload: 100, download: 400)]
            let selected = ActiveSubscription.decode(configuration: ["currentProfileId": "active", "profiles": profiles])
            try check(selected?.id == "active" && selected?.name == "激活套餐" && selected?.usedBytes == 500,
                      "An inactive first profile was selected")
            try check(selected?.currentGroup == "示例选择组" && selected?.selected["示例选择组"] == "示例节点",
                      "Group selection must belong to the active profile")
        }
        try run("Switching the current profile replaces its usage and selection") {
            var first = profile(id: "first", label: "套餐甲", upload: 10, download: 20, total: 100)
            first["selectedMap"] = ["组甲": "节点甲"]
            first["currentGroupName"] = "组甲"
            var second = profile(id: "second", label: "套餐乙", upload: 200, download: 300, total: 900)
            second["selectedMap"] = ["组乙": "节点乙"]
            second["currentGroupName"] = "组乙"
            var config: [String: Any] = ["currentProfileId": "first", "profiles": [first, second]]
            let before = ActiveSubscription.decode(configuration: config)
            config["currentProfileId"] = "second"
            let after = ActiveSubscription.decode(configuration: config)
            try check(before?.name == "套餐甲" && before?.usedBytes == 30 && before?.totalBytes == 100,
                      "Initial active package is incorrect")
            try check(after?.name == "套餐乙" && after?.usedBytes == 500 && after?.totalBytes == 900,
                      "Switching retained usage from the previous package")
            try check(after?.currentGroup == "组乙" && after?.selected == ["组乙": "节点乙"],
                      "Switching retained proxy selection from the previous package")
        }
        try run("Numeric and string profile IDs match consistently") {
            try check(active(profile(id: 42), currentID: "42")?.id == "42", "String selection cannot match numeric ID")
            try check(active(profile(id: "42"), currentID: 42)?.id == "42", "Numeric selection cannot match string ID")
            try check(active(profile(id: "042"), currentID: 42) == nil, "Distinct string identifiers were collapsed")
        }
        try run("Missing, deleted and malformed profile selections never fall back") {
            let candidate = profile(id: "first")
            let invalid: [[String: Any]] = [
                [:], ["profiles": [candidate]],
                ["currentProfileId": "missing", "profiles": [candidate]],
                ["currentProfileId": NSNull(), "profiles": [candidate]],
                ["currentProfileId": ["first"], "profiles": [candidate]],
                ["currentProfileId": "first", "profiles": []],
                ["currentProfileId": "first", "profiles": "invalid"],
                ["currentProfileId": "first", "profiles": [["label": "无 ID 套餐"]]],
            ]
            for config in invalid {
                try check(ActiveSubscription.decode(configuration: config) == nil, "Invalid selection fabricated an active profile")
            }
        }
        try run("Usage adds both upload and download without clamping to quota") {
            let selected = active(profile(id: "active", upload: 1500, download: 750, total: 2000))
            try check(selected?.usedBytes == 2250 && selected?.totalBytes == 2000,
                      "Usage must add upload and download, including over-quota usage")
            try check(active(profile(id: "active", upload: 0, download: 0))?.usedBytes == 0,
                      "A valid zero usage sample became unavailable")
        }
        try run("Missing or malformed traffic remains unavailable") {
            var candidate = profile(id: "active")
            candidate.removeValue(forKey: "subscriptionInfo")
            var selected = active(candidate)
            try check(selected != nil && selected?.usedBytes == nil && selected?.totalBytes == nil && selected?.expiresAt == nil,
                      "A profile without subscription statistics must remain selected without invented usage")
            let incompleteInfo: [[String: Any]] = [["upload": 12], ["download": 20], ["upload": "12", "download": 20],
                                                 ["upload": 12, "download": NSNull()]]
            for info in incompleteInfo {
                candidate["subscriptionInfo"] = info
                selected = active(candidate)
                try check(selected?.usedBytes == nil, "Incomplete traffic was treated as a complete usage total")
            }
            candidate["subscriptionInfo"] = "invalid"
            try check(active(candidate)?.usedBytes == nil, "Malformed subscription metadata fabricated usage")
        }
        try run("Zero, negative and nonfinite quotas do not become a usable denominator") {
            for total in [0.0, -1.0, Double.nan, Double.infinity] {
                let selected = active(profile(id: "active", total: total))
                try check(selected?.usedBytes == 500 && selected?.totalBytes == nil,
                          "Invalid quota should hide progress while retaining known usage")
            }
        }
        try run("Negative and nonfinite traffic do not produce valid usage") {
            for invalid in [-1.0, Double.nan, Double.infinity] {
                try check(active(profile(id: "active", upload: invalid))?.usedBytes == nil,
                          "Invalid upload was accepted")
                try check(active(profile(id: "active", download: invalid))?.usedBytes == nil,
                          "Invalid download was accepted")
            }
        }
        try run("Boolean subscription values are not treated as numeric zero or one") {
            for value in [true, false] {
                try check(active(profile(id: "active", upload: value))?.usedBytes == nil,
                          "Boolean upload became numeric usage")
                try check(active(profile(id: "active", download: value))?.usedBytes == nil,
                          "Boolean download became numeric usage")
                try check(active(profile(id: "active", total: value))?.totalBytes == nil,
                          "Boolean quota became a progress denominator")
                var candidate = profile(id: "active")
                candidate["subscriptionInfo"] = ["upload": 0, "download": 0, "total": 10, "expire": value]
                try check(active(candidate)?.expiresAt == nil, "Boolean expiry became a timestamp")
            }
        }
        try run("Adding finite counters cannot overflow into an infinite usage total") {
            let limit = Double.greatestFiniteMagnitude
            try check(active(profile(id: "active", upload: limit, download: limit))?.usedBytes == nil,
                      "Overflowed usage became a valid infinite counter")
            try check(active(profile(id: "active", upload: limit, download: 0))?.usedBytes == limit,
                      "A large but finite usage total was incorrectly rejected")
        }
        try run("Expiry is a Unix timestamp; zero and invalid expiry remain absent") {
            var candidate = profile(id: "active")
            let selected = active(candidate)
            try check(selected?.expiresAt == Date(timeIntervalSince1970: 1_900_000_000), "Expiry timestamp was shifted")
            let invalidExpiry: [Any] = [0, -1, Double.nan, Double.infinity, "1900000000", NSNull()]
            for value in invalidExpiry {
                candidate["subscriptionInfo"] = ["upload": 0, "download": 0, "total": 10, "expire": value]
                try check(active(candidate)?.expiresAt == nil, "Invalid expiry became a date")
            }
        }
        try run("Explicit date offsets preserve the absolute update time") {
            var candidate = profile(id: "active")
            candidate["lastUpdateDate"] = "2026-10-23T08:09:10+08:00"
            let offsetDate = active(candidate)?.updatedAt
            candidate["lastUpdateDate"] = "2026-10-23T00:09:10Z"
            let utcDate = active(candidate)?.updatedAt
            try check(offsetDate != nil && offsetDate == utcDate, "Timezone offsets changed the update instant")
            candidate["lastUpdateDate"] = "2026-10-23T00:09:10.125Z"
            try check(abs((active(candidate)?.updatedAt?.timeIntervalSince(utcDate!) ?? 100) - 0.125) < 0.001,
                      "Fractional ISO timestamp was lost")
        }
        try run("A timestamp without Z uses the Mac local timezone") {
            let selected = active(profile(id: "active"))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 8, minute: 9, second: 10))!
            try check(selected?.updatedAt != nil && abs(selected!.updatedAt!.timeIntervalSince(expected) - 0.123456) < 0.001,
                      "Local update timestamp was interpreted as UTC or lost")
        }
        try run("Invalid dates and optional selection metadata remain absent") {
            var candidate = profile(id: "active")
            candidate["lastUpdateDate"] = "invalid date"
            candidate.removeValue(forKey: "label")
            candidate.removeValue(forKey: "currentGroupName")
            candidate["selectedMap"] = ["组": 12]
            let selected = active(candidate)
            try check(selected?.updatedAt == nil && selected?.name == "当前套餐" && selected?.currentGroup == nil
                      && selected?.selected.isEmpty == true, "Optional invalid metadata was fabricated")
        }

        try run("Traffic stream decodes byte rates, including real zero and fractional values") {
            let sample = TrafficSample.decode(Data("{\"up\":1024.5,\"down\":8192}".utf8))
            try check(sample?.uploadBps == 1024.5 && sample?.downloadBps == 8192, "Traffic directions or units were changed")
            let idle = TrafficSample.decode(Data("{\"up\":0,\"down\":0}".utf8))
            try check(idle?.uploadBps == 0 && idle?.downloadBps == 0, "Valid idle traffic must remain a real zero sample")
        }
        try run("Invalid traffic stream messages never fabricate zero or partial samples") {
            let invalid = ["", "invalid JSON", "[]", "null", "{}", "{\"up\":1}", "{\"down\":1}",
                           "{\"up\":-1,\"down\":0}", "{\"up\":0,\"down\":-1}",
                           "{\"up\":\"12\",\"down\":0}", "{\"up\":0,\"down\":null}",
                           "{\"up\":true,\"down\":0}", "{\"up\":0,\"down\":false}",
                           "{\"up\":NaN,\"down\":0}", "{\"up\":0,\"down\":1e999}"]
            for text in invalid {
                try check(TrafficSample.decode(Data(text.utf8)) == nil, "Malformed traffic became a valid measurement")
            }
        }
        try run("Direct and global modes resolve independently of saved rule selections") {
            let proxies: [String: Any] = [
                "GLOBAL": ["type": "Selector", "now": "全局节点", "all": ["全局节点"]],
                "手动选择": ["type": "Selector", "now": "规则节点", "all": ["规则节点"]],
                "全局节点": ["type": "Shadowsocks", "history": [["delay": 38]]],
                "规则节点": ["type": "Shadowsocks", "history": [["delay": 99]]],
            ]
            let direct = ProxySelection.resolve(proxies: proxies, mode: "DIRECT", currentGroup: "手动选择")
            try check(direct?.nodeName == "DIRECT" && direct?.latencyMS == nil, "Direct mode fabricated a proxy node or latency")
            let global = ProxySelection.resolve(proxies: proxies, mode: "global", currentGroup: "手动选择")
            try check(global?.nodeName == "全局节点" && global?.groupName == "GLOBAL" && global?.latencyMS == 38,
                      "Global mode used a rule-mode group")
            try check(ProxySelection.resolve(proxies: [:], mode: "global", currentGroup: nil) == nil,
                      "Missing GLOBAL should not fall back to another node")
        }
        try run("Rule mode follows current group and running core choices through nested groups") {
            let proxies: [String: Any] = [
                "当前组": ["type": "Selector", "now": "自动组", "all": ["自动组", "旧节点"]],
                "自动组": ["type": "URLTest", "now": "当前节点", "all": ["当前节点", "旧节点"]],
                "手动选择": ["type": "Selector", "now": "旧节点", "all": ["旧节点"]],
                "当前节点": ["type": "Shadowsocks", "history": [["delay": 80], ["delay": 47]]],
                "旧节点": ["type": "Shadowsocks", "history": [["delay": 12]]],
            ]
            let result = ProxySelection.resolve(proxies: proxies, mode: "rule", currentGroup: "当前组",
                                                selected: ["当前组": "旧节点", "自动组": "旧节点"])
            try check(result?.groupName == "当前组" && result?.nodeName == "当前节点" && result?.latencyMS == 47,
                      "Saved or first node overrode the running core's nested current selection")
        }
        try run("Group fallback requires a unique group or identifiable primary selector") {
            let leaf: [String: Any] = ["type": "Shadowsocks"]
            let unique: [String: Any] = ["普通组": ["type": "Selector", "now": "节点"], "节点": leaf]
            let only = ProxySelection.resolve(proxies: unique, mode: "rule", currentGroup: "已删除组")
            try check(only?.groupName == "普通组" && only?.nodeName == "节点", "Unique group fallback failed")
            let ranked: [String: Any] = ["手动选择": ["type": "Selector", "now": "手动节点"],
                                       "服务组": ["type": "Selector", "now": "服务节点"],
                                       "手动节点": leaf, "服务节点": leaf]
            let primary = ProxySelection.resolve(proxies: ranked, mode: "rule", currentGroup: nil)
            try check(primary?.groupName == "手动选择" && primary?.nodeName == "手动节点", "Clear primary selection was not recognized")
            let ambiguous: [String: Any] = ["服务甲": ["type": "Selector", "now": "甲节点"],
                                          "服务乙": ["type": "Selector", "now": "乙节点"],
                                          "甲节点": leaf, "乙节点": leaf]
            let unresolved = ProxySelection.resolve(proxies: ambiguous, mode: "rule", currentGroup: nil)
            try check(unresolved?.nodeName == nil && unresolved?.latencyMS == nil,
                      "Ambiguous policy groups fabricated an arbitrary current node")
        }
        try run("Cycles, missing leaves and load balancing do not masquerade as a current node") {
            let graphs: [[String: Any]] = [
                ["根组": ["type": "Selector", "now": "循环组"], "循环组": ["type": "Selector", "now": "根组"]],
                ["根组": ["type": "Selector", "now": "已删除节点"]],
                ["根组": ["type": "LoadBalance", "all": ["节点"]], "节点": ["type": "Shadowsocks"]],
            ]
            for graph in graphs {
                let result = ProxySelection.resolve(proxies: graph, mode: "rule", currentGroup: "根组")
                try check(result?.groupName == "根组" && result?.nodeName == nil && result?.latencyMS == nil,
                          "Unresolvable group was presented as a real current node")
            }
        }
        try run("Unknown controller modes never infer a node from saved settings") {
            let proxies: [String: Any] = ["根组": ["type": "Selector", "now": "节点"], "节点": ["type": "Shadowsocks"]]
            for mode in [nil, "", "unsupported"] as [String?] {
                try check(ProxySelection.resolve(proxies: proxies, mode: mode, currentGroup: "根组") == nil,
                          "Unavailable mode fabricated a known proxy selection")
            }
        }
        try run("Only a valid latest latency is shown; old successful probes are never reused") {
            let invalidDelays: [Any] = [0, -1, 65_536, Double.nan, Double.infinity, true, "32", NSNull()]
            for delay in invalidDelays {
                let proxies: [String: Any] = ["根组": ["type": "Selector", "now": "节点"],
                                             "节点": ["type": "Shadowsocks", "history": [["delay": 32], ["delay": delay]]]]
                let result = ProxySelection.resolve(proxies: proxies, mode: "rule", currentGroup: "根组")
                try check(result?.nodeName == "节点" && result?.latencyMS == nil,
                          "Latest failed or malformed probe reused an older latency")
            }
        }

        try run("New SQLite profiles preserve exact selected IDs, dates, quota and live WAL changes") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let database = folder.appendingPathComponent("database.sqlite")
            var db: OpaquePointer?
            try check(sqlite3_open(database.path, &db) == SQLITE_OK, "Fixture DB failed")
            defer { sqlite3_close(db) }
            let sql = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE profiles(id INTEGER PRIMARY KEY,label TEXT,current_group_name TEXT,last_update_date INTEGER,subscription_info TEXT,selected_map TEXT);
            INSERT INTO profiles VALUES(1,'inactive','other',1700000000,'{"upload":1,"download":2,"total":100}','{}');
            INSERT INTO profiles VALUES(371969162982985729,'selected','group',1792740000,'{"upload":20,"download":30,"total":200,"expire":1900000000}','{"group":"node"}');
            """
            try check(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "Fixture setup failed")
            let config: [String: Any] = ["currentProfileId": NSNumber(value: Int64(371969162982985729))]
            var loaded = try FlClashPreferences.addingDatabaseProfile(to: config, database: database)
            let active = ActiveSubscription.decode(configuration: loaded)
            try check(active?.name == "selected" && active?.usedBytes == 50 && active?.selected["group"] == "node", "Selected SQLite record or quota was lost")
            try check(active?.updatedAt?.timeIntervalSince1970 == 1792740000, "SQLite seconds date was decoded incorrectly")
            try check(sqlite3_exec(db, "UPDATE profiles SET label='changed' WHERE id=371969162982985729", nil, nil, nil) == SQLITE_OK, "Fixture update failed")
            loaded = try FlClashPreferences.addingDatabaseProfile(to: config, database: database)
            try check(ActiveSubscription.decode(configuration: loaded)?.name == "changed", "Live WAL updates were missed")
            loaded = try FlClashPreferences.addingDatabaseProfile(to: ["currentProfileId": 999], database: database)
            try check(ActiveSubscription.decode(configuration: loaded) == nil, "Missing selection fell back to another profile")
            try check(sqlite3_exec(db, "UPDATE profiles SET subscription_info='bad JSON'", nil, nil, nil) == SQLITE_OK, "Fixture mutation failed")
            loaded = try FlClashPreferences.addingDatabaseProfile(to: config, database: database)
            try check(ActiveSubscription.decode(configuration: loaded)?.usedBytes == nil, "Malformed quota manufactured usage")
        }
        try run("Legacy profiles remain available and missing new databases are never created") {
            let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let legacy: [String: Any] = ["currentProfileId": "legacy", "profiles": [profile(id: "legacy")]]
            let loaded = try FlClashPreferences.addingDatabaseProfile(to: legacy, database: missing)
            try check(ActiveSubscription.decode(configuration: loaded)?.id == "legacy", "Legacy compatibility failed")
            do {
                _ = try FlClashPreferences.addingDatabaseProfile(to: ["currentProfileId": 1], database: missing)
                throw TestFailure(description: "Missing DB unexpectedly loaded")
            } catch is CocoaError {}
            try check(!FileManager.default.fileExists(atPath: missing.path), "Reader created a database")
        }
        try run("Authentication works for HTTP, traffic WebSocket and delay without leaking beyond loopback") {
            let secret = "synthetic-test-value"
            var requests = [URLRequest(url: URL(string: "http://127.0.0.1:9090/configs")!),
                            URLRequest(url: URL(string: "ws://127.0.0.1:9090/traffic")!)]
            requests.append(try ClashLatencyProbe.request(nodeName: "node/with space", testURL: ClashLatencyProbe.fallbackURL))
            for original in requests {
                let request = try FlClashAuthorization.apply(to: original, secret: secret)
                try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + secret, "Authentication absent")
                try check(request.url == original.url && !request.url!.absoluteString.contains(secret), "Secret leaked to URL")
                try check(FlClashAuthorization.apply(to: original, secret: "").value(forHTTPHeaderField: "Authorization") == nil, "Legacy unauthenticated requests changed")
            }
            for url in ["http://example.com:9090/configs", "http://127.0.0.1:1082/configs", "http://user@127.0.0.1:9090/configs"] {
                do {
                    _ = try FlClashAuthorization.apply(to: URLRequest(url: URL(string: url)!), secret: secret)
                    throw TestFailure(description: "Credential accepted outside controller origin")
                } catch is URLError {}
            }
        }
        print("\n\(passed) fixture-only model tests passed. No FlClash preferences or controller were accessed.")
    }
}
