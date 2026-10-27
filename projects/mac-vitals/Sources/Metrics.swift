import Foundation
struct FanReading:Codable,Equatable { var name:String;var rpm:Double;var maxRPM:Double? }
struct Metrics: Codable {
    var date = Date.distantPast
    var chip = "本机 Mac"
    var systemPower: Double?, chipPower: Double?, cpu: Double?, memoryUsed: Double?, memoryTotal: Double?, cpuTemp: Double?, gpuTemp: Double?, download: Double?, upload: Double?
    var fans:[FanReading]?
    var thermalState:Int?, temperatureDisplayMood:Int?
    var history: [Double] = []
    var message = "正在读取"
    var power: Double? { systemPower ?? chipPower }
    var powerLabel: String { systemPower == nil ? "芯片功率" : "系统功率估算" }
    var memoryPercent: Double? { guard let u=memoryUsed,let t=memoryTotal,t>0 else {return nil};return min(100,max(0,u/t*100)) }
    func fresh(_ now:Date = Date())->Bool { let age=now.timeIntervalSince(date);return age >= -5 && age<90 }
    static let port: UInt16=18766
    static let kind="MacVitalsWidget"
    static func parse(_ data:Data)throws->Metrics {
        guard let d=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CocoaError(.coderReadCorrupt) }
        func number(_ v:Any?,max:Double = 1e15)->Double? {guard let n=v as? Double,n.isFinite,n>=0,n<=max else{return nil};return n}
        var s=Metrics();s.date=Date();s.message="实时更新"
        let p=number(d["sys_power"],max:1500);s.systemPower=p.flatMap{$0>0 ? $0:nil};s.chipPower=number(d["all_power"],max:500)
        s.cpu=number(d["cpu_active_ratio"],max:1).map{$0*100}
        let m=d["memory"] as? [String:Any] ?? [:];s.memoryUsed=number(m["ram_usage"]);s.memoryTotal=number(m["ram_total"])
        let t=d["temp"] as? [String:Any] ?? [:];s.cpuTemp=number(t["cpu_temp_avg"],max:130).flatMap{$0>0 ? $0:nil};s.gpuTemp=number(t["gpu_temp_avg"],max:130).flatMap{$0>0 ? $0:nil}
        if let soc=d["soc"] as? [String:Any],let name=soc["chip_name"] as? String {s.chip=String(name.prefix(60))}
        if let rows=d["fans"] as? [[String:Any]] {
            s.fans=rows.enumerated().compactMap { index,item in
                guard let rpm=number(item["rpm"],max:100000) else{return nil}
                return FanReading(name:String((item["name"] as? String ?? "fan\(index)").prefix(30)),rpm:rpm,maxRPM:number(item["max_rpm"],max:100000))
            }
        }
        return s
    }
    var fanText:String {
        guard let fans,!fans.isEmpty else{return "—"}
        return fans.enumerated().map{index,fan in (fans.count>1 ? "\(index+1): ":"")+String(format:"%.0f",fan.rpm)}.joined(separator:" · ")+" RPM"
    }
    static func temperatureMood(_ value:Double?,thermalState:Int?=nil)->Int {
        let base:Int
        if let value,value.isFinite,value>0,value<=130 {base=value<60 ? 0:value<75 ? 1:value<90 ? 2:value<95 ? 3:4}
        else {base = -1}
        switch thermalState {case 1:return max(base,2);case 2:return max(base,2);case 3:return 4;default:return base}
    }
    static func value(_ v:Double?,_ suffix:String="",decimals:Int=0)->String {guard let v,v.isFinite else{return "—"};return String(format:"%.*f",decimals,v)+suffix}
    static func rate(_ v:Double?)->String { guard let v,v.isFinite,v>=0 else{return "—"};if v>=1e6{return value(v/1e6," MB/s",decimals:1)};if v>=1e3{return value(v/1e3," KB/s",decimals:1)};return value(v," B/s") }
    static var sample:Metrics {var s=Metrics();s.date=Date();s.chip="Apple Silicon";s.systemPower=23.1;s.chipPower=10.1;s.cpu=21;s.memoryUsed=20e9;s.memoryTotal=32e9;s.cpuTemp=55;s.gpuTemp=49;s.download=2.6e6;s.upload=128e3;s.history=[12,13,18,16,21,20,23,22];s.message="示例数据";return s}
}
struct Counter:Equatable {var incoming:UInt64;var outgoing:UInt64}
struct NetworkRate {
    var previous:[String:Counter]=[:];var time:Double?
    mutating func update(_ counters:[String:Counter],at now:Double)->(Double?,Double?) {
        defer{previous=counters;time=now}
        guard let then=time,now>then,now-then<10 else{return(nil,nil)}
        var rx:Double=0,tx:Double=0;var valid=false
        for (key,v) in counters { guard let old=previous[key],v.incoming>=old.incoming,v.outgoing>=old.outgoing else{continue};valid=true;rx += Double(v.incoming-old.incoming);tx += Double(v.outgoing-old.outgoing) }
        return valid ? (rx/(now-then),tx/(now-then)):(nil,nil)
    }
}

/// Visual thresholds, not hardware limits. System thermal pressure has priority.
struct ThermalMoodFilter {
 private(set) var current = -1
 private var pending = -1, since=0.0
 mutating func update(temperature:Double?,system:Int?,at time:Double)->Int {
  let target=Metrics.temperatureMood(temperature,thermalState:system)
  guard target>=0 else {current = -1;pending = -1;return current}
  if current<0 || (system ?? 0)>=2 {current=target;pending = -1;return current}
  if target==current {pending = -1;return current}
  if target<current {
   let boundary=[60.0,75,90,95][max(0,min(3,current-1))]
   guard let temperature,temperature<=boundary-3 else {pending = -1;return current}
  }
  if pending != target {pending=target;since=time}
  if time-since >= (target>current ? 3:10) {current=target;pending = -1}
  return current
 }
}
