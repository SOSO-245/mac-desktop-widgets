import Foundation

struct CalendarTheme:Codable,Equatable {
    var name="蓝紫玻璃"
    var start="#1B203B"
    var end="#0E1324"
    var glow="#A88FFF"
    static let presets:[CalendarTheme]=[
        CalendarTheme(),
        CalendarTheme(name:"翡翠夜色",start:"#092A30",end:"#211738",glow:"#75F5CA"),
        CalendarTheme(name:"深海蓝",start:"#102D49",end:"#10182E",glow:"#61C9FF"),
        CalendarTheme(name:"玫瑰紫",start:"#38223D",end:"#17172B",glow:"#FF87AB"),
        CalendarTheme(name:"石墨黑",start:"#25292F",end:"#111317",glow:"#AAB8CC")]
}
struct Birthday:Codable,Identifiable,Equatable {
    var id=UUID()
    var name:String
    var month:Int
    var day:Int
    var lunar:Bool
    var leap=false
    var contactID:String?
    var valid:Bool {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=80,(1...12).contains(month),(1...(lunar ? 30 : 31)).contains(day) else {return false}
        if !lunar {return day <= [31,29,31,30,31,30,31,31,30,31,30,31][month-1]}
        return true
    }
    func occurs(on date:Date)->Bool {
        if !lunar {
            return Almanac.gregorian.component(.month,from:date)==month && Almanac.day(date)==min(day,Almanac.gregorian.range(of:.day,in:.month,for:date)!.count)
        }
        let c=Almanac.lunarParts(date)
        guard c.month==month else {return false}
        var useLeap=false
        if leap {
            var parts=Almanac.chinese.dateComponents([.era,.year],from:date)
            parts.month=month;parts.day=1;parts.isLeapMonth=true
            if let candidate=Almanac.chinese.date(from:parts) {let p=Almanac.lunarParts(candidate);useLeap=p.month==month && p.leap}
        }
        return c.leap==useLeap && c.day==min(day,Almanac.chinese.range(of:.day,in:.month,for:date)!.count)
    }
    var dateLabel:String {lunar ? "农历"+(leap ? "闰" : "")+Almanac.lunarMonths[month-1]+Almanac.lunarDays[day-1] : "公历\(month)月\(day)日"}
}
struct ScheduleItem:Codable,Identifiable,Equatable {
    var id=UUID()
    var title:String
    var start:Date
    var end:Date
    var allDay=false
    var location=""
    var notes=""
    var reminderMinutes:Int?=nil
    var systemEventID:String?=nil
    var recurrence="none"
    static let repeatChoices=[("none","不重复"),("weekly","每周"),("monthly","每月"),("yearly","每年")]
    var recurrenceLabel:String {Self.repeatChoices.first{$0.0==recurrence}?.1 ?? "不重复"}
    var valid:Bool { !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && title.count<=200 && end>start && location.count<=500 && notes.count<=4000 }
    func occurs(on date:Date)->Bool {
        guard valid else {return false}
        let calendar=Almanac.gregorian
        let begin=calendar.startOfDay(for:date),finish=calendar.date(byAdding:.day,value:1,to:begin)!
        if start<finish && end>begin {return true}
        guard ["weekly","monthly","yearly"].contains(recurrence),finish>start else {return false}
        var components=calendar.dateComponents([.hour,.minute,.second],from:start)
        switch recurrence {
        case "weekly":components.weekday=calendar.component(.weekday,from:start)
        case "monthly":components.day=calendar.component(.day,from:start)
        default:components.month=calendar.component(.month,from:start);components.day=calendar.component(.day,from:start)
        }
        let duration=end.timeIntervalSince(start)
        // Strict matching skips non-existent month days, matching EventKit's recurrence.
        let lower=max(start.addingTimeInterval(-1),begin.addingTimeInterval(-duration))
        guard let occurrence=calendar.nextDate(after:lower,matching:components,matchingPolicy:.strict,repeatedTimePolicy:.first),occurrence>=start else {return false}
        return occurrence<finish && occurrence.addingTimeInterval(duration)>begin
    }
    var timeLabel:String {
        if allDay {return "全天"}
        let formatter=DateFormatter();formatter.timeZone=Almanac.zone;formatter.dateFormat="HH:mm"
        return formatter.string(from:start)+"–"+formatter.string(from:end)
    }
}
extension ScheduleItem {
    enum CodingKeys:String,CodingKey {case id,title,start,end,allDay,location,notes,reminderMinutes,systemEventID,recurrence}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(UUID.self,forKey:.id);title=try c.decode(String.self,forKey:.title)
        start=try c.decode(Date.self,forKey:.start);end=try c.decode(Date.self,forKey:.end)
        allDay=try c.decodeIfPresent(Bool.self,forKey:.allDay) ?? false
        location=try c.decodeIfPresent(String.self,forKey:.location) ?? ""
        notes=try c.decodeIfPresent(String.self,forKey:.notes) ?? ""
        reminderMinutes=try c.decodeIfPresent(Int.self,forKey:.reminderMinutes)
        systemEventID=try c.decodeIfPresent(String.self,forKey:.systemEventID)
        let rule=try c.decodeIfPresent(String.self,forKey:.recurrence) ?? "none"
        recurrence=Self.repeatChoices.contains{$0.0==rule} ? rule : "none"
    }
}
struct MenuIconPreferences:Codable,Equatable {
    var symbol="calendar"
    var mode="system"
    var color="#75F5CA"
    static let choices:[(symbol:String,title:String)]=[
        ("calendar","日历"),("calendar.badge.clock","日程"),("moon.stars.fill","星月"),
        ("sun.max.fill","太阳"),("leaf.fill","叶子"),("star.fill","星星")]
    var resolvedSymbol:String {Self.choices.contains(where:{$0.symbol==symbol}) ? symbol : "calendar"}
    var resolvedMode:String {["system","custom","colorful"].contains(mode) ? mode : "system"}
}
struct CalendarUserData:Codable {
    var theme=CalendarTheme()
    var menuIcon=MenuIconPreferences()
    var showDate=true
    var showYear=false
    var showWeekday=false
    var showLunar=true
    var showHoliday=false
    var birthdays:[Birthday]=[]
    var schedules:[ScheduleItem]=[]
    enum CodingKeys:String,CodingKey {case theme,menuIcon,showDate,showYear,showWeekday,showLunar,showHoliday,birthdays,schedules}
    init() {}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        theme=try c.decodeIfPresent(CalendarTheme.self,forKey:.theme) ?? CalendarTheme()
        menuIcon=try c.decodeIfPresent(MenuIconPreferences.self,forKey:.menuIcon) ?? MenuIconPreferences()
        showDate=try c.decodeIfPresent(Bool.self,forKey:.showDate) ?? true
        showYear=try c.decodeIfPresent(Bool.self,forKey:.showYear) ?? false
        showWeekday=try c.decodeIfPresent(Bool.self,forKey:.showWeekday) ?? false
        showLunar=try c.decodeIfPresent(Bool.self,forKey:.showLunar) ?? true
        showHoliday=try c.decodeIfPresent(Bool.self,forKey:.showHoliday) ?? false
        birthdays=try c.decodeIfPresent([Birthday].self,forKey:.birthdays) ?? []
        schedules=try c.decodeIfPresent([ScheduleItem].self,forKey:.schedules) ?? []
    }
    func menuTitle(now:Date,holidays:HolidaySnapshot)->String {
        var parts:[String]=[]
        if showDate {parts.append((showYear ? "\(Almanac.year(now))年" : "")+"\(Almanac.gregorian.component(.month,from:now))月\(Almanac.day(now))日")}
        if showWeekday {parts.append(Almanac.weekday(now).replacingOccurrences(of:"星期",with:"周"))}
        if showLunar {parts.append(Almanac.lunar(now))}
        if showHoliday,let h=holidays.day(now) {parts.append(h.name+(h.isOffDay ? "·休" : "·班"))}
        return parts.joined(separator:" · ")
    }
}
enum CalendarDataStore {
    static var localURL:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LunarCalendar/state.json")}
    static func load(url:URL?=nil)->CalendarUserData {
        guard let data=try? Data(contentsOf:url ?? localURL),data.count<1_000_000,let result=try? JSONDecoder().decode(CalendarUserData.self,from:data),result.birthdays.count<=2000,result.birthdays.allSatisfy(\.valid),result.schedules.count<=2000,result.schedules.allSatisfy(\.valid) else {return CalendarUserData()}
        return result
    }
#if !WIDGET_EXTENSION
    static func save(_ data:CalendarUserData,url:URL?=nil) throws {
        let file=url ?? localURL
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let bytes=try encoder.encode(data)
        guard bytes.count<1_000_000 else {throw CocoaError(.fileWriteOutOfSpace)}
        try bytes.write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    static func mirror(_ value:CalendarUserData) throws {
        // Only the containing app's own already-created extension container is written.
        let container=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/local.homeatlas.LunarCalendar.Widget/Data")
        guard FileManager.default.fileExists(atPath:container.path) else {return}
        let file=container.appendingPathComponent("Library/Application Support/LunarCalendar/state.json")
        var safe=value;safe.birthdays=safe.birthdays.map {var b=$0;b.contactID=nil;return b}
        safe.schedules=safe.schedules.map {var e=$0;e.notes="";e.location="";e.systemEventID=nil;return e}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let bytes=try encoder.encode(safe)
        if (try? Data(contentsOf:file))==bytes {return}
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bytes.write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
#endif
}

/// Reminders are relative to the actual current Beijing date, never the browsed month.
struct BirthdayReminder:Identifiable {
    let birthday:Birthday
    let date:Date
    let daysUntil:Int
    var id:UUID {birthday.id}
    var timing:String {daysUntil == 0 ? "今天生日":daysUntil == 1 ? "明天生日":"\(daysUntil)天后生日"}
    var title:String {birthday.name+" · "+timing}
    static func upcoming(_ birthdays:[Birthday],now:Date)->[Self] {
        let today=Almanac.gregorian.startOfDay(for:now)
        return birthdays.filter(\.valid).compactMap {birthday in
            for offset in 0...3 {
                guard let date=Almanac.gregorian.date(byAdding:.day,value:offset,to:today) else{continue}
                if birthday.occurs(on:date) {return Self(birthday:birthday,date:date,daysUntil:offset)}
            }
            return nil
        }.sorted {a,b in a.daysUntil != b.daysUntil ? a.daysUntil<b.daysUntil : a.birthday.name != b.birthday.name ? a.birthday.name<b.birthday.name : a.id.uuidString<b.id.uuidString}
    }
}
