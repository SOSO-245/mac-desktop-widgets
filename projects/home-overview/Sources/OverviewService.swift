import Foundation
import CoreFoundation

/// In-memory, credential-free cache. Successful requests keep their own fetch time.
struct OverviewDetails {
    var states: [String: OverviewStatePayload] = [:]
    var stateIssues: [String: String] = [:]
    var history: [OverviewHistorySample] = []
    var historyFetchedAt: Date?
    var historyIssue: String?
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var connectionIssue: String?
    var sourceIdentity: String?
    var outdoorPM25Entity: String?
}

struct OverviewStatePayload {
    let data: Data
    let fetchedAt: Date
}

struct OverviewHistorySample {
    let date: Date
    var temperature: Double?
    var humidity: Double?
    var hasTemperatureSample = false
    var hasHumiditySample = false
}

enum OverviewEntity {
    static let weather = "weather.forecast_wo_de_jia"
    static let nasTemperature = "sensor.ds1525plus_temperature"
    static let volume1Used = "sensor.ds1525plus_volume_1_volume_used"
    static let volume3Used = "sensor.ds1525plus_volume_3_volume_used"
    static let nasUpload = "sensor.ds1525plus_upload_throughput"
    static let nasDownload = "sensor.ds1525plus_download_throughput"
    static let carBattery = LocalEntityMap.resolve("sensor.home_vehicle_battery")
    static let chargeTarget = LocalEntityMap.resolve("number.home_vehicle_charge_limit")
    static let carRange = LocalEntityMap.resolve("sensor.home_vehicle_range")
    static let cloud = "sensor.atlas_wall_connector_cloud"
    static let vehicleUpdated = LocalEntityMap.resolve("sensor.home_vehicle_data_last_update_time")
    static let vehiclePlug = LocalEntityMap.resolve("binary_sensor.home_vehicle_charger")
    static let vehicleCharging = LocalEntityMap.resolve("binary_sensor.home_vehicle_charging")
    static let supplemental = [weather, nasTemperature, volume1Used, volume3Used,
                              nasUpload, nasDownload, carBattery, chargeTarget, carRange,
                              cloud, vehicleUpdated, vehiclePlug, vehicleCharging]
}

/// Reads only the state/history REST endpoints using HAClient's no-redirect session.
final class OverviewClient: @unchecked Sendable {
    private let client = HAClient()

    /// Explicit diagnostic discovery only; this never selects or saves a sensor.
    func discoverAirQuality(settings: Settings, token: String) async -> [[String: String]] {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let base = try? settings.baseURL() else { return [["error": "请先连接 Home Assistant"]] }
        var request = URLRequest(url: base.appendingPathComponent("api/states"))
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await client.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return [["error": "HA 空气质量读取失败（HTTP \(status)）"]] }
            guard data.count <= 16 * 1024 * 1024 else { return [["error": "HA 返回的数据过大"]] }
            return try OverviewParser.airQualityCandidates(data)
        } catch is CancellationError {
            return [["error": "空气质量读取已取消"]]
        } catch {
            return [["error": "空气质量读取失败，请检查连接或返回格式"]]
        }
    }

    func load(settings: Settings, token: String, previous: OverviewDetails,
              includeHistory: Bool, now: Date = Date()) async -> OverviewDetails {
        let outdoorEntity = settings.outdoorPM25Entity.flatMap { $0.isEmpty ? nil : $0 }
        let identity = [settings.address, settings.extraEntity(.temperature), settings.extraEntity(.humidity), outdoorEntity ?? ""].joined(separator: "\n")
        var next = previous.sourceIdentity == identity ? previous : OverviewDetails()
        next.sourceIdentity = identity
        next.outdoorPM25Entity = outdoorEntity
        next.lastAttemptAt = now
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? settings.validate()) != nil else {
            next.states = [:]
            next.history = []
            next.historyFetchedAt = nil
            next.connectionIssue = "请先连接 Home Assistant"
            return next
        }
        let entities = Array(Set(Meter.home.entities + Meter.control.entities + Meter.residential.entities + OverviewEntity.supplemental + [outdoorEntity].compactMap { $0 })).sorted()
        var failed = 0
        var succeeded = 0
        var unauthorized = false
        // Bound concurrent traffic; large session entities do not block the widget's own refresh.
        for start in stride(from: 0, to: entities.count, by: 6) {
            if Task.isCancelled { return previous }
            let batch = Array(entities[start ..< min(start + 6, entities.count)])
            await withTaskGroup(of: (String, Data?, Bool, Bool, String?).self) { group in
                for entity in batch {
                    group.addTask { [client] in
                        do {
                            let data = try await client.stateData(settings: settings, token: token, entity: entity)
                            guard data.count <= 16 * 1024 * 1024,
                                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                                return (entity, nil, false, true, "响应格式无效")
                            }
                            return (entity, data, false, false, nil)
                        } catch {
                            let message = (error as? HAError)?.errorDescription ?? ""
                            let issue = message.contains("找不到实体") ? "HTTP 404" : message.contains("令牌无效") ? "HTTP 401" : message.contains("无读取权限") ? "HTTP 403" : "读取失败"
                            return (entity, nil, message.contains("令牌无效") || message.contains("无读取权限"), message.contains("找不到实体"), issue)
                        }
                    }
                }
                for await (entity, data, authFailure, discardCachedState, issue) in group {
                    next.stateIssues[entity] = issue
                    if let data {
                        next.states[entity] = OverviewStatePayload(data: data, fetchedAt: now)
                        succeeded += 1
                    } else {
                        if discardCachedState { next.states.removeValue(forKey: entity) }
                        failed += 1
                        unauthorized = unauthorized || authFailure
                    }
                }
            }
            if unauthorized { break }
        }
        if Task.isCancelled { return previous }
        if unauthorized {
            next.states = [:]
            next.history = []
            next.historyFetchedAt = nil
            next.connectionIssue = "HA 认证失败 · 请检查令牌与权限"
            next.historyIssue = "历史读取未获授权"
            return next
        }
        if succeeded > 0 { next.lastSuccessAt = now }
        next.connectionIssue = failed == 0 ? nil : succeeded == 0 ? "扩展数据连接中断" : "部分扩展实体读取失败"
        // Expired cache cannot accumulate indefinitely when the server removes entities.
        next.states = next.states.filter { OverviewParser.isFresh($0.value.fetchedAt, now: now, maximumAge: 1200) }
        if includeHistory {
            do {
                let data = try await historyData(settings: settings, token: token, now: now)
                next.history = try OverviewParser.history(data,
                    temperatureEntity: settings.extraEntity(.temperature),
                    humidityEntity: settings.extraEntity(.humidity), now: now)
                next.historyFetchedAt = now
                next.historyIssue = nil
            } catch {
                next.historyIssue = "历史读取失败"
                if !OverviewParser.isFresh(next.historyFetchedAt, now: now, maximumAge: 1200) {
                    next.history = []
                }
            }
        }
        return next
    }

    private func historyData(settings: Settings, token: String, now: Date) async throws -> Data {
        let iso = ISO8601DateFormatter()
        let start = iso.string(from: now.addingTimeInterval(-86400))
        let url = try settings.baseURL().appendingPathComponent("api/history/period/" + start)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HAError.message("历史接口地址无效")
        }
        components.queryItems = [
            URLQueryItem(name: "filter_entity_id", value: [settings.extraEntity(.temperature), settings.extraEntity(.humidity)].joined(separator: ",")),
            URLQueryItem(name: "end_time", value: iso.string(from: now)),
            URLQueryItem(name: "significant_changes_only", value: "0"),
            // Do not accept the server's inferred state at the start as a new sample.
            URLQueryItem(name: "skip_initial_state", value: "1")
        ]
        guard let requestURL = components.url else { throw HAError.message("历史接口地址无效") }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await client.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 16 * 1024 * 1024 else { throw HAError.message("HA 历史读取失败") }
        return data
    }
}

/// Pure conversion and freshness rules shared by the dashboard and parser checks.
enum OverviewParser {
    enum UnitKind { case temperature, percent, range, wind, throughput, power }
    private static let day: TimeInterval = 86400
    private static let cacheAge: TimeInterval = 1200

    struct State {
        let state: String
        let attributes: [String: Any]
        let sourceTime: Date?
        let fetchedAt: Date
    }

    static func isFresh(_ date: Date?, now: Date, maximumAge: TimeInterval) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -60 && age < maximumAge
    }

    static func numeric(_ value: Any?) -> Double? {
        let number: Double?
        if let string = value as? String {
            number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            number = value.doubleValue
        } else { number = nil }
        guard let number, number.isFinite else { return nil }
        return number
    }

    /// Return only the requested air-quality metadata; do not serialize complete states.
    static func airQualityCandidates(_ data: Data) throws -> [[String: String]] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HAError.message("HA 实体列表格式不正确")
        }
        func text(_ value: Any?, maximum: Int) -> String {
            guard let value = value as? String else { return "" }
            return String(String.UnicodeScalarView(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(maximum))
        }
        var result: [[String: String]] = []
        for row in rows {
            let entity = text(row["entity_id"], maximum: 256)
            guard entity.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil else { continue }
            let attributes = row["attributes"] as? [String: Any] ?? [:]
            let name = text(attributes["friendly_name"], maximum: 256)
            let deviceClass = text(attributes["device_class"], maximum: 32)
            let searchable = (entity + " " + name).lowercased().replacingOccurrences(of: " ", with: "")
            let related = ["pm25", "pm2_5", "pm_2_5", "pm2.5", "aqi", "空气质量指数"].contains { searchable.contains($0) }
                || ["pm25", "aqi"].contains(deviceClass.lowercased())
            guard related else { continue }
            let rawState = row["state"] as? String ?? "unknown"
            let state = numeric(rawState).map { String($0) } ?? (["unknown", "unavailable"].contains(rawState) ? rawState : "unknown")
            result.append(["entity_id": entity, "friendly_name": name, "state": state,
                           "unit": text(attributes["unit_of_measurement"], maximum: 32), "device_class": deviceClass])
        }
        return result.sorted { ($0["entity_id"] ?? "") < ($1["entity_id"] ?? "") }
    }

    static func unitValue(_ raw: Any?, unit: String?, kind: UnitKind) -> Double? {
        guard var value = numeric(raw), let unit else { return nil }
        let exact = unit.filter { !$0.isWhitespace }
        let lower = exact.lowercased()
        switch kind {
        case .temperature:
            if ["°f", "f", "℉"].contains(lower) { value = (value - 32) * 5 / 9 }
            else if !["°c", "c", "℃"].contains(lower) { return nil }
            return value.isFinite && value >= -273.15 ? value : nil
        case .percent:
            return exact == "%" && (0 ... 100).contains(value) ? value : nil
        case .range:
            if lower == "mi" { value *= 1.609344 }
            else if lower == "m" { value /= 1000 }
            else if lower != "km" { return nil }
        case .wind:
            if ["km/h", "kph"].contains(lower) { value /= 3.6 }
            else if lower == "mph" { value *= 0.44704 }
            else if ["kn", "kt", "knot", "knots"].contains(lower) { value *= 0.514444444 }
            else if !["m/s", "mps"].contains(lower) { return nil }
        case .power:
            if lower == "kw" { value *= 1000 }
            else if lower != "w" { return nil }
        case .throughput:
            // B = bytes, b = bits. SI and IEC prefixes remain distinct.
            let rates: [String: Double] = [
                "B/s": 1e-6, "byte/s": 1e-6, "bytes/s": 1e-6,
                "kB/s": 0.001, "KB/s": 0.001, "KiB/s": 0.001024,
                "MB/s": 1, "MiB/s": 1.048576, "GB/s": 1000, "GiB/s": 1073.741824,
                "b/s": 1 / 8_000_000, "bit/s": 1 / 8_000_000, "bits/s": 1 / 8_000_000, "bps": 1 / 8_000_000,
                "kb/s": 0.000125, "Kb/s": 0.000125, "kbit/s": 0.000125, "kbps": 0.000125, "Kbps": 0.000125,
                "Mb/s": 0.125, "Mbit/s": 0.125, "Mbps": 0.125,
                "Gb/s": 125, "Gbit/s": 125, "Gbps": 125
            ]
            guard let factor = rates[exact] else { return nil }
            value *= factor
        }
        return value.isFinite && value >= 0 ? value : nil
    }

    static func state(_ payload: OverviewStatePayload?) -> State? {
        guard let payload, let object = try? JSONSerialization.jsonObject(with: payload.data) as? [String: Any],
              let value = object["state"] as? String else { return nil }
        let at = [object["last_reported"], object["last_updated"], object["last_changed"]]
            .compactMap { $0 as? String }.compactMap(parseDate).first
        return State(state: value, attributes: object["attributes"] as? [String: Any] ?? [:],
                     sourceTime: at, fetchedAt: payload.fetchedAt)
    }

    static func weatherPresentation(_ condition: String) -> (symbol: String, text: String) {
        switch condition {
        case "sunny": return ("sun.max.fill", "晴")
        case "clear-night": return ("moon.stars.fill", "晴夜")
        case "partlycloudy": return ("cloud.sun.fill", "多云")
        case "cloudy": return ("cloud.fill", "阴")
        case "rainy": return ("cloud.rain.fill", "雨")
        case "pouring": return ("cloud.heavyrain.fill", "大雨")
        case "lightning": return ("cloud.bolt.fill", "雷电")
        case "lightning-rainy": return ("cloud.bolt.rain.fill", "雷雨")
        case "snowy": return ("cloud.snow.fill", "雪")
        case "snowy-rainy": return ("cloud.sleet.fill", "雨夹雪")
        case "hail": return ("cloud.hail.fill", "冰雹")
        case "fog": return ("cloud.fog.fill", "雾")
        case "windy", "windy-variant": return ("wind", "有风")
        case "exceptional": return ("exclamationmark.triangle", "异常天气")
        default: return ("cloud", "天气暂无读数")
        }
    }

    /// Deliberately excludes raw payloads, sessions, URLs, identifiers and arbitrary strings.
    /// Callers may opt in to writing this bounded summary to a local diagnostic file.
    static func diagnostics(details: OverviewDetails, now: Date = Date()) -> [String: String] {
        let fields: [(String, String, UnitKind?, TimeInterval?)] = [
            ("NAS系统温度", OverviewEntity.nasTemperature, .temperature, day),
            ("NAS卷1", OverviewEntity.volume1Used, .percent, nil),
            ("NAS卷3", OverviewEntity.volume3Used, .percent, nil),
            ("NAS上传", OverviewEntity.nasUpload, .throughput, 300),
            ("NAS下载", OverviewEntity.nasDownload, .throughput, 300),
            ("车辆电池", OverviewEntity.carBattery, .percent, day),
            ("充电目标", OverviewEntity.chargeTarget, .percent, nil),
            ("车辆续航", OverviewEntity.carRange, .range, day),
            ("家充功率", OverviewEntity.cloud, .power, day),
            ("车辆插枪状态", OverviewEntity.vehiclePlug, nil, day),
            ("车辆充电状态", OverviewEntity.vehicleCharging, nil, day)
        ]
        let acceptedUnits: Set<String> = ["W", "kW", "%", "°C", "°F", "℃", "℉", "C", "F", "km", "mi", "m",
            "B/s", "byte/s", "bytes/s", "kB/s", "KB/s", "KiB/s", "MB/s", "MiB/s", "GB/s", "GiB/s",
            "b/s", "bit/s", "bits/s", "bps", "kb/s", "Kb/s", "kbit/s", "kbps", "Kbps", "Mb/s", "Mbit/s", "Mbps", "Gb/s", "Gbit/s", "Gbps"]
        func age(_ date: Date?) -> String {
            guard let date else { return "无有效时间" }
            return "\(Int(now.timeIntervalSince(date).rounded()))s"
        }
        var result: [String: String] = [:]
        for (label, entity, kind, maximumAge) in fields {
            guard let item = state(details.states[entity]) else {
                result[label] = details.stateIssues[entity] ?? "尚未读取或响应无效"
                continue
            }
            let stateText = numeric(item.state).map { String($0) }
                ?? (["unknown", "unavailable", "on", "off"].contains(item.state) ? item.state : "非数字状态")
            let rawUnit = item.attributes["unit_of_measurement"] as? String
            let unit = rawUnit.map { acceptedUnits.contains($0) ? $0 : "未识别单位" } ?? "无单位"
            let validUnit = kind.map { unitValue(item.state, unit: rawUnit, kind: $0) != nil } ?? ["on", "off"].contains(item.state)
            let validTime = isFresh(item.fetchedAt, now: now, maximumAge: cacheAge)
                && (maximumAge.map { isFresh(item.sourceTime, now: now, maximumAge: $0) } ?? true)
            let status = !validUnit ? "值或单位无效" : !validTime ? "已过期或无源时间" : "基础读数有效"
            let request = details.stateIssues[entity] ?? "HTTP 200"
            result[label] = "\(request)；state=\(stateText)；unit=\(unit)；sourceAge=\(age(item.sourceTime))；fetchAge=\(age(item.fetchedAt))；\(status)"
        }
        if let cloud = state(details.states[OverviewEntity.cloud]) {
            let update = (cloud.attributes["updated_at"] as? String).flatMap(parseDate)
            let timestamp = (cloud.attributes["cloud_timestamp"] as? String).flatMap(parseDate)
            result["家充同步时效"] = "同步年龄=\(age(update))；功率年龄=\(age(timestamp))"
        }
        let vehicle = state(details.states[OverviewEntity.vehicleUpdated]).flatMap { parseDate($0.state) }
        result["车辆数据时效"] = "年龄=\(age(vehicle))；15分钟内=\(isFresh(vehicle, now: now, maximumAge: 900))"
        result["历史"] = "记录数=\(details.history.count)；抓取年龄=\(age(details.historyFetchedAt))；\(details.historyIssue == nil ? "无读取错误" : "读取失败")"
        return result
    }

    static func history(_ data: Data, temperatureEntity: String, humidityEntity: String,
                        now: Date) throws -> [OverviewHistorySample] {
        guard let groups = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]] else {
            throw HAError.message("HA 历史格式不正确")
        }
        let start = now.addingTimeInterval(-day)
        var values: [Date: OverviewHistorySample] = [:]
        for group in groups {
            let inheritedID = group.compactMap { $0["entity_id"] as? String }.first
            for row in group {
                guard let id = row["entity_id"] as? String ?? inheritedID,
                      id == temperatureEntity || id == humidityEntity,
                      let date = [row["last_updated"], row["last_changed"]].compactMap({ $0 as? String }).compactMap(parseDate).first,
                      date >= start, date <= now else { continue }
                let attributes = row["attributes"] as? [String: Any] ?? [:]
                let value = unitValue(row["state"], unit: attributes["unit_of_measurement"] as? String,
                                      kind: id == temperatureEntity ? .temperature : .percent)
                var point = values[date] ?? OverviewHistorySample(date: date)
                if id == temperatureEntity {
                    point.temperature = value
                    point.hasTemperatureSample = true
                } else {
                    point.humidity = value
                    point.hasHumiditySample = true
                }
                values[date] = point
            }
        }
        return values.values.sorted { $0.date < $1.date }
    }

    private static func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    static func energyValue(_ reading: Reading?, index: Int, now: Date, total: Bool = false) -> Double? {
        guard let reading, let value = reading.value, value.isFinite, value >= 0,
              isFresh(reading.fetchedAt, now: now, maximumAge: cacheAge),
              isFresh(reading.sourceTime, now: now, maximumAge: index == 0 ? 180 : index >= 3 ? 32 * day : day) else { return nil }
        if total && reading.partial && (index == 0 || index == 2 || index == 4) { return nil }
        if index > 0 {
            guard let source = reading.sourceTime, let fetched = reading.fetchedAt else { return nil }
            let granularity: Calendar.Component = index >= 3 ? .month : .day
            guard calendar().isDate(source, equalTo: now, toGranularity: granularity),
                  calendar().isDate(fetched, equalTo: now, toGranularity: granularity) else { return nil }
        }
        return value
    }

    static func snapshot(core: Snapshot, details: OverviewDetails, now: Date) -> HomeSnapshot {
        var result = HomeSnapshot()
        let liveCore = core.demo ? Snapshot() : core
        func reading(_ entity: String, index: Int) -> Reading? {
            guard let payload = details.states[entity] else { return nil }
            return try? Reading.parse(payload.data, index: index, now: payload.fetchedAt)
        }
        func currentState(_ entity: String, age: TimeInterval? = day) -> State? {
            guard let item = state(details.states[entity]),
                  isFresh(item.fetchedAt, now: now, maximumAge: cacheAge),
                  age.map({ isFresh(item.sourceTime, now: now, maximumAge: $0) }) ?? true else { return nil }
            return item
        }
        func value(_ entity: String, kind: UnitKind, age: TimeInterval? = day) -> Double? {
            guard let item = currentState(entity, age: age) else { return nil }
            return unitValue(item.state, unit: item.attributes["unit_of_measurement"] as? String, kind: kind)
        }
        func account(_ meter: Meter) -> AccountSnapshot {
            let values = meter.entities.enumerated().map { energyValue(reading($0.element, index: $0.offset), index: $0.offset, now: now) }
            return AccountSnapshot(name: meter.label, power: values[0], todayEnergy: values[1], todayCost: values[2], monthEnergy: values[3], monthCost: values[4])
        }
        result.accounts = [account(.home), account(.control)]
        let accountValues = result.accounts.map { [$0.power, $0.todayEnergy, $0.todayCost, $0.monthEnergy, $0.monthCost] }
        var totals: [Double?] = []
        var partialEnergy = false
        for index in 0 ..< 5 {
            let item = liveCore.source == Meter.residential.label && liveCore.readings.indices.contains(index)
                ? liveCore.readings[index] : reading(Meter.residential.entities[index], index: index)
            let complete = accountValues.allSatisfy { $0[index] != nil }
            let number = complete ? energyValue(item, index: index, now: now, total: true) : nil
            if (index == 1 || index == 3) && number != nil && item?.partial == true { partialEnergy = true }
            totals.append(number)
        }
        result.power = totals[0]; result.energyToday = totals[1]; result.costToday = totals[2]
        result.energyMonth = totals[3]; result.costMonth = totals[4]

        func extra(_ metric: ExtraMetric) -> Double? {
            guard let item = liveCore.extras?[metric.rawValue],
                  isFresh(item.fetchedAt, now: now, maximumAge: cacheAge),
                  metric.garage || isFresh(item.sourceTime, now: now, maximumAge: day) else { return nil }
            return liveCore.extraValue(metric, now: now)
        }
        result.temperature = extra(.temperature); result.humidity = extra(.humidity)
        result.pm25 = extra(.pm25); result.cpu = extra(.nasCPU); result.memory = extra(.nasMemory)
        result.garageEnergyToday = extra(.garageEnergyToday); result.garageCostToday = extra(.garageCostToday)
        result.garageEnergyMonth = extra(.garageEnergyMonth); result.garageCostMonth = extra(.garageCostMonth)
        let garageValues = [result.garageEnergyToday, result.garageCostToday, result.garageEnergyMonth, result.garageCostMonth]
        if garageValues.allSatisfy({ $0 != nil }) {
            result.garageNote = "电瓶车支路 ＋ 已记录特斯拉家充 · 费用估算"
        } else if garageValues.contains(where: { $0 != nil }) {
            result.garageNote = "合计来源或费率不完整 · 缺失项暂不显示"
        } else { result.garageNote = "家充或支路数据不可用 · 合计暂不显示" }
        result.pmNote = result.pm25 == nil ? "客厅净化器离线或读数过期" : "客厅空气净化器"
        result.nasTemperature = value(OverviewEntity.nasTemperature, kind: .temperature)
        // A recently fetched static state may be unchanged for days. Its old HA
        // last_updated timestamp alone does not make current capacity invalid.
        result.volume1Used = value(OverviewEntity.volume1Used, kind: .percent, age: nil)
        result.volume3Used = value(OverviewEntity.volume3Used, kind: .percent, age: nil)
        result.nasUpload = value(OverviewEntity.nasUpload, kind: .throughput, age: 300)
        result.nasDownload = value(OverviewEntity.nasDownload, kind: .throughput, age: 300)
        let staleThroughput = [OverviewEntity.nasUpload, OverviewEntity.nasDownload].contains { entity in
            guard let item = currentState(entity, age: nil),
                  unitValue(item.state, unit: item.attributes["unit_of_measurement"] as? String, kind: .throughput) != nil else { return false }
            return !isFresh(item.sourceTime, now: now, maximumAge: 300)
        }
        if staleThroughput {
            result.nasNote = "吞吐读数较旧 · 等待 NAS 更新"
        } else if result.nasUpload == nil || result.nasDownload == nil {
            result.nasNote = "NAS 自身吞吐量 · 部分读数不可用"
        } else { result.nasNote = "NAS 自身吞吐量" }

        if let weather = currentState(OverviewEntity.weather, age: 10800),
           !["", "unknown", "unavailable"].contains(weather.state) {
            result.weatherCondition = weather.state
            result.weatherFetchedAt = weather.fetchedAt
            let presentation = weatherPresentation(weather.state)
            result.weatherSymbol = presentation.symbol
            result.weatherText = presentation.text
            result.outdoorTemperature = unitValue(weather.attributes["temperature"], unit: weather.attributes["temperature_unit"] as? String, kind: .temperature)
            result.outdoorHumidity = unitValue(weather.attributes["humidity"], unit: "%", kind: .percent)
            result.windSpeed = unitValue(weather.attributes["wind_speed"], unit: weather.attributes["wind_speed_unit"] as? String, kind: .wind)
        }
        // A concentration source must be selected explicitly. Discovery never auto-picks
        // an indoor purifier and an AQI score cannot pass the PM2.5 parser.
        result.outdoorPM25 = nil
        if let entity = details.outdoorPM25Entity,
           entity.range(of: #"^sensor\.[a-z0-9_]+$"#, options: .regularExpression) != nil,
           let payload = details.states[entity],
           let reading = try? ExtraMetric.pm25.parse(payload.data, now: payload.fetchedAt),
           isFresh(reading.fetchedAt, now: now, maximumAge: cacheAge),
           isFresh(reading.sourceTime, now: now, maximumAge: day) {
            result.outdoorPM25 = reading.value
        }

        let vehicleAt = currentState(OverviewEntity.vehicleUpdated).flatMap { parseDate($0.state) }
        let vehicleFresh = isFresh(vehicleAt, now: now, maximumAge: 900)
        if vehicleFresh {
            result.carBattery = value(OverviewEntity.carBattery, kind: .percent)
            // Charge limit is a persistent setting; the vehicle freshness gate
            // remains mandatory, but an unchanged target has no source-age TTL.
            result.chargeTarget = value(OverviewEntity.chargeTarget, kind: .percent, age: nil)
            result.carRange = value(OverviewEntity.carRange, kind: .range)
        }
        let cloud = currentState(OverviewEntity.cloud)
        let cloudUpdate = (cloud?.attributes["updated_at"] as? String).flatMap(parseDate)
        let cloudTimestamp = (cloud?.attributes["cloud_timestamp"] as? String).flatMap(parseDate)
        let cloudFresh = isFresh(cloudUpdate, now: now, maximumAge: 900)
            && isFresh(cloudTimestamp, now: now, maximumAge: 900)
        let cloudPower = cloudFresh ? unitValue(cloud?.state, unit: cloud?.attributes["unit_of_measurement"] as? String, kind: .power) : nil
        result.chargingPower = cloudPower.map { $0 / 1000 }
        let plug = vehicleFresh ? currentState(OverviewEntity.vehiclePlug)?.state : nil
        let charging = vehicleFresh ? currentState(OverviewEntity.vehicleCharging)?.state : nil
        if let plug, ["on", "off"].contains(plug) { result.isPlugged = plug == "on" }
        if let cloudPower, let plug, let charging, ["on", "off"].contains(plug), ["on", "off"].contains(charging) {
            if plug == "on", charging == "on", cloudPower > 50 {
                result.isCharging = true
                result.chargeStatus = "家充正在为车辆充电"
            } else if cloudPower <= 50, charging == "off" {
                result.isCharging = false
                result.chargeStatus = plug == "on" ? "已插枪 · 未充电" : "未连接充电枪"
            }
        }
        if result.isCharging == nil {
            result.chargeStatus = cloudPower == nil ? "家充功率待更新" : cloudPower! > 50 ? "家充正在供电 · 车辆状态待同步" : "车辆状态待更新"
        }

        if isFresh(details.historyFetchedAt, now: now, maximumAge: cacheAge) {
            let start = now.addingTimeInterval(-day)
            result.history = details.history.filter { $0.date >= start && $0.date <= now }.map {
                ClimateHistoryPoint(hour: $0.date.timeIntervalSince(start) / 3600,
                                    temperature: $0.temperature, humidity: $0.humidity,
                                    hasTemperatureSample: $0.hasTemperatureSample, hasHumiditySample: $0.hasHumiditySample)
            }
            if result.history.contains(where: { $0.temperature != nil || $0.humidity != nil }) {
                result.historyNote = details.historyIssue == nil ? "HA 近 24 小时历史" : "历史更新失败 · 显示最近读取"
            }
        }
        if result.history.isEmpty, details.historyIssue != nil { result.historyNote = "暂无有效历史 · 请检查 HA 历史记录" }

        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar().timeZone; formatter.dateFormat = "M月d日 EEEE"
        result.dateText = formatter.string(from: now)
        let allValues = totals + [result.temperature, result.humidity, result.pm25, result.cpu, result.memory,
                                 result.garageEnergyToday, result.garageCostToday, result.garageEnergyMonth, result.garageCostMonth,
                                 result.outdoorTemperature, result.windSpeed, result.carBattery, result.chargeTarget, result.carRange,
                                 result.chargingPower, result.nasTemperature, result.volume1Used, result.volume3Used, result.nasUpload, result.nasDownload]
        let anyValue = allValues.contains { $0 != nil }
        result.state = anyValue ? allValues.contains(where: { $0 == nil }) ? .partial : .normal : .stale
        let updated = [liveCore.receivedAt, details.lastSuccessAt].compactMap { $0 }.filter { isFresh($0, now: now, maximumAge: cacheAge) }.max()
        if anyValue {
            formatter.dateFormat = "HH:mm:ss"
            let time = updated.map { formatter.string(from: $0) }
            result.status = time.map { "\($0) 更新" } ?? "已读取 HA"
            if liveCore.connectionIssue != nil || details.connectionIssue != nil {
                result.connectionNote = "连接异常 · 部分读数为最近缓存"
            } else if partialEnergy {
                result.connectionNote = "已同步 HA · 用电监测覆盖不完整"
            } else {
                result.connectionNote = result.state == .partial ? "已同步 HA · 部分读数不可用" : "已同步 HA"
            }
        } else {
            let attempted = liveCore.receivedAt != nil || details.lastAttemptAt != nil
            result.status = attempted ? "暂无有效读数" : "尚未连接 HA"
            result.connectionNote = details.connectionIssue ?? liveCore.connectionIssue ?? "数据已过期 · 等待更新"
        }
        return result
    }
}
