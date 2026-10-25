import AppKit
import Combine
import Foundation
import SystemConfiguration

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
    var reachable: Bool { httpCode.map { (200..<400).contains($0) } ?? false }
    func needsRefresh(at now:Date = Date()) -> Bool {
        guard let checkedAt else { return true }
        let age=now.timeIntervalSince(checkedAt)
        return age < 0 || age >= 60
    }
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

enum SiteRoute: Equatable {
    case proxy(Int)
    case tunnel(String, String)
    var label: String { switch self {
    case .proxy: return "FlClash · 按当前规则"
    case .tunnel: return "Shadowrocket · VPN 隧道"
    } }
    var arguments: [String] { switch self {
    case .proxy(let port): return ["--proxy", "http://127.0.0.1:\(port)", "--noproxy", ""]
    case .tunnel(let name, _): return ["--proxy", "", "--noproxy", "*", "--interface", "if!\(name)"]
    } }
    static func proxyPort(_ config: [String: Any]) -> Int? {
        for key in ["mixed-port", "port"] {
            if let value = config[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
               value.doubleValue.rounded() == value.doubleValue, (1...65535).contains(value.intValue) { return value.intValue }
        }
        return nil
    }
    static func shadowrocket() -> SiteRoute? {
        guard let prefs = SCPreferencesCreate(nil, "Card Site Probe Read Only" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return nil }
        var matches: [SiteRoute] = []
        for service in services {
            guard let id = SCNetworkServiceGetServiceID(service),
                  let raw = SCPreferencesPathGetValue(prefs, ("/NetworkServices/" + (id as String)) as CFString) as? [String: Any],
                  ShadowrocketServiceIdentity.matches(raw),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, id, nil, nil),
                  SCNetworkConnectionGetStatus(connection) == .connected,
                  let status = SCNetworkConnectionCopyExtendedStatus(connection) as? [String: Any] else { continue }
            let name = ((status["IPv4"] as? [String: Any])?["InterfaceName"] as? String)
                ?? ((status["IPv6"] as? [String: Any])?["InterfaceName"] as? String)
            if let name, name.range(of: "^utun[0-9]+$", options: .regularExpression) != nil {
                let connected = (status["VPN"] as? [String: Any])?["ConnectTime"] as? NSNumber
                matches.append(.tunnel(name, "\(id):\(connected?.stringValue ?? "")"))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

// Each probe gets a fresh connection. No browser cookies, credentials, curlrc,
// redirects, response bodies, or inherited proxy environment are used.
@MainActor
final class SiteProbeProcess {
    private var process: Process?
    func cancel() { if let process, process.isRunning { process.terminate() } }
    func run(site: ProbeSite, route: SiteRoute) async -> SiteReading {
        if Task.isCancelled { return SiteReading() }
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        child.arguments = ["-q", "--silent", "--head", "--output", "/dev/null", "--max-time", "8", "--connect-timeout", "5",
                           "--write-out", "%{http_code} %{time_starttransfer}", "--user-agent", "HomeAtlas-Status/1.1"] + route.arguments + [site.url]
        child.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        process = child
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                child.terminationHandler = { child in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: SiteReading.decode(output: String(data: data, encoding: .utf8) ?? "", exitCode: child.terminationStatus))
                }
                do { try child.run() } catch {
                    child.terminationHandler = nil
                    continuation.resume(returning: SiteReading(status: "无法检测", checkedAt: Date()))
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
}

@MainActor
final class SiteLatencyMonitor: ObservableObject {
    @Published private(set) var readings: [String: SiteReading] = [:]
    @Published private(set) var routeLabel = "仅大号检测"
    private var enabled = false
    private var large = false
    private var menuSite = "Google"
    private var snapshot = MonitorSnapshot()
    private var identity = ""
    private var route: SiteRoute?
    private var round: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var lastAttempt: Date?
    private var refreshRequested: Set<String> = []

    func configure(large: Bool, menuSite: String, snapshot: MonitorSnapshot) {
        let enabled = true
        let scopeChanged = self.large != large || self.menuSite != menuSite
        self.large = large; self.menuSite = menuSite
        self.snapshot = snapshot
        let identity = "\(snapshot.client.rawValue)|\(snapshot.isConnected)|\(snapshot.profileName ?? "")|\(snapshot.nodeName ?? "")"
        if self.enabled != enabled || self.identity != identity {
            self.enabled = enabled; self.identity = identity
            reset()
            refresh()
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                    guard let self else { return }
                    // A disconnected or replaced SR tunnel must not keep old values.
                    if self.snapshot.client == .shadowrocket, let route = self.route, SiteRoute.shadowrocket() != route {
                        self.reset(keepTimer: true); self.refresh()
                    } else { self.refresh(onlyStale:true) }
                }
            }
        } else if scopeChanged { refresh(onlyStale:true) }
    }

    func stop() { enabled = false; reset() }
    private func reset(keepTimer: Bool = false) {
        generation = UUID(); round?.cancel(); round = nil
        if !keepTimer { timer?.cancel(); timer = nil }
        readings = [:]; route = nil; lastAttempt = nil; refreshRequested = []
    }
    func refresh(siteID: String? = nil, onlyStale: Bool = false) {
        guard enabled else { return }
        if onlyStale, route == nil, let lastAttempt, (0..<60).contains(Date().timeIntervalSince(lastAttempt)) { return }
        // Do not cancel every other row when one refresh button is pressed.
        if round != nil {
            if let siteID { refreshRequested.insert(siteID) }
            return
        }
        guard snapshot.isConnected else { routeLabel = "\(snapshot.client.title) 未连接"; lastAttempt = Date(); return }
        let token = generation, client = snapshot.client
        let selected = siteID.map { id in ProbeSite.all.filter { $0.id == id } } ?? (large ? ProbeSite.all : ProbeSite.all.filter { $0.id == menuSite })
        let sites = selected.filter { !onlyStale || readings[$0.id]?.needsRefresh() != false }
        guard !sites.isEmpty else { return }
        lastAttempt = Date()
        round = Task { [weak self] in
            guard let self else { return }
            do {
                let newRoute = try await self.resolveRoute(client)
                guard !Task.isCancelled, self.generation == token else { return }
                if self.route != newRoute { self.readings = [:] }
                self.route = newRoute; self.routeLabel = newRoute.label
                for site in sites { self.readings[site.id] = (self.readings[site.id] ?? SiteReading()).refreshing() }
                // At most three independent requests, each capped at eight seconds.
                await withTaskGroup(of: (String, SiteReading).self) { group in
                    var next = 0
                    func enqueue() {
                        let site = sites[next]; next += 1
                        group.addTask {
                            let worker = await SiteProbeProcess()
                            return (site.id, await worker.run(site: site, route: newRoute))
                        }
                    }
                    for _ in 0..<min(3, sites.count) { enqueue() }
                    while let (id, value) = await group.next() {
                        guard !Task.isCancelled, self.generation == token else { group.cancelAll(); return }
                        self.readings[id] = value
                        if next < sites.count { enqueue() }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.readings = [:]; self.route = nil
                self.routeLabel = client == .flclash ? "FlClash 代理端口不可用" : "Shadowrocket 隧道不可用"
            }
            guard self.generation == token else { return }
            self.round = nil
            if let pending = self.refreshRequested.sorted().first {
                self.refreshRequested.remove(pending); self.refresh(siteID: pending)
            } else { self.refresh(onlyStale:true) }
        }
    }

    private func resolveRoute(_ client: ProxyClient) async throws -> SiteRoute {
        if client == .shadowrocket {
            guard let route = SiteRoute.shadowrocket() else { throw URLError(.notConnectedToInternet) }
            return route
        }
        let prefs = try FlClashPreferences.read()
        let patch = prefs["patchClashConfig"] as? [String: Any] ?? [:]
        guard patch["external-controller"] as? String == "127.0.0.1:9090" else { throw URLError(.cannotConnectToHost) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:9090/configs")!)
        request = try FlClashAuthorization.apply(to: request, secret: patch["secret"] as? String ?? "")
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]; config.timeoutIntervalForRequest = 4; config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config, delegate: LoopbackSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = SiteRoute.proxyPort(json) else { throw URLError(.cannotConnectToHost) }
        return .proxy(port)
    }
}
