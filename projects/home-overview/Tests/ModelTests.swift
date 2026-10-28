import Foundation

@main struct ModelTests {
    static func require(_ condition:Bool,_ message:String) { if !condition { fatalError(message) } }
    static func state(_ value:String,_ unit:String,partial:Bool=false) -> Data {
        try! JSONSerialization.data(withJSONObject:["state":value,"last_reported":"2026-10-20T12:00:00.123Z","attributes":["unit_of_measurement":unit,"partial":partial]])
    }
    static func main() async throws {
        let stamp=Date();var meters=Snapshot.sample
        meters.meterPowers=["home":Reading(value:750,sourceTime:stamp,fetchedAt:stamp),"control":Reading(value:250,sourceTime:stamp,fetchedAt:stamp)]
        require(meters.meterShare(.home,now:stamp)==0.75,"home power share")
        require(meters.meterShare(.control,now:stamp)==0.25,"control power share")
        require(meters.meterPower(.home,now:stamp.addingTimeInterval(121))==nil,"stale meter must not look live")
        meters.meterPowers?["home"]?.value=0;meters.meterPowers?["control"]?.value=0
        require(meters.meterShare(.home,now:stamp)==0,"zero load is valid")
        meters.meterPowers?["control"]?.value=nil
        require(meters.meterShare(.home,now:stamp)==nil,"missing meter has no invented ratio")
        meters.meterPowers?["home"]?.sourceTime=stamp.addingTimeInterval(61)
        require(meters.meterPower(.home,now:stamp)==nil,"future meter rejected")
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(meters)) as! [String:Any]
        legacy.removeValue(forKey:"meterPowers")
        require(try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:legacy)).meterPowers==nil,"old snapshot remains readable")
        let aliases=LocalEntityMap.decode(Data(#"{"sensor.indoor_temperature":"sensor.test_temperature","bad":"sensor.other","sensor.bad":"https://example.com"}"#.utf8))
        require(aliases == ["sensor.indoor_temperature":"sensor.test_temperature"],"only valid local entity aliases survive")
        require(LocalEntityMap.decode(Data("broken".utf8)).isEmpty,"corrupt aliases leave defaults usable")
        require(LocalEntityMap.decode(Data(repeating:32,count:65536)).isEmpty,"oversized aliases ignored")
        require(LocalEntityMap.resolve("sensor.unknown_fixture")=="sensor.unknown_fixture","unmapped entity preserved")

        require(try Reading.parse(state("1.248","kW"),index:0).value == 1248,"kW conversion")
        require(try Reading.parse(state("14120","Wh"),index:1).value == 14.12,"Wh conversion")
        require(try Reading.parse(state("0.05","MWh"),index:3).value == 50,"MWh conversion")
        require(try Reading.parse(state("unavailable","W"),index:0).value == nil,"unavailable is not zero")
        require(try Reading.parse(state("nan","W"),index:0).value == nil,"NaN is not a value")
        require(try Reading.parse(state("-1","W"),index:0).value == nil,"negative power rejected")
        require(try Reading.parse(state("45","USD"),index:2).value == nil,"do not label dollars as yuan")
        require(try Reading.parse(state("0","CNY"),index:2).value == 0,"zero cost valid")
        require(try Reading.parse(state("12","kWh",partial:true),index:1).partial,"partial tracking")
        require(try Reading.parse(state("7","W"),index:0).sourceTime != nil,"fractional ISO timestamp")
        require(Meter.home.entities[0] == "sensor.esp_meter_power","real preset")
        require(Meter.residential.entities[4] == "sensor.atlas_residential_total_cost_month","combined preset")
        var settings = Settings()
        for address in ["ha.local:8123","https://user:password@ha.local","https://ha.local/?token=private","ftp://ha.local"] {
            settings.address = address
            do { try settings.validate(); fatalError("invalid address accepted") } catch {}
        }
        settings.address = "http://127.0.0.1:8123"; try settings.validate()
        var snapshot = Snapshot.sample; snapshot.demo = false; snapshot.meterPowers = nil
        let old = parseDate("2026-10-20T15:59:59Z")!, tomorrow = old.addingTimeInterval(2)
        snapshot.readings = [1000,12,6,125,60].map { Reading(value:Double($0),sourceTime:old,fetchedAt:old) }
        require(snapshot.value(1,now:tomorrow) == nil,"midnight invalidates today's cached kWh")
        require(snapshot.value(2,now:tomorrow) == nil,"midnight invalidates cost")
        require(snapshot.value(3,now:tomorrow) == 125,"month survives midnight")
        require(snapshot.value(3,now:parseDate("2026-11-01T00:00:00Z")!) == nil,"month rollover")
        require(snapshot.status(at:old.addingTimeInterval(181)) == "缓存数据","future timeline marks cache")
        require(try ExtraMetric.nasCPU.parse(state("12.5","%")).value == 12.5,"CPU percentage")
        require(try ExtraMetric.nasMemory.parse(state("101","%")).value == nil,"reject out-of-range memory")
        require(try ExtraMetric.temperature.parse(state("-5","°C")).value == -5,"negative Celsius is valid")
        require(try ExtraMetric.temperature.parse(state("77","°F")).value == 25,"Fahrenheit conversion")
        require(try ExtraMetric.humidity.parse(state("51","%")).value == 51,"humidity")
        require(try ExtraMetric.pm25.parse(state("3","μg/m³")).value == 3,"purifier microgram unit")
        require(try ExtraMetric.pm25.parse(state("0.004","mg/m3")).value == 4,"PM mass conversion")
        require(try ExtraMetric.pm25.parse(state("unknown","μg/m³")).value == nil,"missing PM is not zero")
        require(try ExtraMetric.pm25.parse(state("3","ppm")).value == nil,"reject pollutant ppm")
        require(try ExtraMetric.garageEnergyToday.parse(state("5280","Wh")).value == 5.28,"garage Wh")
        require(try ExtraMetric.garageCostMonth.parse(state("29.65","CNY")).value == 29.65,"garage estimated cost")
        require(ExtraMetric.pm25.entity == "sensor.living_room_pm25","use living-room purifier, not balcony fresh air")
        snapshot.extras=Dictionary(uniqueKeysWithValues:ExtraMetric.allCases.map{($0.rawValue,Reading(value:10,sourceTime:old,fetchedAt:old))})
        require(snapshot.extraValue(.garageEnergyToday,now:tomorrow) == nil,"garage day rollover")
        require(snapshot.extraValue(.garageCostMonth,now:tomorrow) == 10,"garage month survives midnight")
        require(snapshot.extraValue(.nasCPU,now:old.addingTimeInterval(1201)) == nil,"expire stale extras")
        var current=Snapshot.sample;current.demo=false;current.extras?[ExtraMetric.pm25.rawValue]=Reading(value:nil,issue:"missing")
        require(current.status == "已同步 HA","optional failures do not break the original core status")
        require(current.largeNote().contains("1 项"),"large widget exposes unavailable extras")
        var oldSnapshot=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Snapshot.sample)) as! [String:Any]
        oldSnapshot.removeValue(forKey:"extras")
        let migrated=try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:oldSnapshot))
        require(migrated.readings.count == 5 && migrated.extras == nil,"legacy snapshots retain core readings")
        settings.meter = .residential; settings.entities=Meter.residential.entities
        let migratedSettings=try JSONDecoder().decode(Settings.self,from:JSONEncoder().encode(settings))
        require(migratedSettings.meter == .residential && migratedSettings.extraEntity(.nasCPU) == ExtraMetric.nasCPU.entity,"legacy settings preserve selected meter")
        if CommandLine.arguments.count > 2 {
            let script=try String(contentsOfFile:CommandLine.arguments[2],encoding:.utf8)
            let calc=GarageCalculator(script:script)
            let date=parseDate("2026-10-20T05:30:00Z")!
            let deep=parseDate("2026-10-20T03:00:00Z")!.timeIntervalSince1970
            let midnight=parseDate("2026-10-19T15:30:00Z")!.timeIntervalSince1970
            let sessions:[[String:Any]]=[
                ["start":deep,"seconds":3600,"kwh":2],
                ["start":deep,"seconds":3600,"kwh":2], // duplicate cloud record
                ["start":midnight,"seconds":3600,"kwh":2], // spans local midnight
                ["start":deep,"seconds":0,"kwh":99] // invalid, never counted
            ]
            func cloud(_ update:Date,_ year:Int=2026)->Data {
                try! JSONSerialization.data(withJSONObject:["state":"0","attributes":["updated_at":ISO8601DateFormatter().string(from:update),"coverage_year":year,"sessions":sessions]])
            }
            let base:[String:Reading]=[
                ExtraMetric.garageEnergyToday.rawValue:Reading(value:1.5,fetchedAt:date),
                ExtraMetric.garageCostToday.rawValue:Reading(value:0.55,fetchedAt:date),
                ExtraMetric.garageEnergyMonth.rawValue:Reading(value:5.5,fetchedAt:date),
                ExtraMetric.garageCostMonth.rawValue:Reading(value:1.97,fetchedAt:date),
                ExtraMetric.nasCPU.rawValue:Reading(value:12,fetchedAt:date)
            ]
            let combined=calc.combine(base:base,cloud:cloud(date),now:date)
            func close(_ metric:ExtraMetric,_ expected:Double) {
                require(abs((combined[metric.rawValue]?.value ?? -999)-expected)<0.000001,"combined garage \(metric.rawValue)")
            }
            close(.garageEnergyToday,4.5); close(.garageEnergyMonth,9.5)
            close(.garageCostToday,1.379); close(.garageCostMonth,3.184)
            require(combined[ExtraMetric.nasCPU.rawValue]?.value == 12,"garage calculation does not touch other metrics")
            let stale=calc.combine(base:base,cloud:cloud(date.addingTimeInterval(-901)),now:date)
            require(stale[ExtraMetric.garageEnergyMonth.rawValue]?.value == nil,"do not present an ebike subtotal as garage total when cloud stale")
            let absent=calc.combine(base:base,cloud:nil,now:date)
            require(absent[ExtraMetric.garageCostToday.rawValue]?.value == nil,"missing charging data is not zero")
        }
        do {
            let now = Date()
            var live = Snapshot()
            live.readings[0] = Reading(value:1234,sourceTime:now,fetchedAt:now)
            require(live.menuPower(at:now) == "1234 W","menu shows current watts")
            require(live.menuPower(at:now.addingTimeInterval(121)) == "功率不可用","menu hides stale fetch")
            live.readings[0].fetchedAt = now.addingTimeInterval(200)
            require(live.menuPower(at:now.addingTimeInterval(200)) == "功率不可用","menu hides stale source")
            live.readings[0] = Reading(value:nil,sourceTime:now,fetchedAt:now)
            require(live.menuPower(at:now) == "功率不可用","missing watts not zero")
            live.readings[0] = Reading(value:0,sourceTime:now,fetchedAt:now)
            require(live.menuPower(at:now) == "0 W","genuine zero power preserved")
            for (watts,tone) in [(0.0,PowerMenuTone.green),(1000,.green),(1000.1,.pink),(3000,.pink),(3000.1,.purple)] {
                live.readings[0] = Reading(value:watts,sourceTime:now,fetchedAt:now)
                require(live.menuPowerTone(at:now) == tone,"power color threshold \(watts)")
            }
            require(live.menuPowerTone(at:now.addingTimeInterval(121)) == .unavailable,"stale power has no load color")

        }
        do {
            let now=Date()
            var s=Snapshot();s.connectionIssue=nil;s.receivedAt=now
            let good=Reading(value:0,sourceTime:now,fetchedAt:now)
            let bad=Reading(value:nil,sourceTime:now,fetchedAt:now,issue:"实体不可用")
            s.meterPowers=["home":bad,"control":good]
            require(s.status(at:now)=="住宅电表不可用","identify home failure")
            require(s.meterPower(.control,now:now)==0,"preserve healthy zero")
            require(s.menuPower(at:now)=="住宅电表不可用","menu names unavailable meter")
            s.meterPowers=["home":good,"control":bad]
            require(s.status(at:now)=="中控室电表不可用","identify control failure")
            s.meterPowers=["home":bad,"control":bad]
            require(s.status(at:now)=="两户电表不可用","identify both failures")
            s.meterPowers=["home":good,"control":good]
            require(s.powerUnavailableReason(at:now)==nil,"clear warning after recovery")
            require(s.powerUnavailableReason(at:now.addingTimeInterval(121))=="两户电表不可用","expired values unavailable")
        }
        if CommandLine.arguments.count > 1 {
            settings.address = CommandLine.arguments[1]
            let client = HAClient()
            settings.entities[0] = "sensor.good"
            require(try await client.read(settings:settings,token:"local-test-only",index:0).value == 1234,"REST success")
            for (entity,text) in [("unauthorized","令牌无效"),("missing","找不到实体"),("redirect","重定向")] {
                settings.entities[0] = "sensor." + entity
                do { _ = try await client.read(settings:settings,token:"local-test-only",index:0); fatalError("must fail " + entity) }
                catch { require(error.localizedDescription.contains(text),"correct error " + entity) }
            }
            settings.extraEntities=[ExtraMetric.nasCPU.rawValue:"sensor.cpu",ExtraMetric.pm25.rawValue:"sensor.pm"]
            require(try await client.readExtra(settings:settings,token:"local-test-only",metric:.nasCPU).value == 12.5,"extra client reads custom CPU mapping")
            require(try await client.readExtra(settings:settings,token:"local-test-only",metric:.pm25).value == 4,"extra client reads purifier PM")
        }
        print("PASS: core + NAS/environment/garage units, missing values, presets, legacy compatibility, day/month/expiry checks, independent failures, REST authentication and redirect handling")
    }
}
