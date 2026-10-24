import Foundation

struct NikkiWidgetSite: Codable {
    var name: String
    var milliseconds: Int?
    var status: String
    var checkedAt: Date?
}
struct NikkiWidgetData: Codable {
    var snapshot = MonitorSnapshot()
    var sites: [NikkiWidgetSite] = []
    var generatedAt = Date.distantPast
    static let port: UInt16 = 18765
    static let kind = "NikkiDesktopWidget"
    func isFresh(at date: Date) -> Bool { (0...90).contains(date.timeIntervalSince(generatedAt)) && snapshot.isConnected }
    static var sample: Self {
        var value = Self()
        value.generatedAt = Date(); value.snapshot.profileName = "示例套餐"
        value.snapshot.nodeName = "示例节点"; value.snapshot.usedBytes = 360e9; value.snapshot.totalBytes = 1e12
        value.snapshot.downloadBps = 2.4e6; value.snapshot.uploadBps = 120e3
        value.snapshot.latencyMS = 128; value.snapshot.isConnected = true
        value.sites = ["Google","GitHub","YouTube","ChatGPT","Claude","bilibili"].enumerated().map {
            NikkiWidgetSite(name:$0.element,milliseconds:80 + $0.offset * 37,status:"响应",checkedAt:Date())
        }
        return value
    }
}
