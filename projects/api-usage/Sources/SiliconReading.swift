import Foundation
struct SiliconAmount: Codable, Equatable { let amount: Decimal; let currency: String }
struct SiliconPageReading {
    let kind: String; let value: SiliconAmount; let period: String?
    static func parse(_ raw: [String:Any], url: URL?) throws -> Self {
        guard url?.scheme == "https", url?.host == "cloud.siliconflow.cn",
              raw["authenticated"] as? Bool == true,
              let rows = raw["values"] as? [[String:Any]], rows.count == 1,
              let row = rows.first, let kind = row["kind"] as? String, let text = row["text"] as? String else { throw APIProblem(message: "页面尚未就绪或字段不唯一，保留缓存") }
        let pattern: String; let period: String?
        if kind == "balance", url?.path == "/me/expensebill" {
            pattern = #"^余额\s*¥\s*(-?[0-9]+(?:\.[0-9]+)?)(?:…|\.\.\.)?\s*[（(]剩余可透支额度\s*¥\s*[0-9]+(?:\.[0-9]+)?[）)]$"#
            period = nil
        } else if kind == "monthly", url?.path == "/me/bills", row["unfiltered"] as? Bool == true,
                  let month = row["period"] as? String, month.range(of: #"^20[0-9]{2}-(?:0[1-9]|1[0-2])$"#, options: .regularExpression) != nil {
            pattern = #"^¥\s*(-?[0-9]+(?:\.[0-9]+)?)$"#; period = month
        } else { throw APIProblem(message: "请打开余额页，或选择无产品筛选的按月账单") }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex...,in: clean)),
              let range = Range(match.range(at: 1), in: clean),
              let amount = Decimal(string: String(clean[range]), locale: Locale(identifier: "en_US_POSIX")) else { throw APIProblem(message: "网页金额格式变化，保留缓存并等待重新核对") }
        return Self(kind: kind, value: SiliconAmount(amount: amount, currency: "CNY"), period: period)
    }
}
