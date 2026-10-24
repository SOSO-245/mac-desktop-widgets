import Foundation

final class Stub:URLProtocol {
    static let lock=NSLock()
    static var count=0
    static var code=200
    static var body=Data()
    static func configure(_ code:Int,_ body:Data) {lock.lock();defer{lock.unlock()};Self.count=0;Self.code=code;Self.body=body}
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        Self.lock.lock();Self.count+=1;let status=Self.code,body=Self.body;Self.lock.unlock()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct ModelTests {
    static var assertions=0
    static func check(_ value:Bool,_ message:String) {assertions+=1;if !value {fatalError(message)}}
    static func date(_ key:String)->Date {Almanac.date(key)!}
    static func invalid(_ value:HolidayYear,year:Int)->Bool {(try? HolidayYear.validated(JSONEncoder().encode(value),year:year)) == nil}
    static func main() async throws {
        let name="local.homeatlas.LunarCalendar.tests.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:name)!
        defer{defaults.removePersistentDomain(forName:name)}
        let cases=try JSONDecoder().decode([[String]].self,from:Data(contentsOf:URL(fileURLWithPath:"Tests/hko-2026.json")))
        check(cases.count==365,"HKO fixture incomplete")
        for row in cases {check(Almanac.lunar(date(row[0]))==row[1],"HKO mismatch \(row[0]): \(Almanac.lunar(date(row[0]))) != \(row[1])")}
        check(Almanac.festival(date("2026-02-16"))=="除夕","eve")
        check(Almanac.festival(date("2026-02-17"))=="春节","new year")
        check(Almanac.zodiac(date("2026-02-17"))=="丙午年 · 属马","zodiac")
        check(Almanac.lunarParts(date("2025-07-25")).leap,"2025 leap sixth month")
        check(Almanac.festival(date("2025-07-25"))==nil,"no repeated festival")
        for key in ["2026-02-30","2026-2-01","x","2026-13-01","2026-01-00"] {check(Almanac.date(key)==nil,"invalid \(key)")}
        check(Almanac.key(Almanac.moved(date("2026-01-31"),months:1))=="2026-02-28","month end")
        check(Almanac.key(Almanac.moved(date("2024-02-28"),days:1))=="2024-02-29","leap day")
        check(Almanac.moved(Almanac.minimum,days:-1)==Almanac.minimum,"lower bound")
        check(Almanac.moved(Almanac.maximum,months:1)==Almanac.maximum,"upper bound")
        check(Almanac.monthDays(date("2026-10-01")).count==42,"month grid count")
        check(Almanac.weekday(Almanac.monthDays(date("2026-10-01"))[0])=="星期一","week start")
        Almanac.select("2026-10-01",defaults:defaults,now:date("2026-10-25"))
        check(Almanac.widgetDate(now:date("2026-10-25"),defaults:defaults)==date("2026-10-01"),"selection retained")
        let touch=date("2026-10-25")
        check(Almanac.widgetDate(now:touch.addingTimeInterval(29),defaults:defaults)==date("2026-10-01"),"widget keeps date before timeout")
        check(Almanac.widgetDate(now:touch.addingTimeInterval(30),defaults:defaults)==touch,"widget returns on 30-second boundary")
        check(Almanac.widgetTimelineDates(now:touch,defaults:defaults).contains(touch.addingTimeInterval(30)),"timeline includes return entry")
        Almanac.select("2026-10-02",defaults:defaults,now:touch.addingTimeInterval(20))
        check(Almanac.widgetDate(now:touch.addingTimeInterval(40),defaults:defaults)==date("2026-10-02"),"interaction extends browsing")
        check(Almanac.widgetDate(now:touch.addingTimeInterval(50),defaults:defaults)==touch,"renewed deadline returns today")
        let beforeMidnight=touch.addingTimeInterval(86400-15)
        Almanac.select("2026-10-02",defaults:defaults,now:beforeMidnight)
        check(Almanac.widgetDate(now:beforeMidnight.addingTimeInterval(30),defaults:defaults)==date("2026-10-26"),"return resolves today across midnight")
        defaults.removeObject(forKey:"widgetLastInteraction")
        check(Almanac.widgetDate(now:touch,defaults:defaults)==touch,"legacy selection returns today")
        Almanac.select("today",defaults:defaults)
        check(Almanac.widgetDate(now:date("2026-10-25"),defaults:defaults)==date("2026-10-25"),"today follows")
        let snapshot=HolidayStore.cached(defaults:defaults),seed=snapshot.years[2026]!
        check(seed.days.filter(\.isOffDay).count==33,"2026 off count")
        check(seed.days.filter{ !$0.isOffDay }.count==6,"2026 work count")
        check(snapshot.status(date("2026-10-10"))=="国庆节 · 补班","make-up work")
        check(snapshot.status(date("2026-10-11"))=="周末","weekend distinction")
        check(snapshot.status(date("2027-01-01"))=="假期安排待更新","future unknown")
        check(invalid(seed,year:2025),"wrong year rejected")
        check(invalid(HolidayYear(year:2026,papers:seed.papers,days:seed.days+[seed.days[0]]),year:2026),"duplicate rejected")
        check(invalid(HolidayYear(year:2027,papers:[],days:[]),year:2027),"unpublished rejected")
        check(invalid(HolidayYear(year:2026,papers:["https://gov.cn.example.com/a"],days:seed.days),year:2026),"bad source rejected")
        let spill=HolidayYear(year:2027,papers:seed.papers,days:[HolidayDay(name:"元旦",date:"2026-12-31",isOffDay:true)])
        check(!invalid(spill,year:2027),"December spillover accepted")
        var combined=snapshot;combined.years[2027]=spill
        check(combined.day(date("2026-12-31"))?.name=="元旦","next-year override")
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[Stub.self]
        let store=HolidayStore(defaults:defaults,session:URLSession(configuration:config))
        let bytes=try JSONEncoder().encode(seed),now=date("2026-10-25")
        Stub.configure(200,bytes)
        let updated=await store.update(year:2026,force:false,now:now)
        check(updated=="已更新","network success")
        check(defaults.data(forKey:"holiday-2026")==bytes,"cache saved")
        _=await store.update(year:2026,force:false,now:now.addingTimeInterval(60))
        check(Stub.count==1,"daily throttle")
        _=await store.update(year:2026,force:true,now:now.addingTimeInterval(10))
        check(Stub.count==1,"manual burst throttle")
        Stub.configure(503,Data())
        let failed=await store.update(year:2026,force:true,now:now.addingTimeInterval(60))
        check(failed=="更新失败，保留缓存","failure exposed")
        check(defaults.data(forKey:"holiday-2026")==bytes,"failure preserves cache")
        let throttled=await store.update(year:2026,force:false,now:now.addingTimeInterval(90))
        check(throttled==failed,"failure remains visible while throttled")
        Stub.configure(200,Data("{\"year\":2027,\"papers\":[],\"days\":[]}".utf8))
        let missing=await store.update(year:2027,force:false,now:now)
        check(missing=="未发布" && defaults.data(forKey:"holiday-2027")==nil,"unpublished is not stored")
        defaults.set(Data("bad".utf8),forKey:"holiday-2026")
        check(HolidayStore.cached(defaults:defaults).years[2026]?.days.count==39,"corrupt cache uses seed")
        let solarBirthday=Birthday(name:"测试生日",month:2,day:29,lunar:false)
        check(solarBirthday.valid,"valid leap birthday")
        check(solarBirthday.occurs(on:date("2026-02-28")),"non leap birthday uses February end")
        check(!solarBirthday.occurs(on:date("2024-02-28")) && solarBirthday.occurs(on:date("2024-02-29")),"leap birthday keeps 29th")
        let lunarBirthday=Birthday(name:"测试农历",month:1,day:1,lunar:true)
        check(lunarBirthday.occurs(on:date("2026-02-17")),"lunar birthday new year")
        let leapBirthday=Birthday(name:"测试闰月",month:6,day:1,lunar:true,leap:true)
        check(leapBirthday.occurs(on:date("2025-07-25")),"birthday in leap sixth month")
        check(!leapBirthday.occurs(on:date("2025-06-25")),"leap year excludes ordinary month")
        check(leapBirthday.occurs(on:date("2026-07-14")),"leap birthday ordinary month fallback")
        check(!Birthday(name:"无效",month:4,day:31,lunar:false).valid,"invalid solar birthday")
        var data=CalendarUserData();data.birthdays=[solarBirthday,lunarBirthday];data.showWeekday=true
        check(data.menuTitle(now:date("2026-10-25"),holidays:snapshot).contains("周日"),"menu options")
        data.showDate=false;data.showLunar=false;data.showWeekday=false
        check(data.menuTitle(now:date("2026-10-25"),holidays:snapshot).isEmpty,"menu icon only")
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("LunarTests-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temporary)}
        let file=temporary.appendingPathComponent("state.json")
        try CalendarDataStore.save(data,url:file)
        let saved=CalendarDataStore.load(url:file)
        check(saved.birthdays==data.birthdays && saved.theme==data.theme,"preferences and birthdays round trip")
        let event=ScheduleItem(title:"测试日程",start:date("2026-10-25").addingTimeInterval(23*3600),end:date("2026-10-26").addingTimeInterval(3600))
        check(event.valid && event.occurs(on:date("2026-10-25")) && event.occurs(on:date("2026-10-26")),"cross-day event")
        let dayEvent=ScheduleItem(title:"全天",start:date("2026-10-25"),end:date("2026-10-26"),allDay:true)
        check(dayEvent.occurs(on:date("2026-10-25")) && !dayEvent.occurs(on:date("2026-10-26")),"all-day exclusive end")
        check(!ScheduleItem(title:"",start:now,end:now.addingTimeInterval(1)).valid,"empty event title")
        check(!ScheduleItem(title:"错误",start:now,end:now).valid,"invalid event duration")
        var oldObject=try JSONSerialization.jsonObject(with:JSONEncoder().encode(data)) as! [String:Any]
        oldObject.removeValue(forKey:"schedules")
        let migrated=try JSONDecoder().decode(CalendarUserData.self,from:JSONSerialization.data(withJSONObject:oldObject))
        check(migrated.birthdays==data.birthdays && migrated.schedules.isEmpty,"migration preserves old birthdays")
        data.schedules=[event];try CalendarDataStore.save(data,url:file)
        check(CalendarDataStore.load(url:file).schedules==[event],"event persistence")
        oldObject.removeValue(forKey:"menuIcon")
        let legacy=try JSONDecoder().decode(CalendarUserData.self,from:JSONSerialization.data(withJSONObject:oldObject))
        check(legacy.menuIcon==MenuIconPreferences() && legacy.birthdays==data.birthdays,"icon migration preserves data")
        data.menuIcon=MenuIconPreferences(symbol:"moon.stars.fill",mode:"custom",color:"#FF88CC")
        try CalendarDataStore.save(data,url:file)
        let iconSaved=CalendarDataStore.load(url:file)
        check(iconSaved.menuIcon==data.menuIcon && iconSaved.schedules==data.schedules,"icon preferences persist alongside schedules")
        check(MenuIconPreferences(symbol:"unknown",mode:"unknown").resolvedSymbol=="calendar" && MenuIconPreferences(mode:"unknown").resolvedMode=="system","unknown icon fallback")
        let termRows=try JSONDecoder().decode([[String]].self,from:Data(contentsOf:URL(fileURLWithPath:"Tests/hko-solar-terms-2026.json")))
        for row in termRows {check(SolarTerms.name(on:date(row[0]))==row[1],"HKO solar term \(row[0])")}
        for year in 1901...2099 {
            check(SolarTerms.days[year-1901].count==24 && SolarTerms.days[year-1901].enumerated().allSatisfy {i,d in (1...31).contains(d) && i%2==0 || (i%2==1 && d>SolarTerms.days[year-1901][i-1] && d<=31)},"solar term year \(year)")
        }
        check(Almanac.festivals(date("2026-03-03")).contains("元宵节"),"traditional lantern festival")
        check(Almanac.festivals(date("2026-09-25")).contains("中秋节"),"traditional mid autumn")
        check(Almanac.festivals(date("2026-03-08")).contains("国际妇女节"),"international women day")
        check(Almanac.daySubtitle(date("2026-06-05"))=="芒种·环境日","coincident term and observance")
        check(Almanac.daySubtitle(date("2026-10-25"))==Almanac.lunar(date("2026-10-25"),short:true),"ordinary date retains lunar label")
        check(snapshot.day(date("2026-03-08"))==nil,"international observance not a statutory holiday")
        let weekly=ScheduleItem(title:"每周",start:date("2026-10-25").addingTimeInterval(23*3600),end:date("2026-10-26").addingTimeInterval(3600),recurrence:"weekly")
        check(weekly.occurs(on:date("2026-11-01")) && weekly.occurs(on:date("2026-11-02")),"weekly recurrence crosses midnight")
        check(!weekly.occurs(on:date("2026-10-18")) && !weekly.occurs(on:date("2026-11-03")),"recurrence excludes earlier and other dates")
        let monthly=ScheduleItem(title:"月末",start:date("2026-01-31"),end:date("2026-02-01"),allDay:true,recurrence:"monthly")
        check(!monthly.occurs(on:date("2026-02-28")) && monthly.occurs(on:date("2026-03-31")),"monthly skips absent day")
        let yearly=ScheduleItem(title:"闰年",start:date("2024-02-29"),end:date("2024-03-01"),allDay:true,recurrence:"yearly")
        check(!yearly.occurs(on:date("2025-02-28")) && yearly.occurs(on:date("2028-02-29")),"yearly leap day recurrence")
        var legacyEvent=try JSONSerialization.jsonObject(with:JSONEncoder().encode(weekly)) as! [String:Any]
        legacyEvent.removeValue(forKey:"recurrence")
        let oldEvent=try JSONDecoder().decode(ScheduleItem.self,from:JSONSerialization.data(withJSONObject:legacyEvent))
        check(oldEvent.recurrence=="none" && oldEvent.title==weekly.title,"old event recurrence migration")
        data.schedules=[weekly];try CalendarDataStore.save(data,url:file)
        check(CalendarDataStore.load(url:file).schedules.first?.recurrence=="weekly","recurrence persistence")
        Stub.configure(200,bytes)
        let midnight=date("2026-10-27")
        defaults.set(midnight.addingTimeInterval(-1),forKey:"attempt-2026")
        _=await store.update(year:2026,force:false,now:midnight)
        check(Stub.count==1,"midnight refresh even if last request was one second ago")
        _=await store.update(year:2026,force:false,now:midnight.addingTimeInterval(60))
        check(Stub.count==1,"one automatic request per Beijing calendar day")
        check(Almanac.nextMidnight(after:midnight.addingTimeInterval(1))==date("2026-10-28"),"next Beijing midnight")
        check(Almanac.isInternationalFestival("国际妇女节") && !Almanac.isInternationalFestival("中秋节"),"international and traditional color classification")
        print("PASS: \(assertions) checks, including all 365 lunar dates from HKO 2026, date navigation, holiday validation and update/cache behavior.")
    }
}
