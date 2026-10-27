import AppKit
import SwiftUI
@main struct AtmosphereTests {
 @MainActor static func main() throws {
  let now=Date(),output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  func reading(_ text:String,_ symbol:String="cloud.fill",_ temp:Double=12,_ wind:Double?=nil)->CalendarWeatherReading {
   CalendarWeatherReading(temperature:temp,humidity:65,pm25:20,symbol:symbol,condition:text,checkedAt:now.timeIntervalSince1970,windSpeedMs:wind)
  }
  let cases:[(CalendarWeatherReading,WeatherScene)]=[(reading("雨","cloud.rain.fill"),.rain),(reading("雪","cloud.snow.fill"),.snow),(reading("雾","cloud.fog.fill"),.fog),(reading("晴","sun.max.fill",15,12),.wind),(reading("冻雨"),.frost),(reading("台风"),.typhoon),(reading("沙尘暴"),.dust),(reading("雷雨","cloud.bolt.rain.fill"),.thunder),(reading("晴","sun.max.fill",-3),.frost),(reading("晴","sun.max.fill",15,50),.wind)]
  for (input,expected) in cases {precondition(WeatherScene.resolve(input,now:now)==expected)}
  var invalid=reading("雨","cloud.rain.fill");invalid.checkedAt-=10801;precondition(WeatherScene.resolve(invalid,now:now) == .none)
  invalid=reading("晴","sun.max.fill");invalid.pm25=600;precondition(WeatherScene.resolve(invalid,now:now) == .none)
  precondition(WeatherScene.resolve(nil,now:now) == .none)
  let legacy=Data("{\"temperature\":12,\"humidity\":65,\"pm25\":20,\"symbol\":\"cloud.fill\",\"condition\":\"阴\",\"checkedAt\":\(now.timeIntervalSince1970)}".utf8)
  let decoded=try JSONDecoder().decode(CalendarWeatherReading.self,from:legacy);precondition(decoded.windSpeedMs==nil)
  _=NSApplication.shared
  for scene in WeatherScene.allCases where scene != .none {
   let frame=NSRect(x:0,y:0,width:344,height:164)
   let content=ZStack {
    Color(red:0.05,green:0.12,blue:0.2)
    WeatherAtmosphere(scene:scene,intensity:0.85,fixedTime:12)
    HStack {VStack(alignment:.leading) {Text("万年历").font(.headline);Text("27").font(.system(size:45,weight:.semibold));Text("九月十八").foregroundStyle(.mint)};Spacer();VStack(alignment:.leading) {Text(scene.title+" · 效果示例").font(.headline);Text("不代表当前天气").font(.caption)}}.padding(20).foregroundStyle(.white)
   }.frame(width:344,height:164).clipShape(RoundedRectangle(cornerRadius:28))
   let w=NSWindow(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false);w.isReleasedWhenClosed=false;w.backgroundColor = .clear;w.isOpaque=false
   let host=NSHostingView(rootView:content);host.frame=frame;w.contentView=host;host.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.1));host.displayIfNeeded()
   let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
   try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(scene.rawValue+".png"));w.close()
  }
  print("PASS 14 weather classification/legacy-data checks; eight offline atmosphere renders; no network or location requests")
 }
}
