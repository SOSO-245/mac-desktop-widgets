import Foundation
import SwiftUI
@main struct Tests {
 static func main() throws {
  var checks=0
  func check(_ result:Bool,_ label:String) {precondition(result,label);checks+=1}
  let now=Date(timeIntervalSince1970:1_790_000_000)
  func date(_ month:Int)->Date {var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!;return c.date(from:DateComponents(year:2026,month:month,day:15,hour:12))!}
  var weather=DuckWeather()
  for (month,style) in [(3,DuckWeather.Appearance.spring),(5,.spring),(6,.summer),(8,.summer),(9,.original),(11,.original),(12,.winter),(2,.winter)] {
   check(weather.appearance(at:date(month),timezone:"UTC")==style,"season \(month)")
  }
  weather.observe("rainy",at:now,now:now)
  check(weather.appearance(at:now,timezone:"UTC") == .rain,"rain overrides season")
  weather.observe("cloudy",at:now+60,now:now+60)
  check(weather.rainEndedAt == now+60,"observed rain end")
  weather.observe("cloudy",at:now+1800,now:now+1800)
  check(weather.rainEndedAt == now+60,"no retrigger on refresh")
  check(weather.rainbowOpacity(at:now+1800)>0.9,"rainbow within two hours")
  weather.observe("sunny",at:now+7260,now:now+7260)
  check(weather.rainbowOpacity(at:now+7260)==0,"rainbow expires exactly two hours")
  weather.observe("snowy",at:now+7261,now:now+7261)
  check(weather.appearance(at:now+7261,timezone:"UTC") == .snow,"snow wins")
  for condition in ["lightning-rainy","lightning","typhoon","hurricane"] {
   weather.observe(condition,at:now,now:now)
   check(weather.appearance(at:now,timezone:"UTC") == .football,"explicit storm \(condition)")
  }
  weather.observe("windy",at:now,now:now)
  check(weather.appearance(at:now,timezone:"UTC") != .football,"ordinary wind is not typhoon")
  weather.observe("rainy",at:now,now:now)
  weather.observe("sunny",at:now+1000,now:now+1000)
  check(weather.rainEndedAt == nil,"no guessed transition over stale gap")
  weather.observe("rainy",at:now,now:now);weather.observe("unavailable",at:now,now:now)
  check(weather.condition == nil && weather.rainbowOpacity(at:now)==0,"invalid weather cleared")
  let legacy=Snapshot();let bytes=try JSONEncoder().encode(legacy)
  check(try JSONDecoder().decode(Snapshot.self,from:bytes).duckWeather == nil,"backward snapshot")
  var motion=DuckMotion(action:.swim,began:100,from:0.2,target:0.8)
  check(motion.pose(at:100,share:0.2).position==0.2,"starts at duck")
  let swim=0.8+0.6*1.6
  check(abs(motion.pose(at:100+swim,share:0.2).position-0.8)<1e-8,"swims to click")
  check(motion.pose(at:100+swim+0.324,share:0.2).pitch > 1.56 && motion.pose(at:100+swim+0.30,share:0.2).depth==0,"rotates ninety before diving")
  check(motion.pose(at:100+swim+0.9,share:0.2).opacity==0,"submerges")
  check(motion.pose(at:110,share:0.4).position==0.4,"returns to current metered ratio")
  for t in stride(from:100.0,through:110,by:0.02) {let p=motion.pose(at:t,share:0.4);check((0...1).contains(p.position) && p.depth>=0 && (0...1).contains(p.opacity),"finite bounded pose")}
  motion=DuckMotion(action:.bob,began:100,from:0.3,target:0.3)
  check(abs(motion.pose(at:100.0625,share:0.3).bounce)>2,"quick bob")
  check(motion.pose(at:102,share:0.4).position==0.4,"bob settles")
  let starts=stride(from:0.0,through:0.8,by:0.01).map{DuckMotion.shockVisible(age:$0)}
  let rising=zip([false]+starts,starts).filter{!$0.0 && $0.1}.count
  check(rising==2,"exactly two bounded flashes")
  let wet=CGRect(x:34,y:1084,width:136,height:15)
  for point in [CGPoint(x:50,y:1099),CGPoint(x:50,y:1084),CGPoint(x:34,y:1090),CGPoint(x:170,y:1090)] {check(DuckImpact.contains(point,in:wet),"closed water contact edge")}
  check(!DuckImpact.contains(CGPoint(x:50,y:1102),in:wet),"reject above water")
  check(!DuckImpact.contains(CGPoint(x:50,y:1080),in:wet),"reject below water")
  print("Duck tests: \(checks) passed")
 }
}
