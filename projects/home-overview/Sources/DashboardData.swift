import Foundation

enum PreviewState: String, CaseIterable, Identifiable {
    case normal = "实时数据"
    case partial = "部分不可用"
    case stale = "数据过期"
    var id: String { rawValue }
}

/// A presentation snapshot of real HA readings. Missing values stay missing.
struct HomeSnapshot {
    var power: Double?
    var energyToday: Double?
    var costToday: Double?
    var energyMonth: Double?
    var costMonth: Double?
    var garageEnergyToday: Double?
    var garageCostToday: Double?
    var garageEnergyMonth: Double?
    var garageCostMonth: Double?
    var temperature: Double?
    var humidity: Double?
    var pm25: Double?
    var cpu: Double?
    var memory: Double?
    var outdoorTemperature: Double?
    var outdoorHumidity: Double?
    var windSpeed: Double?
    var outdoorPM25: Double?
    var carBattery: Double?
    var chargeTarget: Double?
    var carRange: Double?
    var chargingPower: Double? // kW
    var isCharging: Bool?
    var isPlugged: Bool?
    var nasTemperature: Double?
    var volume1Used: Double?
    var volume3Used: Double?
    var nasUpload: Double? // MB/s, NAS traffic only.
    var nasDownload: Double?
    var accounts = [AccountSnapshot(name: "住宅电表"), AccountSnapshot(name: "中控室电表")]
    var state: PreviewState = .partial
    var history: [ClimateHistoryPoint] = []
    var weatherCondition: String?
    var weatherFetchedAt: Date?
    var weatherSymbol = "cloud"
    var weatherText = "天气暂无读数"
    var dateText = ""
    var status = "尚未连接 HA"
    var historyNote = "暂无有效历史读数"
    var connectionNote = "请先连接 Home Assistant"
    var garageNote = "合计来源不完整 · 暂不显示缺失项"
    var pmNote = "客厅净化器暂无有效读数"
    var chargeStatus = "充电状态不可用"
    var nasNote = "NAS 自身吞吐量 · 暂无有效读数"

    static func live(core: Snapshot, details: OverviewDetails, now: Date = Date()) -> HomeSnapshot {
        OverviewParser.snapshot(core: core, details: details, now: now)
    }

    static func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}

struct AccountSnapshot: Identifiable {
    var id: String { name }
    let name: String
    var power: Double?
    var todayEnergy: Double?
    var todayCost: Double?
    var monthEnergy: Double?
    var monthCost: Double?
}
