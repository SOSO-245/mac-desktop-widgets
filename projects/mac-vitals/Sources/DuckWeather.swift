import Foundation

struct DuckWeather: Codable, Equatable {
    var condition: String?
    var observedAt: Date?
    var rainEndedAt: Date?
    static let rain: Set<String> = ["rainy", "pouring", "lightning-rainy"]
    static let snow: Set<String> = ["snowy", "snowy-rainy"]
    static let storms: Set<String> = ["lightning", "lightning-rainy", "typhoon", "hurricane"]
    static let known: Set<String> = rain.union(snow).union(storms).union(["sunny","clear-night","partlycloudy","cloudy","fog","hail","windy","windy-variant","exceptional"])
    func fresh(at now: Date) -> Bool {
        guard let observedAt, condition != nil else { return false }
        return (-60...1800).contains(now.timeIntervalSince(observedAt))
    }
    mutating func observe(_ next: String?, at date: Date?, now: Date) {
        guard let next, Self.known.contains(next), let date, (-60...1800).contains(now.timeIntervalSince(date)) else {
            condition = nil; observedAt = nil; rainEndedAt = nil; return
        }
        // Only an observed rain-to-dry transition creates a rainbow; restart/cache gaps do not.
        if fresh(at: now), let old = condition, Self.rain.contains(old),
           !Self.rain.contains(next), !Self.snow.contains(next), !Self.storms.contains(next), next != "hail", next != "exceptional" {
            rainEndedAt = now
        }
        if Self.rain.contains(next) || Self.snow.contains(next) || Self.storms.contains(next) || next == "hail" { rainEndedAt = nil }
        condition = next; observedAt = date
    }
    enum Appearance: String { case original, spring, summer, winter, rain, snow, football }
    func appearance(at now: Date, timezone: String) -> Appearance {
        if fresh(at: now), let condition {
            if Self.storms.contains(condition) { return .football }
            if Self.snow.contains(condition) { return .snow }
            if Self.rain.contains(condition) { return .rain }
        }
        // Calendar seasons use the configured weather time zone and northern-hemisphere months.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: timezone) ?? .current
        switch cal.component(.month, from: now) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 12,1,2: return .winter
        default: return .original
        }
    }
    func rainbowOpacity(at now: Date) -> Double {
        guard fresh(at: now), let rainEndedAt, let condition,
              !Self.rain.contains(condition), !Self.snow.contains(condition), !Self.storms.contains(condition), condition != "hail", condition != "exceptional" else { return 0 }
        let age = now.timeIntervalSince(rainEndedAt)
        guard age >= 0, age < 7200 else { return 0 }
        return min(1, age / 30) * min(1, (7200 - age) / 600)
    }
}
