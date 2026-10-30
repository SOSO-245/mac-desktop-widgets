import AppKit
import SwiftUI
import Security

struct Vault {
    static let service = "local.homeatlas.APIUsage"
    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read(_ account: String) throws -> String? {
        var q = query(account); q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &data)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let d = data as? Data, let key = String(data: d, encoding: .utf8) else { throw APIProblem(message: "钥匙串未允许读取，请在系统提示中允许") }
        return key
    }
    static func save(_ key: String, account: String) throws {
        let q = query(account)
        let value = [kSecValueData as String: Data(key.utf8)]
        let updated = SecItemUpdate(q as CFDictionary, value as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw APIProblem(message: "钥匙串保存失败（\(updated)）") }
        var add = q; add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let s = SecItemAdd(add as CFDictionary, nil)
        guard s == errSecSuccess else { throw APIProblem(message: "钥匙串保存失败（\(s)）") }
    }
    static func delete(_ account: String) throws {
        let s = SecItemDelete(query(account) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw APIProblem(message: "钥匙串删除失败") }
    }
}
@MainActor final class Store: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var errors: [String: String] = [:]
    @Published var refreshing = false
    @Published var hasOpenAI = false
    @Published var hasDeepSeek = false
    @Published var message = ""
    let defaults = UserDefaults.standard
    var onChange: (() -> Void)?
    private var keys: [String: String] = [:]
    private var generation = 0
    private var timer: Timer?
    private let client = APIClient()
    private let cache: URL
    let preview: Bool
    init(preview: Bool = false) {
        self.preview = preview
        cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("APIUsageCard/cache.json")
        if preview {
            snapshot.costs = Record(value: ["USD": Decimal(string: "12.48")!], date: Date(), period: Month().id)
            snapshot.costHistory = Record(value: [0.2,0.38,0.3,0.66,0.48,0.92,0.7,1.18,0.91,1.45,1.12,1.8].enumerated().map { CostPoint(day: Month().start.addingTimeInterval(Double($0.offset)*86400), currency: "USD", amount: Decimal($0.element)) }, date: Date(), period: Month().id)
            snapshot.usage = Record(value: Usage(input: 1_820_000, output: 348_000, requests: 1264), date: Date(), period: Month().id)
            snapshot.balances = Record(value: [Balance(currency: "CNY", total: 86.42, granted: 6.42, topped: 80)], date: Date(), period: nil)
            let samples: [Int64] = [0,0,2,0,3,0,1,0,2,0,3,0,1,0,3,12,36,210,71,19,8,3,0,2]
            snapshot.hourly = Record(value: samples.enumerated().map { UsagePoint(date: Date().addingTimeInterval(Double($0.offset - 23)*3600), tokens: $0.element*1000, requests: $0.element) }, date: Date(), period: nil)
            snapshot.weekly = Record(value: [40,75,62,120,85,240,95].enumerated().map { UsagePoint(date: Date().addingTimeInterval(Double($0.offset - 6)*86400), tokens: Int64($0.element)*10000, requests: Int64($0.element)) }, date: Date(), period: nil)
            hasOpenAI = true; hasDeepSeek = true
            return
        }
        if let d = try? Data(contentsOf: cache), let s = try? JSONDecoder().decode(Snapshot.self, from: d) { snapshot = s }
        expireMonth()
    }
    func start() {
        guard !preview else { return }
        // Only this application's own explicitly saved connections are read.
        for p in ["openai", "deepseek"] {
            do { keys[p] = try Vault.read(p) }
            catch { errors[p] = error.localizedDescription }
        }
        hasOpenAI = keys["openai"] != nil; hasDeepSeek = keys["deepseek"] != nil
        schedule(); Task { await refresh() }
    }
    func schedule() {
        timer?.invalidate()
        let minutes = defaults.integer(forKey: "interval")
        timer = Timer.scheduledTimer(withTimeInterval: Double([1,5,15,30].contains(minutes) ? minutes : 5) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
    func expireMonth() {
        let id = Month().id
        if snapshot.costs?.period != id { snapshot.costs = nil }
        if snapshot.costHistory?.period != id { snapshot.costHistory = nil }
        if snapshot.usage?.period != id { snapshot.usage = nil }
    }
    func saveConnection(_ provider: String, key: String, project: String = "") {
        guard !refreshing else { message = "请等待本次刷新结束"; return }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { message = "请填写密钥"; return }
        guard !value.contains(where: { $0.isWhitespace }) else { message = "密钥不能包含空格或换行"; return }
        do {
            try Vault.save(value, account: provider)
            generation += 1; keys[provider] = value
            if provider == "openai" {
                hasOpenAI = true; snapshot.costs = nil; snapshot.costHistory = nil; snapshot.usage = nil; snapshot.hourly = nil; snapshot.weekly = nil
                defaults.set(project.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "project")
                errors["costs"] = nil; errors["usage"] = nil; errors["history24"] = nil; errors["history7"] = nil
            } else { hasDeepSeek = true; snapshot.balances = nil; snapshot.available = nil }
            errors[provider] = nil; message = "连接已保存，正在读取 API 数据"; persist()
            Task { await refresh() }
        } catch { message = error.localizedDescription }
    }
    func remove(_ p: String) {
        guard !refreshing else { return }
        do {
            try Vault.delete(p); keys[p] = nil; generation += 1; errors[p] = nil
            if p == "openai" { hasOpenAI = false; snapshot.costs = nil; snapshot.costHistory = nil; snapshot.usage = nil; snapshot.hourly = nil; snapshot.weekly = nil; errors["costs"] = nil; errors["usage"] = nil; errors["history24"] = nil; errors["history7"] = nil; defaults.removeObject(forKey: "project") }
            else { hasDeepSeek = false; snapshot.balances = nil; snapshot.available = nil }
            persist(); onChange?(); message = "连接和缓存已移除"
        } catch { message = error.localizedDescription }
    }
    func refresh() async {
        guard !refreshing, !preview else { return }
        refreshing = true; defer { refreshing = false; onChange?() }
        expireMonth(); let month = Month(); let revision = generation
        if let key = keys["openai"] {
            let project = defaults.string(forKey: "project") ?? ""
            do {
                let c = try await client.costReport(key: key, month: month, project: project)
                if revision == generation { snapshot.costs = Record(value: c.totals, date: Date(), period: month.id); snapshot.costHistory = Record(value: c.points, date: Date(), period: month.id); errors["costs"] = nil }
            } catch { errors["costs"] = safe(error) }
            do {
                let u = try await client.usage(key: key, month: month, project: project)
                if revision == generation { snapshot.usage = Record(value: u, date: Date(), period: month.id); errors["usage"] = nil }
            } catch { errors["usage"] = safe(error) }
            for hourly in [true, false] {
                let id = hourly ? "history24" : "history7"
                do {
                    let points = try await client.usageHistory(key: key, now: month.end, project: project, hourly: hourly)
                    if revision == generation {
                        let record = Record(value: points, date: Date(), period: Optional<String>.none)
                        if hourly { snapshot.hourly = record } else { snapshot.weekly = record }
                        errors[id] = nil
                    }
                } catch { errors[id] = safe(error) }
            }
        }
        if let key = keys["deepseek"] {
            do {
                let (balances, available) = try await client.balance(key: key)
                if revision == generation { snapshot.balances = Record(value: balances, date: Date(), period: nil); snapshot.available = available; errors["deepseek"] = nil }
            } catch { errors["deepseek"] = safe(error) }
        }
        expireMonth(); persist()
    }
    private func safe(_ error: Error) -> String {
        if let p = error as? APIProblem { return p.message }
        if let u = error as? URLError, u.code == .timedOut { return "网络超时，保留上次数据" }
        return "网络或数据读取失败，请稍后刷新"
    }
    private func persist() {
        guard !preview else { return }
        do {
            let dir = cache.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: cache, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        } catch { message = "缓存保存失败，本次读取仍可显示" }
    }
    var costText: String { snapshot.costs.map { $0.value.sorted(by: { $0.key < $1.key }).map { money($0.value, $0.key) }.joined(separator: " / ") } ?? "—" }
    var balanceText: String { snapshot.balances.map { $0.value.map { money($0.total, $0.currency) }.joined(separator: " / ") } ?? "—" }
}
