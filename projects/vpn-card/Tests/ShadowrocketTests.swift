import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private func rejects(_ operation: () throws -> Any) throws {
    do {
        _ = try operation()
    } catch {
        return
    }
    throw TestFailure(description: "Corrupt archive was accepted")
}

private let selectedKey = "group.com.liguangming.SelectedServerUUID"
private let fixtureDate = Date(timeIntervalSince1970: 1_900_000_000)
private let gibibyte: Double = 1_073_741_824

private func records() -> [[String: Any]] {
    // Subscription identifiers are inert fixture strings, never real addresses.
    [
        ["uuid": "inactive", "type": "VLESS", "title": "未选中节点", "ping": 9, "data": "fixture-subscription-b"],
        ["uuid": "active", "type": "VLESS", "title": "选中节点", "ping": 42, "data": "fixture-subscription-a"],
        ["uuid": "subscription-b", "type": "Subscribe", "host": "fixture-subscription-b", "title": "套餐乙",
         "data": "↑:4G,↓:5G,TOT:20G"],
        ["uuid": "subscription-a", "type": "Subscribe", "host": "fixture-subscription-a", "title": "套餐甲",
         "data": "↑:1G,↓:2G,TOT:10G,Expires:2027-01-01", "updated": fixtureDate],
    ]
}

private func fields() -> [String: Any] {
    ["wifiInBytes": 1000, "cellularInBytes": 200, "wifiOutBytes": 500, "cellularOutBytes": 100, "startTime": 12]
}

private func vpnService() -> [String: Any] {
    ["UserDefinedName": "任意显示名称",
     "Interface": ["Type": "VPN", "SubType": "com.liguangming.Shadowrocket"],
     "VPN": ["NEProviderBundleIdentifier": "com.liguangming.Shadowrocket.PacketTunnel"]]
}

private func vpnStatistics(incoming: Any = 1200, outgoing: Any = 600) -> [String: Any] {
    ["VPN": ["BytesIn": incoming, "BytesOut": outgoing],
     "PPP": ["BytesIn": 999_999, "BytesOut": 888_888]]
}

private func vpnStatus(connectedAt: Any = 3000, interface: String = "utun7") -> [String: Any] {
    ["VPN": ["ConnectTime": connectedAt], "IPv4": ["InterfaceName": interface],
     "NestedRoutingInformation": ["InterfaceName": "en9"]]
}

private func keyedArchive(_ objects: [Any], root: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$version": 100000,
                                                         "$objects": objects, "$top": ["root": root]],
                                       format: .binary, options: 0)
}

@main
private enum ShadowrocketTests {
    static func main() throws {
        var passed = 0
        func run(_ name: String, _ operation: () throws -> Void) throws {
            try operation()
            passed += 1
            print("PASS \(name)")
        }

        try run("Foundation keyed archives decode nested records, strings and dates") {
            let bytes = try NSKeyedArchiver.archivedData(withRootObject: records(), requiringSecureCoding: false)
            guard let decoded = try ShadowrocketArchive.decode(bytes) as? [[String: Any]] else {
                throw TestFailure(description: "Archived records did not decode as dictionaries")
            }
            try check(decoded.count == 4 && decoded[1]["uuid"] as? String == "active", "Archive references changed record order or identifiers")
            try check(decoded[3]["updated"] as? Date == fixtureDate, "Archived NSDate lost its absolute timestamp")
            let selected = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: decoded)
            try check(selected?.nodeName == "选中节点" && selected?.quota?.usedBytes == 3 * gibibyte,
                      "Decoded keyed archive could not feed the selected-subscription parser")
        }
        try run("Repeated archive references are valid and dictionary counters survive decoding") {
            let shared = fields() as NSDictionary
            let bytes = try NSKeyedArchiver.archivedData(withRootObject: [shared, shared], requiringSecureCoding: false)
            let decoded = try ShadowrocketArchive.decode(bytes) as? [[String: Any]]
            try check(decoded?.count == 2 && decoded?[0]["wifiInBytes"] as? Int == 1000
                      && decoded?[1]["wifiOutBytes"] as? Int == 500, "Repeated UID references were mistaken for a cycle")
        }
        try run("Malformed, cyclic and out-of-range archive references are rejected") {
            try rejects { try ShadowrocketArchive.decode(Data("not a plist".utf8)) }
            let plain = try PropertyListSerialization.data(fromPropertyList: ["root": "plain"], format: .binary, options: 0)
            try rejects { try ShadowrocketArchive.decode(plain) }
            let beyond = try keyedArchive(["$null", "value"], root: ["CF$UID": 99])
            try rejects { try ShadowrocketArchive.decode(beyond) }
            let cycle = try keyedArchive(["$null", ["next": ["CF$UID": 1]]], root: ["CF$UID": 1])
            try rejects { try ShadowrocketArchive.decode(cycle) }
            let mismatch = try keyedArchive(["$null", ["NS.keys": ["key"], "NS.objects": []]], root: ["CF$UID": 1])
            try rejects { try ShadowrocketArchive.decode(mismatch) }
            try rejects { try ShadowrocketArchive.decode(Data(repeating: 0, count: 4_000_001)) }
        }
        try run("Quota parsing combines upload and download using binary units") {
            let quota = ShadowrocketQuota.parse("↑:1.5GB,↓:512MiB,TOTAL:4G,Expires:2027-01-01")
            try check(quota?.usedBytes == 2 * gibibyte && quota?.totalBytes == 4 * gibibyte,
                      "Mixed-unit quota or upload plus download total is incorrect")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let expiry = quota?.expiresAt.map { calendar.dateComponents([.year, .month, .day], from: $0) }
            try check(expiry?.year == 2027 && expiry?.month == 1 && expiry?.day == 1, "Quota expiry lost its local date")
            let overQuota = ShadowrocketQuota.parse("↑:2G,↓:3G,TOT:4G")
            try check(overQuota?.usedBytes == 5 * gibibyte, "Over-quota usage was clamped")
        }
        try run("Incomplete and invalid quota strings do not invent subscription usage") {
            for text in ["", "↑:1G,TOT:10G", "↓:2G,TOT:10G", "↑:-1G,↓:2G,TOT:10G",
                         "↑:1G,↓:2G,TOT:0G", "↑:NaNG,↓:2G,TOT:10G", "↑:1G,↓:2G,TOT:10unknown"] {
                try check(ShadowrocketQuota.parse(text) == nil, "Invalid quota string became a usable subscription counter")
            }
            let zero = ShadowrocketQuota.parse("↑:0K,↓:0K,TOT:10M,Expires:2027-02-30")
            try check(zero?.usedBytes == 0 && zero?.expiresAt == nil, "Valid zero usage or invalid expiry was misclassified")
        }
        try run("Selected UUID maps to its unique subscription rather than the first record") {
            let first = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: records())
            let switched = ShadowrocketSelection.decode(preferences: [selectedKey: "inactive"], records: records())
            try check(first?.nodeName == "选中节点" && first?.latencyMS == 42 && first?.profileName == "套餐甲"
                      && first?.quota?.usedBytes == 3 * gibibyte && first?.updatedAt == fixtureDate,
                      "Selected node inherited a different subscription")
            try check(switched?.profileName == "套餐乙" && switched?.quota?.usedBytes == 9 * gibibyte,
                      "Switching the selected UUID retained the previous package")
        }
        try run("Missing or duplicate selected UUIDs never fall back to another node") {
            for preferences: [String: Any] in [[:], [selectedKey: ""], [selectedKey: "missing"], [selectedKey: 1], [selectedKey: "subscription-a"]] {
                try check(ShadowrocketSelection.decode(preferences: preferences, records: records()) == nil,
                          "Invalid selection fabricated an active node")
            }
            var duplicate = records()
            duplicate.append(duplicate[1])
            try check(ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: duplicate) == nil,
                      "Duplicate UUIDs produced an arbitrary selected node")
        }
        try run("Ambiguous or missing subscription links retain the node but omit package data") {
            var ambiguous = records()
            ambiguous.append(ambiguous[3])
            let result = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: ambiguous)
            try check(result?.nodeName == "选中节点" && result?.profileName == nil && result?.quota == nil,
                      "Duplicate subscription links fabricated a current package")
            let missing = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: Array(records().prefix(3)))
            try check(missing?.nodeName == "选中节点" && missing?.quota == nil && missing?.profileName == nil,
                      "Missing subscription link fell back to an inactive package")
        }
        try run("Information-only quota entries do not masquerade as network nodes") {
            for title in ["剩余流量 100 GB", "套餐到期 2027-01-01", "1.5GB / 10GB"] {
                var entries = records()
                entries[1]["title"] = title
                let result = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: entries)
                try check(result?.nodeName == nil && result?.latencyMS == nil && result?.profileName == "套餐甲",
                          "A quota information row was displayed as a real node")
            }
        }
        try run("Invalid saved latency remains unavailable without erasing the selected node") {
            let bad: [Any] = [0, -1, 65_536, Double.nan, Double.infinity, true, "42", NSNull()]
            for ping in bad {
                var entries = records()
                entries[1]["ping"] = ping
                let result = ShadowrocketSelection.decode(preferences: [selectedKey: "active"], records: entries)
                try check(result?.nodeName == "选中节点" && result?.latencyMS == nil,
                          "Invalid latency became a measured delay")
            }
        }
        try run("Traffic counter combines Wi-Fi and cellular bytes without swapping directions") {
            let counter = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate, now: fixtureDate)
            try check(counter?.uploadBytes == 600 && counter?.downloadBytes == 1200 && counter?.startedAt == 12,
                      "Counter directions or interface totals are incorrect")
            var zero = fields()
            for key in ["wifiInBytes", "cellularInBytes", "wifiOutBytes", "cellularOutBytes"] { zero[key] = 0 }
            let idle = ShadowrocketTrafficCounter.decode(zero, modifiedAt: fixtureDate, now: fixtureDate)
            try check(idle?.uploadBytes == 0 && idle?.downloadBytes == 0, "Valid zero counters became unavailable")
        }
        try run("Only fresh counter archives can seed a live speed sample") {
            for age in [0.0, 5.0, -1.0] {
                try check(ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate.addingTimeInterval(-age), now: fixtureDate) != nil,
                          "A timestamp on a valid freshness boundary was rejected")
            }
            for age in [5.001, 60.0, -1.001] {
                try check(ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate.addingTimeInterval(-age), now: fixtureDate) == nil,
                          "An old or excessively future counter was treated as live")
            }
        }
        try run("Missing, malformed and overflowing counters cannot fabricate rates") {
            for key in ["wifiInBytes", "cellularInBytes", "wifiOutBytes", "cellularOutBytes", "startTime"] {
                var missing = fields()
                missing.removeValue(forKey: key)
                try check(ShadowrocketTrafficCounter.decode(missing, modifiedAt: fixtureDate, now: fixtureDate) == nil,
                          "Missing required counter field was treated as zero")
                for invalid in [-1, Double.nan, Double.infinity, true, "123"] as [Any] {
                    var broken = fields()
                    broken[key] = invalid
                    try check(ShadowrocketTrafficCounter.decode(broken, modifiedAt: fixtureDate, now: fixtureDate) == nil,
                              "Invalid counter was accepted")
                }
            }
            var overflow = fields()
            overflow["wifiInBytes"] = Double.greatestFiniteMagnitude
            overflow["cellularInBytes"] = Double.greatestFiniteMagnitude
            try check(ShadowrocketTrafficCounter.decode(overflow, modifiedAt: fixtureDate, now: fixtureDate) == nil,
                      "Overflowed interface total became a valid counter")
        }
        try run("Speed uses counter differences and the actual sampling interval") {
            let first = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate, now: fixtureDate)!
            var next = fields()
            next["wifiInBytes"] = 1200; next["cellularInBytes"] = 250
            next["wifiOutBytes"] = 650; next["cellularOutBytes"] = 150
            let secondDate = fixtureDate.addingTimeInterval(2)
            let second = ShadowrocketTrafficCounter.decode(next, modifiedAt: secondDate, now: secondDate)!
            let rate = second.rate(since: first)
            try check(rate?.uploadBps == 100 && rate?.downloadBps == 125, "Rates used cumulative bytes or the wrong time interval")
            let idleDate = secondDate.addingTimeInterval(1)
            let idle = ShadowrocketTrafficCounter.decode(next, modifiedAt: idleDate, now: idleDate)!.rate(since: second)
            try check(idle?.uploadBps == 0 && idle?.downloadBps == 0, "Two equal fresh counters must produce a genuine idle rate")
        }
        try run("Repeated, reversed and delayed samples cannot fabricate live speed") {
            let first = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate, now: fixtureDate)!
            for interval in [0.0, -1.0, 5.001] {
                let sampled = fixtureDate.addingTimeInterval(interval)
                let current = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: sampled, now: sampled)!
                try check(current.rate(since: first) == nil, "A repeated or discontinuous sample yielded a live rate")
            }
            let last = fixtureDate.addingTimeInterval(5)
            let boundary = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: last, now: last)!
            try check(boundary.rate(since: first)?.uploadBps == 0, "The valid five-second interval was rejected")
        }
        try run("A restarted tunnel or counter rollback resets the speed baseline") {
            let first = ShadowrocketTrafficCounter.decode(fields(), modifiedAt: fixtureDate, now: fixtureDate)!
            let nextDate = fixtureDate.addingTimeInterval(1)
            for changed in [["startTime": 13], ["wifiInBytes": 1], ["wifiOutBytes": 1]] {
                var next = fields()
                for (key, value) in changed { next[key] = value }
                let current = ShadowrocketTrafficCounter.decode(next, modifiedAt: nextDate, now: nextDate)!
                try check(current.rate(since: first) == nil, "Restarted or decreasing counters yielded an old or negative speed")
            }
        }

        try run("VPN service identity matches exact provider fields rather than the display name") {
            try check(ShadowrocketServiceIdentity.matches(vpnService()), "Correct provider identity was rejected")
            var renamed = vpnService()
            renamed["UserDefinedName"] = "Shadowrocket"
            renamed["VPN"] = ["NEProviderBundleIdentifier": "example.fixture.OtherTunnel"]
            try check(!ShadowrocketServiceIdentity.matches(renamed), "An unrelated VPN named Shadowrocket was selected")
            for badInterface in [["Type": "PPP", "SubType": "com.liguangming.Shadowrocket"],
                                 ["Type": "VPN", "SubType": "example.fixture.OtherClient"],
                                 ["Type": "VPN"]] {
                var invalid = vpnService()
                invalid["Interface"] = badInterface
                try check(!ShadowrocketServiceIdentity.matches(invalid), "Incomplete or mismatched service identity was accepted")
            }
            try check(!ShadowrocketServiceIdentity.matches(["UserDefinedName": "Shadowrocket"]),
                      "Display name alone was accepted as a provider identity")
        }
        try run("VPN counters use service bytes and the direct IPv4 or IPv6 tunnel interface") {
            let sample = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                       serviceID: "fixture-service-a", monotonicTime: 100)
            try check(sample?.downloadBytes == 1200 && sample?.uploadBytes == 600,
                      "VPN bytes were swapped or came from a different statistics section")
            try check(sample?.interfaceName == "utun7" && sample?.serviceID == "fixture-service-a"
                      && sample?.connectedAt == 3000 && sample?.monotonicTime == 100,
                      "Tunnel identity came from a nested physical interface or lost its session metadata")
            var ipv6 = vpnStatus()
            ipv6.removeValue(forKey: "IPv4")
            ipv6["IPv6"] = ["InterfaceName": "utun8"]
            let six = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: ipv6,
                                                    serviceID: "fixture-service-a", monotonicTime: 100)
            try check(six?.interfaceName == "utun8", "IPv6-only tunnel interface was not identified")
        }
        try run("Incomplete, invalid or non-tunnel VPN counters cannot seed live speed") {
            let invalidStatistics: [[String: Any]] = [[:], ["VPN": [:]], ["VPN": ["BytesIn": 1]],
                                                     ["PPP": ["BytesIn": 1200, "BytesOut": 600]],
                                                     vpnStatistics(incoming: -1), vpnStatistics(outgoing: true),
                                                     vpnStatistics(incoming: Double.nan), vpnStatistics(outgoing: Double.infinity)]
            for statistics in invalidStatistics {
                try check(ShadowrocketVPNCounter.decode(statistics: statistics, extendedStatus: vpnStatus(),
                                                        serviceID: "fixture-service-a", monotonicTime: 100) == nil,
                          "Invalid VPN statistics became a live counter")
            }
            for status in [vpnStatus(interface: "en9"), vpnStatus(connectedAt: true), vpnStatus(connectedAt: Double.nan),
                           ["VPN": ["ConnectTime": 3000], "NestedRoutingInformation": ["InterfaceName": "utun7"]],
                           ["VPN": ["ConnectTime": 3000], "IPv4": ["InterfaceName": "utun7"], "IPv6": ["InterfaceName": "utun8"]]] {
                try check(ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: status,
                                                        serviceID: "fixture-service-a", monotonicTime: 100) == nil,
                          "Invalid or nested tunnel identity became a live counter")
            }
            try check(ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                    serviceID: "fixture-service-a", monotonicTime: Double.nan) == nil,
                      "A nonfinite monotonic sample time was accepted")
        }
        try run("VPN speed divides cumulative byte deltas by monotonic elapsed time") {
            let first = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                      serviceID: "fixture-service-a", monotonicTime: 100)!
            let next = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(incoming: 1450, outgoing: 800),
                                                     extendedStatus: vpnStatus(), serviceID: "fixture-service-a", monotonicTime: 102)!
            let rate = next.rate(since: first)
            try check(rate?.uploadBps == 100 && rate?.downloadBps == 125,
                      "VPN speed used totals or a fixed sampling interval")
            let idle = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                     serviceID: "fixture-service-a", monotonicTime: 101)!
            try check(idle.rate(since: first)?.uploadBps == 0 && idle.rate(since: first)?.downloadBps == 0,
                      "Unchanged counters in a connected tunnel must yield real zero rates")
        }
        try run("Changing VPN service, session or interface invalidates the old speed baseline") {
            let first = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                      serviceID: "fixture-service-a", monotonicTime: 100)!
            let changes: [(String, [String: Any])] = [("fixture-service-b", vpnStatus()),
                                                     ("fixture-service-a", vpnStatus(connectedAt: 3010)),
                                                     ("fixture-service-a", vpnStatus(interface: "utun8"))]
            for (service, status) in changes {
                let current = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(incoming: 1450, outgoing: 800),
                                                            extendedStatus: status, serviceID: service, monotonicTime: 101)!
                try check(current.rate(since: first) == nil, "A new tunnel reused the previous tunnel's speed baseline")
            }
        }
        try run("VPN duplicate, late or rolled-back samples never retain an old live rate") {
            let first = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                      serviceID: "fixture-service-a", monotonicTime: 100)!
            for time in [100.0, 99.0, 105.001] {
                let current = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                            serviceID: "fixture-service-a", monotonicTime: time)!
                try check(current.rate(since: first) == nil, "A duplicate, reversed or stale sample generated a rate")
            }
            for statistics in [vpnStatistics(incoming: 1199), vpnStatistics(outgoing: 599)] {
                let current = ShadowrocketVPNCounter.decode(statistics: statistics, extendedStatus: vpnStatus(),
                                                            serviceID: "fixture-service-a", monotonicTime: 101)!
                try check(current.rate(since: first) == nil, "Rolled-back VPN counters generated a negative or stale rate")
            }
            let boundary = ShadowrocketVPNCounter.decode(statistics: vpnStatistics(), extendedStatus: vpnStatus(),
                                                         serviceID: "fixture-service-a", monotonicTime: 105)!
            try check(boundary.rate(since: first)?.downloadBps == 0, "The valid five-second sampling boundary was rejected")
        }

        print("\n\(passed) synthetic Shadowrocket tests passed. No preferences, subscription URLs, live counters or VPN controls were accessed.")
    }
}
