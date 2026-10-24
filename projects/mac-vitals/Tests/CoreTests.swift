import Foundation
@main enum Tests {static func main()throws{
 var checks=0
 func expect(_ v:Bool,_ label:String){precondition(v,label);checks+=1}
 let raw=Data(#"{"sys_power":23.0,"all_power":8.0,"cpu_active_ratio":0.25,"memory":{"ram_usage":16,"ram_total":32},"temp":{"cpu_temp_avg":54,"gpu_temp_avg":49}}"#.utf8)
 let m=try Metrics.parse(raw);expect(m.systemPower==23,"system watts");expect(m.cpu==25,"active percentage");expect(m.memoryPercent==50,"memory ratio");expect(m.cpuTemp==54,"cpu temperature");expect(m.powerLabel=="系统功率估算","power label");expect(m.fresh(m.date.addingTimeInterval(89)),"fresh");expect(!m.fresh(m.date.addingTimeInterval(91)),"expired")
 let empty=try Metrics.parse(Data("{}".utf8));expect(empty.cpu==nil && empty.systemPower==nil,"missing not zero");expect(empty.memoryPercent==nil,"missing memory")
 let fallback=try Metrics.parse(Data(#"{"sys_power":0,"all_power":8}"#.utf8));expect(fallback.power==8 && fallback.powerLabel=="芯片功率","fallback label")
 var n=NetworkRate();expect(n.update(["en0":Counter(incoming:100,outgoing:50)],at:1).0==nil,"initial rate")
 let r=n.update(["en0":Counter(incoming:2100,outgoing:1050)],at:3);expect(r.0==1000 && r.1==500,"time delta")
 expect(n.update(["en1":Counter(incoming:9_000_000,outgoing:9_000_000)],at:4).0==nil,"new interface no spike")
 expect(n.update(["en1":Counter(incoming:1,outgoing:1)],at:5).0==nil,"counter reset")
 expect(n.update(["en1":Counter(incoming:500,outgoing:500)],at:30).0==nil,"sleep gap")
 expect(Metrics.rate(nil)=="—","missing speed");expect(Metrics.rate(1000)=="1.0 KB/s","speed unit")
 let decoded=try JSONDecoder().decode(Metrics.self,from:JSONEncoder().encode(m));expect(decoded.power==23,"snapshot roundtrip")
 print("PASS \(checks) metric/network checks")
}}
