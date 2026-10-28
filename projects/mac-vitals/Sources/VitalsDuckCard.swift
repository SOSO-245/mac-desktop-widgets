import SwiftUI

struct VitalsDuckCard:View {
    let data:Metrics
    let weather:DuckWeather
    let timezone:String
    var size="medium"
    var locked=false
    var menuSurface=false
    var onLock:()->Void
    private var small:Bool{size=="small"}
    private var large:Bool{size=="large"}
    private var live:Bool{data.fresh()}
    private var reading:DuckPowerReading?{DuckPowerReading.current(data)}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func value(_ label:String,_ text:String,_ tint:Color = .white)->some View {
        VStack(alignment:.leading,spacing:3) {
            Text(label).font(.system(size:9)).foregroundStyle(.white.opacity(0.55))
            Text(text).font(.system(size:large ? 17:12,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    var body:some View {
        VStack(alignment:.leading,spacing:large ? 7:3) {
            HStack {
                Image(systemName:"desktopcomputer").foregroundStyle(neon)
                Text(small ? "Mac 小鸭子":"Mac 实时监测 · 小鸭子").font(.system(size:small ? 12:14,weight:.bold)).lineLimit(1)
                Spacer(minLength:0)
                Button(action:onLock){Image(systemName:locked ? "lock.fill":"lock.open").foregroundStyle(.cyan)}.buttonStyle(.plain).focusEffectDisabled().help(locked ? "解锁位置":"锁定位置")
            }.frame(height:20)
            // Fixed-height rows keep the water anchored as readings gain or lose digits.
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:3) {
                    Text(data.powerLabel).font(.system(size:8)).foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength:0)
                    HStack(spacing:3) {
                        TemperatureFace(value:live ? data.cpuTemp:nil,displayMood:live ? data.temperatureDisplayMood:-1).frame(width:16,height:16)
                        Text(Metrics.value(live ? data.cpuTemp:nil," °C",decimals:1)).monospacedDigit().fixedSize()
                    }.foregroundStyle(.cyan).font(.system(size:small ? 10:13,weight:.semibold))
                }.frame(height:16)
                HStack(alignment:.center,spacing:3) {
                    HStack(alignment:.firstTextBaseline,spacing:3) {
                        Text(Metrics.value(reading?.watts,decimals:1)).font(.system(size:large ? 37:27,weight:.medium,design:.rounded)).monospacedDigit().fixedSize()
                        Text("W").font(.system(size:11,weight:.semibold))
                    }.foregroundStyle(neon).fixedSize().frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.trailing,spacing:2) {
                        Text("CPU "+Metrics.value(live ? data.cpu:nil,"%"))
                        Text("内存 "+Metrics.value(live ? data.memoryPercent:nil,"%"))
                    }.font(.system(size:8)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).fixedSize().frame(width:small ? 48:80,alignment:.trailing)
                }.frame(height:large ? 47:34)
            }.frame(height:large ? 63:50)
            VStack(spacing:0) {
                Group {
                    if let reading {
                        PowerWater(share:reading.fraction,animated:true,interactive:true,weather:weather,timezone:timezone)
                    } else {
                        VStack{Spacer();Capsule().fill(.white.opacity(0.08)).frame(height:6)}.accessibilityLabel("功率待采集，小鸭子进度不可用")
                    }
                }.frame(height:large ? 45:34).anchorPreference(key:WaterSurfaceAnchor.self,value:.bounds){$0}
                HStack {
                    Text("0 W")
                    Spacer()
                    if reading == nil {Text("待采集");Spacer()}
                    Text("50 W")
                }.font(.system(size:8,weight:.medium)).monospacedDigit().foregroundStyle(.white.opacity(0.5)).frame(height:10)
            }.frame(height:large ? 55:44).padding(.top,small ? 3:0).help("小鸭子位置对应实时功率 0–50 W；点击鸭子浮动或清雪，点水面游泳潜水。超过 50 W 仍显示真实数值。")
            if large {
                HStack(spacing:8) {
                    value("CPU",Metrics.value(live ? data.cpu:nil,"%"))
                    value("内存已用",Metrics.value(live ? data.memoryUsed.map{$0/1073741824}:nil," GB",decimals:1),violet)
                    value("GPU 温度",Metrics.value(live ? data.gpuTemp:nil," °C",decimals:1),.cyan)
                }
                Divider().overlay(.white.opacity(0.08))
            }
            if large {HStack(spacing:10) {
                value("↓ 下载",Metrics.rate(live ? data.download:nil),.cyan)
                value("↑ 上传",Metrics.rate(live ? data.upload:nil),violet)
                value("风扇",live ? data.fanText:"—",.cyan)
            }} else {HStack {
                Text("↓ "+Metrics.rate(live ? data.download:nil)).foregroundStyle(.cyan)
                Spacer(minLength:2)
                Text("↑ "+Metrics.rate(live ? data.upload:nil)).foregroundStyle(violet)
            }.font(.system(size:10,weight:.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(height:12)}
            if large {
                VStack(alignment:.leading,spacing:3) {
                    HStack{Text("最近一分钟 · 功率");Spacer();Text(data.chip)}.font(.system(size:8)).foregroundStyle(.white.opacity(0.5))
                    GlowPower(values:live ? data.history:[]).frame(height:25)
                }.padding(7).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
            }
            if large {Spacer(minLength:0)
            HStack(spacing:4) {
                Circle().fill(reading == nil ? .gray:neon).frame(width:4,height:4)
                Text(reading == nil ? "等待实时功率":"每秒更新 · 0–50 W")
                Spacer(minLength:0)
                if data.date != .distantPast {Text(data.date,style:.time)}
            }.font(.system(size:7)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)}
        }
        .padding(small ? 12:14).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background {
            if !menuSurface {RoundedRectangle(cornerRadius:28).fill(LinearGradient(colors:[Color(red:0.18,green:0.17,blue:0.34),Color(red:0.055,green:0.075,blue:0.13),Color(red:0.13,green:0.11,blue:0.26)],startPoint:.topLeading,endPoint:.bottomTrailing))}
        }
        .overlayPreferenceValue(WaterSurfaceAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {AfterRainRainbow(strength:weather.rainbowOpacity(at:Date()),water:proxy[anchor]).allowsHitTesting(false)}
            }.allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius:28)).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
