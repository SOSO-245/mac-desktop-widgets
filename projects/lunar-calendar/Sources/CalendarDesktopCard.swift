import AppKit
import SwiftUI
import Charts

/// Native vector animation avoids a web view per card and remains animated when the card is inactive.
struct AnimatedCalendarWeather:View {
    let icon:String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:reduceMotion)){ timeline in
            Canvas {context,size in
                let t=reduceMotion ? 0:timeline.date.timeIntervalSinceReferenceDate
                let sx=size.width/64,sy=size.height/64
                context.scaleBy(x:sx,y:sy)
                func symbol(_ name:String,_ rect:CGRect,_ color:Color,_ opacity:Double=1){
                    var c=context;c.opacity=opacity
                    var img=c.resolve(Image(systemName:name));img.shading = .color(color);c.draw(img,in:rect)
                }
                let cloud=Color(red:0.86,green:0.92,blue:0.99)
                let cyan=Color(red:0.40,green:0.80,blue:0.95)
                let sunny=icon.contains("day"),night=icon.contains("night")
                let clear=icon.hasPrefix("clear")
                if sunny {
                    let center=CGPoint(x:clear ? 32:22,y:clear ? 30:23)
                    var rays=Path()
                    for i in 0..<8 {let angle=Double(i)*Double.pi/4+(reduceMotion ? 0:t*0.45);rays.move(to:CGPoint(x:center.x+cos(angle)*17,y:center.y+sin(angle)*17));rays.addLine(to:CGPoint(x:center.x+cos(angle)*23,y:center.y+sin(angle)*23))}
                    context.stroke(rays,with:.color(.yellow),style:StrokeStyle(lineWidth:2.6,lineCap:.round))
                    context.fill(Path(ellipseIn:CGRect(x:center.x-11,y:center.y-11,width:22,height:22)),with:.color(.yellow))
                }
                if night {
                    let dy=reduceMotion ? 0:sin(t*1.5)*2.5
                    symbol("moon.fill",CGRect(x:clear ? 16:8,y:clear ? 15+dy:8+dy,width:clear ? 34:28,height:clear ? 35:29),cyan)
                    for i in 0..<3 {let opacity=reduceMotion ? 0.8:0.35+0.65*(sin(t*2+Double(i)*1.8)+1)/2;symbol("sparkle",CGRect(x:40+Double(i%2)*10,y:9+Double(i)*12,width:6,height:6),.white,opacity)}
                }
                if !clear && icon != "wind" {
                    let shift=reduceMotion ? 0:sin(t*1.5)*3.5
                    if icon=="cloudy" {symbol("cloud.fill",CGRect(x:7-shift,y:14,width:36,height:24),cloud.opacity(0.55))}
                    symbol("cloud.fill",CGRect(x:10+shift,y:sunny || night ? 27:20,width:46,height:28),cloud)
                }
                if icon=="rain" || icon=="snow" {
                    for i in 0..<3 {
                        let phase=reduceMotion ? 0.4:(t*0.7+Double(i)*0.31).truncatingRemainder(dividingBy:1)
                        let y=41+phase*17;let x=19+Double(i)*13+(icon=="snow" ? sin(t*2+Double(i))*2:0)
                        let alpha=reduceMotion ? 1:min(1,(1-phase)*2)
                        symbol(icon=="rain" ? "drop.fill":"snowflake",CGRect(x:x,y:y,width:icon=="rain" ? 4:7,height:icon=="rain" ? 8:7),cyan,alpha)
                    }
                }
                if icon=="thunderstorms" {symbol("bolt.fill",CGRect(x:29,y:40,width:13,height:21),.yellow,reduceMotion ? 1:0.55+0.45*(sin(t*2.4)+1)/2)}
                if icon=="fog" || icon=="wind" {
                    for i in 0..<3 {
                        let shift=reduceMotion ? 0:sin(t*1.5+Double(i))*5
                        let y=Double(icon=="fog" ? 44:22)+Double(i)*7
                        var p=Path();p.move(to:CGPoint(x:10+shift,y:y));p.addLine(to:CGPoint(x:53+shift-Double(i)*4,y:y));context.stroke(p,with:.color(cyan.opacity(0.85)),style:StrokeStyle(lineWidth:2.5,lineCap:.round))
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}
struct DesktopDatePopover:View {
    @ObservedObject var model:CalendarModel
    let close:()->Void
    @State private var choosingMonth=false
    var body:some View {
        Group {
            if choosingMonth {
                MonthChooser(selected:model.selected,action:{model.select($0);choosingMonth=false},close:{choosingMonth=false})
            } else {
                CalendarCard(selected:model.selected,now:Date(),holidays:model.holidays,size:.large,action:model.select,openDatePicker:{choosingMonth=true})
                    .frame(width:344,height:344).background(CalendarBackground())
            }
        }.environment(\.calendarData,model.data).preferredColorScheme(.dark)
            .task(id:Almanac.year(model.selected)) {await model.update()}
    }
}
struct CalendarWeatherCard:View {
    @AppStorage("calendarWeather.fullCardEffects") private var fullCardEffects=true
    @AppStorage("calendarWeather.effectIntensity") private var effectIntensity=0.65
    @ObservedObject var model:CalendarModel
    @ObservedObject var weather:CalendarWeatherStore
    let controls:AnyView
    let settings:()->Void
    @State private var showingCalendar=false
    @State private var showingForecast=false
    @State private var showingBirthdays=false
    @AppStorage("calendarWeather.trendRange") private var trendIndex=0
    @AppStorage("calendarWeather.clock12Hour") private var clock12Hour=false
    private var range:WeatherTrendRange {WeatherTrendRange(rawValue:trendIndex) ?? .day}
    private var day:Date {model.selected}
    private var birthdayReminders:[BirthdayReminder] {BirthdayReminder.upcoming(model.data.birthdays,now:Date())}
    private func value(_ v:Double?,_ unit:String)->String {v.map{String(format:"%.0f",$0)+unit} ?? "—"}
    var body:some View {
        let reminders=birthdayReminders
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:2) {
                Button {showingCalendar=true} label:{HStack(spacing:3) {Text(Almanac.monthTitle(day));Image(systemName:"chevron.down").font(.system(size:8))}.font(.system(size:12,weight:.semibold))}
                    .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("打开万年历").popover(isPresented:$showingCalendar,arrowEdge:.bottom) {DesktopDatePopover(model:model,close:{showingCalendar=false})}
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text("\(Almanac.day(day))").font(.system(size:reminders.isEmpty ? 52:46,weight:.semibold)).monospacedDigit()
                    Text(Almanac.weekday(day).replacingOccurrences(of:"星期",with:"周")).font(.system(size:12)).foregroundStyle(muted)
                }
                HStack(spacing:6) {
                    Text(Almanac.lunar(day)).font(.system(size:14,weight:.semibold)).foregroundStyle(jade)
                    if Almanac.festival(day) != nil {annotatedDateText(day,short:true).font(.system(size:10,weight:.medium))}
                }.lineLimit(1).minimumScaleFactor(0.7).help(Almanac.dayLabels(day).joined(separator:" · "))
                if let reminder=reminders.first {
                    Button {showingBirthdays=true} label:{
                        HStack(spacing:3) {Image(systemName:"gift.fill").foregroundStyle(holidayPink);Text(reminder.title).lineLimit(1);if reminders.count>1 {Text("+\(reminders.count-1)").foregroundStyle(muted)}}
                            .font(.system(size:9,weight:.medium)).foregroundStyle(holidayPink).frame(maxWidth:.infinity,alignment:.leading)
                    }.buttonStyle(.plain).focusEffectDisabled().help(reminders.map(\.title).joined(separator:"；"))
                     .popover(isPresented:$showingBirthdays,arrowEdge:.bottom) {BirthdayReminderPopover(reminders:reminders)}
                }
                Spacer(minLength:0)
                TimelineView(.periodic(from:.now,by:1)) {context in
                    Button {clock12Hour.toggle()} label:{
                        Text(clock(context.date)).font(.system(size:clock12Hour ? 18:(reminders.isEmpty ? 24:22),weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).focusEffectDisabled().foregroundStyle(.white)
                     .help("点击切换12／24小时制 · 北京时间").accessibilityLabel("当前时间，点击切换12或24小时制")
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Rectangle().fill(.white.opacity(0.15)).frame(width:0.5)
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:5) {
                    Button(action:settings) {Text(weather.location).font(.system(size:10,weight:.semibold)).lineLimit(1)}.buttonStyle(.plain).help("天气来源与区县")
                    Spacer(minLength:0);controls
                }
                HStack(spacing:5) {
                    Button {showingForecast=true} label:{
                        Group {
                            if let reading=weather.reading {AnimatedCalendarWeather(icon:reading.icon).allowsHitTesting(false).accessibilityHidden(true)}
                            else {Image(systemName:"cloud").font(.system(size:26)).foregroundStyle(muted)}
                        }.frame(width:44,height:46).contentShape(Rectangle())
                    }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("查看未来七天天气预报")
                     .popover(isPresented:$showingForecast,arrowEdge:.bottom) {CalendarForecastPopover(weather:weather,settings:{showingForecast=false;settings()})}
                    VStack(alignment:.leading,spacing:3) {
                        HStack(alignment:.firstTextBaseline,spacing:6) {
                            Text(value(weather.reading?.temperature,"°")).font(.system(size:25,weight:.medium)).monospacedDigit()
                            Label(value(weather.reading?.humidity,"%"),systemImage:"humidity").font(.system(size:10,weight:.medium)).foregroundStyle(jade)
                        }.lineLimit(1).minimumScaleFactor(0.7)
                        Text((weather.reading?.condition ?? "等待天气")+" · PM2.5 "+value(weather.reading?.pm25,"")).font(.system(size:8)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                temperatureChart
                Spacer(minLength:0)
                Text(weather.note.isEmpty ? "当前天气 · PM2.5 μg/m³" : weather.reading == nil ? "点击设置区县或定位":"当前天气 · 更新延迟")
                    .font(.system(size:7)).foregroundStyle(muted).lineLimit(1).help(weather.note)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(15).frame(width:344,height:164).foregroundStyle(.white).fontDesign(.rounded)
            .background {
                if fullCardEffects {WeatherAtmosphere(scene:WeatherScene.resolve(weather.reading),intensity:effectIntensity)}
            }
    }
    private var temperatureChart:some View {
        let points=weather.trend?.samples(range) ?? []
        let low=points.map(\.temperature).min() ?? 0,high=points.map(\.temperature).max() ?? 1
        return Button {
            if weather.source == .home {settings()}
            else {trendIndex=range.next.rawValue}
        } label:{
            VStack(alignment:.leading,spacing:2) {
                HStack(spacing:3) {
                    Text(range.title).font(.system(size:8,weight:.medium))
                    Image(systemName:"arrow.triangle.2.circlepath").font(.system(size:7))
                    Spacer(minLength:1)
                    if !points.isEmpty {Text("\(Int(low.rounded()))–\(Int(high.rounded()))°").font(.system(size:8)).monospacedDigit()}
                }.foregroundStyle(muted)
                if points.count>1 {
                    Chart(points) {point in
                        AreaMark(x:.value("时间",Date(timeIntervalSince1970:point.time)),yStart:.value("下限",low-1),yEnd:.value("温度",point.temperature))
                            .interpolationMethod(.monotone).foregroundStyle(LinearGradient(colors:[jade.opacity(0.25),jade.opacity(0.02)],startPoint:.top,endPoint:.bottom))
                        LineMark(x:.value("时间",Date(timeIntervalSince1970:point.time)),y:.value("温度",point.temperature))
                            .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth:1.5,lineCap:.round)).foregroundStyle(jade)
                    }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain:(low-1)...(high+1)).frame(height:34)
                } else {
                    Text(weather.source == .home ? "选择区县或定位查看曲线":"暂无温度曲线").font(.system(size:8)).foregroundStyle(muted).frame(maxWidth:.infinity,minHeight:34,alignment:.leading)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("\(range.title)温度曲线，点击切换时间范围")
        .help("点击切换未来24小时、过去一周、未来一周。数据为所选区县的天气模型；未来数据为预报。")
    }
    private func clock(_ date:Date)->String {
        let format=DateFormatter();format.locale=Locale(identifier:"zh_CN");format.timeZone=TimeZone(identifier:"Asia/Shanghai");format.dateFormat=clock12Hour ? "a h:mm:ss":"HH:mm:ss";return format.string(from:date)
    }
}
struct CalendarDesktopContent:View {
    @ObservedObject var model:CalendarModel
    @ObservedObject var weather:CalendarWeatherStore
    let size:CalendarSize
    let weatherLayout:Bool
    let controls:AnyView
    let settings:()->Void
    @State private var choosingMonth=false
    var body:some View {
        Group {
            if size == .medium && weatherLayout {CalendarWeatherCard(model:model,weather:weather,controls:controls,settings:settings)}
            else {
                CalendarCard(selected:model.selected,now:Date(),holidays:model.holidays,size:size,action:model.select,openDatePicker:{choosingMonth=true},desktopControls:controls)
                    .frame(width:size == .small ? 164:344,height:size == .large ? 344:164)
                    .popover(isPresented:$choosingMonth) {MonthChooser(selected:model.selected,action:model.select,close:{choosingMonth=false})}
            }
        }.environment(\.calendarData,model.data).preferredColorScheme(.dark)
            .task(id:Almanac.year(model.selected)) {await model.update()}
    }
}
struct BirthdayReminderPopover:View {
    let reminders:[BirthdayReminder]
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("生日提醒",systemImage:"gift.fill").font(.system(size:16,weight:.semibold)).foregroundStyle(holidayPink)
            ScrollView {VStack(alignment:.leading,spacing:13) {ForEach(reminders) {reminder in
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:4) {Text(reminder.birthday.name).font(.system(size:13,weight:.medium));Text(reminder.birthday.dateLabel).font(.system(size:10)).foregroundStyle(muted)}
                    Spacer();Text(reminder.timing).font(.system(size:11,weight:.medium)).foregroundStyle(jade)
                }
            }}}.frame(height:min(240,CGFloat(reminders.count)*48))
            Text("生日提前3天起显示，按北京时间计算。").font(.system(size:10)).foregroundStyle(muted)
        }.padding(18).frame(width:300).foregroundStyle(.white).background(CalendarBackground()).preferredColorScheme(.dark)
    }
}
struct CalendarForecastPopover:View {
    @ObservedObject var weather:CalendarWeatherStore
    let settings:()->Void
    private func date(_ seconds:Double)->String {
        let f=DateFormatter();f.locale=Locale(identifier:"zh_CN");f.timeZone=TimeZone(identifier:weather.trend?.timezone ?? "UTC");f.dateFormat="M/d EEE";return f.string(from:Date(timeIntervalSince1970:seconds))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text(weather.location).font(.system(size:16,weight:.semibold));Spacer();Text("未来七天").font(.system(size:12)).foregroundStyle(muted)}
            if let trend=weather.trend,!trend.days.isEmpty,Date().timeIntervalSince(trend.loadedAt)<10800 {
                ForEach(trend.days) {day in
                    let presentation=CalendarWeatherReading.presentation(day.code,day:true)
                    HStack(spacing:9) {
                        Text(date(day.time)).font(.system(size:11)).frame(width:76,alignment:.leading)
                        Image(systemName:presentation.0).symbolRenderingMode(.multicolor).font(.system(size:19)).frame(width:25)
                        Text(presentation.1).font(.system(size:11)).frame(width:25,alignment:.leading)
                        Spacer(minLength:0)
                        Text(day.rainProbability.map{String(format:"%.0f%%",$0)} ?? "—").font(.system(size:10)).foregroundStyle(.cyan).frame(width:28,alignment:.trailing)
                        HStack(spacing:5) {Text(String(format:"%.0f°",day.minimum)).foregroundStyle(muted);Text(String(format:"%.0f°",day.maximum))}.font(.system(size:12,weight:.medium)).monospacedDigit().frame(width:66,alignment:.trailing)
                    }.frame(height:30)
                }
                Text("蓝色百分比为降雨概率 · 气温为最低／最高").font(.system(size:9)).foregroundStyle(muted)
            } else {
                Text(weather.source == .home ? "选择区县或系统定位后查看预报":"预报暂未更新，请稍后刷新").font(.system(size:12)).foregroundStyle(muted).padding(.vertical,16)
                Button("天气地点设置",action:settings).buttonStyle(.borderless)
            }
            Text("Open-Meteo · 天气预报").font(.system(size:9)).foregroundStyle(muted)
        }.padding(18).frame(width:344).foregroundStyle(.white).background(CalendarBackground()).preferredColorScheme(.dark)
    }
}
struct CalendarWeatherSettings:View {
    @ObservedObject var weather:CalendarWeatherStore
    @AppStorage("calendarWeather.fullCardEffects") private var fullCardEffects=true
    @AppStorage("calendarWeather.effectIntensity") private var effectIntensity=0.65
    @State private var effectPreview=WeatherScene.rain
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("天气来源与区县").font(.title2.bold())
            Toggle("整张天气卡片动态效果",isOn:$fullCardEffects)
            HStack {Text("效果浓度");Slider(value:$effectIntensity,in:0.2...1);Text("\(Int(effectIntensity*100))%").monospacedDigit().frame(width:40)}
            DisclosureGroup("预览特殊天气效果") {
                Picker("演示天气",selection:$effectPreview) {ForEach(WeatherScene.allCases.filter{$0 != .none}) {scene in Text(scene.title).tag(scene)}}
                ZStack {
                    Color(red:0.05,green:0.12,blue:0.2)
                    WeatherAtmosphere(scene:effectPreview,intensity:effectIntensity)
                    VStack {Text(effectPreview.title+" · 效果演示").font(.headline);Text("不改变当前天气").font(.caption).foregroundStyle(.secondary)}
                }.frame(height:120).clipShape(RoundedRectangle(cornerRadius:22))
            }
            Text("随当前天气自动切换；低温可显示薄霜装饰，不代表霜冻预警。台风、沙尘须来源明确标识，当前来源未提供时仅可预览。尊重系统减少动态效果设置。").font(.caption).foregroundStyle(.secondary)
            Picker("来源",selection:Binding(get:{weather.source},set:weather.setSource)) {Text("家庭概览天气").tag(CalendarWeatherStore.Source.home);Text("指定区县").tag(CalendarWeatherStore.Source.city);Text("系统定位").tag(CalendarWeatherStore.Source.location)}.pickerStyle(.segmented)
            if weather.source == .home {
                Text("读取本机家庭概览的室外天气、湿度和 PM2.5。请保持家庭概览运行；不需要填写家庭连接或令牌。").font(.callout).foregroundStyle(.secondary)
            } else if weather.source == .location {
                Button(weather.locating ? "正在定位…":"使用当前位置",action:weather.useCurrentLocation).disabled(weather.locating)
                if let city=weather.locatedCity {Label(city.label,systemImage:"location.fill").foregroundStyle(.mint)}
                Text("首次使用会申请系统定位权限。只查询区县附近的天气，不持续跟踪或保存精确坐标。定位天气约每 15 分钟更新位置。").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {TextField("搜索城市或区县，如北京市朝阳区",text:$weather.query).onSubmit {Task {await weather.search()}};Button(weather.searching ? "搜索中…":"搜索") {Task {await weather.search()}}.disabled(weather.searching)}
                if let city=weather.city {Label("当前："+city.label,systemImage:"mappin.circle.fill").font(.caption).foregroundStyle(.mint)}
                if !weather.searchNote.isEmpty {Text(weather.searchNote).font(.caption).foregroundStyle(.secondary)}
                ScrollView {VStack(alignment:.leading,spacing:4) {ForEach(weather.results) {city in
                    Button {weather.choose(city)} label:{HStack {Text(city.label);Spacer();Image(systemName:weather.city?.id==city.id ? "checkmark.circle.fill":"plus.circle")}.padding(9).contentShape(Rectangle())}.buttonStyle(.plain)
                }}}.frame(height:160)
            }
            Text("日期切换仅浏览日历；天气始终为所选地点当前数据。区县天气约每 15 分钟更新，家庭天气每分钟读取。").font(.caption).foregroundStyle(.secondary)
            if !weather.note.isEmpty {Text(weather.note).font(.caption).foregroundStyle(.secondary)}
            HStack {Button("立即更新") {Task {await weather.refresh(force:true)}}.disabled(weather.busy);Spacer();Link("Open-Meteo · CAMS",destination:URL(string:"https://open-meteo.com/en/docs/air-quality-api")!)}
            Text("区县定位使用附近天气网格，并非街道实测；PM2.5 单位 μg/m³。动态图标：Meteocons（MIT）。").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
