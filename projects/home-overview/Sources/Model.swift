import Foundation

enum Meter: String, CaseIterable, Identifiable, Codable {
    case home, control, residential, custom
    var id: String { rawValue }
    var label: String {
        switch self { case .home: return "住宅电表"; case .control: return "中控室电表"
        case .residential: return "住宅两户合计"; case .custom: return "自定义实体" }
    }
    var prefix: String {
        switch self { case .home, .custom: return "atlas_home"; case .control: return "atlas_104"
        case .residential: return "atlas_residential_total" }
    }
    var entities: [String] {
        let power: String
        switch self {
        case .home,.custom: power = "sensor.esp_meter_power"
        case .control: power = LocalEntityMap.resolve("sensor.control_room_power")
        case .residential: power = "sensor.atlas_residential_total_power"
        }
        return [power] + ["energy_today", "cost_today", "energy_month", "cost_month"].map { "sensor.\(prefix)_\($0)" }
    }
}

struct Settings: Codable {
    var address = "http://homeassistant.local:8123"
    var meter: Meter = .home
    var entities = Meter.home.entities
    var title = "家庭概览"
    var timezone = "Asia/Shanghai"
    // Optional for backward-compatible decoding of existing saved settings.
    var extraEntities: [String:String]?
    var outdoorPM25Entity: String?
    func extraEntity(_ metric:ExtraMetric) -> String { extraEntities?[metric.rawValue] ?? metric.entity }
    static var file: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HomeEnergy/settings.json") }
    static func load() -> Self {
        var value = (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: file))) ?? Self()
        if value.title == "家庭用电" { value.title = "家庭概览" }
        return value
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }
    func baseURL() throws -> URL {
        guard let c = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""), c.host != nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              let u = c.url else { throw HAError.message("请填写 HA 的 http(s) 地址，不含账号、查询参数或 #。") }
        return u
    }
    func validate() throws {
        _ = try baseURL()
        guard entities.count == 5, entities.allSatisfy({ $0.range(of: #"^sensor\.[a-z0-9_]+$"#, options: .regularExpression) != nil }) else {
            throw HAError.message("请填写五个有效的 sensor 实体 ID。")
        }
        guard TimeZone(identifier: timezone) != nil else { throw HAError.message("时区名称无效。") }
        guard ExtraMetric.allCases.allSatisfy({ extraEntity($0).range(of:#"^sensor\.[a-z0-9_]+$"#,options:.regularExpression) != nil }) else {
            throw HAError.message("大号扩展项需要有效的 sensor 实体 ID。")
        }
        if let entity = outdoorPM25Entity, !entity.isEmpty,
           entity.range(of:#"^sensor\.[a-z0-9_]+$"#,options:.regularExpression) == nil {
            throw HAError.message("室外 PM2.5 需要有效的 sensor 实体 ID，也可留空。")
        }
    }
}

enum ExtraMetric:String,CaseIterable,Identifiable {
    case nasCPU, nasMemory, temperature, humidity, pm25
    case garageEnergyToday, garageCostToday, garageEnergyMonth, garageCostMonth
    var id:String { rawValue }
    var label:String {
        switch self {
        case .nasCPU:return "NAS CPU 使用率";case .nasMemory:return "NAS 内存使用率"
        case .temperature:return "室内温度";case .humidity:return "室内湿度"
        case .pm25:return "客厅空气净化器 PM2.5"
        case .garageEnergyToday:return "电瓶车支路今日用电";case .garageCostToday:return "电瓶车支路今日电费"
        case .garageEnergyMonth:return "电瓶车支路本月用电";case .garageCostMonth:return "电瓶车支路本月电费"
        }
    }
    var entity:String {
        switch self {
        case .nasCPU:return "sensor.ds1525plus_cpu_utilization_total"
        case .nasMemory:return "sensor.ds1525plus_memory_usage_real"
        case .temperature:return LocalEntityMap.resolve("sensor.indoor_temperature")
        case .humidity:return LocalEntityMap.resolve("sensor.indoor_humidity")
        case .pm25:return LocalEntityMap.resolve("sensor.living_room_pm25")
        case .garageEnergyToday:return "sensor.atlas_garage_energy_today"
        case .garageCostToday:return "sensor.atlas_garage_cost_today"
        case .garageEnergyMonth:return "sensor.atlas_garage_energy_month"
        case .garageCostMonth:return "sensor.atlas_garage_cost_month"
        }
    }
    var garage:Bool { [.garageEnergyToday,.garageCostToday,.garageEnergyMonth,.garageCostMonth].contains(self) }
    var daily:Bool { self == .garageEnergyToday || self == .garageCostToday }
    var decimals:Int {
        switch self { case .pm25:return 0;case .temperature,.nasCPU,.nasMemory:return 1;case .humidity:return 0;default:return 2 }
    }
    func parse(_ data:Data,now:Date = Date()) throws -> Reading {
        if garage { return try Reading.parse(data,index:(self == .garageEnergyToday || self == .garageEnergyMonth) ? 1 : 2,now:now) }
        guard let o=try JSONSerialization.jsonObject(with:data) as? [String:Any],let state=o["state"] as? String else { throw HAError.message("HA 返回的数据格式不正确。") }
        let a=o["attributes"] as? [String:Any] ?? [:]
        let date=[o["last_reported"],o["last_updated"]].compactMap{$0 as? String}.compactMap(parseDate).first
        func invalid(_ issue:String)->Reading { Reading(value:nil,sourceTime:date,fetchedAt:now,issue:issue) }
        guard var value=Double(state),value.isFinite else { return invalid("实体不可用") }
        let unit=(a["unit_of_measurement"] as? String ?? "").lowercased()
        switch self {
        case .nasCPU,.nasMemory,.humidity:
            guard unit == "%",(0...100).contains(value) else { return invalid("百分比单位或范围不正确") }
        case .temperature:
            if ["°f","f"].contains(unit) { value=(value-32)*5/9 }
            else if !["°c","c","℃"].contains(unit) { return invalid("温度单位须为摄氏或华氏度") }
            guard value >= -273.15 else { return invalid("温度超出有效范围") }
        case .pm25:
            let normalized=unit.replacingOccurrences(of:"μ",with:"u").replacingOccurrences(of:"µ",with:"u").replacingOccurrences(of:"³",with:"3")
            if normalized == "mg/m3" { value *= 1000 }
            else if normalized != "ug/m3" { return invalid("PM2.5 单位须为 μg/m³") }
            if let dc=a["device_class"] as? String,dc != "pm25" { return invalid("该实体不是 PM2.5 读数") }
            guard value >= 0 else { return invalid("PM2.5 读数无效") }
        default:break
        }
        return Reading(value:value,sourceTime:date,fetchedAt:now)
    }
}

struct Reading: Codable {
    var value: Double?
    var sourceTime: Date?
    var fetchedAt: Date?
    var partial = false
    var issue: String?
    static func parse(_ data: Data, index: Int, now: Date = Date()) throws -> Self {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = o["state"] as? String else { throw HAError.message("HA 返回的数据格式不正确。") }
        let a = o["attributes"] as? [String: Any] ?? [:]
        let date = [o["last_reported"], o["last_updated"]].compactMap { $0 as? String }.compactMap(parseDate).first
        let partial = (a["partial"] as? Bool == true) || ["true", "on", "1"].contains((a["partial"] as? String ?? "").lowercased())
        guard var v = Double(s), v.isFinite, v >= 0 else {
            return Self(value: nil, sourceTime: date, fetchedAt: now, partial: partial, issue: "实体不可用")
        }
        let unit = (a["unit_of_measurement"] as? String ?? "").lowercased()
        if index == 0 {
            if unit == "kw" { v *= 1000 } else if unit != "w" { return Self(value: nil, issue: "功率单位须为 W/kW") }
        } else if index == 1 || index == 3 {
            if unit == "wh" { v /= 1000 } else if unit == "mwh" { v *= 1000 } else if unit != "kwh" { return Self(value: nil, issue: "电量单位须为 Wh/kWh/MWh") }
        } else if !["cny", "rmb", "元", "¥", "￥"].contains(unit) { return Self(value: nil, issue: "费用单位须为人民币") }
        return Self(value: v, sourceTime: date, fetchedAt: now, partial: partial)
    }
}

func parseDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}

struct Snapshot: Codable {
    var title = "家庭概览"
    var source = "住宅电表"
    var timezone = "Asia/Shanghai"
    var readings = Array(repeating: Reading(), count: 5)
    var connectionIssue: String? = "请先打开「家庭概览」连接 HA"
    var receivedAt: Date?
    var demo = false
    var extras:[String:Reading]?
    var garageSource:String?
    var meterPowers:[String:Reading]?
    var duckWeather: DuckWeather?
    func meterPower(_ meter:Meter,now:Date=Date())->Double? {
        guard let reading=meterPowers?[meter.rawValue],reading.issue==nil,let fetched=reading.fetchedAt,now.timeIntervalSince(fetched)<120,now.timeIntervalSince(fetched)>=(-60),let source=reading.sourceTime,now.timeIntervalSince(source)<180,now.timeIntervalSince(source)>=(-60),let value=reading.value,value.isFinite,value>=0 else {return nil}
        return value
    }
    func powerUnavailableReason(at now:Date = Date())->String? {
        guard !demo else { return nil }
        if let meters=meterPowers, !meters.isEmpty {
            let home=meterPower(.home,now:now) == nil
            let control=meterPower(.control,now:now) == nil
            if home && control { return "两户电表不可用" }
            if home { return "住宅电表不可用" }
            if control { return "中控室电表不可用" }
        }
        return nil
    }
    func meterShare(_ meter:Meter,now:Date=Date())->Double? {
        guard let home=meterPower(.home,now:now),let control=meterPower(.control,now:now),let value=meterPower(meter,now:now) else {return nil}
        return home+control>0 ? min(1,max(0,value/(home+control))):0
    }
    func extraValue(_ metric:ExtraMetric,now:Date = Date())->Double? {
        guard let reading=extras?[metric.rawValue],let fetched=reading.fetchedAt,
              now.timeIntervalSince(fetched) < 1200 else { return nil }
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:timezone) ?? .current
        if metric.daily && !cal.isDate(fetched,inSameDayAs:now) { return nil }
        if metric.garage && !metric.daily && !cal.isDate(fetched,equalTo:now,toGranularity:.month) { return nil }
        return reading.value
    }
    func extraNumber(_ metric:ExtraMetric,now:Date = Date())->String {
        guard let value=extraValue(metric,now:now) else { return "—" }
        return String(format:"%.\(metric.decimals)f",locale:Locale(identifier:"en_US_POSIX"),value)
    }
    func largeNote(now:Date = Date())->String {
        let missing=ExtraMetric.allCases.filter{extraValue($0,now:now) == nil}.count
        if missing > 0 { return "\(missing) 项不可用 · 电瓶车＋已记录家充 · 费用估算" }
        if readings.contains(where:{$0.partial}) || extras?.values.contains(where:{$0.partial}) == true { return "电瓶车＋已记录家充 · 部分监测 · 费用估算" }
        return "电瓶车＋已记录家充 · 客厅净化器 · 费用估算"
    }
    func value(_ index: Int, now: Date = Date()) -> Double? {
        guard readings.indices.contains(index), let fetched = readings[index].fetchedAt else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: timezone) ?? .current
        if index == 1 || index == 2 { guard cal.isDate(fetched, inSameDayAs: now) else { return nil } }
        if index == 3 || index == 4 { guard cal.isDate(fetched, equalTo: now, toGranularity: .month) else { return nil } }
        return readings[index].value
    }
    func number(_ index: Int, now: Date = Date()) -> String {
        guard let value = value(index, now: now) else { return "—" }
        return String(format: index == 0 ? "%.0f" : "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    var status: String { status(at: Date()) }
    func status(at now: Date) -> String {
        if demo { return "示例数据" }
        if let reason=powerUnavailableReason(at:now) { return reason }
        if connectionIssue != nil { return receivedAt == nil ? "未连接" : "数据不可用" }
        if readings.contains(where: { $0.value == nil }) { return "部分不可用" }
        guard let d = readings.first?.fetchedAt, now.timeIntervalSince(d) < 120 else { return "缓存数据" }
        if let source = readings.first?.sourceTime, now.timeIntervalSince(source) > 180 { return "功率读数较旧" }
        return "已同步 HA"
    }
    var warning: Bool { !demo && status != "已同步 HA" }
    var shortTime: String {
        guard let d = readings.first?.sourceTime else { return "" }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: timezone); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    var timeText: String {
        guard let d = readings.first?.sourceTime else { return "尚无功率读数" }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: timezone); f.dateFormat = "HH:mm:ss"
        return "功率读数 " + f.string(from: d)
    }
    var dateText: String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: timezone); f.dateFormat = "M月d日"
        return f.string(from: Date())
    }
    static var sample: Self {
        var s = Self(); s.connectionIssue = nil; s.demo = true; s.receivedAt = Date()
        s.readings = [1248.0,14.12,10.98,49.87,39.18].map { Reading(value: $0, sourceTime: Date(), fetchedAt: Date()) }
        s.meterPowers=["home":Reading(value:920,sourceTime:Date(),fetchedAt:Date()),"control":Reading(value:328,sourceTime:Date(),fetchedAt:Date())]
        s.extras=Dictionary(uniqueKeysWithValues:zip(ExtraMetric.allCases,[12.8,36.4,25.2,51,3,5.28,1.56,87.43,29.65]).map{($0.0.rawValue,Reading(value:$0.1,sourceTime:Date(),fetchedAt:Date()))})
        return s
    }
}

enum HAError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class HAClient: @unchecked Sendable {
    let session: URLSession
    init() {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 10; c.timeoutIntervalForResource = 12
        c.httpCookieStorage = nil; c.urlCredentialStorage = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }
    func read(settings: Settings, token: String, index: Int) async throws -> Reading {
        return try Reading.parse(try await stateData(settings:settings,token:token,entity:settings.entities[index]),index:index)
    }
    func readExtra(settings:Settings,token:String,metric:ExtraMetric) async throws -> Reading {
        return try metric.parse(try await stateData(settings:settings,token:token,entity:settings.extraEntity(metric)))
    }
    func stateData(settings:Settings,token:String,entity:String) async throws -> Data {
        let u = try settings.baseURL().appendingPathComponent("api/states/" + entity)
        var req = URLRequest(url: u); req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let text = [401:"令牌无效或已过期", 403:"该账号无读取权限", 404:"找不到实体：" + entity][code] ?? "HA 请求失败（HTTP \(code)）；请检查地址，重定向不会自动跟随。"
            throw HAError.message(text)
        }
        return data
    }
}


enum PowerMenuTone { case green, pink, purple, unavailable }
extension Snapshot {
    func menuPowerValue(at now: Date = Date()) -> Double? {
        guard !demo, let reading = readings.first, reading.issue == nil,
              let fetched = reading.fetchedAt, now.timeIntervalSince(fetched) >= -60,
              now.timeIntervalSince(fetched) < 120,
              reading.sourceTime.map({ now.timeIntervalSince($0) <= 180 }) ?? false,
              let value = reading.value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    func menuPower(at now: Date = Date()) -> String {
        guard let value = menuPowerValue(at:now) else { return powerUnavailableReason(at:now) ?? "功率不可用" }
        return String(format: "%.0f W", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    func menuPowerTone(at now: Date = Date()) -> PowerMenuTone {
        guard let value = menuPowerValue(at:now) else { return .unavailable }
        return value > 3000 ? .purple : value > 1000 ? .pink : .green
    }
}

// Device aliases are local settings, kept outside the replaceable application.
enum LocalEntityMap {
    static func valid(_ value:String)->Bool {value.range(of:#"^[a-z_]+\.[a-z0-9_]+$"#,options:.regularExpression) != nil}
    static func decode(_ bytes:Data)->[String:String] {
        guard bytes.count < 65536, let entries=try? JSONDecoder().decode([String:String].self,from:bytes) else{return [:]}
        return entries.filter{valid($0.key) && valid($0.value)}
    }
    static let mappings:[String:String] = {
        #if HOME_ENERGY_TESTING
        return [:] // Tests must never read a user's device mapping.
        #else
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        let url=base.appendingPathComponent("HomeEnergy/entity-overrides.json")
        guard let bytes=try? Data(contentsOf:url) else{return [:]}
        return decode(bytes)
        #endif
    }()
    static func resolve(_ entity:String)->String {mappings[entity] ?? entity}
}

/// Presentation-only weather state. No location or credentials are retained.
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
        return (-60...180).contains(now.timeIntervalSince(observedAt))
    }
    mutating func observe(_ next: String?, at date: Date?, now: Date) {
        guard let next, Self.known.contains(next), let date, (-60...180).contains(now.timeIntervalSince(date)) else {
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
        // Calendar seasons use the configured home time zone and northern-hemisphere months.
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
