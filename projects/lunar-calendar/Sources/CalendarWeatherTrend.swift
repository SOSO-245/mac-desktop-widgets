import Foundation

enum WeatherTrendRange:Int,CaseIterable {
    case day,week,nextWeek
    var title:String {switch self {case .day:return "未来24小时";case .week:return "过去一周";case .nextWeek:return "未来一周"}}
    var next:Self {Self(rawValue:(rawValue+1)%3)!}
}
struct WeatherTemperaturePoint:Identifiable,Equatable {
    let time:Double
    let temperature:Double
    var id:Double {time}
}
struct WeatherForecastDay:Identifiable {
    let time:Double
    let minimum:Double
    let maximum:Double
    let code:Int
    let rainProbability:Double?
    var id:Double {time}
}
struct WeatherTemperatureTrend {
    let points:[WeatherTemperaturePoint]
    let loadedAt:Date
    var days:[WeatherForecastDay]=[]
    var timezone:String="UTC"
    func samples(_ range:WeatherTrendRange,now:Date=Date())->[WeatherTemperaturePoint] {
        guard (0...10800).contains(now.timeIntervalSince(loadedAt)) else{return []}
        let end=now.timeIntervalSince1970
        let bounds:ClosedRange<Double>
        switch range {case .day:bounds=end...(end+86400);case .week:bounds=(end-7*86400)...end;case .nextWeek:bounds=end...(end+7*86400)}
        return points.filter{bounds.contains($0.time)}
    }
    static func parse(_ data:Data,now:Date=Date()) throws->Self {
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let units=root["hourly_units"] as? [String:String],units["temperature_2m"]=="°C",units["time"]=="unixtime",
              let hourly=root["hourly"] as? [String:Any],let times=hourly["time"] as? [Double],let values=hourly["temperature_2m"] as? [Any],times.count==values.count,times.count<=500 else{throw URLError(.cannotParseResponse)}
        var seen=Set<Double>()
        let points=zip(times,values).compactMap {time,value->WeatherTemperaturePoint? in
            guard time.isFinite,abs(time-now.timeIntervalSince1970)<16*86400,let temp=value as? Double,let valid=CalendarWeatherReading.number(temp,range:-100...65),seen.insert(time).inserted else{return nil}
            return WeatherTemperaturePoint(time:time,temperature:valid)
        }.sorted{$0.time<$1.time}
        guard !points.isEmpty else{throw URLError(.cannotParseResponse)}
        var days:[WeatherForecastDay]=[]
        if let daily=root["daily"] as? [String:Any],let dayUnits=root["daily_units"] as? [String:String],dayUnits["temperature_2m_min"]=="°C",dayUnits["temperature_2m_max"]=="°C",
           let dates=daily["time"] as? [Double],let mins=daily["temperature_2m_min"] as? [Any],let maxs=daily["temperature_2m_max"] as? [Any],let codes=daily["weather_code"] as? [Any],dates.count==mins.count,dates.count==maxs.count,dates.count==codes.count,dates.count<=30 {
            let rain=daily["precipitation_probability_max"] as? [Any] ?? []
            let offset=root["utc_offset_seconds"] as? Double ?? 0
            let midnight=floor((now.timeIntervalSince1970+offset)/86400)*86400-offset
            for i in dates.indices where dates[i]>=midnight && dates[i]<midnight+7*86400 {
                guard dates[i].isFinite,let low=CalendarWeatherReading.number(mins[i] as? Double,range:-100...65),let high=CalendarWeatherReading.number(maxs[i] as? Double,range:-100...65),low<=high,let code=codes[i] as? Int else{continue}
                let chance=dayUnits["precipitation_probability_max"]=="%" && rain.indices.contains(i) ? CalendarWeatherReading.number(rain[i] as? Double,range:0...100):nil
                days.append(WeatherForecastDay(time:dates[i],minimum:low,maximum:high,code:code,rainProbability:chance))
            }
        }
        return Self(points:points,loadedAt:now,days:days,timezone:root["timezone"] as? String ?? "UTC")
    }
}
extension CalendarWeatherAPI {
    static func trend(_ city:WeatherCity) async throws->WeatherTemperatureTrend {
        guard city.valid else{throw URLError(.badURL)}
        let u=url("https://api.open-meteo.com/v1/forecast",[.init(name:"latitude",value:String(city.latitude)),.init(name:"longitude",value:String(city.longitude)),.init(name:"hourly",value:"temperature_2m"),.init(name:"daily",value:"weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),.init(name:"past_days",value:"7"),.init(name:"forecast_days",value:"8"),.init(name:"timeformat",value:"unixtime"),.init(name:"timezone",value:"auto")])
        return try WeatherTemperatureTrend.parse(await read(u))
    }
}
