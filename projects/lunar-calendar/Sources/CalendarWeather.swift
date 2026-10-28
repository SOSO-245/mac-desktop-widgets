import Foundation
import Combine

struct WeatherCity: Codable, Identifiable, Equatable {
    let id:Int
    let name:String
    let latitude:Double
    let longitude:Double
    let admin1:String?
    let country:String?
    var label:String {[name,admin1,country].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ")}
    var valid:Bool {latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)}
}
struct CalendarWeatherReading: Codable {
    var temperature:Double?
    var humidity:Double?
    var pm25:Double?
    var symbol:String
    var condition:String
    var checkedAt:Double
    var windSpeedMs:Double? = nil
    var icon:String {
        switch symbol {
        case "sun.max", "sun.max.fill":return "clear-day"
        case "moon.stars", "moon.stars.fill", "moon.fill":return "clear-night"
        case "cloud.sun", "cloud.sun.fill":return "partly-cloudy-day"
        case "cloud.moon", "cloud.moon.fill":return "partly-cloudy-night"
        case "cloud.rain", "cloud.rain.fill", "cloud.drizzle.fill", "cloud.heavyrain.fill":return "rain"
        case "cloud.snow", "cloud.snow.fill", "snowflake":return "snow"
        case "cloud.bolt", "cloud.bolt.fill", "cloud.bolt.rain.fill":return "thunderstorms"
        case "cloud.fog", "cloud.fog.fill":return "fog"
        case "wind":return "wind"
        default:return "cloudy"
        }
    }
    static func number(_ value:Double?, range:ClosedRange<Double>)->Double? {
        guard let value,value.isFinite,range.contains(value) else{return nil};return value
    }
    static func fresh(_ seconds:Double,now:Date = Date())->Bool {seconds.isFinite && (-60...10800).contains(now.timeIntervalSince1970-seconds)}
    func validated(now:Date = Date())->Self? {
        guard Self.fresh(checkedAt,now:now) else{return nil}
        var v=self;v.temperature=Self.number(temperature,range:-100...65);v.humidity=Self.number(humidity,range:0...100);v.pm25=Self.number(pm25,range:0...5000)
        guard v.temperature != nil || v.humidity != nil || v.pm25 != nil else{return nil}
        v.windSpeedMs=Self.number(windSpeedMs,range:0...150);v.condition=String(condition.prefix(30));return v
    }
    static func presentation(_ code:Int,day:Bool)->(String,String) {
        switch code {
        case 0:return (day ? "sun.max.fill":"moon.stars.fill","晴")
        case 1,2:return (day ? "cloud.sun.fill":"cloud.moon.fill","多云")
        case 3:return ("cloud.fill","阴")
        case 45,48:return ("cloud.fog.fill","雾")
        case 56,57,66,67:return ("cloud.rain.fill","冻雨")
        case 51...67,80...82:return ("cloud.rain.fill","雨")
        case 71...77,85,86:return ("cloud.snow.fill","雪")
        case 95...99:return ("cloud.bolt.rain.fill","雷雨")
        default:return ("cloud","天气")
        }
    }
}
private final class WeatherRedirectPolicy:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
}
enum CalendarWeatherAPI {
    private static let policy=WeatherRedirectPolicy()
    private static func session(local:Bool)->URLSession {
        let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=12;c.timeoutIntervalForResource=18;c.urlCache=nil
        if local {c.connectionProxyDictionary=[:]}
        return URLSession(configuration:c,delegate:policy,delegateQueue:nil)
    }
    static func read(_ url:URL,local:Bool=false) async throws -> Data {
        let s=session(local:local);defer{s.invalidateAndCancel()}
        let (data,response)=try await s.data(from:url)
        guard let http=response as? HTTPURLResponse,http.statusCode==200,data.count<1_000_000 else{throw URLError(.badServerResponse)}
        return data
    }
    static func url(_ base:String,_ query:[URLQueryItem])->URL {var c=URLComponents(string:base)!;c.queryItems=query;return c.url!}
    static func search(_ text:String) async throws->[WeatherCity] {
        struct Result:Decodable {let results:[WeatherCity]?}
        let u=url("https://geocoding-api.open-meteo.com/v1/search",[.init(name:"name",value:text),.init(name:"count",value:"10"),.init(name:"language",value:"zh"),.init(name:"format",value:"json")])
        return try JSONDecoder().decode(Result.self,from:await read(u)).results?.filter(\.valid) ?? []
    }
    static func home() async throws->CalendarWeatherReading {
        let value=try JSONDecoder().decode(CalendarWeatherReading.self,from:await read(URL(string:"http://127.0.0.1:18763/v1/weather")!,local:true))
        guard let valid=value.validated() else{throw URLError(.cannotParseResponse)};return valid
    }
    static func city(_ city:WeatherCity) async throws->CalendarWeatherReading {
        guard city.valid else{throw URLError(.badURL)}
        let query=[URLQueryItem(name:"latitude",value:String(city.latitude)),.init(name:"longitude",value:String(city.longitude)),.init(name:"timeformat",value:"unixtime"),.init(name:"timezone",value:"auto"),.init(name:"forecast_days",value:"1")]
        let weather=url("https://api.open-meteo.com/v1/forecast",query+[.init(name:"current",value:"temperature_2m,relative_humidity_2m,weather_code,is_day,wind_speed_10m"),.init(name:"wind_speed_unit",value:"ms")])
        let air=url("https://air-quality-api.open-meteo.com/v1/air-quality",query+[.init(name:"current",value:"pm2_5")])
        async let weatherData=read(weather)
        async let airData:Data?=try? read(air)
        let root=try JSONSerialization.jsonObject(with:await weatherData) as? [String:Any]
        guard let row=root?["current"] as? [String:Any],let units=root?["current_units"] as? [String:String],let time=row["time"] as? Double,CalendarWeatherReading.fresh(time) else{throw URLError(.cannotParseResponse)}
        let presentation=CalendarWeatherReading.presentation(row["weather_code"] as? Int ?? -1,day:(row["is_day"] as? Int ?? 1)==1)
        var v=CalendarWeatherReading(temperature:units["temperature_2m"]=="°C" ? row["temperature_2m"] as? Double:nil,humidity:units["relative_humidity_2m"]=="%" ? row["relative_humidity_2m"] as? Double:nil,pm25:nil,symbol:presentation.0,condition:presentation.1,checkedAt:time)
        v.windSpeedMs=units["wind_speed_10m"]=="m/s" ? row["wind_speed_10m"] as? Double:nil
        if let bytes=await airData,let airRoot=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],let current=airRoot["current"] as? [String:Any],let airUnits=airRoot["current_units"] as? [String:String],let at=current["time"] as? Double,CalendarWeatherReading.fresh(at),["μg/m³","µg/m³"].contains(airUnits["pm2_5"] ?? "") {v.pm25=current["pm2_5"] as? Double}
        guard let valid=v.validated() else{throw URLError(.cannotParseResponse)};return valid
    }
}
@MainActor final class CalendarWeatherStore:ObservableObject {
    enum Source:String,CaseIterable {case home,city,location}
    @Published private(set) var source:Source
    @Published private(set) var city:WeatherCity?
    @Published private(set) var reading:CalendarWeatherReading? {didSet{publishDuckWeather()}}
    @Published private(set) var trend:WeatherTemperatureTrend?
    @Published private(set) var note=""
    @Published private(set) var busy=false
    @Published var query=""
    @Published private(set) var results:[WeatherCity]=[]
    @Published private(set) var searching=false
    @Published private(set) var locating=false
    @Published private(set) var locatedCity:WeatherCity?
    private lazy var locator=CalendarWeatherLocation()
    private var locationChecked=Date.distantPast
    @Published private(set) var searchNote=""
    private var generation=UUID(),searchGeneration=UUID()
    private var lastAttempt=Date.distantPast
    private var timer:Timer?
    private func publishDuckWeather() {
        let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox/status")
        let file=folder.appendingPathComponent("calendar-weather.json")
        guard let reading,CalendarWeatherReading.fresh(reading.checkedAt) else{try? FileManager.default.removeItem(at:file);return}
        var condition:String
        switch reading.symbol {
        case "cloud.bolt", "cloud.bolt.fill", "cloud.bolt.rain.fill":condition="lightning-rainy"
        case "cloud.snow", "cloud.snow.fill", "snowflake":condition="snowy"
        case "cloud.rain", "cloud.rain.fill", "cloud.drizzle.fill", "cloud.heavyrain.fill":condition="rainy"
        case "sun.max", "sun.max.fill":condition="sunny"
        case "moon.stars", "moon.stars.fill", "moon.fill":condition="clear-night"
        case "cloud.fog", "cloud.fog.fill":condition="fog"
        case "wind":condition="windy"
        default:condition="cloudy"
        }
        if ["台风","typhoon","hurricane","飓风"].contains(reading.condition.lowercased()){condition="typhoon"}
        let value:[String:Any]=["schema":1,"condition":condition,"checkedAt":reading.checkedAt,"timezone":TimeZone.current.identifier]
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if let bytes=try? JSONSerialization.data(withJSONObject:value){try? bytes.write(to:file,options:.atomic)}
    }
    init() {
        source=Source(rawValue:UserDefaults.standard.string(forKey:"calendarWeather.source") ?? "home") ?? .home
        city=UserDefaults.standard.data(forKey:"calendarWeather.city").flatMap{try? JSONDecoder().decode(WeatherCity.self,from:$0)}
        if city?.valid == false {city=nil}
    }
    var location:String {source == .home ? "家庭天气":source == .location ? locatedCity?.name ?? "系统定位":city?.name ?? "选择区县"}
    func start() {
        Task {await refresh(force:true)}
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true) {[weak self] _ in Task {@MainActor in await self?.refresh()}}
    }
    func setSource(_ next:Source) {
        guard next != source else{return};source=next;UserDefaults.standard.set(next.rawValue,forKey:"calendarWeather.source");reset()
    }
    func choose(_ next:WeatherCity) {
        guard next.valid else{return};city=next;source = .city
        UserDefaults.standard.set(try? JSONEncoder().encode(next),forKey:"calendarWeather.city");UserDefaults.standard.set(source.rawValue,forKey:"calendarWeather.source");reset()
    }
    private func reset() {generation=UUID();locator.cancel();locating=false;busy=false;reading=nil;trend=nil;note="";lastAttempt = .distantPast;Task {await refresh(force:true)}}
    func search() async {
        let text=query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.count>=2 else{searchNote="请输入至少两个字或字母";return}
        let request=UUID();searchGeneration=request;searching=true;searchNote="";results=[]
        do {
            async let regions=WeatherCity.searchDistrict(text)
            let cities=(try? await CalendarWeatherAPI.search(text)) ?? []
            let districts=await regions
            guard request==searchGeneration else{return};let found=districts+cities.filter{candidate in !districts.contains{abs($0.latitude-candidate.latitude)<0.03 && abs($0.longitude-candidate.longitude)<0.03}};results=found;searchNote=found.isEmpty ? "未找到城市，可试试拼音或英文名称":""}
        searching=false
    }
    func useCurrentLocation() {
        if source != .location {source = .location;UserDefaults.standard.set(source.rawValue,forKey:"calendarWeather.source");generation=UUID();reading=nil;trend=nil;busy=false}
        requestLocation(allowPrompt:true)
    }
    private func requestLocation(allowPrompt:Bool) {
        guard !locating else{return};locating=true;note="正在定位…";let request=generation
        locator.request(allowPrompt:allowPrompt) {[weak self] city,message in
            guard let self,self.source == .location,self.generation==request else{return}
            self.locating=false;self.note=message;self.locationChecked=Date()
            if let city {self.locatedCity=city;self.reading=nil;self.trend=nil;self.lastAttempt = .distantPast;Task {await self.refresh(force:true)}}
        }
    }
    func refresh(force:Bool=false) async {
        let now=Date();if let trend,now.timeIntervalSince(trend.loadedAt)>10800 {self.trend=nil};if let reading,!CalendarWeatherReading.fresh(reading.checkedAt,now:now) {self.reading=nil}
        guard !busy,force || now.timeIntervalSince(lastAttempt)>=(source == .home ? 55:900) else{return}
        if source == .location && now.timeIntervalSince(locationChecked)>=900 {requestLocation(allowPrompt:false);return}
        let target=source == .location ? locatedCity:city
        guard source == .home || target != nil else{note=source == .location ? "点击使用当前位置，或手动选择区县":"请在天气设置中选择城市或区县";return}
        let request=generation;busy=true;lastAttempt=now
        do {
            let result:CalendarWeatherReading
            if source == .home {result=try await CalendarWeatherAPI.home()}
            else {
                async let current=CalendarWeatherAPI.city(target!)
                async let series:WeatherTemperatureTrend?=try? CalendarWeatherAPI.trend(target!)
                result=try await current
                let newTrend=await series
                guard request==generation else{return}
                if let newTrend {trend=newTrend}
            }
            guard request==generation else{return};reading=result;note=""
        } catch {guard request==generation else{return};note=source == .home ? "家庭天气暂不可用，可打开家庭概览或选择城市":"天气暂未更新，稍后重试"}
        busy=false
    }
}
