import Foundation
import CoreFoundation

/// `/traffic` reports bytes per second for traffic handled by the Clash core.
/// It is not a subscription billing counter, and may include DIRECT traffic.
struct TrafficSample {
    let uploadBps: Double
    let downloadBps: Double

    static func decode(_ data: Data) -> TrafficSample? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let up = finiteNumber(object["up"]),
              let down = finiteNumber(object["down"]) else { return nil }
        return TrafficSample(uploadBps: up, downloadBps: down)
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
}

/// Difference each live connection, never difference the sum of a changing list.
/// Short-lived connections between snapshots cannot be observed by this API.
struct ProxyTrafficSampler {
    private struct Counter {
        let up: Double
        let down: Double
        let chains: [String]
    }
    private var previous: [String: Counter] = [:]
    private var previousTime: TimeInterval?
    private var previousDate: Date?

    mutating func sample(_ data: Data, proxyTypes: [String: String],
                         time: TimeInterval = ProcessInfo.processInfo.systemUptime,
                         date: Date = Date()) -> TrafficSample? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["connections"],
              raw is NSNull || raw is [[String: Any]] else { self = Self(); return nil }
        let rows = raw as? [[String: Any]] ?? []
        guard rows.count <= 100_000 else { self = Self(); return nil }
        var current: [String: Counter] = [:]
        var newStarts: [String: Date] = [:]
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, current[id] == nil,
                  let up = number(row["upload"]), let down = number(row["download"]),
                  let chains = row["chains"] as? [String], !chains.isEmpty else {
                self = Self(); return nil
            }
            current[id] = Counter(up: up, down: down, chains: chains)
            if let start = row["start"] as? String { newStarts[id] = Self.parseDate(start) }
        }
        defer { previous = current; previousTime = time; previousDate = date }
        guard let oldTime = previousTime, let oldDate = previousDate,
              time.isFinite, time > oldTime, time - oldTime <= 5 else { return nil }
        var up = 0.0, down = 0.0
        for (id, now) in current {
            guard Self.isProxy(now.chains, types: proxyTypes) else { continue }
            if let old = previous[id] {
                guard now.chains == old.chains else { continue }
                guard now.up >= old.up, now.down >= old.down else { return nil }
                up += now.up - old.up; down += now.down - old.down
            } else if let start = newStarts[id], start >= oldDate, start <= date {
                // Only include a new connection's total if it began in this interval.
                up += now.up; down += now.down
            }
        }
        guard up.isFinite, down.isFinite else { return nil }
        return TrafficSample(uploadBps: up / (time - oldTime), downloadBps: down / (time - oldTime))
    }

    static func isProxy(_ chains: [String], types: [String: String]) -> Bool {
        // Mihomo lists the actual outbound first, followed by policy groups.
        guard let leaf = chains.first, !leaf.isEmpty else { return false }
        let excluded = ["direct", "reject", "reject-drop", "compatible", "pass"]
        return !excluded.contains(leaf.lowercased()) && !excluded.contains((types[leaf] ?? "").lowercased())
    }
    private func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
        return n.doubleValue
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}


/// Global counters include closed connections. Do not sum changing live totals.
struct DualTrafficSampler {
    private var proxySampler=ProxyTrafficSampler()
    private var previous:(time:Double,up:Double,down:Double)?
    mutating func sample(_ data:Data,proxyTypes:[String:String],time:Double=ProcessInfo.processInfo.systemUptime,date:Date=Date())->TrafficPairPoint? {
        guard let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let raw=json["connections"],raw is NSNull || raw is [[String:Any]],time.isFinite else {self=Self();return nil}
        let proxy=proxySampler.sample(data,proxyTypes:proxyTypes,time:time,date:date)
        func number(_ key:String)->Double? {
            guard let n=json[key] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,n.doubleValue>=0 else{return nil}
            return n.doubleValue
        }
        var up:Double?,down:Double?
        if let u=number("uploadTotal"),let d=number("downloadTotal") {
            if let old=previous,time>old.time,time-old.time<=5,u>=old.up,d>=old.down {
                let a=(u-old.up)/(time-old.time),b=(d-old.down)/(time-old.time)
                if a.isFinite,b.isFinite {up=a;down=b}
            }
            previous=(time,u,d)
        } else {previous=nil}
        return TrafficPairPoint(allDown:down,allUp:up,proxyDown:proxy?.downloadBps,proxyUp:proxy?.uploadBps)
    }
}
