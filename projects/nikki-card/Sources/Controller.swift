import Foundation
import Security

struct ConnectionSettings: Codable, Equatable {
    var endpoint = "http://router.local:9090"
    var group = "节点选择"
    var provider = ""
    static func load() -> Self {
        UserDefaults.standard.data(forKey: "connection").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "connection") }
    static func normalized(_ raw: String) throws -> String {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(c.scheme ?? ""), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path == "" || c.path == "/", c.port.map({ (1...65535).contains($0) }) ?? true else { throw APIError.message("请填写控制接口地址，不含网页路径或密钥参数") }
        var clean = c; clean.path = ""; return clean.string!
    }
}

enum Vault {
    static let service = "local.homeatlas.NikkiMonitor.controller"
    static func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:endpoint]
    }
    static func read(_ endpoint: String) -> String {
        var q = query(endpoint); q[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &data) == errSecSuccess, let value = data as? Data else { return "" }
        return String(data: value, encoding: .utf8) ?? ""
    }
    static func save(_ secret: String, endpoint: String) throws {
        guard !secret.contains("\n"), !secret.contains("\r"), secret.utf8.count <= 4096 else { throw APIError.message("密钥格式不正确") }
        let q = query(endpoint), value = [kSecValueData as String: Data(secret.utf8)]
        var status = SecItemUpdate(q as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = q; item.merge(value) { _,new in new }; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.message("钥匙串保存失败（\(status)）") }
    }
}

enum APIError: LocalizedError {
    case status(Int), message(String)
    var errorDescription: String? { switch self {
    case .status(401): return "控制密钥不正确，请检查连接设置"
    case .status(let code): return "接口返回 \(code)"
    case .message(let text): return text
    } }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class NikkiAPI {
    let settings: ConnectionSettings
    private let secret: String
    let session: URLSession
    init(settings: ConnectionSettings, secret: String) {
        self.settings = settings; self.secret = secret
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = ["HTTPEnable":0, "HTTPSEnable":0, "SOCKSEnable":0]
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    func close() { session.invalidateAndCancel() }
    func request(_ path: [String], query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil, websocket: Bool = false) throws -> URLRequest {
        let base = try ConnectionSettings.normalized(settings.endpoint)
        var c = URLComponents(string: base)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        c.percentEncodedPath = "/" + path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        c.queryItems = query.isEmpty ? nil : query
        if websocket { c.scheme = c.scheme == "https" ? "wss" : "ws" }
        guard !secret.contains("\r"), !secret.contains("\n") else { throw APIError.message("密钥格式不正确") }
        var r = URLRequest(url: c.url!); r.httpMethod = method; r.httpBody = body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty { r.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization") }
        return r
    }
    func json(_ path: [String], query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request(path, query: query, method: method, body: body))
        guard let code = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(code) else { throw APIError.status(code) }
        if data.isEmpty { return [:] }
        guard data.count < 16_000_000, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return json
    }
    func select(group: String, node: String) async throws {
        // Re-read the exact group immediately before the only mutating request.
        let current = try await json(["proxies", group])
        guard current["type"] as? String == "Selector", (current["all"] as? [String])?.contains(node) == true else {
            throw APIError.message("节点列表已变化，请刷新后重选")
        }
        if current["now"] as? String == node { return }
        _ = try await json(["proxies", group], method: "PUT", body: JSONSerialization.data(withJSONObject: ["name":node]))
        let confirmed = try await json(["proxies", group])
        guard confirmed["now"] as? String == node else { throw APIError.message("切换结果未确认，请刷新查看当前节点") }
    }
}

enum NikkiData {
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
        return n.doubleValue
    }
    static func leaf(_ name: String, proxies: [String: [String: Any]]) -> String? {
        var seen = Set<String>(), current = name
        for _ in 0..<32 {
            guard seen.insert(current).inserted, let node = proxies[current] else { return nil }
            guard let next = node["now"] as? String, !next.isEmpty else {
                return node["all"] == nil ? current : nil
            }
            current = next
        }
        return nil
    }
    static func recentDelay(_ node: [String: Any]?, now: Date = Date()) -> Int? {
        guard let history = node?["history"] as? [[String: Any]], let last = history.last,
              let value = number(last["delay"]), value > 0, value < 60000,
              let stamp = last["time"] as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp), (0...600).contains(now.timeIntervalSince(date)) else { return nil }
        return Int(value)
    }
    static func subscription(_ provider: [String: Any]?, snapshot: inout MonitorSnapshot) {
        snapshot.usedBytes = nil; snapshot.totalBytes = nil; snapshot.expiresAt = nil; snapshot.subscriptionUpdatedAt = nil
        guard let info = provider?["subscriptionInfo"] as? [String: Any] else { return }
        if let up = number(info["Upload"] ?? info["upload"]), let down = number(info["Download"] ?? info["download"]), (up+down).isFinite { snapshot.usedBytes = up+down }
        if let total = number(info["Total"] ?? info["total"]), total > 0 { snapshot.totalBytes = total }
        if let expire = number(info["Expire"] ?? info["expire"]), expire > 0 { snapshot.expiresAt = Date(timeIntervalSince1970: expire) }
        if let stamp = provider?["updatedAt"] as? String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            snapshot.subscriptionUpdatedAt = f.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
        }
    }
}
