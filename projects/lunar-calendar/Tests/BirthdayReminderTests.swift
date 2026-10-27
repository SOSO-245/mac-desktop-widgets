import Foundation
@main struct BirthdayReminderTests {
 static func main() {
  func date(_ key:String)->Date {Almanac.date(key)!}
  func check(_ value:Bool,_ title:String) {precondition(value,title)}
  let now=date("2026-10-26")
  let entries=[Birthday(name:"三天",month:10,day:29,lunar:false),Birthday(name:"今天",month:10,day:26,lunar:false),Birthday(name:"明天",month:10,day:27,lunar:false),Birthday(name:"两天",month:10,day:28,lunar:false),Birthday(name:"四天",month:10,day:30,lunar:false),Birthday(name:"已过",month:10,day:25,lunar:false)]
  let result=BirthdayReminder.upcoming(entries,now:now)
  check(result.map(\.daysUntil)==[0,1,2,3],"inclusive three-day reminders, sorted")
  check(result.first?.timing=="今天生日","today label")
  check(result[1].timing=="明天生日","tomorrow label")
  check(result.last?.timing=="3天后生日","advance label")
  check(BirthdayReminder.upcoming([Birthday(name:"跨年",month:1,day:1,lunar:false)],now:date("2026-12-30")).first?.daysUntil==2,"cross year")
  check(BirthdayReminder.upcoming([Birthday(name:"闰日",month:2,day:29,lunar:false)],now:date("2027-02-25")).first?.daysUntil==3,"non leap year uses established Feb28 rule")
  let lunarDate=Almanac.lunarParts(date("2026-10-29"))
  let lunar=Birthday(name:"农历",month:lunarDate.month,day:lunarDate.day,lunar:true,leap:lunarDate.leap)
  check(BirthdayReminder.upcoming([lunar],now:now).first?.daysUntil==3,"lunar advance calculation")
  check(BirthdayReminder.upcoming(entries,now:now.addingTimeInterval(86399)).count==4,"calendar days not 72 elapsed hours")
  check(BirthdayReminder.upcoming([Birthday(name:"",month:99,day:99,lunar:false)],now:now).isEmpty,"invalid records ignored")
  var same=entries[1];same.id=UUID();same.name="同日另一位"
  check(BirthdayReminder.upcoming([same,entries[1]],now:now).count==2,"multiple friends retained")
  print("PASS: 10 birthday reminder checks; no personal data loaded")
 }
}
