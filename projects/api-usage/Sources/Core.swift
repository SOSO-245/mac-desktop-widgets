import Foundation

struct APIProblem: LocalizedError { let message: String; var errorDescription: String? { message } }
struct Usage: Codable, Equatable {
    var input: Int64 = 0; var output: Int64 = 0; var requests: Int64 = 0
    var total: Int64 { input + output }
}
struct Balance: Codable, Equatable {
    let currency: String; let total: Decimal; let granted: Decimal; let topped: Decimal
}
struct Record<Value: Codable>: Codable {
    var value: Value; var date: Date; var period: String?
}
struct UsagePoint: Codable, Equatable, Identifiable {
    var date: Date; var tokens: Int64; var requests: Int64
    var id: Date { date }
}
struct CostPoint: Codable, Equatable, Identifiable {
    var day: Date; var currency: String; var amount: Decimal
    var id: String { "\(day.timeIntervalSince1970)-\(currency)" }
}
struct CostReport { var totals: [String: Decimal]; var points: [CostPoint] }
struct Snapshot: Codable {
    var siliconBalance: Record<SiliconAmount>?
    var siliconMonthly: Record<SiliconAmount>?
    var costHistory: Record<[CostPoint]>?
    var hourly: Record<[UsagePoint]>?
    var weekly: Record<[UsagePoint]>?
    var costs: Record<[String: Decimal]>?
    var usage: Record<Usage>?
    var balances: Record<[Balance]>?
    var available: Bool?
}
struct Month {
    let start: Date; let end: Date; let id: String
    // Costs uses daily buckets. Ending inside today omits today's bucket;
    // request through the next UTC midnight to include today's reported costs.
    var costsEndExclusive: Date {
        Date(timeIntervalSince1970: (floor(end.timeIntervalSince1970 / 86400) + 1) * 86400)
    }
    init(now: Date = Date()) {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        start = c.date(from: c.dateComponents([.year, .month], from: now))!
        end = now
        let p = c.dateComponents([.year, .month], from: now)
        id = String(format: "%04d-%02d", p.year!, p.month!)
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class APIClient {
    let session: URLSession
    init(session: URLSession? = nil) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20; c.timeoutIntervalForResource = 40
        c.httpShouldSetCookies = false; c.urlCache = nil
        self.session = session ?? URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }
    func get(_ url: URL, key: String) async throws -> [String: Any] {
        guard url.scheme == "https", ["api.openai.com", "api.deepseek.com"].contains(url.host ?? "") else { throw APIProblem(message: "地址不受支持") }
        var r = URLRequest(url: url); r.httpMethod = "GET"
        r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: r)
        guard let h = response as? HTTPURLResponse else { throw APIProblem(message: "响应无效") }
        switch h.statusCode {
        case 200...299: break
        case 401: throw APIProblem(message: "密钥无效或已过期，请在设置中更新")
        case 403: throw APIProblem(message: "权限不足；OpenAI 需要组织 Admin Key")
        case 429: throw APIProblem(message: "请求受限，稍后自动重试")
        case 300...399: throw APIProblem(message: "已拒绝接口重定向")
        default: throw APIProblem(message: "服务暂不可用（\(h.statusCode)）")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIProblem(message: "响应格式无效") }
        return json
    }
    func rows(path: String, key: String, month: Month, project: String, since: Date? = nil, width: String = "1d", includeDates: Bool = false) async throws -> [[String: Any]] {
        var all = [[String: Any]](); var cursor: String?; var seen = Set<String>()
        for _ in 0..<100 {
            var u = URLComponents(string: "https://api.openai.com/v1/organization/" + path)!
            let queryEnd = path == "costs" ? month.costsEndExclusive : month.end
            u.queryItems = [URLQueryItem(name: "start_time", value: String(Int((since ?? month.start).timeIntervalSince1970))), URLQueryItem(name: "end_time", value: String(Int(queryEnd.timeIntervalSince1970))), URLQueryItem(name: "bucket_width", value: width), URLQueryItem(name: "limit", value: "31")]
            if !project.isEmpty { u.queryItems!.append(URLQueryItem(name: "project_ids", value: project)) }
            if let cursor { u.queryItems!.append(URLQueryItem(name: "page", value: cursor)) }
            let j = try await get(u.url!, key: key)
            guard let buckets = j["data"] as? [[String: Any]], let more = j["has_more"] as? Bool else { throw APIProblem(message: "统计响应缺少字段") }
            for b in buckets {
                guard let results = b["results"] as? [[String: Any]] else { throw APIProblem(message: "统计分桶无效") }
                if path == "costs" || includeDates {
                    guard let start = b["start_time"] as? NSNumber else { throw APIProblem(message: "费用分桶缺少日期") }
                    if results.isEmpty {
                        all.append(path == "costs" ? ["_bucket_start": start, "amount": ["value": 0, "currency": "usd"]] : ["_bucket_start": start, "input_tokens": 0, "output_tokens": 0, "num_model_requests": 0])
                    } else {
                        all += results.map { var row = $0; row["_bucket_start"] = start; return row }
                    }
                } else { all += results }
            }
            if !more { return all }
            guard let next = j["next_page"] as? String, !next.isEmpty, seen.insert(next).inserted else { throw APIProblem(message: "统计分页异常，未显示不完整数据") }
            cursor = next
        }
        throw APIProblem(message: "统计分页过多，请缩小项目范围")
    }
    func costs(key: String, month: Month, project: String) async throws -> [String: Decimal] {
        try await costReport(key: key, month: month, project: project).totals
    }
    func costReport(key: String, month: Month, project: String) async throws -> CostReport {
        let rows = try await rows(path: "costs", key: key, month: month, project: project)
        var totals: [String: Decimal] = [:]
        var daily: [String: CostPoint] = [:]
        for row in rows {
            guard let a = row["amount"] as? [String: Any], let currency = a["currency"] as? String,
                  let d = Self.decimal(a["value"]), let timestamp = row["_bucket_start"] as? NSNumber else { throw APIProblem(message: "费用字段无效") }
            let day = Date(timeIntervalSince1970: timestamp.doubleValue)
            guard day >= month.start, day <= month.end else { throw APIProblem(message: "费用日期不在查询范围内") }
            let c = currency.uppercased()
            totals[c, default: 0] += d
            let id = "\(timestamp.int64Value)-\(c)"
            if var point = daily[id] { point.amount += d; daily[id] = point }
            else { daily[id] = CostPoint(day: day, currency: c, amount: d) }
        }
        return CostReport(totals: totals.isEmpty ? ["USD": 0] : totals,
                          points: daily.values.sorted { $0.day == $1.day ? $0.currency < $1.currency : $0.day < $1.day })
    }
    func usage(key: String, month: Month, project: String) async throws -> Usage {
        var result = Usage()
        for r in try await rows(path: "usage/completions", key: key, month: month, project: project) {
            guard let i = r["input_tokens"] as? NSNumber, let o = r["output_tokens"] as? NSNumber, let n = r["num_model_requests"] as? NSNumber, i.int64Value >= 0, o.int64Value >= 0, n.int64Value >= 0 else { throw APIProblem(message: "用量字段无效") }
            result.input += i.int64Value; result.output += o.int64Value; result.requests += n.int64Value
        }
        return result
    }
    func usageHistory(key: String, now: Date, project: String, hourly: Bool) async throws -> [UsagePoint] {
        let seconds: Double = hourly ? 3600 : 86400
        let count = hourly ? 24 : 7
        // Current partial bucket plus the preceding 23 hours / 6 UTC days.
        let since = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / seconds) * seconds - Double(count - 1) * seconds)
        let rows = try await rows(path: "usage/completions", key: key, month: Month(now: now), project: project, since: since, width: hourly ? "1h" : "1d", includeDates: true)
        var points: [Date: UsagePoint] = [:]
        for r in rows {
            guard let t = r["_bucket_start"] as? NSNumber, let i = r["input_tokens"] as? NSNumber,
                  let o = r["output_tokens"] as? NSNumber, let n = r["num_model_requests"] as? NSNumber,
                  i.int64Value >= 0, o.int64Value >= 0, n.int64Value >= 0 else { throw APIProblem(message: "趋势字段无效") }
            let day = Date(timeIntervalSince1970: t.doubleValue)
            guard day >= since, day <= now else { throw APIProblem(message: "趋势日期超出范围") }
            var p = points[day] ?? UsagePoint(date: day, tokens: 0, requests: 0)
            p.tokens += i.int64Value + o.int64Value; p.requests += n.int64Value; points[day] = p
        }
        return points.values.sorted { $0.date < $1.date }
    }
    func balance(key: String) async throws -> ([Balance], Bool) {
        let j = try await get(URL(string: "https://api.deepseek.com/user/balance")!, key: key)
        guard let a = j["is_available"] as? Bool, let rows = j["balance_infos"] as? [[String: Any]], !rows.isEmpty else { throw APIProblem(message: "余额响应缺少字段") }
        return (try rows.map { r in
            guard let c = r["currency"] as? String, ["CNY", "USD"].contains(c), let t = Self.decimal(r["total_balance"]), let g = Self.decimal(r["granted_balance"]), let p = Self.decimal(r["topped_up_balance"]) else { throw APIProblem(message: "余额字段无效") }
            return Balance(currency: c, total: t, granted: g, topped: p)
        }, a)
    }
    static func decimal(_ a: Any?) -> Decimal? {
        if let s = a as? String { return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) }
        if let n = a as? NSNumber { return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
    }
}
func money(_ x: Decimal, _ currency: String) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
    return (currency == "USD" ? "$" : currency == "CNY" ? "¥" : currency + " ") + (f.string(from: x as NSDecimalNumber) ?? "—")
}
func compact(_ n: Int64) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
    return String(n)
}
