import Foundation

let calendarWidgetKind = "LunarCalendarWidget"
enum Almanac {
    static let zone = TimeZone(identifier:"Asia/Shanghai")!
    static var gregorian:Calendar { var c = Calendar(identifier:.gregorian); c.timeZone=zone; c.firstWeekday=2; return c }
    static var chinese:Calendar { var c=Calendar(identifier:.chinese); c.timeZone=zone; return c }
    static let minimum = date("1901-01-01")!
    static let maximum = date("2099-12-31")!
    static func date(_ key:String) -> Date? {
        guard key.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil else { return nil }
        let f=DateFormatter(); f.calendar=gregorian; f.timeZone=zone; f.locale=Locale(identifier:"en_US_POSIX"); f.dateFormat="yyyy-MM-dd"; f.isLenient=false
        guard let d=f.date(from:key), f.string(from:d)==key else { return nil }; return d
    }
    static func key(_ date:Date) -> String {
        let c=gregorian.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
    static func clamp(_ date:Date)->Date { min(maximum,max(minimum,gregorian.startOfDay(for:date))) }
    static func year(_ date:Date)->Int { gregorian.component(.year,from:date) }
    static func day(_ date:Date)->Int { gregorian.component(.day,from:date) }
    static func monthTitle(_ date:Date)->String { "\(year(date))年\(gregorian.component(.month,from:date))月" }
    static func weekday(_ date:Date)->String { ["星期日","星期一","星期二","星期三","星期四","星期五","星期六"][gregorian.component(.weekday,from:date)-1] }
    static func moved(_ date:Date,days:Int=0,months:Int=0)->Date { clamp(gregorian.date(byAdding:DateComponents(month:months,day:days),to:date) ?? date) }
    static func monthDays(_ date:Date)->[Date] {
        let first=gregorian.date(from:gregorian.dateComponents([.year,.month],from:date))!
        let offset=(gregorian.component(.weekday,from:first)+5)%7
        let start=gregorian.date(byAdding:.day,value:-offset,to:first)!
        return (0..<42).map { gregorian.date(byAdding:.day,value:$0,to:start)! }
    }
    static func lunarParts(_ date:Date)->(month:Int,day:Int,leap:Bool,year:Int) {
        let c=chinese.dateComponents([.month,.day,.year,.isLeapMonth],from:date)
        return (c.month!,c.day!,c.isLeapMonth ?? false,c.year!)
    }
    static let lunarMonths=["正月","二月","三月","四月","五月","六月","七月","八月","九月","十月","冬月","腊月"]
    static let lunarDays=["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十","廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]
    static func lunar(_ date:Date,short:Bool=false)->String {
        let c=lunarParts(date), month=(c.leap ? "闰" : "")+lunarMonths[c.month-1]
        return short ? (c.day==1 ? month : lunarDays[c.day-1]) : month+lunarDays[c.day-1]
    }
    static func zodiac(_ date:Date)->String {
        let y=lunarParts(date).year-1
        return ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"][y%10]+["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"][y%12]+"年 · 属"+["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"][y%12]
    }
    static let internationalFestivals=["1-1":"元旦","3-8":"国际妇女节","3-22":"世界水日","4-7":"世界卫生日","4-22":"世界地球日","4-23":"世界读书日","5-1":"劳动节","6-1":"儿童节","6-5":"世界环境日","6-8":"世界海洋日","7-30":"国际友谊日","9-8":"国际扫盲日","9-21":"国际和平日","10-5":"世界教师日","10-16":"世界粮食日","11-20":"世界儿童日","12-1":"世界艾滋病日","12-3":"国际残疾人日","12-10":"人权日"]
    static func isInternationalFestival(_ name:String)->Bool {internationalFestivals.values.contains(name)}
    static func festivals(_ date:Date)->[String] {
        var values:[String]=[]
        let c=lunarParts(date)
        if !c.leap {
            let traditional=["1-1":"春节","1-15":"元宵节","2-2":"龙抬头","3-3":"上巳节","5-5":"端午节","7-7":"七夕","7-15":"中元节","8-15":"中秋节","9-9":"重阳节","10-1":"寒衣节","10-15":"下元节","12-8":"腊八节","12-23":"北方小年","12-24":"南方小年"]
            if let name=traditional["\(c.month)-\(c.day)"] {values.append(name)}
            let next=lunarParts(gregorian.date(byAdding:.day,value:1,to:date)!)
            if c.month==12 && next.month==1 && next.day==1 {values.append("除夕")}
        }
        // International observances; these names never imply a statutory day off.

        let solarKey="\(gregorian.component(.month,from:date))-\(day(date))"
        if let name=internationalFestivals[solarKey] {values.append(name)}
        if solarKey=="10-1" {values.append("国庆节")}
        return values
    }
    static func dayLabels(_ date:Date)->[String] {
        var values:[String]=[]
        if let term=SolarTerms.name(on:date) {values.append(term)}
        values += festivals(date)
        return values
    }
    static func festival(_ date:Date)->String? {
        let names=dayLabels(date)
        return names.isEmpty ? nil : names.joined(separator:"·")
    }
    static func shortDayLabel(_ name:String)->String {
        let short=["国际妇女节":"妇女节","世界环境日":"环境日","世界地球日":"地球日","世界读书日":"读书日","国际和平日":"和平日","国际残疾人日":"残疾人日","世界艾滋病日":"艾滋病日","国际友谊日":"友谊日","世界儿童日":"世界儿童日","国际扫盲日":"扫盲日","世界教师日":"世界教师日"]
        return short[name] ?? name
    }
    static func daySubtitle(_ date:Date)->String {
        let names=dayLabels(date).map(shortDayLabel)
        return names.isEmpty ? lunar(date,short:true) : names.joined(separator:"·")
    }
    static func nextMidnight(after now:Date)->Date {
        gregorian.date(byAdding:.day,value:1,to:gregorian.startOfDay(for:now))!
    }
    static func widgetReturnDate(now:Date=Date(),defaults:UserDefaults = .standard)->Date? {
        guard defaults.string(forKey:"selectedDate").flatMap(date) != nil,
              let touched=defaults.object(forKey:"widgetLastInteraction") as? Date,
              touched<=now,now.timeIntervalSince(touched)<30 else {return nil}
        return touched.addingTimeInterval(30)
    }
    static func widgetDate(now:Date=Date(),defaults:UserDefaults = .standard)->Date {
        guard widgetReturnDate(now:now,defaults:defaults) != nil else {return clamp(now)}
        return defaults.string(forKey:"selectedDate").flatMap(date).map(clamp) ?? clamp(now)
    }
    static func widgetTimelineDates(now:Date=Date(),defaults:UserDefaults = .standard)->[Date] {
        let start=gregorian.startOfDay(for:now)
        var dates=[now,gregorian.date(byAdding:.day,value:1,to:start)!,gregorian.date(byAdding:.day,value:2,to:start)!]
        if let reset=widgetReturnDate(now:now,defaults:defaults) {dates.append(reset)}
        return Array(Set(dates)).sorted()
    }
    static func select(_ key:String,defaults:UserDefaults = .standard,now:Date=Date()) {
        if key=="today" {
            defaults.removeObject(forKey:"selectedDate");defaults.removeObject(forKey:"widgetLastInteraction")
        } else if let d=date(key), (minimum...maximum).contains(d) {
            defaults.set(key,forKey:"selectedDate");defaults.set(now,forKey:"widgetLastInteraction")
        }
    }
}

struct HolidayDay:Codable { let name:String; let date:String; let isOffDay:Bool }
struct HolidayYear:Codable {
    let year:Int; let papers:[String]; let days:[HolidayDay]
    static func validated(_ data:Data,year:Int) throws -> HolidayYear {
        guard data.count<200_000 else { throw HolidayError.invalid }
        let result=try JSONDecoder().decode(Self.self,from:data)
        guard result.year==year, result.days.count<=100, Set(result.days.map(\.date)).count==result.days.count else { throw HolidayError.invalid }
        guard !result.papers.isEmpty, !result.days.isEmpty else { throw HolidayError.unpublished }
        guard result.papers.allSatisfy({ value in
            guard let u=URL(string:value), ["https","http"].contains(u.scheme ?? ""),let host=u.host else { return false }
            return host=="www.gov.cn" || host=="gov.cn"
        }) else { throw HolidayError.invalid }
        for day in result.days {
            guard let d=Almanac.date(day.date), !day.name.isEmpty,day.name.count<=30,
                (Almanac.year(d)==year || (Almanac.year(d)==year-1 && Almanac.gregorian.component(.month,from:d)==12)) else { throw HolidayError.invalid }
        }
        return result
    }
}
enum HolidayError:Error { case invalid,unpublished,http }
struct HolidaySnapshot {
    var years:[Int:HolidayYear]=[:]
    var note="离线日历"
    func day(_ date:Date)->HolidayDay? {
        let y=Almanac.year(date),key=Almanac.key(date)
        return years[y+1]?.days.first{$0.date==key} ?? years[y]?.days.first{$0.date==key}
    }
    func status(_ date:Date)->String {
        if let d=day(date) { return d.name + (d.isOffDay ? " · 放假" : " · 补班") }
        if years[Almanac.year(date)] == nil { return "假期安排待更新" }
        return Almanac.gregorian.isDateInWeekend(date) ? "周末" : "工作日"
    }
}
final class HolidayNoRedirect:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
}
actor HolidayStore {
    static let shared=HolidayStore()
    let defaults:UserDefaults
    let session:URLSession
    var pending:[Int:Task<String,Never>]=[:]
    init(defaults:UserDefaults = .standard,session:URLSession?=nil) {
        self.defaults=defaults
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=8;config.timeoutIntervalForResource=12
        config.httpCookieStorage=nil;config.urlCredentialStorage=nil;config.urlCache=nil
        self.session=session ?? URLSession(configuration:config,delegate:HolidayNoRedirect(),delegateQueue:nil)
    }
    nonisolated static func cached(defaults:UserDefaults = .standard)->HolidaySnapshot {
        var result=HolidaySnapshot()
        for data in BundledHoliday.jsons {
            if let bytes=data.data(using:.utf8),let y=try? JSONDecoder().decode(HolidayYear.self,from:bytes),let valid=try? HolidayYear.validated(bytes,year:y.year) { result.years[y.year]=valid }
        }
        for year in 2007...2100 {
            if let bytes=defaults.data(forKey:"holiday-\(year)"),let value=try? HolidayYear.validated(bytes,year:year) { result.years[year]=value }
        }
        return result
    }
    func load(year:Int,force:Bool=false,now:Date=Date()) async -> HolidaySnapshot {
        let current=Almanac.year(now)
        let needed=Set([year,year+1,current,current+1]).filter{(2007...2100).contains($0)}.sorted()
        let notes=await withTaskGroup(of:String.self,returning:[String].self) { group in
            for y in needed { group.addTask { await self.update(year:y,force:force,now:now) } }
            var values:[String]=[];for await value in group {values.append(value)};return values
        }
        var result=Self.cached(defaults:defaults)
        result.note=notes.contains("更新失败，保留缓存") ? "更新失败，保留缓存" : "每日0点检查 · 北京时间"
        return result
    }
    func update(year:Int,force:Bool,now:Date) async -> String {
        if let task=pending[year] { return await task.value }
        if let last=defaults.object(forKey:"attempt-\(year)") as? Date,last<=now {
            let throttled=force ? now.timeIntervalSince(last)<30 : Almanac.gregorian.isDate(last,inSameDayAs:now)
            if throttled {return defaults.string(forKey:"outcome-\(year)") ?? "已检查"}
        }
        defaults.set(now,forKey:"attempt-\(year)")
        let task=Task { () -> String in
            do {
                let url=URL(string:"https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!
                var request=URLRequest(url:url);request.setValue("LunarCalendarMac/1.0",forHTTPHeaderField:"User-Agent")
                let (data,response)=try await self.session.data(for:request)
                if (response as? HTTPURLResponse)?.statusCode==404 { return "未发布" }
                guard (response as? HTTPURLResponse)?.statusCode==200 else { throw HolidayError.http }
                _=try HolidayYear.validated(data,year:year)
                self.defaults.set(data,forKey:"holiday-\(year)");self.defaults.set(now,forKey:"success-\(year)")
                return "已更新"
            } catch HolidayError.unpublished { return "未发布" }
            catch { return "更新失败，保留缓存" }
        }
        pending[year]=task;let note=await task.value;defaults.set(note,forKey:"outcome-\(year)");pending[year]=nil;return note
    }
}

enum BundledHoliday { static let jsons = [
#"{"$schema":"https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/schema.json","$id":"https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2025.json","year":2025,"papers":["https://www.gov.cn/zhengce/zhengceku/202411/content_6986383.htm"],"days":[{"name":"元旦","date":"2025-01-01","isOffDay":true},{"name":"春节","date":"2025-01-26","isOffDay":false},{"name":"春节","date":"2025-01-28","isOffDay":true},{"name":"春节","date":"2025-01-29","isOffDay":true},{"name":"春节","date":"2025-01-30","isOffDay":true},{"name":"春节","date":"2025-01-31","isOffDay":true},{"name":"春节","date":"2025-02-01","isOffDay":true},{"name":"春节","date":"2025-02-02","isOffDay":true},{"name":"春节","date":"2025-02-03","isOffDay":true},{"name":"春节","date":"2025-02-04","isOffDay":true},{"name":"春节","date":"2025-02-08","isOffDay":false},{"name":"清明节","date":"2025-04-04","isOffDay":true},{"name":"清明节","date":"2025-04-05","isOffDay":true},{"name":"清明节","date":"2025-04-06","isOffDay":true},{"name":"劳动节","date":"2025-04-27","isOffDay":false},{"name":"劳动节","date":"2025-05-01","isOffDay":true},{"name":"劳动节","date":"2025-05-02","isOffDay":true},{"name":"劳动节","date":"2025-05-03","isOffDay":true},{"name":"劳动节","date":"2025-05-04","isOffDay":true},{"name":"劳动节","date":"2025-05-05","isOffDay":true},{"name":"端午节","date":"2025-05-31","isOffDay":true},{"name":"端午节","date":"2025-06-01","isOffDay":true},{"name":"端午节","date":"2025-06-02","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-09-28","isOffDay":false},{"name":"国庆节、中秋节","date":"2025-10-01","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-02","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-03","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-04","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-05","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-06","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-07","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-08","isOffDay":true},{"name":"国庆节、中秋节","date":"2025-10-11","isOffDay":false}]}"#,
#"{"$schema":"https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/schema.json","$id":"https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.json","year":2026,"papers":["https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm"],"days":[{"name":"元旦","date":"2026-01-01","isOffDay":true},{"name":"元旦","date":"2026-01-02","isOffDay":true},{"name":"元旦","date":"2026-01-03","isOffDay":true},{"name":"元旦","date":"2026-01-04","isOffDay":false},{"name":"春节","date":"2026-02-14","isOffDay":false},{"name":"春节","date":"2026-02-15","isOffDay":true},{"name":"春节","date":"2026-02-16","isOffDay":true},{"name":"春节","date":"2026-02-17","isOffDay":true},{"name":"春节","date":"2026-02-18","isOffDay":true},{"name":"春节","date":"2026-02-19","isOffDay":true},{"name":"春节","date":"2026-02-20","isOffDay":true},{"name":"春节","date":"2026-02-21","isOffDay":true},{"name":"春节","date":"2026-02-22","isOffDay":true},{"name":"春节","date":"2026-02-23","isOffDay":true},{"name":"春节","date":"2026-02-28","isOffDay":false},{"name":"清明节","date":"2026-04-04","isOffDay":true},{"name":"清明节","date":"2026-04-05","isOffDay":true},{"name":"清明节","date":"2026-04-06","isOffDay":true},{"name":"劳动节","date":"2026-05-01","isOffDay":true},{"name":"劳动节","date":"2026-05-02","isOffDay":true},{"name":"劳动节","date":"2026-05-03","isOffDay":true},{"name":"劳动节","date":"2026-05-04","isOffDay":true},{"name":"劳动节","date":"2026-05-05","isOffDay":true},{"name":"劳动节","date":"2026-05-09","isOffDay":false},{"name":"端午节","date":"2026-06-19","isOffDay":true},{"name":"端午节","date":"2026-06-20","isOffDay":true},{"name":"端午节","date":"2026-06-21","isOffDay":true},{"name":"国庆节","date":"2026-09-20","isOffDay":false},{"name":"中秋节","date":"2026-09-25","isOffDay":true},{"name":"中秋节","date":"2026-09-26","isOffDay":true},{"name":"中秋节","date":"2026-09-27","isOffDay":true},{"name":"国庆节","date":"2026-10-01","isOffDay":true},{"name":"国庆节","date":"2026-10-02","isOffDay":true},{"name":"国庆节","date":"2026-10-03","isOffDay":true},{"name":"国庆节","date":"2026-10-04","isOffDay":true},{"name":"国庆节","date":"2026-10-05","isOffDay":true},{"name":"国庆节","date":"2026-10-06","isOffDay":true},{"name":"国庆节","date":"2026-10-07","isOffDay":true},{"name":"国庆节","date":"2026-10-10","isOffDay":false}]}"#
] }
