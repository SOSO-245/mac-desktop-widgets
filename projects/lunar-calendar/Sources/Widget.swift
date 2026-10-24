import SwiftUI
import WidgetKit
import AppIntents
struct SelectCalendarDateIntent:AppIntent {
    static var title:LocalizedStringResource="切换日历日期"
    static var openAppWhenRun=false
    @Parameter(title:"日期") var key:String
    init() {}
    init(key:String) {self.key=key}
    func perform() async throws -> some IntentResult {
        Almanac.select(key)
        WidgetCenter.shared.reloadTimelines(ofKind:calendarWidgetKind)
        return .result()
    }
}
struct CalendarEntry:TimelineEntry {let date:Date;let selected:Date;let holidays:HolidaySnapshot;var data=CalendarDataStore.load()}
struct CalendarProvider:TimelineProvider {
    func placeholder(in context:Context)->CalendarEntry {CalendarEntry(date:Date(),selected:Date(),holidays:HolidayStore.cached())}
    func getSnapshot(in context:Context,completion:@escaping(CalendarEntry)->Void) {completion(CalendarEntry(date:Date(),selected:Almanac.widgetDate(),holidays:HolidayStore.cached()))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<CalendarEntry>)->Void) {
        Task {
            let requested=Date(),selected=Almanac.widgetDate(now:requested)
            let snapshot=await HolidayStore.shared.load(year:Almanac.year(selected))
            // Re-read after the request: interaction and the 30-second deadline may have changed.
            let now=Date()
            let entries=Almanac.widgetTimelineDates(now:now).map {time in
                CalendarEntry(date:time,selected:Almanac.widgetDate(now:time),holidays:snapshot)
            }
            let nextDay=Almanac.gregorian.date(byAdding:.day,value:1,to:Almanac.gregorian.startOfDay(for:now))!
            completion(Timeline(entries:entries,policy:.after(nextDay)))
        }
    }
}
struct CalendarWidgetView:View {
    @Environment(\.widgetFamily) var family
    let entry:CalendarEntry
    var body:some View {
        CalendarCard(selected:entry.selected,now:entry.date,holidays:entry.holidays,size:family == .systemSmall ? .small : family == .systemMedium ? .medium : .large)
            .containerBackground(for:.widget) { CalendarBackground() }
            .environment(\.calendarData,entry.data)
            .widgetURL(URL(string:"lunarcalendar://date/"+Almanac.key(entry.selected)))
    }
}
@main struct LunarCalendarWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:calendarWidgetKind,provider:CalendarProvider()) { CalendarWidgetView(entry:$0) }
            .configurationDisplayName("万年历")
            .description("农历、放假与补班。直接翻日、翻月和选择日期，假期安排自动更新。")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
            .contentMarginsDisabled().containerBackgroundRemovable(false)
    }
}
