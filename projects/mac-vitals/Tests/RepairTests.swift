import Foundation
@main enum Test {static func main()throws{
 let temp=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString);let p=temp.appendingPathComponent("Sample.app/Contents/PlugIns/Sample.appex");try FileManager.default.createDirectory(at:p.appendingPathComponent("Contents"),withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:temp)}
 let d:[String:Any]=["CFBundleIdentifier":"local.test.Widget","CFBundleExecutable":"Sample","CFBundlePackageType":"XPC!"];try PropertyListSerialization.data(fromPropertyList:d,format:.xml,options:0).write(to:p.appendingPathComponent("Contents/Info.plist"))
 precondition(WidgetSelfRepair.temporaryDuplicate(p.path,identifier:"local.test.Widget",expected:"/Applications/Sample.app/Contents/PlugIns/Sample.appex"))
 precondition(!WidgetSelfRepair.temporaryDuplicate(p.path,identifier:"local.other.Widget",expected:"/Applications/Sample.app/Contents/PlugIns/Sample.appex"))
 precondition(!WidgetSelfRepair.temporaryDuplicate(p.path,identifier:"local.test.Widget",expected:p.path))
 precondition(!WidgetSelfRepair.temporaryDuplicate("/Applications/Sample.app/Contents/PlugIns/Sample.appex",identifier:"local.test.Widget",expected:p.path))
 print("PASS 4 self-repair scope checks; no registrations changed")
}}
