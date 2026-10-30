import Foundation
@main struct SiliconTests {
 static func main() throws {
  var count = 0
  func check(_ value: Bool) { precondition(value); count += 1 }
  let wallet = URL(string:"https://cloud.siliconflow.cn/me/expensebill")!
  let bills = URL(string:"https://cloud.siliconflow.cn/me/bills")!
  let balance:[String:Any] = ["kind":"balance","text":"余额 ¥123.4567… （剩余可透支额度 ¥ 0）"]
  let monthly:[String:Any] = ["kind":"monthly","text":"¥ 4.25","period":"2026-10","unfiltered":true]
  func raw(_ rows:[[String:Any]], auth:Bool = true) -> [String:Any] { ["authenticated":auth,"values":rows] }
  func rejected(_ value:[String:Any],_ url:URL?) { check((try? SiliconPageReading.parse(value,url:url)) == nil) }
  let a = try SiliconPageReading.parse(raw([balance]),url:wallet)
  check(a.value.amount == Decimal(string:"123.4567") && a.period == nil)
  let b = try SiliconPageReading.parse(raw([monthly]),url:bills)
  check(b.value.amount == Decimal(string:"4.25") && b.period == "2026-10")
  rejected(raw([balance,balance]),wallet)
  rejected(raw([]),wallet)
  rejected(raw([balance],auth:false),wallet)
  rejected(raw([monthly]),wallet)
  rejected(raw([balance]),URL(string:"https://cloud.siliconflow.cn.attacker.example/me/expensebill"))
  rejected(raw([balance]),URL(string:"http://cloud.siliconflow.cn/me/expensebill"))
  for text in ["¥ 4.25 $ 2.00","账单金额 ¥4.25","¥ 4.25 trailing","$ 4.25","¥ 4.25 ¥0.00"] {
   var bad = monthly; bad["text"] = text; rejected(raw([bad]),bills)
  }
  var filtered = monthly; filtered["unfiltered"] = false; rejected(raw([filtered]),bills)
  var daily = monthly; daily["period"] = "2026-10-30"; rejected(raw([daily]),bills)
  var invalidMonth = monthly; invalidMonth["period"] = "2026-13"; rejected(raw([invalidMonth]),bills)
  var snapshot = Snapshot(); snapshot.siliconBalance = Record(value:a.value,date:Date(timeIntervalSince1970:1234),period:nil)
  snapshot.siliconMonthly = Record(value:b.value,date:Date(timeIntervalSince1970:1235),period:b.period)
  let data = try JSONEncoder().encode(snapshot), decoded = try JSONDecoder().decode(Snapshot.self,from:data)
  check(decoded.siliconBalance?.value == a.value && decoded.siliconMonthly?.period == b.period)
  check(!String(data:data,encoding:.utf8)!.contains("session"))
  let old = try JSONDecoder().decode(Snapshot.self,from:Data("{}".utf8))
  check(old.siliconBalance == nil && old.siliconMonthly == nil)
  print("PASS \(count) SiliconFlow cache and ambiguity checks")
 }
}
