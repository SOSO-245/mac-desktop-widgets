import Foundation
@main struct BillingTests {
 static func main() throws {
  let iso=ISO8601DateFormatter()
  func date(_ s:String)->Date {iso.date(from:s)!}
  var n=0
  func check(_ b:Bool,_ name:String){n+=1;precondition(b,name)}
  let now=date("2026-11-01T12:00:00Z")
  var s=CreditSchedule();s.startDay=7;s.regularUSD="300";s.firstEnabled=true;s.firstStart=date("2026-10-21T18:10:00Z");s.firstUSD="75"
  let p=s.period(now:now)
  check(p.start==date("2026-10-21T00:00:00Z"),"first actual grant day, not the regular October seventh")
  check(p.nextStart==date("2026-11-07T00:00:00Z"),"first period ends next reset seventh")
  check(s.allowance(now:now)==75,"first prorated allowance")
  check(s.estimatedRemaining(spent:Decimal(string:"12.48"),now:now)==Decimal(string:"62.52"),"exact decimal estimate")
  check(s.estimatedRemaining(spent:100,now:now)==0,"negative remainder capped, not account overdraft")
  check(s.estimatedRemaining(spent:nil,now:now)==nil,"missing costs not fabricated zero")
  let next=date("2026-11-07T00:00:00Z")
  check(s.period(now:next).start==next,"exact boundary activates regular period")
  check(s.allowance(now:next)==300,"next grant uses recurring 200, no rollover")
  check(s.period(now:date("2027-01-01T00:00:00Z")).start==date("2026-12-07T00:00:00Z"),"year boundary")
  check(Month(now:now).id=="2026-11","legacy month cache retains ID")
  check(Month(now:now,startDay:7).id != Month(now:now).id,"custom cycle cannot reuse calendar-month cache")
  check(Month(now:now,startDay:7).start==date("2026-10-07T00:00:00Z"),"before reset, previous month start")
  check(Month(now:date("2026-02-28T10:00:00Z"),startDay:31).start==date("2026-02-28T00:00:00Z"),"short month clamped")
  check(Month(now:date("2028-02-29T10:00:00Z"),startDay:31).start==date("2028-02-29T00:00:00Z"),"leap year clamped")
  check(Month(now:now,startDay:7).costsEndExclusive==date("2026-11-02T00:00:00Z"),"daily Costs still includes current day")
  let round=try JSONDecoder().decode(CreditSchedule.self,from:JSONEncoder().encode(s))
  check(round==s,"schedule survives restart")
  for bad in ["-1","nan","Infinity","$58","1,000","58x","1.12345"] {check(CreditSchedule.amount(bad)==nil,"reject invalid amount "+bad)}
  check(CreditSchedule.amount("0")==0,"zero grant supported")
  check(CreditSchedule.amount("200.50")==Decimal(string:"200.50"),"precise manual amount")
  s.startDay=32;check(!s.valid,"invalid billing day rejected")
  print("PASS \(n) custom cycle, first grant, rollover and estimate checks")
 }
}
