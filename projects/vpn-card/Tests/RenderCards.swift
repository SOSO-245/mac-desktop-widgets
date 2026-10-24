import AppKit
import SwiftUI
@main struct RenderCards {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "/tmp/flclash-card-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for client in ProxyClient.allCases {
            for size in CardSize.allCases {
                var sample = MonitorSnapshot(client: client)
                sample.profileName = "示例套餐"; sample.usedBytes = 368.5 * 1073741824
                sample.expiresAt = Date().addingTimeInterval(64 * 86400 + 3600)
                sample.totalBytes = 1099511627776; sample.subscriptionUpdatedAt = Date()
                sample.nodeName = "🇺🇸 美国 04 | 流媒体 | 0.1x"; sample.isConnected = true
                sample.latencyMS = 190; sample.downloadBps = 123456; sample.uploadBps = 34567
                sample.speedHistory = (0..<30).map { Double(($0 * 11) % 23) * 4000 }
                sample.uploadSpeedHistory = sample.speedHistory.reversed()
                var readings: [String: SiteReading] = [:]
                for (index, site) in ProbeSite.all.enumerated() {
                    readings[site.id] = SiteReading.decode(output: "\(index == 4 ? 403 : 200) \(Double(index + 1) * 0.127)", exitCode: index == 5 ? 28 : 0)
                }
                let card = FlClashCard(size: size, siteReadings: readings, siteRoute: "\(client.title) · 按当前规则", onSize: {_ in}, menuSite: "Google", onMenuSite: {_ in}, onSiteRefresh: {_ in}, snapshot: sample, alwaysOnTop: false, positionLocked: true, onOpen: {}, onSwitch: {}, onRefresh: {}, onToggleTop: {}, onToggleLock: {}, onQuit: {}, onMenuSettings: {})
                let renderer = ImageRenderer(content: card)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("render") }
                try png.write(to: directory.appendingPathComponent("\(client.rawValue)-\(size.rawValue).png"))
            }
        }
        print(directory.path)
    }
}
