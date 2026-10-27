import Foundation

let resetsWebsite = URL(string: "https://codex-resets.com/zh-CN")!
let resetsWidgetKind = "CodexResetsWidget"

enum ResetNavigation {
    static let widgetURL = URL(string: "codexresets://website")!

    static func originalPostURL(_ raw:String?) -> URL? {
        guard let raw, let url=URL(string:raw), url.scheme?.lowercased()=="https",
              let host=url.host?.lowercased(), ["x.com","www.x.com","twitter.com","www.twitter.com"].contains(host),
              url.user==nil, url.password==nil, url.port==nil,
              url.path.range(of:"^/[A-Za-z0-9_]+/status/[0-9]+/?$",options:.regularExpression) != nil else {return nil}
        return url
    }

    static func websiteDestination(for url: URL) -> URL? {
        // Accept the old timeline URL as well as the new explicit widget route.
        // Never forward an arbitrary URL or URL-supplied redirect destination.
        guard url == widgetURL || url == resetsWebsite else { return nil }
        return resetsWebsite
    }
}

struct APIEnvelope<T: Codable>: Codable {
    let data: T
    let meta: APIMeta
}
struct APIMeta: Codable { let apiVersion: String; let generatedAt: Date }
struct ResetSource: Codable { let type: String; let author: String?; let url: String? }
struct ResetEvent: Codable, Identifiable {
    let id: String
    let resetType: String
    let announcedAt: Date
    let source: ResetSource
    var typeLabel: String { resetType == "regular" ? "常规额度" : resetType == "banked" ? "储备额度" : "额度重置" }
}
struct ScheduledReset: Codable {
    let id: String
    let status: String
    let resetType: String
    let announcedAt: Date
    let scheduledFor: Date?
}
struct ActiveWatch: Codable { let expiresAt: Date? } // A watch is never a confirmed reset.
struct ResetStats: Codable {
    let total: Int
    let lastResetAt: Date?
    let daysSinceLast: Double?
    let avgIntervalDays: Double?
}
struct ResetStatus: Codable {
    let latestReset: ResetEvent?
    let scheduledReset: ScheduledReset?
    let activeWatch: ActiveWatch?
    let stats: ResetStats
}

enum ResetPhase: Equatable {
    case scheduled(Date), awaitingConfirmation, unscheduledTime, watching, noSchedule, unavailable
}
struct ResetSnapshot {
    var status: ResetStatus?
    var history: [ResetEvent]
    var checkedAt: Date?
    var generatedAt: Date?
    var issue: String?
    var isSample = false
    static let empty = ResetSnapshot(status: nil, history: [], checkedAt: nil, generatedAt: nil, issue: nil)
    func phase(at now: Date) -> ResetPhase {
        guard let status else { return .unavailable }
        if let scheduled = status.scheduledReset, scheduled.status == "scheduled" {
            guard let deadline = scheduled.scheduledFor else { return .unscheduledTime }
            return deadline > now ? .scheduled(deadline) : .awaitingConfirmation
        }
        if let watch = status.activeWatch, let expiresAt = watch.expiresAt, expiresAt > now { return .watching }
        return .noSchedule
    }
    func isStale(at now: Date) -> Bool {
        guard let checkedAt, let generatedAt else { return true }
        return issue != nil || now.timeIntervalSince(checkedAt) > 3600 || now.timeIntervalSince(generatedAt) > 21600
    }
    func freshness(at now: Date) -> String {
        if isSample { return "示例" }
        guard status != nil else { return issue == nil ? "待更新" : "连接失败" }
        return isStale(at: now) ? "缓存" : "已更新"
    }
    static var sample: ResetSnapshot {
        let now = Date()
        let source = ResetSource(type: "x_post", author: "thsottiaux", url: nil)
        let events = [2.4, 4.8, 7.4].enumerated().map { ResetEvent(id: "sample-\($0.offset)", resetType: "regular", announcedAt: now.addingTimeInterval(-$0.element * 86400), source: source) }
        return ResetSnapshot(status: ResetStatus(latestReset: events[0], scheduledReset: ScheduledReset(id: "sample", status: "scheduled", resetType: "regular", announcedAt: now.addingTimeInterval(-3600), scheduledFor: now.addingTimeInterval(3900)), activeWatch: nil, stats: ResetStats(total: 64, lastResetAt: events[0].announcedAt, daysSinceLast: 2.4, avgIntervalDays: 6.3)), history: events, checkedAt: now, generatedAt: now, issue: nil, isSample: true)
    }
}

enum ResetJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return value }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date"))
        }
        return decoder
    }
}

private struct CachedResponse: Codable { let data: Data; let etag: String?; let checkedAt: Date }
enum ResetFetchError: Error { case response, http(Int), missingCache, invalidPayload }

enum ResetClient {
    private static let store = ResetStore()
    static func load(force: Bool = false) async -> ResetSnapshot { await store.load(force: force) }
}

actor ResetStore {
    private let session: URLSession
    private let defaults: UserDefaults
    private func retryDate(_ path: String) -> Date? { defaults.object(forKey: "public-api-retry-" + path) as? Date }
    private var inFlight: Task<ResetSnapshot, Never>?
    init(session: URLSession? = nil, defaults: UserDefaults = .standard) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 25
        self.session = session ?? URLSession(configuration: config); self.defaults = defaults
    }
    func load(force: Bool = false) async -> ResetSnapshot {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.fetchSnapshot(force: force) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
    private func fetchSnapshot(force: Bool) async -> ResetSnapshot {
        var result = ResetSnapshot.empty
        do {
            let status: (APIEnvelope<ResetStatus>, Date) = try await fetch("status", force: force)
            result.status = status.0.data; result.generatedAt = status.0.meta.generatedAt; result.checkedAt = status.1
        } catch {
            if let cache = cached("status"), let status = try? ResetJSON.decoder().decode(APIEnvelope<ResetStatus>.self, from: cache.data) {
                result.status = status.data; result.generatedAt = status.meta.generatedAt; result.checkedAt = cache.checkedAt
            }
            result.issue = "网络暂不可用，保留上次数据"
        }
        do {
            let history: (APIEnvelope<[ResetEvent]>, Date) = try await fetch("resets?limit=3&order=desc", force: force)
            result.history = history.0.data.sorted { $0.announcedAt > $1.announcedAt }
        } catch {
            if let cache = cached("resets?limit=3&order=desc"), let history = try? ResetJSON.decoder().decode(APIEnvelope<[ResetEvent]>.self, from: cache.data) {
                result.history = history.data.sorted { $0.announcedAt > $1.announcedAt }
            }
            result.issue = result.issue ?? "历史记录暂未更新"
        }
        return result
    }
    private func cached(_ path: String) -> CachedResponse? {
        guard let bytes = defaults.data(forKey: "public-api-v1-" + path) else { return nil }
        guard let cache = try? JSONDecoder().decode(CachedResponse.self, from: bytes) else {
            defaults.removeObject(forKey: "public-api-v1-" + path)
            return nil
        }
        return cache
    }
    private func fetch<T: Codable>(_ path: String, force: Bool) async throws -> (APIEnvelope<T>, Date) {
        var cache = cached(path)
        let now = Date()
        if let retry = retryDate(path), retry > now { throw ResetFetchError.http(429) }
        defaults.removeObject(forKey: "public-api-retry-" + path)
        if let saved = cache {
            let decoded = try? ResetJSON.decoder().decode(APIEnvelope<T>.self, from: saved.data)
            if decoded?.meta.apiVersion != "v1" {
                // Only discard unusable cache. Valid offline snapshots are retained.
                defaults.removeObject(forKey: "public-api-v1-" + path)
                cache = nil
            }
        }
        if !force, let cache, now.timeIntervalSince(cache.checkedAt) < 60 {
            return (try ResetJSON.decoder().decode(APIEnvelope<T>.self, from: cache.data), cache.checkedAt)
        }
        var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/" + path)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexResetsMacWidget/1.0", forHTTPHeaderField: "User-Agent")
        if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResetFetchError.response }
        if http.statusCode == 429 {
            let value = http.value(forHTTPHeaderField: "Retry-After") ?? "60"
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let retry = Double(value).map { now.addingTimeInterval(max(1, $0)) } ?? formatter.date(from: value) ?? now.addingTimeInterval(60)
            defaults.set(retry, forKey: "public-api-retry-" + path)
            throw ResetFetchError.http(429)
        }
        let data: Data
        switch http.statusCode {
        case 200: data = bytes
        case 304:
            guard let cache else { throw ResetFetchError.missingCache }
            data = cache.data
        default: throw ResetFetchError.http(http.statusCode)
        }
        let decoded = try ResetJSON.decoder().decode(APIEnvelope<T>.self, from: data)
        guard decoded.meta.apiVersion == "v1" else { throw ResetFetchError.invalidPayload }
        let saved = CachedResponse(data: data, etag: http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? cache?.etag : nil), checkedAt: now)
        defaults.set(try JSONEncoder().encode(saved), forKey: "public-api-v1-" + path)
        defaults.removeObject(forKey: "public-api-retry-" + path)
        return (decoded, now)
    }
}

// Clock text is an absolute local time. Supply minute entries so it does not
// stay frozen between network refreshes. No network request is made per minute.
// Bound the batch to one hour: 180 rendered large entries exceeded the desktop
// host's archive limit (10,498,872 bytes) and left the entire widget blank.
enum ResetTimelineDates {
    static func dates(now: Date, snapshot: ResetSnapshot, showClock: Bool) -> [Date] {
        var dates = [now, now.addingTimeInterval(3601)]
        if showClock {
            let first = floor(now.timeIntervalSince1970 / 60) * 60 + 60
            dates += (0..<60).map { Date(timeIntervalSince1970: first + Double($0 * 60)) }
        }
        if case .scheduled(let deadline) = snapshot.phase(at: now) { dates.append(deadline) }
        if let expiry = snapshot.status?.activeWatch?.expiresAt, expiry > now { dates.append(expiry) }
        return Array(Set(dates)).sorted()
    }
}


enum ResetMenuTone { case green, pink, neutral }
struct ResetMenuDisplay {
    let text: String
    let tone: ResetMenuTone
    static func make(snapshot: ResetSnapshot, now: Date) -> ResetMenuDisplay {
        let stale = snapshot.isStale(at:now)
        switch snapshot.phase(at:now) {
        case .scheduled(let deadline):
            let delta = deadline.timeIntervalSince(now)
            guard delta.isFinite, delta > 0, delta < 315_360_000 else { return .init(text:"时间待确认",tone:.neutral) }
            let seconds = Int(ceil(delta)), days = seconds / 86400
            let time = String(format:"%02d:%02d:%02d",(seconds % 86400) / 3600,(seconds % 3600) / 60,seconds % 60)
            return .init(text:(stale ? "缓存 " : "") + (days > 0 ? "\(days)天 " : "") + time,
                         tone:!stale && !snapshot.isSample ? .pink : .neutral)
        case .awaitingConfirmation: return .init(text:"重置待确认",tone:.neutral)
        case .unscheduledTime: return .init(text:"重置时间待定",tone:.neutral)
        case .watching, .noSchedule:
            let last = snapshot.status?.stats.lastResetAt ?? snapshot.status?.latestReset?.announcedAt
                ?? snapshot.history.map(\.announcedAt).max()
            guard let last, now.timeIntervalSince(last).isFinite,
                  now.timeIntervalSince(last) >= 0, now.timeIntervalSince(last) < 315_360_000 else {
                return .init(text:"上次重置时间未知",tone:.neutral)
            }
            let totalHours = Int(now.timeIntervalSince(last) / 3600)
            let days = totalHours / 24, hours = totalHours % 24
            return .init(text:(stale ? "缓存 · " : "") + "已重置 \(days) 天 \(hours) 小时",tone:snapshot.isSample ? .neutral : .green)
        case .unavailable: return .init(text:"重置 —",tone:.neutral)
        }
    }
}

// Only a fresh, explicitly dated schedule is actionable. Persist acknowledgements
// by schedule identity AND deadline so a revised time asks for attention again.
enum ResetAttention {
    static func planKey(snapshot:ResetSnapshot,now:Date)->String? {
        guard !snapshot.isSample,!snapshot.isStale(at:now),
              let plan=snapshot.status?.scheduledReset,plan.status=="scheduled",
              let deadline=plan.scheduledFor,deadline.timeIntervalSince1970.isFinite else {return nil}
        return plan.id+"|"+String(format:"%.3f",deadline.timeIntervalSince1970)
    }
    static func pendingKey(snapshot:ResetSnapshot,now:Date,acknowledged:[String])->String? {
        guard let key=planKey(snapshot:snapshot,now:now),!acknowledged.contains(key) else{return nil}
        return key
    }
    static func acknowledging(_ key:String,in previous:[String])->[String] {
        Array((previous.filter{$0 != key}+[key]).suffix(32))
    }
}
