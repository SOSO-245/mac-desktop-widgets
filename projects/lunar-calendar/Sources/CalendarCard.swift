import SwiftUI
#if WIDGET_EXTENSION
import AppIntents
#endif

private struct CalendarDataKey:EnvironmentKey {static let defaultValue=CalendarUserData()}
extension EnvironmentValues {var calendarData:CalendarUserData {get{self[CalendarDataKey.self]}set{self[CalendarDataKey.self]=newValue}}}
extension Color {
    init(calendarHex:String) {
        let raw=calendarHex.trimmingCharacters(in:CharacterSet(charactersIn:"#"))
        let value=UInt64(raw,radix:16) ?? 0x1B203B
        self.init(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
}
func solarTermColor(_ date:Date,chosen:Bool=false)->Color {
    let month=Almanac.gregorian.component(.month,from:date)
    let colors:([String],[String])=(["#7BD7FF","#75F5CA","#FF87AB","#FFD381"],["#145575","#14624C","#8A244C","#78520D"])
    let season=(month==12 || month<=1) ? 0 : month<=4 ? 1 : month<=7 ? 2 : month<=10 ? 3 : 0
    return Color(calendarHex:(chosen ? colors.1 : colors.0)[season])
}
func annotatedDateText(_ date:Date,short:Bool=true,chosen:Bool=false,opacity:Double=1)->Text {
    let labels=Almanac.dayLabels(date)
    if labels.isEmpty {return Text(Almanac.lunar(date,short:short))}
    var result=Text("")
    for (index,label) in labels.enumerated() {
        let color:Color
        if label==SolarTerms.name(on:date) {color=solarTermColor(date,chosen:chosen)}
        else if Almanac.isInternationalFestival(label) {color = .accentColor}
        else {color = chosen ? Color(calendarHex:"#8A244C") : holidayPink}
        let part=Text(short ? Almanac.shortDayLabel(label) : label).foregroundColor(color.opacity(opacity))
        result=Text("\(result)\(Text(index==0 ? "" : "·"))\(part)")
    }
    return result
}
enum CalendarSize:String,CaseIterable { case small,medium,large }
let jade=Color(red:0.46,green:0.96,blue:0.79)
let muted=Color(red:0.66,green:0.75,blue:0.82)
let holidayGreen=Color(red:0.40,green:0.96,blue:0.62)
let workRed=Color(red:1,green:0.36,blue:0.40)
let holidayPink=Color(red:1,green:0.53,blue:0.67)
struct CalendarBackground:View {
    @Environment(\.calendarData) var data
    var body:some View {
        ZStack {
            LinearGradient(colors:[Color(calendarHex:data.theme.start).opacity(0.97),Color(calendarHex:data.theme.end).opacity(0.97)],startPoint:.topLeading,endPoint:.bottomTrailing)
            RadialGradient(colors:[Color(calendarHex:data.theme.glow).opacity(0.14),.clear],center:.topLeading,startRadius:0,endRadius:300)
            RoundedRectangle(cornerRadius:23).strokeBorder(.white.opacity(0.17),lineWidth:0.8)
        }
    }
}
struct DateAction<Content:View>:View {
    let key:String
    let label:String
    let action:(String)->Void
    @ViewBuilder var content:()->Content
    var body:some View {
#if WIDGET_EXTENSION
        Button(intent:SelectCalendarDateIntent(key:key)) { content() }.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(label)
#else
        Button { action(key) } label:{content()}.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel(label)
#endif
    }
}
struct CalendarCard:View {
    @Environment(\.calendarData) var data
    let selected:Date
    let now:Date
    let holidays:HolidaySnapshot
    let size:CalendarSize
    var action:(String)->Void = {_ in}
    var openDatePicker:(()->Void)? = nil
    var desktopControls:AnyView? = nil
    var body:some View {
        Group {
            switch size {
            case .small:small
            case .medium:medium
            case .large:large
            }
        }.padding(size == .small ? 13 : 15)
        .foregroundStyle(.white).fontDesign(.rounded)
        .environment(\.locale,Locale(identifier:"zh_CN"))
    }
    var isToday:Bool { Almanac.key(selected)==Almanac.key(now) }
    var badge:some View {
        let reminders=BirthdayReminder.upcoming(data.birthdays,now:now)
        let birthday=data.birthdays.first{$0.occurs(on:selected)}
        let count=data.schedules.filter{$0.occurs(on:selected)}.count
        let text:Text = reminders.first.map {Text("🎁 "+$0.title+(reminders.count>1 ? "（另\(reminders.count-1)位）":""))} ?? birthday.map{Text("生日 · "+$0.name)} ?? (count>0 ? Text("\(count)项日程") : Almanac.festival(selected) != nil ? annotatedDateText(selected,short:false) : Text(holidays.status(selected)))
        return text.font(.system(size:10,weight:.medium))
            .foregroundStyle(holidays.day(selected)?.isOffDay == true ? holidayGreen : holidays.day(selected)?.isOffDay == false ? workRed : jade)
            .lineLimit(1).minimumScaleFactor(0.75).help(reminders.map(\.title).joined(separator:"；"))
    }
    var small:some View {
        VStack(alignment:.leading,spacing:3) {
            HStack { if desktopControls == nil {Image(systemName:"moonphase.waxing.crescent").foregroundStyle(jade)};Text(Almanac.monthTitle(selected)).font(.system(size:desktopControls == nil ? 11:10,weight:.semibold));Spacer(minLength:0);if let desktopControls {desktopControls} }
            HStack(alignment:.firstTextBaseline,spacing:7) {
                Text("\(Almanac.day(selected))").font(.system(size:48,weight:.semibold)).monospacedDigit()
                VStack(alignment:.leading,spacing:4) { Text(Almanac.weekday(selected)).font(.system(size:10));Text(isToday ? "今天" : "查看").font(.system(size:9)).foregroundStyle(jade) }
            }
            Text(Almanac.lunar(selected)).font(.system(size:14,weight:.semibold)).foregroundStyle(jade)
            badge
            Spacer(minLength:0)
            navigation(months:false)
        }
    }
    var medium:some View {
        HStack(spacing:9) {
            VStack(alignment:.leading,spacing:4) {
                Text(Almanac.monthTitle(selected)).font(.system(size:11,weight:.semibold))
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text("\(Almanac.day(selected))").font(.system(size:38,weight:.semibold)).monospacedDigit()
                    Text(Almanac.weekday(selected).replacingOccurrences(of:"星期",with:"周")).font(.system(size:11)).foregroundStyle(muted)
                }
                Text(Almanac.lunar(selected)).font(.system(size:12,weight:.semibold)).foregroundStyle(jade)
                badge
                Spacer(minLength:0)
            }.frame(width:84,alignment:.leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width:0.5)
            VStack(spacing:5) {
                HStack {navigation(months:true);if let desktopControls {desktopControls}}
                MonthGrid(selected:selected,now:now,holidays:holidays,compact:true,action:action)
            }
        }
    }
    var large:some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Image(systemName:"moonphase.waxing.crescent").foregroundStyle(jade)
                Text("万年历").font(.system(size:14,weight:.semibold));Spacer()
                if let desktopControls {desktopControls} else {Text(isToday ? "今天" : "日期浏览").font(.system(size:10)).foregroundStyle(muted)}
            }
            HStack(alignment:.center,spacing:10) {
                Text("\(Almanac.day(selected))").font(.system(size:42,weight:.semibold)).monospacedDigit().frame(width:56,alignment:.leading)
                VStack(alignment:.leading,spacing:3) {
                    Text(Almanac.lunar(selected)).font(.system(size:16,weight:.semibold)).foregroundStyle(jade)
                    Text(Almanac.zodiac(selected)).font(.system(size:10)).foregroundStyle(muted)
                }
                Spacer();badge
            }.frame(height:46)
            HStack {
                if let openDatePicker {
                    Button(action:openDatePicker) {HStack(spacing:4) {Text(Almanac.monthTitle(selected));Image(systemName:"chevron.down").font(.system(size:9))}.frame(height:24).contentShape(Rectangle())}.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("快速切换年月")
                } else {Text(Almanac.monthTitle(selected))}
                Spacer();navigation(months:true).frame(width:116)
            }.font(.system(size:13,weight:.semibold))
            MonthGrid(selected:selected,now:now,holidays:holidays,compact:false,action:action)
                .padding(6).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.09),lineWidth:0.5))
            Spacer(minLength:0)
            HStack(spacing:5) {
                Circle().fill(holidayGreen).frame(width:4,height:4);Text("放假").foregroundStyle(muted)
                Circle().fill(workRed).frame(width:4,height:4).padding(.leading,6);Text("补班").foregroundStyle(muted)
                Spacer();Text(holidays.years[Almanac.year(selected)] == nil ? "本年假期待更新" : "中国大陆 · 北京时间").foregroundStyle(muted)
            }.font(.system(size:9))
        }
    }
    func navigation(months:Bool)->some View {
        HStack(spacing:5) {
            DateAction(key:Almanac.key(Almanac.moved(selected,days:months ? 0 : -1,months:months ? -1 : 0)),label:months ? "上个月" : "前一天",action:action) {
                Image(systemName:"chevron.left").frame(width:22,height:20).contentShape(Rectangle())
            }
            Spacer(minLength:0)
            DateAction(key:"today",label:"回到今天",action:action) {Text("今天").font(.system(size:10,weight:.medium)).frame(height:20)}
            Spacer(minLength:0)
            DateAction(key:Almanac.key(Almanac.moved(selected,days:months ? 0 : 1,months:months ? 1 : 0)),label:months ? "下个月" : "后一天",action:action) {
                Image(systemName:"chevron.right").frame(width:22,height:20).contentShape(Rectangle())
            }
        }.font(.system(size:10,weight:.semibold)).foregroundStyle(jade)
    }
}
struct MonthGrid:View {
    @Environment(\.calendarData) var data
    let selected:Date;let now:Date;let holidays:HolidaySnapshot
    var compact=false
    var spacious=false
    var action:(String)->Void = {_ in}
    var body:some View {
        VStack(spacing:compact ? 2 : 4) {
            HStack(spacing:0) {ForEach(Array(["一","二","三","四","五","六","日"].enumerated()),id:\.offset) {i,s in Text(s).frame(maxWidth:.infinity).foregroundStyle(i>=5 ? holidayPink.opacity(0.8) : muted)}}.font(.system(size:compact ? 9 : 10))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:compact ? 1 : 3) {
                ForEach(Almanac.monthDays(selected),id:\.self) {date in cell(date)}
            }
        }
    }
    func cell(_ date:Date)->some View {
        let key=Almanac.key(date), chosen=key==Almanac.key(selected)
        let today=key==Almanac.key(now),sameMonth=Almanac.gregorian.component(.month,from:date)==Almanac.gregorian.component(.month,from:selected)
        let holiday=holidays.day(date)
        return DateAction(key:key,label:key+" "+Almanac.lunar(date)+" "+Almanac.dayLabels(date).joined(separator:" ")+" "+holidays.status(date),action:action) {
            VStack(spacing:1) {
                Text("\(Almanac.day(date))").font(.system(size:compact ? 12 : spacious ? 18 : 13,weight:chosen ? .bold : .medium))
                if !compact { annotatedDateText(date,chosen:chosen,opacity:sameMonth ? 1 : 0.35).font(.system(size:spacious ? 11 : 8)).lineLimit(1).minimumScaleFactor(0.6) }
            }
            .foregroundStyle(chosen ? Color(red:0.03,green:0.16,blue:0.14) : holiday?.isOffDay == true ? holidayGreen : .white.opacity(sameMonth ? 0.95 : 0.30))
            .frame(maxWidth:.infinity).frame(height:compact ? 15 : spacious ? 43 : 26)
            .background(chosen ? jade : .clear,in:RoundedRectangle(cornerRadius:compact ? 4 : 7))
            .overlay(RoundedRectangle(cornerRadius:compact ? 4 : 7).strokeBorder(today && !chosen ? jade : .clear,lineWidth:1))
            .overlay(alignment:.topTrailing) {
                if let holiday,sameMonth {Circle().fill(holiday.isOffDay ? holidayGreen : workRed).frame(width:compact ? 3 : 4,height:compact ? 3 : 4).overlay(Circle().stroke(.black.opacity(chosen ? 0.5 : 0),lineWidth:0.5)).padding(1)}
            }
            .overlay(alignment:.bottomTrailing) {
                if data.birthdays.contains(where:{$0.occurs(on:date)}) {Image(systemName:"gift.fill").font(.system(size:compact ? 5 : 7)).foregroundStyle(chosen ? .black : jade).padding(1)}
            }
            .overlay(alignment:.bottomLeading) {
                if data.schedules.contains(where:{$0.occurs(on:date)}) {Capsule().fill(Color(red:0.38,green:0.79,blue:1)).frame(width:compact ? 3 : 6,height:2).padding(2)}
            }
            .contentShape(Rectangle())
        }.help(Almanac.lunar(date)+" "+Almanac.dayLabels(date).joined(separator:" · ")).disabled(date<Almanac.minimum || date>Almanac.maximum)
    }
}
