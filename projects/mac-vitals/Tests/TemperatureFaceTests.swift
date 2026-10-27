import Foundation
@main struct TemperatureFaceTests {
 static func main() throws {
  let values:[(Double?,Int)]=[(nil,-1),(Double.nan,-1),(-1,-1),(0,-1),(131,-1),(59.9,0),(60,1),(74.9,1),(75,2),(89.9,2),(90,3),(94.9,3),(95,4),(100,4)]
  for (v,m) in values {precondition(Metrics.temperatureMood(v)==m)}
  precondition(Metrics.temperatureMood(50,thermalState:1)==2)
  precondition(Metrics.temperatureMood(50,thermalState:2)==2)
  precondition(Metrics.temperatureMood(nil,thermalState:3)==4)
  var f=ThermalMoodFilter()
  precondition(f.update(temperature:74,system:0,at:0)==1)
  precondition(f.update(temperature:76,system:0,at:1)==1)
  precondition(f.update(temperature:76,system:0,at:4)==2)
  precondition(f.update(temperature:74,system:0,at:20)==2)
  precondition(f.update(temperature:71,system:0,at:21)==2)
  precondition(f.update(temperature:71,system:0,at:31)==1)
  precondition(f.update(temperature:71,system:3,at:32)==4)
  precondition(f.update(temperature:nil,system:0,at:33)==(-1))
  let bytes=try JSONSerialization.data(withJSONObject:["fans":[["name":"fan0","rpm":1001,"max_rpm":4900],["name":"fan1","rpm":0],["name":"invalid","rpm":-1]]])
  let data=try Metrics.parse(bytes)
  precondition(data.fans?.count==2 && data.fans?[0].rpm==1001 && data.fans?[1].rpm==0)
  precondition(data.fanText=="1: 1001 · 2: 0 RPM")
  let empty=try Metrics.parse(Data("{}".utf8));precondition(empty.fanText=="—")
  var old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(data)) as! [String:Any]
  for key in ["fans","thermalState","temperatureDisplayMood"] {old.removeValue(forKey:key)}
  let legacy=try JSONDecoder().decode(Metrics.self,from:JSONSerialization.data(withJSONObject:old));precondition(legacy.fans==nil)
  print("PASS 29 thermal thresholds, hysteresis, fan parsing and legacy snapshot checks")
 }
}
