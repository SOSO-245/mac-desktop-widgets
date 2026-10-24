import AppKit
import Combine
import Foundation
import Network
import SystemConfiguration
import OSLog

/// Decode archive data without loading or instantiating Shadowrocket classes.
enum ShadowrocketArchive {
    static func decode(_ data: Data) throws -> Any {
        guard data.count <= 4_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        // Foundation hides binary-plist UIDs behind an opaque Core Foundation
        // type. The public XML serializer represents them as CF$UID dictionaries.
        // Rename that marker before reparsing to retain ordinary, safe values.
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        guard let text = String(data: xml, encoding: .utf8),
              let plain = text.replacingOccurrences(of: "<key>CF$UID</key>",
                                                    with: "<key>SRReadOnlyArchiveUID</key>").data(using: .utf8),
              let archive = try PropertyListSerialization.propertyList(from: plain, format: nil) as? [String: Any],
              archive["$archiver"] as? String == "NSKeyedArchiver",
              let objects = archive["$objects"] as? [Any], objects.count <= 40_000,
              let top = archive["$top"] as? [String: Any], let root = top["root"] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var remaining = 80_000
        var visiting = Set<Int>()
        func resolve(_ item: Any, depth: Int = 0) throws -> Any {
            remaining -= 1
            guard remaining >= 0, depth < 60 else { throw CocoaError(.fileReadCorruptFile) }
            if let dict = item as? [String: Any] {
                if let uid = dict["SRReadOnlyArchiveUID"] as? NSNumber {
                    let i = uid.intValue
                    guard i >= 0, i < objects.count, visiting.insert(i).inserted else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    defer { visiting.remove(i) }
                    return try resolve(objects[i], depth: depth + 1)
                }
                if let keys = dict["NS.keys"] as? [Any], let values = dict["NS.objects"] as? [Any] {
                    guard keys.count == values.count else { throw CocoaError(.fileReadCorruptFile) }
                    var result: [String: Any] = [:]
                    for (key, value) in zip(keys, values) {
                        guard let name = try resolve(key, depth: depth + 1) as? String else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        result[name] = try resolve(value, depth: depth + 1)
                    }
                    return result
                }
                if let values = dict["NS.objects"] as? [Any] {
                    return try values.map { try resolve($0, depth: depth + 1) }
                }
                if let value = dict["NS.string"] { return try resolve(value, depth: depth + 1) }
                if let value = ShadowrocketValues.number(dict["NS.time"]) {
                    return Date(timeIntervalSinceReferenceDate: value)
                }
                var result: [String: Any] = [:]
                for (key, value) in dict where key != "$class" {
                    result[key] = try resolve(value, depth: depth + 1)
                }
                return result
            }
            if let array = item as? [Any] { return try array.map { try resolve($0, depth: depth + 1) } }
            return item
        }
        return try resolve(root)
    }
}

private enum ShadowrocketValues {
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
    static func title(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count < 200, !clean.contains("://") else { return nil }
        return clean
    }
}

struct ShadowrocketQuota {
    let usedBytes: Double
    let totalBytes: Double
    let expiresAt: Date?

    static func parse(_ text: String) -> ShadowrocketQuota? {
        guard text.count < 1000, !text.contains("://") else { return nil }
        func amount(_ key: String) -> Double? {
            let pattern = "(?:^|[,，\\s💡🚀])" + key + "\\s*[:：]\\s*([0-9]+(?:\\.[0-9]+)?)\\s*([KMGTPE]?)(?:I?B)?(?=[,，\\s💡🚀]|$)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]), value.isFinite else { return nil }
            let unit = String(text[unitRange]).uppercased()
            let exponent = ["": 0, "K": 1, "M": 2, "G": 3, "T": 4, "P": 5, "E": 6][unit] ?? 0
            let result = value * pow(1024, Double(exponent))
            return result.isFinite ? result : nil
        }
        guard let up = amount("↑"), let down = amount("↓"), let total = amount("TOT(?:AL)?"),
              total > 0, (up + down).isFinite else { return nil }
        var expires: Date?
        let datePattern = "(?:Expire[sd]?|Expiry|到期)\\s*[:：]\\s*(\\d{4}-\\d{2}-\\d{2})"
        if let regex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            expires = formatter.date(from: String(text[range]))
        }
        return ShadowrocketQuota(usedBytes: up + down, totalBytes: total, expiresAt: expires)
    }
}

struct ShadowrocketSelection {
    let selectedUUID: String
    let nodeName: String?
    let latencyMS: Int?
    let profileName: String?
    let quota: ShadowrocketQuota?
    let updatedAt: Date?

    static func decode(preferences: [String: Any], records: [[String: Any]]) -> ShadowrocketSelection? {
        guard let selectedID = preferences["group.com.liguangming.SelectedServerUUID"] as? String,
              !selectedID.isEmpty else { return nil }
        let matches = records.filter { $0["uuid"] as? String == selectedID }
        guard matches.count == 1, let node = matches.first, node["type"] as? String != "Subscribe" else { return nil }
        let rawName = ShadowrocketValues.title(node["title"])
            ?? ShadowrocketValues.title(preferences["group.com.liguangming.SelectedServerName"])
        let nodeName = rawName.flatMap { isInformationNode($0) ? nil : $0 }
        var latency: Int?
        if nodeName != nil, let ping = ShadowrocketValues.number(node["ping"]), ping > 0, ping <= 65_535 {
            latency = Int(ping)
        }
        // Compare subscription identifiers in memory only. These URL strings are
        // never requested, retained in snapshots, displayed, logged, or exported.
        let source = node["data"] as? String
        let subscriptions = records.filter {
            $0["type"] as? String == "Subscribe" && source?.isEmpty == false && $0["host"] as? String == source
        }
        let subscription = subscriptions.count == 1 ? subscriptions.first : nil
        let quota = (subscription?["data"] as? String).flatMap(ShadowrocketQuota.parse)
        return ShadowrocketSelection(selectedUUID: selectedID, nodeName: nodeName, latencyMS: latency,
                                     profileName: subscription.map { ShadowrocketValues.title($0["title"]) ?? "当前订阅" },
                                     quota: quota, updatedAt: subscription?["updated"] as? Date)
    }

    static func isInformationNode(_ name: String) -> Bool {
        if ["剩余流量", "套餐到期", "到期时间", "剩余时间", "流量重置", "订阅到期"].contains(where: name.contains) { return true }
        let quotaPattern = "\\d+(?:\\.\\d+)?\\s*[KMGT]I?B?\\s*[|/｜]\\s*\\d+(?:\\.\\d+)?\\s*[KMGT]I?B?"
        return name.range(of: quotaPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

struct ShadowrocketRate {
    let uploadBps: Double
    let downloadBps: Double
}

struct ShadowrocketTrafficCounter {
    let uploadBytes: Double
    let downloadBytes: Double
    let startedAt: Double
    let sampledAt: Date

    static func decode(_ fields: [String: Any], modifiedAt: Date, now: Date) -> ShadowrocketTrafficCounter? {
        let age = now.timeIntervalSince(modifiedAt)
        guard age >= -1, age <= 5,
              let wifiIn = ShadowrocketValues.number(fields["wifiInBytes"]),
              let cellIn = ShadowrocketValues.number(fields["cellularInBytes"]),
              let wifiOut = ShadowrocketValues.number(fields["wifiOutBytes"]),
              let cellOut = ShadowrocketValues.number(fields["cellularOutBytes"]),
              let startedAt = ShadowrocketValues.number(fields["startTime"]),
              (wifiIn + cellIn).isFinite, (wifiOut + cellOut).isFinite else { return nil }
        return ShadowrocketTrafficCounter(uploadBytes: wifiOut + cellOut, downloadBytes: wifiIn + cellIn,
                                          startedAt: startedAt, sampledAt: modifiedAt)
    }

    func rate(since previous: ShadowrocketTrafficCounter) -> ShadowrocketRate? {
        let interval = sampledAt.timeIntervalSince(previous.sampledAt)
        guard interval > 0, interval <= 5, startedAt == previous.startedAt,
              uploadBytes >= previous.uploadBytes, downloadBytes >= previous.downloadBytes else { return nil }
        let up = (uploadBytes - previous.uploadBytes) / interval
        let down = (downloadBytes - previous.downloadBytes) / interval
        guard up.isFinite, down.isFinite else { return nil }
        return ShadowrocketRate(uploadBps: up, downloadBps: down)
    }
}

enum ShadowrocketServiceIdentity {
    static func matches(_ service: [String: Any]) -> Bool {
        guard let interface = service["Interface"] as? [String: Any],
              interface["Type"] as? String == "VPN",
              interface["SubType"] as? String == "com.liguangming.Shadowrocket",
              let vpn = service["VPN"] as? [String: Any],
              vpn["NEProviderBundleIdentifier"] as? String == "com.liguangming.Shadowrocket.PacketTunnel" else { return false }
        return true
    }
}

/// Live counters belong to the identified Shadowrocket VPN service, not to the
/// Mac's physical interface. The monotonic clock makes wall-clock changes safe.
struct ShadowrocketVPNCounter {
    let uploadBytes: Double
    let downloadBytes: Double
    let serviceID: String
    let connectedAt: Double
    let interfaceName: String
    let monotonicTime: Double

    static func decode(statistics: [String: Any], extendedStatus: [String: Any],
                       serviceID: String, monotonicTime: Double) -> ShadowrocketVPNCounter? {
        guard !serviceID.isEmpty, monotonicTime.isFinite, monotonicTime >= 0,
              let stats = statistics["VPN"] as? [String: Any],
              let downloaded = ShadowrocketValues.number(stats["BytesIn"]),
              let uploaded = ShadowrocketValues.number(stats["BytesOut"]),
              let vpn = extendedStatus["VPN"] as? [String: Any],
              let connected = ShadowrocketValues.number(vpn["ConnectTime"]) else { return nil }
        let ipv4 = (extendedStatus["IPv4"] as? [String: Any])?["InterfaceName"] as? String
        let ipv6 = (extendedStatus["IPv6"] as? [String: Any])?["InterfaceName"] as? String
        guard let name = ipv4 ?? ipv6, name.range(of: "^utun[0-9]+$", options: .regularExpression) != nil,
              ipv4 == nil || ipv6 == nil || ipv4 == ipv6 else { return nil }
        return ShadowrocketVPNCounter(uploadBytes: uploaded, downloadBytes: downloaded, serviceID: serviceID,
                                      connectedAt: connected, interfaceName: name, monotonicTime: monotonicTime)
    }

    func rate(since previous: ShadowrocketVPNCounter) -> ShadowrocketRate? {
        let interval = monotonicTime - previous.monotonicTime
        guard interval > 0, interval <= 5, serviceID == previous.serviceID,
              connectedAt == previous.connectedAt, interfaceName == previous.interfaceName,
              uploadBytes >= previous.uploadBytes, downloadBytes >= previous.downloadBytes else { return nil }
        let up = (uploadBytes - previous.uploadBytes) / interval
        let down = (downloadBytes - previous.downloadBytes) / interval
        guard up.isFinite, down.isFinite else { return nil }
        return ShadowrocketRate(uploadBps: up, downloadBps: down)
    }
}

@MainActor
final class ShadowrocketMonitor: ObservableObject {
    @Published var snapshot = MonitorSnapshot(client: .shadowrocket)
    private var task: Task<Void, Never>?
    private let metadataLog = Logger(subsystem: "local.homeatlas.FlClashMonitor", category: "metadata")
    private var lastMetadataError: String?
    private var previousVPNCounter: ShadowrocketVPNCounter?
    private var vpnService: (id: String, connection: SCNetworkConnection)?
    private var lastServiceDiscovery: Double?
    private var selectedUUID: String?
    private struct Endpoint: Equatable {
        let host: String
        let port: UInt16
    }
    private var endpoint: Endpoint?
    private var savedLatency: Int?
    private var liveLatency: Int?
    private var liveLatencyAt: Date?
    private var lastProbeAt: Date?
    private var probeFailed = false
    private var probeConnection: NWConnection?
    private var probeTimeout: Task<Void, Never>?
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.liguangming.Shadowrocket")

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        previousVPNCounter = nil
        vpnService = nil
        lastServiceDiscovery = nil
        cancelProbe()
        clearSpeeds()
        snapshot.connectionState = "监测已暂停"
    }

    func refresh() {
        snapshot.isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.liguangming.Shadowrocket" }
        do {
            let prefsURL = root.appendingPathComponent("Library/Preferences/group.com.liguangming.Shadowrocket.plist")
            guard let prefs = try PropertyListSerialization.propertyList(from: Data(contentsOf: prefsURL), format: nil) as? [String: Any],
                  let records = try ShadowrocketArchive.decode(Data(contentsOf: root.appendingPathComponent("ServerManager"))) as? [[String: Any]] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let selected = ShadowrocketSelection.decode(preferences: prefs, records: records)
            snapshot.metadataIssue = selected == nil ? "未识别所选节点" : nil
            lastMetadataError = nil
            let selectedRecord = records.first { $0["uuid"] as? String == selected?.selectedUUID }
            let nextEndpoint = selected?.nodeName == nil ? nil : selectedRecord.flatMap(Self.tcpEndpoint)
            if selected?.selectedUUID != selectedUUID || nextEndpoint != endpoint {
                clearSpeeds()
                previousVPNCounter = nil
                cancelProbe()
                liveLatency = nil
                liveLatencyAt = nil
                lastProbeAt = nil
                probeFailed = false
                selectedUUID = selected?.selectedUUID
                endpoint = nextEndpoint
            }
            snapshot.nodeName = selected?.nodeName
            savedLatency = selected?.latencyMS
            updateLatencyDisplay()
            snapshot.groupName = selected == nil ? nil : "已选节点"
            snapshot.profileName = selected?.profileName
            snapshot.usedBytes = selected?.quota?.usedBytes
            snapshot.totalBytes = selected?.quota?.totalBytes
            snapshot.expiresAt = selected?.quota?.expiresAt
            snapshot.subscriptionUpdatedAt = selected?.updatedAt
        } catch {
            let failure = error as NSError
            let code = "\(failure.domain):\(failure.code)"
            if code != lastMetadataError {
                metadataLog.error("Shadowrocket metadata read failed: \(code, privacy: .public)")
                lastMetadataError = code
            }
            let denied = (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
                || (failure.domain == NSPOSIXErrorDomain && [1, 13].contains(failure.code))
            snapshot.metadataIssue = denied ? "请允许读取应用数据" : "节点数据读取失败"
            selectedUUID = nil
            endpoint = nil
            savedLatency = nil
            liveLatency = nil
            cancelProbe()
            snapshot.nodeName = nil
            snapshot.latencyMS = nil
            snapshot.latencyIsLive = false
            snapshot.latencyKind = "保存的测速结果"
            snapshot.groupName = nil
            snapshot.profileName = nil
            snapshot.usedBytes = nil
            snapshot.totalBytes = nil
            snapshot.expiresAt = nil
            snapshot.subscriptionUpdatedAt = nil
        }
        readTraffic()
        updateLatencyDisplay()
        probeLatencyIfNeeded()
    }

    private static func tcpEndpoint(_ record: [String: Any]) -> Endpoint? {
        let type = (record["type"] as? String ?? "").lowercased()
        // TCP handshakes are not a useful test for UDP-only protocols.
        let supported = ["vless", "vmess", "trojan", "trojan-go", "snell", "shadowsocks", "shadowsocksr", "ss", "ssr", "socks", "socks5", "http", "https", "ssh"]
        guard supported.contains(type), let host = record["host"] as? String,
              !host.isEmpty, host.count <= 255, !host.contains("://"),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let portText = record["port"] as? String, let port = UInt16(portText), port > 0 else { return nil }
        return Endpoint(host: host, port: port)
    }

    private func probeLatencyIfNeeded() {
        guard snapshot.isConnected, task != nil, let endpoint, probeConnection == nil,
              lastProbeAt.map({ Date().timeIntervalSince($0) >= 30 }) ?? true,
              let port = NWEndpoint.Port(rawValue: endpoint.port) else { return }
        lastProbeAt = Date()
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let started = ProcessInfo.processInfo.systemUptime
        probeConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            let succeeded: Bool
            switch state {
            case .ready: succeeded = true
            case .failed, .cancelled: succeeded = false
            default: return
            }
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.probeConnection === connection else { return }
                let elapsed = max(1, Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
                self.finishProbe(latency: succeeded ? elapsed : nil)
            }
        }
        connection.start(queue: DispatchQueue(label: "local.homeatlas.shadowrocket-latency"))
        probeTimeout = Task { [weak self, weak connection] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) }
            catch { return }
            guard let self, let connection, self.probeConnection === connection else { return }
            self.finishProbe(latency: nil)
        }
    }

    private func finishProbe(latency: Int?) {
        cancelProbe()
        guard snapshot.isConnected else { return }
        liveLatency = latency
        liveLatencyAt = Date()
        probeFailed = latency == nil
        updateLatencyDisplay()
    }

    private func cancelProbe() {
        probeTimeout?.cancel()
        probeTimeout = nil
        let connection = probeConnection
        probeConnection = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }

    private func updateLatencyDisplay() {
        if snapshot.isConnected, let measured = liveLatencyAt,
           Date().timeIntervalSince(measured) <= 60, liveLatency != nil || probeFailed {
            snapshot.latencyMS = liveLatency
            snapshot.latencyIsLive = liveLatency != nil
            snapshot.latencyKind = "TCP 自动测速"
        } else {
            snapshot.latencyMS = savedLatency
            snapshot.latencyIsLive = false
            snapshot.latencyKind = "保存的测速结果"
        }
    }

    private func readTraffic() {
        let tick = ProcessInfo.processInfo.systemUptime
        if vpnService == nil || lastServiceDiscovery.map({ tick - $0 >= 10 }) ?? true {
            let discovered = discoverVPNService()
            if vpnService?.id != discovered?.id { previousVPNCounter = nil }
            vpnService = discovered
            lastServiceDiscovery = tick
        }
        guard let service = vpnService else {
            previousVPNCounter = nil
            clearSpeeds()
            snapshot.connectionState = "未找到 Shadowrocket VPN 服务"
            return
        }
        let state = SCNetworkConnectionGetStatus(service.connection)
        guard state == .connected else {
            previousVPNCounter = nil
            clearSpeeds()
            liveLatency = nil
            liveLatencyAt = nil
            lastProbeAt = nil
            probeFailed = false
            snapshot.connectionState = state == .connecting ? "Shadowrocket 连接中" : "Shadowrocket 未连接"
            return
        }
        snapshot.isConnected = true
        snapshot.isRunning = true
        let statistics = SCNetworkConnectionCopyStatistics(service.connection) as? [String: Any] ?? [:]
        let extended = SCNetworkConnectionCopyExtendedStatus(service.connection) as? [String: Any] ?? [:]
        guard let counter = ShadowrocketVPNCounter.decode(statistics: statistics, extendedStatus: extended,
                                                          serviceID: service.id, monotonicTime: tick) else {
            previousVPNCounter = nil
            clearSpeeds(disconnected: false)
            snapshot.connectionState = "已连接 · 等待流量采样"
            return
        }
        if let previous = previousVPNCounter,
           previous.serviceID != counter.serviceID || previous.connectedAt != counter.connectedAt || previous.interfaceName != counter.interfaceName {
            cancelProbe()
            liveLatency = nil
            liveLatencyAt = nil
            lastProbeAt = nil
            probeFailed = false
        }
        if let previous = previousVPNCounter, let rate = counter.rate(since: previous) {
            snapshot.uploadBps = rate.uploadBps
            snapshot.downloadBps = rate.downloadBps
            snapshot.sampledAt = Date()
            snapshot.connectionState = "Shadowrocket 已连接"
            snapshot.speedHistory.append(rate.downloadBps)
            snapshot.uploadSpeedHistory.append(rate.uploadBps)
            if snapshot.speedHistory.count > 30 { snapshot.speedHistory.removeFirst(snapshot.speedHistory.count - 30) }
            if snapshot.uploadSpeedHistory.count > 30 { snapshot.uploadSpeedHistory.removeFirst(snapshot.uploadSpeedHistory.count - 30) }
        } else {
            clearSpeeds(disconnected: false)
            snapshot.connectionState = "已连接 · 等待流量采样"
        }
        previousVPNCounter = counter
    }

    private func discoverVPNService() -> (id: String, connection: SCNetworkConnection)? {
        guard let prefs = SCPreferencesCreate(nil, "Shadowrocket Monitor Read Only" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return nil }
        var matches: [(id: String, connection: SCNetworkConnection)] = []
        for service in services {
            guard let id = SCNetworkServiceGetServiceID(service),
                  let raw = SCPreferencesPathGetValue(prefs, ("/NetworkServices/" + (id as String)) as CFString) as? [String: Any],
                  ShadowrocketServiceIdentity.matches(raw),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, id, nil, nil) else { continue }
            matches.append((id as String, connection))
        }
        let connected = matches.filter { SCNetworkConnectionGetStatus($0.connection) == .connected }
        if connected.count == 1 { return connected[0] }
        // Never substitute another VPN merely because its user-visible name is similar.
        return matches.count == 1 ? matches[0] : nil
    }

    private func clearSpeeds(disconnected: Bool = true) {
        if disconnected {
            cancelProbe()
            snapshot.isConnected = false
            snapshot.latencyIsLive = false
            liveLatency = nil
            liveLatencyAt = nil
            lastProbeAt = nil
            probeFailed = false
        }
        snapshot.uploadBps = nil
        snapshot.downloadBps = nil
        snapshot.sampledAt = nil
        snapshot.speedHistory = []
        snapshot.uploadSpeedHistory = []
    }
}
