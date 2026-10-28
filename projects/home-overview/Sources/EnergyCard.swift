import SwiftUI

enum CardSize: String, CaseIterable { case small = "小号", medium = "中号", large = "大号" }

struct EnergyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.12,green:0.23,blue:0.36), Color(red:0.055,green:0.10,blue:0.20), Color(red:0.16,green:0.13,blue:0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.cyan.opacity(0.16),.clear], center: .topTrailing, startRadius: 0, endRadius: 270)
        }
    }
}

struct EnergyCard: View {
    var waterTheme="duck"
    var menuSurface=false
    var interactiveWater=false
    var animatePower=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: Snapshot
    let size: CardSize
    var refresh: AnyView? = nil
    var managementURL: URL? = nil
    var websiteURL: URL? = nil
    var overviewURL: URL? = nil
    var now = Date()
    private let ice = Color(red:0.79,green:0.91,blue:0.99)
    private let yellow = Color(red:0.94,green:0.98,blue:0.54)
    private var compact: Bool { size == .small }
    private var status: String { snapshot.status(at:now) }
    private var warning: Bool { !snapshot.demo && status != "已同步 HA" }
    private func number(_ i:Int) -> String { snapshot.number(i,now:now) }
    private var powerNumber:String {
        let value=snapshot.demo ? snapshot.value(0,now:now):snapshot.menuPowerValue(at:now)
        return value.map{String(format:$0>=1000 ? "%.0f":"%.1f",$0)} ?? "不可用"
    }
    private var powerAvailable:Bool { powerNumber != "不可用" }
    private func extra(_ metric:ExtraMetric)->String { snapshot.extraNumber(metric,now:now) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : (size == .medium ? 4 : 7)) {
            header
            if let overviewURL, !interactiveWater {
                Link(destination:overviewURL) {
                    cardContent.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("打开家庭概览")
            } else { cardContent.background { if let overviewURL { Link(destination:overviewURL) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain) } } }
        }
        .padding(compact ? 14 : size == .medium ? 14:16)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // WidgetKit supplies the actual container contour. A fixed radius is
        // clipped on the desktop, where the system uses a different curve.
        .overlay {
            if !menuSurface { ContainerRelativeShape().inset(by:1)
                .strokeBorder(LinearGradient(colors:[ice.opacity(0.65),.white.opacity(0.08),Color(red:0.51,green:0.43,blue:0.94).opacity(0.7)], startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.75)
                .allowsHitTesting(false) }
        }
        .overlayPreferenceValue(WaterSurfaceAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {AfterRainRainbow(strength:snapshot.duckWeather?.rainbowOpacity(at:now) ?? 0,water:proxy[anchor]).clipShape(ContainerRelativeShape()).allowsHitTesting(false)}
            }.allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var cardContent:some View {
        if compact { smallContent } else if size == .medium { mediumContent } else { largeContent }
    }
    var header: some View {
        HStack(alignment: .top) {
            if let websiteURL {
                Link(destination:websiteURL) { titleLabel.contentShape(Rectangle()) }
                    .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("打开 Home Assistant 网页")
            } else { titleLabel }
            Spacer(minLength:4)
            if compact {
                if let refresh { refresh }
                else { Circle().fill(warning ? .orange : .cyan).frame(width:6,height:6).padding(.top,7).accessibilityLabel(status) }
            } else {
                HStack(spacing:4) {
                    if let managementURL {
                        Link(destination:managementURL) { statusLabel.padding(.leading,8).padding(.vertical,6).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("打开家庭概览连接设置")
                    } else {
                        statusLabel.padding(.leading,8).padding(.vertical,6)
                    }
                    if let refresh { refresh.padding(.trailing,8).padding(.vertical,6) }
                }.padding(.trailing,refresh == nil ? 8 : 0).background(.white.opacity(0.07),in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.16),lineWidth:0.7).allowsHitTesting(false))
            }
        }
    }
    private var titleLabel:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:5) {
                if compact {Image(systemName:"house.fill").font(.system(size:12,weight:.semibold)).foregroundStyle(ice)}
                Text(snapshot.title).font(.system(size:compact ? 13 : size == .medium ? 16:21,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.8)
                if size == .medium {Text(snapshot.dateText).font(.system(size:8,weight:.medium)).foregroundStyle(ice.opacity(0.65)).lineLimit(1)}
            }
            if !compact && size != .medium { Text("\(snapshot.dateText) · \(snapshot.source)").font(.system(size:10,weight:.medium)).foregroundStyle(ice.opacity(0.8)).lineLimit(1) }
        }
    }
    private var statusLabel:some View {
        HStack(spacing:4) {
            Circle().fill(warning ? .orange : .cyan).frame(width:5,height:5)
            Text(status == "已同步 HA" ? snapshot.shortTime + " 更新" : status).font(.system(size:9,weight:.semibold))
        }
    }
    var power: some View {
        VStack(alignment:.leading,spacing:compact ? 3 : 5) {
            HStack(alignment:.firstTextBaseline,spacing:4) {
                Image(systemName:"bolt.fill").font(.system(size:compact ? 17 : 23)).foregroundStyle(yellow)
                Text(powerNumber).font(.system(size:powerAvailable ? (compact ? 34 : (size == .large ? 42 : 30)):18,weight:.light,design:.rounded)).monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                if powerAvailable { Text("W").font(.system(size:12,weight:.semibold)).foregroundStyle(ice) }
            }
        }
    }
    private let homePowerColor=Color(red:0.67,green:0.53,blue:1)
    private let controlPowerColor=Color(red:0.37,green:0.78,blue:1)
    @ViewBuilder private func meterLegend(_ meter:Meter)->some View {
        let color=meter == .home ? homePowerColor:controlPowerColor
        let value=snapshot.meterPower(meter,now:now).map{String(format:"%.1f W",$0)} ?? "不可用"
        if compact {
            VStack(alignment:meter == .home ? .leading:.trailing,spacing:2) {
                HStack(spacing:3) {
                    Circle().fill(color).frame(width:4,height:4)
                    Text(meter == .home ? "住宅":"中控室").foregroundStyle(ice.opacity(0.65))
                }.font(.system(size:8,weight:.medium))
                Text(value).font(.system(size:10,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(ice.opacity(0.9))
            }.lineLimit(1).minimumScaleFactor(0.75)
        } else {
            HStack(spacing:4) {
                Circle().fill(color).frame(width:5,height:5)
                Text(meter == .home ? "住宅":"中控室")
                Text(value).monospacedDigit()
            }.font(.system(size:9,weight:.medium)).foregroundStyle(ice.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }
    private var meterBars:some View {
        let share=snapshot.meterShare(.home,now:now)
        let home=snapshot.meterPower(.home,now:now)
        let control=snapshot.meterPower(.control,now:now)
        return VStack(alignment:.leading,spacing:5) {
            Group {
                if let share, let home, let control, home+control>0 {
                    if waterTheme == "native" {
                        GeometryReader { p in
                            HStack(spacing:2) {
                                Capsule().fill(homePowerColor).frame(width:max(0,(p.size.width-2)*share))
                                Capsule().fill(controlPowerColor).frame(width:max(0,(p.size.width-2)*(1-share)))
                            }.frame(height:7).frame(maxHeight:.infinity,alignment:.bottom)
                        }
                    } else { PowerWater(share:share,character:waterTheme,animated:animatePower && !reduceMotion,interactive:interactiveWater,weather:snapshot.duckWeather,timezone:snapshot.timezone) }
                } else {
                    VStack { Spacer(); Capsule().fill(.white.opacity(0.08)).frame(height:5) }
                }
            }.frame(height:size == .medium ? 40:37).anchorPreference(key:WaterSurfaceAnchor.self,value:.bounds){$0}
            HStack(spacing:compact ? 4:12) {meterLegend(.home);Spacer(minLength:0);meterLegend(.control)}
        }.help(waterTheme == "native" ? "两户当前功率占比":"两户当前功率占比；角色标记住宅占比，右侧为中控室")
    }
    var smallContent: some View {
        VStack(alignment:.leading,spacing:0) {
            Spacer(minLength:2)
            HStack(alignment:.lastTextBaseline,spacing:6) {
                HStack(alignment:.firstTextBaseline,spacing:2) {
                    Text(powerNumber).font(.system(size:powerAvailable ? 34:18,weight:.light,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    if powerAvailable { Text("W").font(.system(size:9)).foregroundStyle(ice.opacity(0.8)) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.trailing,spacing:3) {
                    Text("今日").font(.system(size:7)).foregroundStyle(ice.opacity(0.6))
                    Text(number(1)+" 度").foregroundStyle(ice)
                    Text("¥"+number(2)).foregroundStyle(yellow.opacity(0.9))
                }.font(.system(size:9,weight:.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).frame(width:40,alignment:.trailing)
            }
            Spacer(minLength:2)
            meterBars
        }
    }
    var mediumContent: some View {
        VStack(spacing:3) {
            HStack(alignment:.center,spacing:12) {
                power.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.trailing,spacing:4) {
                    Text("今日 "+number(1)+" 度")
                    Text("电费估算 ¥"+number(2)).foregroundStyle(yellow)
                }.font(.system(size:10,weight:.medium)).lineLimit(1)
            }.frame(height:36)
            meterBars
            HStack {Text("本月 "+number(3)+" 度");Spacer();Text("估算 ¥"+number(4))}
                .font(.system(size:9)).foregroundStyle(ice.opacity(0.8)).lineLimit(1)
        }
    }
    var largeContent: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(alignment:.center,spacing:14) {
                VStack(alignment:.leading,spacing:2) {
                    HStack(alignment:.firstTextBaseline,spacing:4) {
                        Image(systemName:"bolt.fill").font(.system(size:19)).foregroundStyle(yellow)
                        Text(powerNumber).font(.system(size:powerAvailable ? 34:18,weight:.light,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                        if powerAvailable { Text("W").font(.system(size:11,weight:.semibold)).foregroundStyle(ice) }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.trailing,spacing:4) {
                    Text("今日 "+number(1)+" 度")
                    Text("估算 ¥"+number(2)).foregroundStyle(yellow)
                }.font(.system(size:10,weight:.medium))
            }
            meterBars
            HStack(spacing:14) {
                inline("本月用电",number(3)+" 度",color:.white)
                Rectangle().fill(.white.opacity(0.15)).frame(width:0.7,height:16)
                inline("本月电费估算","¥"+number(4),color:.white)
            }.padding(.vertical,2)
            Rectangle().fill(.white.opacity(0.19)).frame(height:0.7)
            garageSection
            HStack(spacing:8) {
                environmentStat("室内温度",extra(.temperature),"°C")
                environmentStat("室内湿度",extra(.humidity),"%")
                environmentStat("净化器 PM2.5",extra(.pm25),"μg/m³")
            }
            nasSection

        }
    }
    var garageSection:some View {
        Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:4) {
            GridRow {
                Text("车库合计").font(.system(size:10,weight:.semibold)).foregroundStyle(ice)
                Text("用电 / 度").frame(maxWidth:.infinity,alignment:.trailing)
                Text("电费估算 / 元").frame(maxWidth:.infinity,alignment:.trailing)
            }.font(.system(size:9)).foregroundStyle(ice.opacity(0.8))
            garageRow("今日",.garageEnergyToday,.garageCostToday)
            garageRow("本月",.garageEnergyMonth,.garageCostMonth)
        }.frame(maxWidth:.infinity)
    }
    func garageRow(_ title:String,_ energy:ExtraMetric,_ cost:ExtraMetric)->some View {
        GridRow {
            Text(title).font(.system(size:10)).foregroundStyle(ice.opacity(0.8))
            Text(extra(energy)).frame(maxWidth:.infinity,alignment:.trailing)
            Text("¥"+extra(cost)).frame(maxWidth:.infinity,alignment:.trailing)
        }.font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
    }
    func environmentStat(_ title:String,_ value:String,_ unit:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(size:9)).foregroundStyle(ice.opacity(0.8)).lineLimit(1)
            HStack(alignment:.firstTextBaseline,spacing:2) {
                Text(value).font(.system(size:17,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.system(size:8)).foregroundStyle(ice)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
        .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    var nasSection:some View {
        HStack(spacing:13) {
            VStack(alignment:.leading,spacing:3) {
                Text("NAS").font(.system(size:11,weight:.semibold))
                Text("DS1525+").font(.system(size:8)).foregroundStyle(ice.opacity(0.7))
            }.frame(width:43,alignment:.leading)
            nasMetric("CPU",.nasCPU)
            nasMetric("内存",.nasMemory)
        }.padding(.horizontal,9).padding(.vertical,7)
        .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    func nasMetric(_ label:String,_ metric:ExtraMetric)->some View {
        VStack(spacing:5) {
            HStack(alignment:.firstTextBaseline,spacing:3) {
                Text(label).font(.system(size:9)).foregroundStyle(ice.opacity(0.8))
                Spacer(minLength:2)
                Text(extra(metric)+"%").font(.system(size:11,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.1))
                if let value=snapshot.extraValue(metric,now:now) {
                    Capsule().fill(ice.opacity(0.8)).frame(width:proxy.size.width*min(max(value,0),100)/100)
                }
            }.frame(height:3)
        }.frame(maxWidth:.infinity)
    }
    func caption(_ text: String) -> some View { Text(text).font(.system(size:compact ? 8 : 10,weight:.medium)).foregroundStyle(ice.opacity(0.8)) }
    func inline(_ title: String,_ value: String,color:Color) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:5) {
            caption(title)
            Spacer(minLength:1)
            Text(value).font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth:.infinity)
    }
    func tile(_ title:String,_ value:String,unit:String,color:Color) -> some View {
        VStack(alignment:.leading,spacing:6) {
            caption(title)
            HStack(alignment:.firstTextBaseline,spacing:3) {
                Text(value).font(.system(size:22,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                if !unit.isEmpty { Text(unit).font(.system(size:10,weight:.medium)) }
            }.foregroundStyle(color)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
        .background(LinearGradient(colors:[ice.opacity(0.14),.white.opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:19))
        .overlay(RoundedRectangle(cornerRadius:19).stroke(.white.opacity(0.2),lineWidth:0.7))
    }
}
