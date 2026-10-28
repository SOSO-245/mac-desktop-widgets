import Foundation

enum VitalsSkin:String {
    case classic,duck
    var smallWidth:Double {self == .duck ? 164:220}
}

/// A critically damped response preserves both position and velocity when a
/// new sample arrives. The measured number stays live; only the duck glides.
struct DuckProgressMotion {
    private var position=0.5
    private var velocity=0.0
    private var target=0.5
    private var updated=0.0
    mutating func reset(to value:Double,at time:Double) {
        guard value.isFinite,time.isFinite else{return}
        position=min(1,max(0,value));target=position;velocity=0;updated=time
    }
    private func state(at time:Double)->(Double,Double) {
        let age=max(0,time-updated),frequency=3.0
        let error=position-target,coefficient=velocity+frequency*error,decay=exp(-frequency*age)
        return (target+(error+coefficient*age)*decay,(velocity-frequency*coefficient*age)*decay)
    }
    func value(at time:Double)->Double {
        guard time.isFinite else{return position}
        return min(1,max(0,state(at:time).0))
    }
    mutating func retarget(_ value:Double,at time:Double) {
        guard value.isFinite,time.isFinite,time>=updated else{return}
        let current=state(at:time)
        position=min(1,max(0,current.0));velocity=current.1
        target=min(1,max(0,value));updated=time
    }
}

struct DuckPowerReading:Equatable {
    let watts:Double
    var fraction:Double {min(1,max(0,watts/50))}
    static func current(_ metrics:Metrics,now:Date=Date())->Self? {
        guard metrics.fresh(now),let value=metrics.power,value.isFinite,value>=0 else{return nil}
        return Self(watts:value)
    }
}

/// Only public display conditions are shared locally; no coordinates or
/// calendar/contact data enter the duck weather bridge.
struct DuckWeatherReading:Codable {
    var schema=1
    var condition:String
    var checkedAt:Double
    var timezone:String
    func validated(at now:Date)->Self? {
        guard schema==1,DuckWeather.known.contains(condition),checkedAt.isFinite,
              (-60...1800).contains(now.timeIntervalSince1970-checkedAt),
              TimeZone(identifier:timezone) != nil else{return nil}
        return self
    }
}

@MainActor final class DuckWeatherStore {
    private(set) var weather=DuckWeather()
    private(set) var timezone=TimeZone.current.identifier
    private var lastPoll=Date.distantPast
    private var reading=false
    private var generation=UUID()
    var onUpdate:(()->Void)?
    func refresh(now:Date=Date()) {
        guard !reading,now.timeIntervalSince(lastPoll)>=15 else{return}
        lastPoll=now;reading=true
        let run=generation
        Task { [weak self] in
            let value=await Task.detached(priority:.utility) { () -> DuckWeatherReading? in
                let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox/status/calendar-weather.json")
                guard let bytes=try? Data(contentsOf:url),bytes.count<8192 else{return nil}
                return (try? JSONDecoder().decode(DuckWeatherReading.self,from:bytes))?.validated(at:now)
            }.value
            guard let self,run==self.generation else{return}
            self.reading=false
            if let value {
                self.timezone=value.timezone
                let observed=Date(timeIntervalSince1970:value.checkedAt)
                if self.weather.observedAt != observed || self.weather.condition != value.condition {
                    self.weather.observe(value.condition,at:observed,now:now)
                }
            } else {self.weather.observe(nil,at:nil,now:now)}
            self.onUpdate?()
        }
    }
}
