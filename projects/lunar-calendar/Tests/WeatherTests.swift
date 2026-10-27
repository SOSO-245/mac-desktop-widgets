import Foundation
@main struct WeatherTests {
 @MainActor static func main() async throws {
  let now=Date(timeIntervalSince1970:2_000_000_000)
  func check(_ value:Bool,_ label:String) {if !value {fatalError(label)}}
  let base=CalendarWeatherReading(temperature:13,humidity:60,pm25:27,symbol:"cloud.sun.fill",condition:"多云",checkedAt:now.timeIntervalSince1970)
  check(base.validated(now:now)?.humidity==60,"real humidity preserved")
  var invalid=base;invalid.checkedAt-=10801;check(invalid.validated(now:now)==nil,"stale weather rejected")
  invalid=base;invalid.checkedAt+=61;check(invalid.validated(now:now)==nil,"future weather rejected")
  invalid=base;invalid.humidity=160;invalid.pm25 = -1;check(invalid.validated(now:now)?.humidity==nil && invalid.validated(now:now)?.pm25==nil,"bad values do not become zero")
  invalid=base;invalid.temperature=nil;invalid.humidity=nil;invalid.pm25=nil;check(invalid.validated(now:now)==nil,"all-missing weather rejected")
  invalid=base;invalid.pm25=0;check(invalid.validated(now:now)?.pm25==0,"valid zero retained")
  invalid=base;invalid.temperature = .infinity;check(invalid.validated(now:now)?.temperature==nil,"nonfinite temperature rejected")
  check(CalendarWeatherReading.presentation(0,day:false).0=="moon.stars.fill","night icon")
  check(CalendarWeatherReading.presentation(95,day:true).0=="cloud.bolt.rain.fill","storm icon")
  check(base.icon=="partly-cloudy-day","bundled animated icon mapping")
  check(!WeatherCity(id:1,name:"bad",latitude:91,longitude:0,admin1:nil,country:nil).valid,"invalid city coordinates")
  check(WeatherCity(id:1,name:"城市",latitude:0,longitude:0,admin1:nil,country:nil).valid,"valid equatorial city")
  let anchor=now.timeIntervalSince1970
  let points=(-170...170).map {WeatherTemperaturePoint(time:anchor+Double($0)*3600,temperature:10+sin(Double($0)))}
  let trend=WeatherTemperatureTrend(points:points,loadedAt:now)
  check(trend.samples(.day,now:now).count==25 && trend.samples(.day,now:now).allSatisfy{$0.time>=anchor},"future 24-hour window endpoints")
  check(trend.samples(.week,now:now).count==169,"past week")
  check(trend.samples(.nextWeek,now:now).count==169,"next week")
  check(trend.samples(.day,now:now.addingTimeInterval(10801)).isEmpty,"stale trend hidden")
  check(WeatherTrendRange.day.next == .week && WeatherTrendRange.week.next == .nextWeek && WeatherTrendRange.nextWeek.next == .day,"cycle time ranges")
  let missing=try JSONSerialization.data(withJSONObject:["hourly_units":["temperature_2m":"°C","time":"unixtime"],"hourly":["time":[anchor-3600,anchor,anchor+3600],"temperature_2m":[12,NSNull(),14]]])
  check(try WeatherTemperatureTrend.parse(missing,now:now).points.count==2,"missing temperature never becomes zero")
  let mismatched=try JSONSerialization.data(withJSONObject:["hourly_units":["temperature_2m":"°F","time":"unixtime"],"hourly":["time":[anchor],"temperature_2m":[45]]])
  check((try? WeatherTemperatureTrend.parse(mismatched,now:now))==nil,"wrong units rejected")
  let midnight=floor(anchor/86400)*86400
  let dailyFixture=try JSONSerialization.data(withJSONObject:["timezone":"UTC","utc_offset_seconds":0,"hourly_units":["temperature_2m":"°C","time":"unixtime"],"hourly":["time":[anchor],"temperature_2m":[12]],"daily_units":["temperature_2m_min":"°C","temperature_2m_max":"°C","precipitation_probability_max":"%"],"daily":["time":(-1...7).map{midnight+Double($0)*86400},"temperature_2m_min":Array(repeating:10,count:9),"temperature_2m_max":Array(repeating:20,count:9),"weather_code":Array(repeating:2,count:9),"precipitation_probability_max":Array(repeating:40,count:9)]])
  let seven=try WeatherTemperatureTrend.parse(dailyFixture,now:now)
  check(seven.days.count==7 && seven.days.first?.time==midnight,"seven local days excludes yesterday and day eight")
  check(seven.days.allSatisfy{$0.minimum==10 && $0.maximum==20 && $0.rainProbability==40},"daily units and precipitation retained")
  if CommandLine.arguments.contains("--forecast-live") {
   let place=WeatherCity(id:1,name:"Beijing",latitude:39.9,longitude:116.4,admin1:nil,country:nil)
   let forecast=try await CalendarWeatherAPI.trend(place)
   check(forecast.days.count==7 && forecast.samples(.day).count>=23,"live future24h and seven-day forecast")
   print("LIVE forecast: future24h and seven days verified")
  }
  if CommandLine.arguments.contains("--live") {
   let cities=try await CalendarWeatherAPI.search("Beijing");check(!cities.isEmpty,"geocoding response")
   let result=try await CalendarWeatherAPI.city(cities[0]);check(result.temperature != nil && result.humidity != nil,"public weather API")
   let liveTrend=try await CalendarWeatherAPI.trend(cities[0]);check(liveTrend.samples(.day).count>=20 && liveTrend.samples(.week).count>=160 && liveTrend.samples(.nextWeek).count>=160,"live forecast/history coverage")
   let districts=await WeatherCity.searchDistrict("北京市朝阳区");check(districts.contains{$0.label.contains("朝阳")},"district-level search result")
   let home=try await CalendarWeatherAPI.home();check(home.temperature != nil,"local weather bridge")
   print("LIVE PASS: city search, current temperature/humidity, home weather; city PM available: \(result.pm25 != nil), home humidity available: \(home.humidity != nil)")
  }
  print("21 weather and forecast validation checks passed")
 }
}
