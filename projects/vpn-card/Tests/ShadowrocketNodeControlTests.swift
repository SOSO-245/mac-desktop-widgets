import Foundation

@main enum ShadowrocketNodeControlTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
            checks += 1
        }
        func expectThrows(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); fatalError(message) } catch { checks += 1 }
        }
        let sourceA = "https://fixture.invalid/sub/a"
        let sourceB = "https://fixture.invalid/sub/b"
        let preferences: [String: Any] = ["group.com.liguangming.SelectedServerUUID": "node-a"]
        func node(_ id: String, _ name: String, source: String? = nil, type: String = "VLESS", host: String = "node.fixture.invalid", port: Any = "443") -> [String: Any] {
            ["uuid": id, "title": name, "type": type, "data": source ?? sourceA,
             "host": host, "port": port, "password": "fixture-password", "user": "fixture-user", "ping": 99]
        }
        func subscription(_ id: String, _ name: String, host: String) -> [String: Any] {
            ["uuid": id, "title": name, "type": "Subscribe", "host": host]
        }
        let a = node("node-a", "香港 A"), b = node("node-b", "东京 B")
        let profile = subscription("subscription-a", "套餐 A", host: sourceA)
        func decode(_ records: [[String: Any]], prefs: [String: Any]? = nil) throws -> ShadowrocketNodeCatalog {
            try ShadowrocketNodeCatalog.decode(preferences: prefs ?? preferences, records: records)
        }
        func option(_ catalog: ShadowrocketNodeCatalog, _ id: String) -> ShadowrocketNodeOption {
            guard let value = catalog.nodes.first(where: { $0.id == id }) else { fatalError("Missing fixture option") }
            return value
        }

        let baseline = try decode([a, profile, b, subscription("subscription-b", "套餐 B", host: sourceB), node("outside", "其他订阅节点", source: sourceB)])
        expect(baseline.selectedID == "node-a" && baseline.sourceKey == "subscription-a", "Selection and source identity must use opaque UUIDs")
        expect(baseline.profileName == "套餐 A" && baseline.nodes.map(\.id) == ["node-a", "node-b"], "Only the selected subscription may appear")
        expect(option(baseline, "node-a").isCurrent && !option(baseline, "node-b").isCurrent, "The exact selected UUID must be marked current")
        expect(baseline.nodes.allSatisfy { $0.canSelect && $0.canTest && !$0.isTesting && $0.latencyMS == nil }, "Initial options must not present archived ping as a new measurement")
        let switched = try decode([a, profile, b], prefs: ["group.com.liguangming.SelectedServerUUID": "node-b"])
        expect(switched.selectedID == "node-b" && option(switched, "node-b").isCurrent, "Changing the selected UUID must change the current marker")
        for bad in [[:], ["group.com.liguangming.SelectedServerUUID": "missing"], ["group.com.liguangming.SelectedServerUUID": 12], ["group.com.liguangming.SelectedServerUUID": " "]] as [[String: Any]] {
            expectThrows("Invalid selection must not fall back to the first node") { _ = try decode([a, profile, b], prefs: bad) }
        }
        expectThrows("Duplicate selected UUID must be rejected") { _ = try decode([a, a, profile]) }
        expectThrows("A subscription record cannot serve as a selected node") { _ = try decode([a, profile], prefs: ["group.com.liguangming.SelectedServerUUID": "subscription-a"]) }
        expectThrows("Missing subscription match must not fall back") { _ = try decode([a, subscription("other", "Other", host: sourceB)]) }
        expectThrows("Ambiguous subscription host must be rejected") { _ = try decode([a, profile, subscription("duplicate", "Other", host: sourceA)]) }
        expectThrows("Ambiguous subscription UUID must be rejected") { _ = try decode([a, profile, node("subscription-a", "Collision", source: sourceB)]) }
        var noSource = a; noSource.removeValue(forKey: "data")
        expectThrows("A node without a subscription identity must be rejected") { _ = try decode([noSource, profile]) }
        var emptySource = a; emptySource["data"] = ""
        expectThrows("An empty subscription identity must be rejected") { _ = try decode([emptySource, profile]) }

        let filtered = try decode([a, profile, node("quota", "剩余流量：20 GB"), node("expire", "到期时间：2027-01-01"), node("url-title", sourceA), node("blank", "  "), node("control", "Bad\nname"), node("long", String(repeating: "x", count: 200))])
        expect(filtered.nodes.map(\.id) == ["node-a"], "Information and invalid title records must not become selectable nodes")
        // Reproduce the live UI regression: this subscription notice has normal
        // protocol/endpoint fields, but it is not a usable selectable server.
        let resetNotice = node("reset-notice", "距离下次重置剩余：5 天")
        let withoutResetNotice = try decode([a, profile, resetNotice, b])
        expect(withoutResetNotice.nodes.map(\.id) == ["node-a", "node-b"], "Reset-countdown information records must be excluded from selectable and testable rows")
        expectThrows("A filtered reset-countdown notice must not produce a node-selection URL") { _ = try withoutResetNotice.selectionURL(for: "reset-notice") }
        let selectedResetNotice = try decode([a, profile, resetNotice, b], prefs: ["group.com.liguangming.SelectedServerUUID": "reset-notice"])
        expect(selectedResetNotice.nodes.map(\.id) == ["node-a", "node-b"] && !selectedResetNotice.nodes.contains(where: \.isCurrent), "An already-selected information notice must not reappear as a node or cause a false current-node fallback")
        let fallbackProfile = try decode([a, subscription("subscription-a", sourceA, host: sourceA)])
        expect(fallbackProfile.profileName == "当前订阅", "A private URL must not be displayed as the profile title")

        let duplicateTitle = try decode([a, profile, node("other", "香港 A", source: sourceB)])
        expect(!option(duplicateTitle, "node-a").canSelect && option(duplicateTitle, "node-a").disabledReason != nil, "Global duplicate titles must disable selection")
        expectThrows("An ambiguous title must never produce a selection URL") { _ = try duplicateTitle.selectionURL(for: "node-a") }
        let caseCollision = try decode([node("node-a", "Alpha"), profile, node("other", "aLPHA", source: sourceB)])
        expect(!option(caseCollision, "node-a").canSelect, "Case-insensitive global duplicate titles must match the app selector's ambiguity")
        expectThrows("Case-insensitive ambiguity must not produce a URL") { _ = try caseCollision.selectionURL(for: "node-a") }
        let subscriptionTitleCollision = try decode([node("node-a", "Alpha"), profile, subscription("other-subscription", "aLPHA", host: sourceB)])
        expect(!option(subscriptionTitleCollision, "node-a").canSelect, "Subscription record titles must also participate in the app selector's global ambiguity check")
        expectThrows("A subscription title collision must not produce a selection URL") { _ = try subscriptionTitleCollision.selectionURL(for: "node-a") }
        let duplicateID = try decode([a, profile, b, node("node-b", "Different title", source: sourceB)])
        expect(!option(duplicateID, "node-b").canSelect && !option(duplicateID, "node-b").canTest, "Duplicate UUIDs must not be selected or probed")
        expectThrows("A duplicate UUID must not produce a URL") { _ = try duplicateID.selectionURL(for: "node-b") }
        let repeatedRow = try decode([a, profile, b, b])
        expect(repeatedRow.nodes.filter { $0.id == "node-b" }.count == 1 && !option(repeatedRow, "node-b").canSelect, "Duplicate records must not create duplicate SwiftUI row identities")

        let specialName = "🇭🇰 香港 & A?x=1/#fragment + %"
        let encoded = try decode([node("node-a", specialName), profile])
        let url = try encoded.selectionURL(for: "node-a")
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        expect(parts.scheme == "shadowrocket" && parts.host == "select" && parts.path.isEmpty, "Selection must target only the documented select action")
        expect(parts.queryItems?.count == 1 && parts.queryItems?.first?.name == "s" && parts.queryItems?.first?.value == specialName, "Unicode, emoji, and query metacharacters must round-trip as one name")
        expect(parts.fragment == nil && parts.user == nil && parts.password == nil && parts.port == nil, "Names must not create additional URL components")
        expect(!url.absoluteString.contains(sourceA) && !url.absoluteString.contains("node.fixture.invalid") && !url.absoluteString.contains("fixture-password") && !url.absoluteString.contains("fixture-user"), "A selection URL must contain no subscription or endpoint credentials")
        expectThrows("Unknown UUIDs must be rejected") { _ = try encoded.selectionURL(for: "unknown") }

        for type in ["VLESS", "vmess", "Trojan", "trojan-go", "snell", "Shadowsocks", "shadowsocksr", "ss", "ssr", "socks", "socks5", "http", "https", "ssh", "anytls"] {
            let catalog = try decode([a, profile, node("test", "Protocol test", type: type)])
            expect(option(catalog, "test").canTest, "Supported TCP protocol should expose testing: \(type)")
        }
        for type in ["Hysteria2", "WireGuard", "TUIC", "unknown"] {
            let catalog = try decode([a, profile, node("test", "Protocol test", type: type)])
            expect(!option(catalog, "test").canTest && option(catalog, "test").canSelect, "Unsupported TCP probes must not disable a uniquely named selection")
        }
        for host in ["", "https://fixture.invalid", "fixture.invalid/path", "user@fixture.invalid", "fixture invalid", "fixture.invalid\n", String(repeating: "x", count: 256)] {
            let catalog = try decode([a, profile, node("test", "Endpoint test", host: host)])
            expect(!option(catalog, "test").canTest, "Malformed endpoints must not be probed")
        }
        for port in ["0", "65536", "-1", "not-a-port", 443, true] as [Any] {
            let catalog = try decode([a, profile, node("test", "Endpoint test", port: port)])
            expect(!option(catalog, "test").canTest, "Invalid endpoint ports must not be probed")
        }
        let oversized = Array(repeating: a, count: 20_001)
        expectThrows("Oversized catalogs must be rejected before parsing") { _ = try decode(oversized) }

        // Compare the indexed implementation against the original Foundation
        // matching predicate, including Unicode case and canonical equivalents.
        let unicodeNames = ["Alpha", "aLPHA", "Straße", "STRASSE", "Σ", "σ", "ς", "İ", "i", "I", "ı", "É", "E\u{301}", "K", "k", "香港", "香港 A", "🇯🇵 Japan", "🇯🇵 JAPAN"]
        let unicodeRecords = [a, profile] + unicodeNames.enumerated().map { index, name in
            index.isMultiple(of: 3) ? subscription("unicode-\(index)", name, host: sourceB + "/\(index)") : node("unicode-\(index)", name)
        }
        let unicodeCatalog = try decode(unicodeRecords)
        for candidate in unicodeCatalog.nodes {
            let count = unicodeRecords.filter { ($0["title"] as? String).map { candidate.name.caseInsensitiveCompare($0) == .orderedSame } ?? false }.count
            expect(candidate.canSelect == (count == 1), "Indexed title counts must exactly match Foundation for Unicode and subscription headings")
        }

        var largeRecords = [a, profile]
        for index in 0..<19_996 { largeRecords.append(node("large-\(index)", "Large node \(index)")) }
        largeRecords.append(subscription("large-collision", "lARGE NODE 19995", host: sourceB))
        largeRecords.append(node("large-19994", "An external UUID collision", source: sourceB))
        let started = ProcessInfo.processInfo.systemUptime
        let largeCatalog = try decode(largeRecords)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        expect(largeCatalog.nodes.count == 19_997, "A large active subscription must retain all unique row identities")
        expect(!option(largeCatalog, "large-19995").canSelect, "A subscription heading must still disable a same-name node in a large catalog")
        expect(!option(largeCatalog, "large-19994").canSelect && !option(largeCatalog, "large-19994").canTest, "An external UUID collision must still disable selection and probing")
        expect(option(largeCatalog, "large-19993").canSelect && option(largeCatalog, "large-19993").canTest, "Unambiguous neighbors must retain selection and testing")
        print(String(format: "Large catalog fixture: %d records parsed in %.3f s", largeRecords.count, elapsed))

        let catalog = try decode([a, profile, b])
        let changedEndpoint = try decode([a, profile, node("node-b", "东京 B", host: "changed.fixture.invalid")])
        let changedType = try decode([a, profile, node("node-b", "东京 B", type: "Trojan")])
        let changedName = try decode([a, profile, node("node-b", "Changed")])
        let changedSource = try decode([node("node-a", "香港 A", source: sourceB), subscription("subscription-b", "套餐 B", host: sourceB), node("node-b", "东京 B", source: sourceB)])
        let changedAmbiguity = try decode([a, profile, b, node("collision", "东京 b", source: sourceB)])
        for fresh in [changedEndpoint, changedType, changedName, changedSource, changedAmbiguity] {
            expectThrows("Changed selection identity must not reuse a stale catalog") { _ = try fresh.selectionURL(for: "node-b", matching: catalog) }
        }
        let matchedURL = try catalog.selectionURL(for: "node-b", matching: catalog)
        let normalURL = try catalog.selectionURL(for: "node-b")
        expect(matchedURL == normalURL, "An unchanged catalog must preserve the selection URL")

        // Every production dependency is replaced. No controller below can read
        // the real container, launch an application, or start automatic probes.
        let fixtureApplication = URL(fileURLWithPath: "/tmp/FixtureShadowrocket.app")
        func drainTasks() async { for _ in 0..<20 { await Task.yield() } }
        var cancelledOpens = 0
        let cancelled = ShadowrocketNodeController(catalogReader: { catalog }, applicationURLProvider: { fixtureApplication }, urlOpener: { _, _, done in cancelledOpens += 1; done(true) })
        cancelled.load(automaticallyTest: false); await drainTasks()
        expect(!cancelled.isTesting && cancelled.nodes.count == 2, "Fixture loading must not start network tests")
        cancelled.selectNode(id: "node-b"); cancelled.cancel()
        await drainTasks()
        expect(cancelledOpens == 0 && !cancelled.isSelecting, "Closing before task dispatch must prevent application opening")
        cancelled.selectNode(id: "node-b")
        await drainTasks()
        expect(cancelledOpens == 0, "A closed session must not accept stale row actions")
        cancelled.load(automaticallyTest: false); await drainTasks(); cancelled.selectNode(id: "node-a")
        await drainTasks()
        expect(cancelledOpens == 0 && !cancelled.isSelecting, "Selecting the already-current node must not dispatch an application URL")
        cancelled.cancel()

        for fresh in [changedEndpoint, changedType, changedName, changedSource, changedAmbiguity] {
            var reads = 0, opens = 0
            let guarded = ShadowrocketNodeController(catalogReader: { reads += 1; return reads >= 3 ? fresh : catalog }, applicationURLProvider: { fixtureApplication }, urlOpener: { _, _, done in opens += 1; done(true) })
            guarded.load(automaticallyTest: false); await drainTasks(); guarded.selectNode(id: "node-b")
            await drainTasks()
            expect(reads >= 3 && opens == 0 && !guarded.isSelecting, "Final dispatch must revalidate endpoint, identity, source, and ambiguity")
            guarded.cancel()
        }

        var confirmedCatalog = catalog, successOpens = 0, successChanges = 0
        let selectedB = try decode([a, profile, b], prefs: ["group.com.liguangming.SelectedServerUUID": "node-b"])
        var dispatchedURL: URL?
        let success = ShadowrocketNodeController(catalogReader: { confirmedCatalog }, applicationURLProvider: { fixtureApplication }, urlOpener: { value, application, done in
            expect(application == fixtureApplication, "Only the injected fixture application may receive a selection")
            successOpens += 1; dispatchedURL = value; confirmedCatalog = selectedB; done(true)
        })
        success.onSelectionChanged = { successChanges += 1 }
        success.load(automaticallyTest: false); await drainTasks(); success.selectNode(id: "node-b")
        await drainTasks()
        expect(successOpens == 1 && successChanges == 1 && success.selectedID == "node-b" && !success.isSelecting, "Success must require read-back confirmation of the selected UUID")
        expect(dispatchedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first?.value == "东京 B", "Dispatch must preserve the exact requested node name")
        success.cancel()

        var lateCompletion: ((Bool) -> Void)?, lateChanges = 0
        let late = ShadowrocketNodeController(catalogReader: { catalog }, applicationURLProvider: { fixtureApplication }, urlOpener: { _, _, done in lateCompletion = done })
        late.onSelectionChanged = { lateChanges += 1 }
        late.load(automaticallyTest: false); await drainTasks(); late.selectNode(id: "node-b")
        await drainTasks()
        expect(lateCompletion != nil, "The fixture must reach its injected pending dispatch")
        late.cancel(); lateCompletion?(true)
        await drainTasks()
        expect(lateChanges == 0 && !late.isSelecting && late.selectedID == "node-a", "Completion after closing must not publish a stale selection")

        var failedChanges = 0
        let failed = ShadowrocketNodeController(catalogReader: { catalog }, applicationURLProvider: { fixtureApplication }, urlOpener: { _, _, done in done(false) })
        failed.onSelectionChanged = { failedChanges += 1 }
        failed.load(automaticallyTest: false); await drainTasks(); failed.selectNode(id: "node-b")
        await drainTasks()
        expect(failedChanges == 0 && !failed.isSelecting && failed.selectedID == "node-a", "A failed dispatch must not claim the node changed")
        failed.cancel()
        print("Shadowrocket node controls: \(checks) synthetic checks passed; no real containers, URLs, or probes used")
    }
}
