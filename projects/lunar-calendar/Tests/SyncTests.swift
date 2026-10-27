import Foundation
@main struct SyncTests {
 static func main() throws {
  var count=0
  func check(_ pass:Bool,_ name:String) {count+=1;if !pass {fatalError(name)}}
  var a=CalendarUserData();let birthday=Birthday(name:"测试生日",month:2,day:29,lunar:false,contactID:"LOCAL-CONTACT")
  a.birthdays=[birthday];a.schedules=[ScheduleItem(title:"测试日程",start:Date(timeIntervalSince1970:1700000000),end:Date(timeIntervalSince1970:1700003600),systemEventID:"LOCAL-EVENT",recurrence:"weekly")]
  let extras=["popup":try CalendarSyncDocument.bytes("glass")]
  var j1=CalendarSyncJournal();j1.capture(try CalendarSyncDocument.values(a,extras:extras))
  let bytes=try CalendarSyncDocument.bytes(j1.document)
  let json=String(decoding:bytes,as:UTF8.self)
  check(!json.contains("LOCAL-"),"private device IDs stripped")
  let (same,_)=try j1.document.materialize(preserving:a)
  check(same.birthdays.first?.contactID=="LOCAL-CONTACT","local contact retained")
  check(same.schedules.first?.systemEventID=="LOCAL-EVENT","local event retained")
  let (new,_)=try j1.document.materialize(preserving:CalendarUserData())
  check(new.birthdays.first?.contactID==nil && new.schedules.first?.systemEventID==nil,"other Mac has no device IDs")
  check(new.schedules.first?.recurrence=="weekly","recurrence preserved")
  var j2=CalendarSyncJournal();j2.capture(try CalendarSyncDocument.values(CalendarUserData(),extras:extras));try j2.document.merge(j1.document)
  j2.baseline=try CalendarSyncDocument.values(new,extras:extras)
  var b=new;b.birthdays[0].name="另一台 Mac 修改";j2.capture(try CalendarSyncDocument.values(b,extras:extras))
  a.schedules.append(ScheduleItem(title:"离线新增",start:Date(timeIntervalSince1970:1800000000),end:Date(timeIntervalSince1970:1800003600)))
  j1.capture(try CalendarSyncDocument.values(a,extras:extras))
  var left=j1.document,right=j2.document;try left.merge(j2.document);try right.merge(j1.document)
  check(left==right,"concurrent merge converges")
  let (merged,_)=try left.materialize(preserving:a)
  check(merged.birthdays.first?.name=="另一台 Mac 修改" && merged.schedules.count==2,"independent changes preserved")
  j1.document=left;j1.baseline=try CalendarSyncDocument.values(merged,extras:extras)
  var removed=merged;removed.birthdays=[];j1.capture(try CalendarSyncDocument.values(removed,extras:extras));try j1.document.merge(j2.document)
  check(try j1.document.materialize(preserving:a).0.birthdays.isEmpty,"deletion not resurrected by stale peer")
  let encoded=try CalendarSyncDocument.bytes(j1);var restarted=try JSONDecoder().decode(CalendarSyncJournal.self,from:encoded)
  let before=restarted.document;restarted.capture(try CalendarSyncDocument.values(removed,extras:extras))
  check(before==restarted.document,"restart does not create false edits")
  var invalid=j1.document;invalid.schema=2
  do {try left.merge(invalid);fatalError("accepted future schema")} catch {check(true,"future schema rejected")}
  invalid=j1.document;invalid.records["birthday/"+birthday.id.uuidString]?.payload=try CalendarSyncDocument.bytes(birthday)
  do {_ = try invalid.validated();fatalError("accepted device IDs")} catch {check(true,"reject device associations in cloud")}
  var settings=merged;settings.showYear=true
  var j3=CalendarSyncJournal();j3.document=left;j3.baseline=try CalendarSyncDocument.values(merged,extras:extras);j3.initialized=true
  j3.capture(try CalendarSyncDocument.values(settings,extras:extras));try j3.document.merge(left)
  check(try j3.document.materialize(preserving:a).0.showYear,"display edit persists")
  var duplicate=j3.document;try duplicate.merge(j3.document);check(duplicate==j3.document,"idempotent merge")
  var stale=j3.document;stale.records["display/showYear"]?.revision=0;try duplicate.merge(stale);check(duplicate==j3.document,"old snapshot cannot overwrite")
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent("calendar-sync-test-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:directory)}
  _ = try CalendarCloudIO.write(j1.document,device:j1.device,folder:directory)
  _ = try CalendarCloudIO.write(j2.document,device:j2.device,folder:directory)
  let read=try CalendarCloudIO.read(directory);check(read.count==2,"two device files read")
  var replay=CalendarSyncDocument();for document in read {try replay.merge(document)}
  check(try replay.materialize(preserving:CalendarUserData()).0.birthdays.isEmpty,"file roundtrip retains deletion")
  let file=directory.appendingPathComponent("mac-"+j1.device+".json")
  let modified=try file.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
  _ = try CalendarCloudIO.write(j1.document,device:j1.device,folder:directory)
  check(try file.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate==modified,"unchanged data not rewritten")
  try Data("broken".utf8).write(to:directory.appendingPathComponent("mac-broken.json"))
  do {_ = try CalendarCloudIO.read(directory);fatalError("accepted damaged cloud document")} catch {check(true,"damaged peer stops cycle without resetting data")}
  print("Passed \(count) calendar sync checks")
 }
}
