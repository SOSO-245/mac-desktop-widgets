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
  weather.observe("sunny",at:now+1900,now:now+1900)
  check(weather.rainEndedAt == nil,"no guessed transition over stale gap")
  weather.observe("rainy",at:now,now:now);weather.observe("unavailable",at:now,now:now)
  check(weather.condition == nil && weather.rainbowOpacity(at:now)==0,"invalid weather cleared")
  let legacy=Metrics();let bytes=try JSONEncoder().encode(legacy)
  check(try JSONDecoder().decode(Metrics.self,from:bytes).systemPower == nil,"backward snapshot")
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
  var metrics=Metrics.sample
  metrics.date=now
  for watts in [0.0,1,12.5,25,49.9,50,50.1,100] {
   metrics.systemPower=watts
   let reading=DuckPowerReading.current(metrics,now:now)
   check(reading?.watts==watts,"real power never clamped")
   check(reading?.fraction==min(1,watts/50),"zero to fifty watt progress")
  }
  metrics.systemPower=0;check(DuckPowerReading.current(metrics,now:now)?.fraction==0,"real zero is valid")
  metrics.systemPower=nil;metrics.chipPower=10;check(DuckPowerReading.current(metrics,now:now)?.watts==10,"explicit chip fallback")
  metrics.chipPower=nil;check(DuckPowerReading.current(metrics,now:now)==nil,"missing is not zero")
  metrics.systemPower = .nan;check(DuckPowerReading.current(metrics,now:now)==nil,"nan rejected")
  metrics.systemPower = -1;check(DuckPowerReading.current(metrics,now:now)==nil,"negative rejected")
  metrics.systemPower=25;check(DuckPowerReading.current(metrics,now:now+90)==nil,"stale never shown as live progress")
  metrics.date=now+61;check(DuckPowerReading.current(metrics,now:now)==nil,"future sample rejected")
  let exported=DuckWeatherReading(condition:"rainy",checkedAt:now.timeIntervalSince1970,timezone:"Asia/Shanghai")
  check(exported.validated(at:now) != nil,"weather bridge current reading")
  check(exported.validated(at:now+1801)==nil,"weather bridge stale source rejected")
  let unknown=DuckWeatherReading(condition:"unknown",checkedAt:now.timeIntervalSince1970,timezone:"Asia/Shanghai")
  check(unknown.validated(at:now)==nil,"unknown weather cannot invent conditions")
  let shared=try JSONSerialization.jsonObject(with:JSONEncoder().encode(exported)) as! [String:Any]
  check(Set(shared.keys)==["schema","condition","checkedAt","timezone"],"weather bridge contains no location or private calendar data")
  var glide=DuckProgressMotion();glide.reset(to:0.2,at:100)
  glide.retarget(0.9,at:100)
  check(abs(glide.value(at:100)-0.2)<1e-12,"a new power sample cannot teleport the duck")
  check(glide.value(at:100.02)>0.2 && glide.value(at:100.02)<0.205,"first animation frames are small")
  let before=glide.value(at:100.4);glide.retarget(0.1,at:100.4)
  check(abs(glide.value(at:100.4)-before)<1e-12,"retargeting preserves current position")
  check(abs(glide.value(at:110)-0.1)<1e-8,"settles at newest power value")
  var previous=glide.value(at:100.4)
  for i in 1...300 {
   let time=100.4+Double(i)/60
   if i%12==0 {let value=glide.value(at:time);glide.retarget(i%24==0 ? 1:0,at:time);check(abs(glide.value(at:time)-value)<1e-10,"rapid samples remain continuous")}
   let value=glide.value(at:time)
   check(value.isFinite && (0...1).contains(value),"rapid-sample glide remains in water")
   check(abs(value-previous)<0.04,"sixty-Hz progress has no jumps")
   previous=value
  }
  check(VitalsSkin.duck.smallWidth==164 && VitalsSkin.classic.smallWidth==220,"duck square and classic widths stay distinct")
  let packed=CardGrid.pack(["duck":NSSize(width:VitalsSkin.duck.smallWidth,height:164),"calendar":NSSize(width:164,height:164)],order:["duck","calendar"],area:NSRect(x:0,y:0,width:344,height:164),anchor:NSPoint(x:0,y:164))
  check(packed.count==2 && packed["duck"]?.width==164 && packed["calendar"]?.minX==180,"two square small cards share the toolbox lane")
  let legacyPresence=CardPresence(id:"mac",updated:now,visible:true,size:"small",frame:CardPlacement(NSRect(x:0,y:0,width:220,height:164)))
  check(try JSONDecoder().decode(CardPresence.self,from:JSONEncoder().encode(legacyPresence)).smallWidth==nil,"old layout status remains compatible")
  print("Duck tests: \(checks) passed")
 }
}
