import Foundation
import JavaScriptCore

/// Uses the existing Home Atlas charging model, with no network/OS bindings in JS.
/// Sessions stay in memory. Only the four combined numeric values enter the bridge.
struct GarageCalculator {
    static let cloudEntity="sensor.atlas_wall_connector_cloud"
    let script:String?
    init(script:String?=nil) {
        self.script=script ?? Bundle.main.url(forResource:"charging-model",withExtension:"js").flatMap{try? String(contentsOf:$0,encoding:.utf8)}
    }
    func combine(base:[String:Reading],cloud:Data?,now:Date=Date(),failure:String?=nil)->[String:Reading] {
        var result=base
        func unavailable(_ issue:String)->[String:Reading] {
            for metric in ExtraMetric.allCases where metric.garage {
                result[metric.rawValue]=Reading(value:nil,fetchedAt:now,partial:true,issue:issue)
            }
            return result
        }
        guard let cloud, let script,let state=try? JSONSerialization.jsonObject(with:cloud) as? [String:Any],let context=JSContext() else {
            return unavailable(failure ?? "家充数据不可用，无法合计")
        }
        // Export keywords are the only adaptation to execute the unchanged local module.
        context.evaluateScript(script.replacingOccurrences(of:"export ",with:""))
        guard context.exception == nil else { return unavailable("家充统计模块无法加载") }
        let function=context.evaluateScript("(function(state,key,now){ return chargingSummary({states:{[cloudEntity]:state}},key,now); })")
        let formatter=DateFormatter();formatter.timeZone=TimeZone(identifier:"Asia/Shanghai");formatter.dateFormat="yyyy-MM-dd"
        let day=formatter.string(from:now),month=String(day.prefix(7))
        for (key,energy,cost) in [(day,ExtraMetric.garageEnergyToday,ExtraMetric.garageCostToday),(month,.garageEnergyMonth,.garageCostMonth)] {
            guard let summary=function?.call(withArguments:[state,key,now.timeIntervalSince1970*1000])?.toDictionary(),
                  context.exception == nil,summary["fresh"] as? Bool == true,
                  let kwh=summary["kwh"] as? Double,kwh.isFinite,kwh >= 0 else {
                return unavailable("家充记录缺失或同步已过期，无法合计")
            }
            for (metric,increment) in [(energy,Optional(kwh)),(cost,summary["fee"] as? Double)] {
                let reading=base[metric.rawValue]
                guard let old=reading?.value,let increment,increment.isFinite,increment >= 0 else {
                    result[metric.rawValue]=Reading(value:nil,fetchedAt:now,partial:true,issue:"合计来源不完整或家充费率年度待核验")
                    continue
                }
                result[metric.rawValue]=Reading(value:old+increment,sourceTime:now,fetchedAt:now,partial:true)
            }
        }
        return result
    }
}
