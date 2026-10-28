import Foundation

@main struct OverviewDataTests {
    static var assertions = 0
    static let now = parseDate("2026-10-23T04:00:00Z")!
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }
    static func close(_ actual: Double?, _ expected: Double, _ message: String) {
        require(actual != nil && abs(actual! - expected) < 0.00001, message)
    }
    static func date(_ offset: Double = 0) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(offset)) }
    static func data(_ state: String, unit: String? = nil, attributes: [String: Any] = [:],
                     source: String? = date(), entity: String? = nil) -> Data {
        var attrs = attributes
        if let unit { attrs["unit_of_measurement"] = unit }
        var object: [String: Any] = ["state": state, "attributes": attrs]
        if let source { object["last_reported"] = source; object["last_updated"] = source }
        if let entity { object["entity_id"] = entity }
        return try! JSONSerialization.data(withJSONObject: object)
    }
    static func payload(_ state: String, unit: String? = nil, attributes: [String: Any] = [:],
                        source: String? = date(), fetched: Date = now) -> OverviewStatePayload {
        OverviewStatePayload(data: data(state, unit: unit, attributes: attributes, source: source), fetchedAt: fetched)
    }
    static func baseDetails() -> OverviewDetails {
        var details = OverviewDetails()
        details.lastSuccessAt = now
        let units = ["W", "kWh", "CNY", "kWh", "CNY"]
        for meter in [Meter.home, .control, .residential] {
            for (index, entity) in meter.entities.enumerated() {
                details.states[entity] = payload(meter == .residential ? "20" : "10", unit: units[index])
            }
        }
        return details
    }
    static func baseCore() -> Snapshot {
        var core = Snapshot()
        core.connectionIssue = nil; core.receivedAt = now
        core.source = Meter.residential.label
        core.readings = [100, 20, 10, 200, 100].map { Reading(value: Double($0), sourceTime: now, fetchedAt: now) }
        core.extras = Dictionary(uniqueKeysWithValues: ExtraMetric.allCases.map { ($0.rawValue, Reading(value: 12, sourceTime: now, fetchedAt: now)) })
        return core
    }
    static func main() throws {
        // Byte/bit units must not silently differ by eight, and IEC is not SI.
        close(OverviewParser.unitValue(8, unit: "b/s", kind: .throughput), 0.000001, "b/s -> MB/s")
        close(OverviewParser.unitValue(1, unit: "B/s", kind: .throughput), 0.000001, "B/s -> MB/s")
        close(OverviewParser.unitValue("1000", unit: "KB/s", kind: .throughput), 1, "KB bytes")
        close(OverviewParser.unitValue(8, unit: "Mb/s", kind: .throughput), 1, "Mb bits")
        close(OverviewParser.unitValue(8, unit: "MB/s", kind: .throughput), 8, "MB bytes")
        close(OverviewParser.unitValue(1, unit: "MiB/s", kind: .throughput), 1.048576, "binary MiB")
        require(OverviewParser.unitValue(1, unit: "mb/s", kind: .throughput) == nil, "ambiguous lowercase m rejected")
        require(OverviewParser.unitValue(-1, unit: "MB/s", kind: .throughput) == nil, "negative throughput rejected")
        require(OverviewParser.unitValue("nan", unit: "MB/s", kind: .throughput) == nil, "non-finite value rejected")
        require(OverviewParser.unitValue(true, unit: "MB/s", kind: .throughput) == nil, "JSON bool is not numeric")
        close(OverviewParser.unitValue(77, unit: "°F", kind: .temperature), 25, "Fahrenheit")
        close(OverviewParser.unitValue(-12, unit: "°C", kind: .temperature), -12, "negative Celsius")
        close(OverviewParser.unitValue(36, unit: "km/h", kind: .wind), 10, "weather wind conversion")
        require(OverviewParser.unitValue(10, unit: "unknown", kind: .wind) == nil, "unknown wind unit stays missing")
        close(OverviewParser.unitValue(100, unit: "mi", kind: .range), 160.9344, "range miles")
        require(OverviewParser.unitValue(101, unit: "%", kind: .percent) == nil, "percent >100 rejected")
        require(OverviewParser.isFresh(now.addingTimeInterval(61), now: now, maximumAge: 900) == false, "future timestamp rejected")
        require(OverviewParser.isFresh(nil, now: now, maximumAge: 900) == false, "missing timestamp is not now")

        let empty = HomeSnapshot()
        require(empty.power == nil && empty.pm25 == nil && empty.carBattery == nil && empty.history.isEmpty, "default is all empty, no sample figures")
        let emptyLive = HomeSnapshot.live(core: Snapshot(), details: OverviewDetails(), now: now)
        require(emptyLive.power == nil && emptyLive.history.isEmpty && emptyLive.status == "尚未连接 HA", "unconfigured state")
        require(HomeSnapshot.live(core: Snapshot.sample, details: OverviewDetails(), now: Date()).power == nil, "demo snapshot cannot become live")

        var core = baseCore(); var details = baseDetails()
        var live = HomeSnapshot.live(core: core, details: details, now: now)
        require(live.power == 100 && live.accounts[0].power == 10, "use 15s core residential total with separate accounts")
        core.source = Meter.home.label
        live = HomeSnapshot.live(core: core, details: details, now: now)
        require(live.power == 20, "selected single meter cannot masquerade as residential total")
        details.states[Meter.control.entities[0]] = payload("unavailable", unit: "W")
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.power == nil && live.energyToday == 20, "missing one account invalidates only matching total")
        details = baseDetails(); core = baseCore()
        core.readings[1].partial = true
        core.readings[2].partial = true
        live = HomeSnapshot.live(core: core, details: details, now: now)
        require(live.energyToday == 20 && live.costToday == nil && live.connectionNote.contains("覆盖不完整"), "partial energy retained and disclosed; partial fee hidden")
        core = baseCore(); core.readings[0].sourceTime = now.addingTimeInterval(-181)
        require(HomeSnapshot.live(core: core, details: baseDetails(), now: now).power == nil, "old source power expires even when fetched now")
        let oldDay = parseDate("2026-10-22T15:59:59Z")!
        let yesterday = Reading(value: 8, sourceTime: oldDay, fetchedAt: now)
        require(OverviewParser.energyValue(yesterday, index: 1, now: now) == nil, "yesterday source not relabeled today")
        require(OverviewParser.energyValue(yesterday, index: 3, now: now) == 8, "current month may retain prior day source")

        details = baseDetails()
        details.states[OverviewEntity.weather] = payload("sunny", attributes: ["temperature": 68, "temperature_unit": "°F", "wind_speed": 36, "wind_speed_unit": "km/h"])
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.weatherSymbol == "sun.max.fill" && live.weatherText == "晴", "weather condition mapping")
        close(live.outdoorTemperature, 20, "weather source Fahrenheit converted")
        close(live.windSpeed, 10, "weather source kmh converted")
        require(live.outdoorPM25 == nil && live.pm25 == 12, "outdoor PM never copied from purifier")
        details.states[OverviewEntity.weather] = payload("rainy", attributes: ["temperature": 20, "temperature_unit": "°C", "wind_speed": 3], source: date(-10801))
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.outdoorTemperature == nil && live.windSpeed == nil && live.weatherText == "天气暂无读数", "old weather hidden")
        details.states[OverviewEntity.nasUpload] = payload("8", unit: "Mbps")
        details.states[OverviewEntity.nasDownload] = payload("10", unit: "MB/s", source: date(-301))
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.nasUpload == 1 && live.nasDownload == nil && live.nasNote.contains("较旧"), "NAS rate has shorter source TTL and explains stale data")
        details.states[OverviewEntity.nasUpload] = payload("10", unit: "MB/s", source: nil)
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).nasUpload == nil, "missing source date not replaced with fetch time")
        details.states[OverviewEntity.volume1Used] = payload("34.9", unit: "%", source: date(-135922))
        details.states[OverviewEntity.volume3Used] = payload("14.8", unit: "%", source: date(-135922))
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.volume1Used == 34.9 && live.volume3Used == 14.8, "static volume values remain valid when unchanged for more than a day")
        details.states[OverviewEntity.volume3Used] = payload("unavailable", unit: "%", source: date(-135922))
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).volume3Used == nil, "static volume unavailable is not retained or fabricated")
        details.states[OverviewEntity.volume3Used] = payload("14.8", unit: "%", source: date(-135922), fetched: now.addingTimeInterval(-1201))
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).volume3Used == nil, "static state still requires recent successful fetch")

        details = baseDetails()
        details.states[OverviewEntity.cloud] = payload("7100", unit: "W", attributes: ["updated_at": date(), "cloud_timestamp": date()])
        details.states[OverviewEntity.vehicleUpdated] = payload(date())
        details.states[OverviewEntity.vehiclePlug] = payload("on")
        details.states[OverviewEntity.vehicleCharging] = payload("on")
        details.states[OverviewEntity.carBattery] = payload("68", unit: "%")
        details.states[OverviewEntity.chargeTarget] = payload("80", unit: "%")
        details.states[OverviewEntity.carRange] = payload("100", unit: "mi")
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.isCharging == true && live.isPlugged == true && live.chargingPower == 7.1 && live.carBattery == 68, "fresh, matching vehicle and wall connector are charging")
        close(live.carRange, 160.9344, "vehicle range conversion")
        details.states[OverviewEntity.chargeTarget] = payload("85", unit: "%", source: date(-133643))
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).chargeTarget == 85, "fresh vehicle accepts a static target unchanged for more than a day")
        details.states[OverviewEntity.vehicleUpdated] = payload(date(-901))
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.isCharging == nil && live.carBattery == nil && live.chargeTarget == nil && live.chargingPower == 7.1 && live.chargeStatus.contains("待同步"), "old car state must not be paired with fresh wall power; target still requires fresh vehicle")
        details.states[OverviewEntity.vehicleUpdated] = payload(date())
        details.states[OverviewEntity.vehicleCharging] = payload("off")
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.isCharging == nil, "conflicting active power and car off is unknown")
        details.states[OverviewEntity.cloud] = payload("0", unit: "W", attributes: ["updated_at": date(), "cloud_timestamp": date()])
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.isCharging == false && live.chargingPower == 0 && live.chargeStatus.contains("已插枪"), "zero power is valid, plugged not charging")
        details.states[OverviewEntity.cloud] = payload("7100", unit: "W", attributes: ["updated_at": date(), "cloud_timestamp": date(-901)])
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).chargingPower == nil, "successful sync cannot make old cloud power fresh")

        let temp = ExtraMetric.temperature.entity, humidity = ExtraMetric.humidity.entity
        func row(_ entity: String, _ seconds: Double, _ state: String, _ unit: String) -> [String: Any] {
            ["entity_id": entity, "last_updated": date(seconds), "last_reported": date(), "state": state, "attributes": ["unit_of_measurement": unit]]
        }
        let groups = [[row(temp, -7200, "77", "°F"), row(temp, -3600, "unavailable", "°C"), row(temp, -1800, "26", "°C"), row(temp, 60, "99", "°C"), row(temp, -90000, "99", "°C")],
                      [row(humidity, -7000, "55", "%"), row(humidity, -2000, "56", "%")]]
        let historyData = try JSONSerialization.data(withJSONObject: groups)
        let history = try OverviewParser.history(historyData, temperatureEntity: temp, humidityEntity: humidity, now: now)
        require(history.count == 5 && history.first?.date == now.addingTimeInterval(-7200), "history uses actual historical last_updated, bounds checked")
        require(history[0].temperature == 25 && !history[0].hasHumiditySample && history[0].humidity == nil, "no humidity fabricated at temperature sample")
        require(history[1].humidity == 55 && !history[1].hasTemperatureSample, "asynchronous humidity marked independently")
        require(history[2].temperature == nil && history[2].hasTemperatureSample, "explicit unavailable is a real gap")
        details = baseDetails(); details.history = history; details.historyFetchedAt = now
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.history.count == 5 && live.history.last!.hour < 24, "do not extend history to current time")
        let temperatureRuns = ClimateCurve.runs(live.history.filter { $0.hasTemperatureSample }, value: { $0.temperature })
        require(temperatureRuns.count == 2 && temperatureRuns.allSatisfy { $0.count == 1 }, "temperature unavailable breaks line; other sensor times do not invent points")
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now.addingTimeInterval(1201)).history.isEmpty, "expired history hidden")
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now.addingTimeInterval(1201)).nasUpload == nil, "expired supplemental readings hidden")
        let invalidHistory = try JSONSerialization.data(withJSONObject: [[ ["entity_id": temp, "state": "23", "last_updated": "invalid", "attributes": ["unit_of_measurement": "°C"]] ]])
        let parsedInvalidHistory = try OverviewParser.history(invalidHistory, temperatureEntity: temp, humidityEntity: humidity, now: now)
        require(parsedInvalidHistory.isEmpty, "invalid timestamp never becomes now")
        details.states[OverviewEntity.nasUpload] = payload("private-arbitrary-state", unit: "private-unit", attributes: ["sessions": [["secret": "PRIVATE_SESSION"]], "url": "https://PRIVATE_HOST"])
        details.stateIssues[OverviewEntity.volume3Used] = "HTTP 404"
        let diagnostics = OverviewParser.diagnostics(details: details, now: now)
        let diagnosticText = diagnostics.values.joined(separator: " ")
        require(!diagnosticText.contains("PRIVATE") && !diagnosticText.contains("private-"), "diagnostics redact arbitrary payload content and units")
        require(diagnostics["NAS卷3"] == "HTTP 404", "diagnostics expose only normalized missing-entity status")

        let airStates: [[String: Any]] = [
            ["entity_id": "sensor.outdoor_pm2_5", "state": "4", "attributes": ["friendly_name": "室外 PM2.5", "unit_of_measurement": "μg/m³", "device_class": "pm25", "latitude": 99, "longitude": 88, "sessions": ["PRIVATE_SESSION"]]],
            ["entity_id": "sensor.living_room_air", "state": "unavailable", "attributes": ["friendly_name": "客厅净化器", "device_class": "pm25", "unit_of_measurement": "μg/m³"]],
            ["entity_id": "sensor.city_aqi", "state": "23", "attributes": ["friendly_name": "城市空气质量指数", "unit_of_measurement": "AQI"]],
            ["entity_id": "sensor.pm25_problem", "state": "PRIVATE_STATE", "attributes": ["friendly_name": "PM2.5"]],
            ["entity_id": "sensor.vehicle_position", "state": "PRIVATE_POSITION", "attributes": ["latitude": 77, "longitude": 66]]
        ]
        let candidates = try OverviewParser.airQualityCandidates(JSONSerialization.data(withJSONObject: airStates))
        require(candidates.count == 4, "discovery includes PM2.5 and AQI candidates only")
        require(candidates.allSatisfy { Set($0.keys) == Set(["entity_id", "friendly_name", "state", "unit", "device_class"]) }, "air discovery returns only five approved metadata fields")
        require(candidates.first(where: { $0["entity_id"] == "sensor.pm25_problem" })?["state"] == "unknown", "arbitrary states are not exposed")
        let candidateText = String(data: try JSONSerialization.data(withJSONObject: candidates), encoding: .utf8)!
        require(!candidateText.contains("PRIVATE"), "air discovery excludes sessions and unrelated entities")
        details = baseDetails()
        details.states["sensor.outdoor_pm2_5"] = payload("0.004", unit: "mg/m3", attributes: ["device_class": "pm25"])
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).outdoorPM25 == nil, "air discovery does not automatically select even valid concentration")
        details.outdoorPM25Entity = "sensor.outdoor_pm2_5"
        live = HomeSnapshot.live(core: baseCore(), details: details, now: now)
        require(live.outdoorPM25 == 4 && live.pm25 == 12, "explicit outdoor source is separate and converted from mg to micrograms")
        details.states["sensor.outdoor_pm2_5"] = payload("23", unit: "μg/m³", attributes: ["device_class": "aqi"])
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).outdoorPM25 == nil, "AQI cannot masquerade as mass concentration")
        details.states["sensor.outdoor_pm2_5"] = payload("4", unit: "μg/m³", attributes: ["device_class": "pm25"], source: date(-86401))
        require(HomeSnapshot.live(core: baseCore(), details: details, now: now).outdoorPM25 == nil, "outdoor PM source expiration")
        print("OverviewDataTests: \(assertions) assertions passed")
    }
}
