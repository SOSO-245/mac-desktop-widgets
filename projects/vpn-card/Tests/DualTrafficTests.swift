import Foundation
@main struct DualTests {
 static func main() throws {
  var count=0
  func check(_ b:Bool,_ msg:String){count+=1;precondition(b,msg)}
  func data(_ up:Int,_ down:Int,_ pu:Int,_ pd:Int,_ include:Bool=true)->Data {
   let rows:[[String:Any]]=include ? [["id":"proxy","upload":pu,"download":pd,"chains":["node","group"]],["id":"direct","upload":8000,"download":9000,"chains":["DIRECT"]]]:[]
   return try! JSONSerialization.data(withJSONObject:["uploadTotal":up,"downloadTotal":down,"connections":rows])
  }
  let date=Date(timeIntervalSince1970:1000);var s=DualTrafficSampler()
  let first=s.sample(data(1000,2000,100,200),proxyTypes:[:],time:10,date:date)!
  check(first.allDown==nil && first.proxyDown==nil,"first observation is unknown")
  let p=s.sample(data(1500,3000,150,300),proxyTypes:[:],time:11,date:date.addingTimeInterval(1))!
  check(p.allDown==1000 && p.allUp==500,"core cumulative counters yield total speed")
  check(p.proxyDown==100 && p.proxyUp==50,"only proxy connections contribute")
  let closed=s.sample(data(1900,3800,0,0,false),proxyTypes:[:],time:12,date:date.addingTimeInterval(2))!
  check(closed.allDown==800 && closed.allUp==400,"closed connections never remove core total")
  check(closed.proxyDown==0,"no active proxy connection is measured zero")
  let reset=s.sample(data(0,0,0,0,false),proxyTypes:[:],time:13,date:date.addingTimeInterval(3))!
  check(reset.allDown==nil,"counter reset never produces negative speed")
  let restored=s.sample(data(10,20,0,0,false),proxyTypes:[:],time:14,date:date.addingTimeInterval(4))!
  check(restored.allDown==20,"counter reset rebaselines")
  let missing=try JSONSerialization.data(withJSONObject:["connections":[]])
  check(s.sample(missing,proxyTypes:[:],time:15,date:date.addingTimeInterval(5))!.allDown==nil,"missing total is not fabricated zero")
  let bool=try JSONSerialization.data(withJSONObject:["uploadTotal":true,"downloadTotal":true,"connections":[]])
  check(s.sample(bool,proxyTypes:[:],time:16,date:date.addingTimeInterval(6))!.allDown==nil,"booleans rejected")
  check(s.sample(Data("bad".utf8),proxyTypes:[:],time:17)==nil,"malformed payload resets")
  var m=MonitorSnapshot();m.trafficScope = .proxyOnly;m.recordTrafficComparison(p)
  check(m.downloadBps==100 && m.uploadBps==50,"proxy active numeric matches foreground")
  m.trafficScope = .all;m.selectTrafficComparison()
  check(m.downloadBps==1000 && m.trafficComparison?.count==1,"switch immediately keeps both aligned histories")
  for _ in 0..<40 {m.recordTrafficComparison(p)}
  check(m.trafficComparison?.count==30,"bounded 30 paired samples")
  check(m.trafficComparison!.allSatisfy{$0.value(proxy:false,upload:false)==1000 && $0.value(proxy:true,upload:false)==100},"pair order preserved")
  print("PASS \(count) paired rate and mode-switch checks")
 }
}
