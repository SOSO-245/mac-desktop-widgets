import AppKit
import SwiftUI

struct FlClashCard: View {
    var menuSurface=false
    let size: CardSize
    let siteReadings: [String: SiteReading]
    let siteRoute: String
    let onSize: (CardSize) -> Void
    let menuSite: String
    let onMenuSite: (String) -> Void
    let onSiteRefresh: (String?) -> Void

    let snapshot: MonitorSnapshot
    let alwaysOnTop: Bool
    let positionLocked: Bool
    let onOpen: () -> Void
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onToggleTop: () -> Void
    let onToggleLock: () -> Void
    let onQuit: () -> Void
    let onMenuSettings: () -> Void

    var onTrafficScope: (TrafficScope) -> Void = { _ in }
    var onAppearance:(()->Void)? = nil
    var onChooseNode: () -> Void = {}

    @State private var showsTrafficExplanation = false

    private let secondary = Color(red: 0.66, green: 0.72, blue: 0.83)
    private let cyan = Color(red: 0.38, green: 0.79, blue: 1)
    private let purple = Color(red: 0.66, green: 0.56, blue: 1)

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 24)
            if size == .small {
                compactContent
            } else {
                Spacer().frame(height: 8)
                subscription.frame(height: 27)
                Spacer().frame(height: 8)
                node.frame(height: 22)
                Spacer().frame(height: 9)
                speeds.frame(height: 38).help(snapshot.trafficHint)
                if size == .large { sitesContent }
            }
        }
        .padding(14)
        .frame(width: size.dimensions.width, height: size.dimensions.height, alignment: .top)
        .popover(isPresented: $showsTrafficExplanation) {
            VStack(alignment: .leading, spacing: 10) {
                Label("隧道总网速", systemImage: "info.circle").font(.headline)
                Text(snapshot.trafficHint)
                Text("仅代理／代理＋直连切换适用于 FlClash 和 Nikki。灰点表示当前统计范围不能拆分。")
                    .foregroundStyle(.secondary)
                Button("知道了") { showsTrafficExplanation = false }
            }.padding(18).frame(width: 280)
        }
        .foregroundStyle(.white)
        .background {
            if !menuSurface { ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.105, green: 0.125, blue: 0.23).opacity(0.97),
                        Color(red: 0.055, green: 0.075, blue: 0.14).opacity(0.97)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(RadialGradient(colors: [purple.opacity(0.14), .clear],
                                         center: .topLeading, startRadius: 0, endRadius: 280))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.065)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
        }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button(action: onOpen) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: snapshot.client.appPath))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("打开 \(snapshot.client.title)")
            .accessibilityLabel("打开 \(snapshot.client.title)")
            Text(snapshot.client.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
            if size != .small {
            Text("·")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondary.opacity(0.7))
            Text(snapshot.profileName ?? snapshot.metadataIssue ?? "等待激活套餐")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(subscriptionHint)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(snapshot.isConnected ? Color(red: 0.40, green: 0.87, blue: 0.68) : secondary)
                .frame(width: 5, height: 5)
                .help(snapshot.connectionState)
                .accessibilityLabel(snapshot.connectionState)
            Button(action: onToggleLock) {
                Image(systemName: positionLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(positionLocked ? cyan : secondary)
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(positionLocked ? "解锁位置后可拖动" : "锁定位置")
            .accessibilityLabel(positionLocked ? "解锁位置" : "锁定位置")
            if size != .small {
            ClientSwitchButton(otherClient: snapshot.client.other.title,
                               onSwitch: onSwitch, onChooseNode: onChooseNode)
                .frame(width: 20, height: 24)
            }

        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 3) {
                Text(snapshot.profileName ?? "等待套餐").lineLimit(1)
                Spacer(minLength: 0)
                Text(usagePercentage ?? "—").foregroundStyle(cyan)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
            node.frame(height: 22)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                compactSpeed("↓", value: snapshot.downloadBps, color: cyan)
                Spacer(minLength: 0)
                compactSpeed("↑", value: snapshot.uploadBps, color: purple)
            }
            Text("已用 \(storage(snapshot.usedBytes)) / \(storage(snapshot.totalBytes))")
                .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
        }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trafficDots: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(snapshot.client == .shadowrocket ? secondary : Color(red: 0.40, green: 1, blue: 0.68))
                .frame(width: 4, height: 4)
            if snapshot.client == .flclash && snapshot.trafficScope == .all {
                Circle().fill(purple).frame(width: 4, height: 4)
            }
        }.fixedSize().accessibilityHidden(true)
    }
    private var trafficHelp: String {
        snapshot.trafficLabel + "。" + snapshot.trafficHint + (snapshot.client == .flclash ? " 点击速度切换统计范围。" : " 点击查看统计说明。")
    }
    private func toggleTrafficScope() {
        guard snapshot.client == .flclash else { showsTrafficExplanation = true; return }
        onTrafficScope(snapshot.trafficScope == .all ? .proxyOnly : .all)
    }

    private func compactSpeed(_ arrow: String, value: Double?, color: Color) -> some View {
        let display = speed(snapshot.isConnected ? value : nil)
        return Button(action: toggleTrafficScope) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            trafficDots
            Text(arrow).foregroundStyle(color).font(.system(size: 12, weight: .bold))
            Text(display.value).font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(display.unit).font(.system(size: 9)).foregroundStyle(secondary)
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).contentShape(Rectangle())
        }.buttonStyle(.plain).help(trafficHelp)
            .accessibilityLabel((arrow == "↓" ? "下载" : "上传") + "速度，" + snapshot.trafficLabel)
            .accessibilityValue(display.value + " " + display.unit)
    }

    private var sitesContent: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5).padding(.top, 12)
            HStack {
                Text("站点延迟").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("每分钟").font(.system(size: 10)).foregroundStyle(secondary)
                Button { onSiteRefresh(nil) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 26)
                }.buttonStyle(.plain).help("重新检测全部站点").accessibilityLabel("重新检测全部站点")
            }.frame(height: 22).help(siteRoute + " · HTTPS 首响应，每分钟更新")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ProbeSite.all) { site in siteRow(site) }
            }.padding(.top, 6)
        }
    }

    private func siteRow(_ site: ProbeSite) -> some View {
        let reading = siteReadings[site.id] ?? SiteReading()
        let color: Color = reading.reachable ? Color.mint : reading.httpCode != nil ? .orange : reading.checkedAt != nil ? .red : secondary
        return Button { if !reading.busy { onSiteRefresh(site.id) } } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Text(site.id).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Circle().fill(color).frame(width: 4, height: 4)
                }.foregroundStyle(secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(reading.milliseconds.map(String.init) ?? (reading.busy && reading.checkedAt == nil ? "…" : "—"))
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                    if reading.milliseconds != nil {
                        Text("ms").font(.system(size: 10, weight: .medium))
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 9).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 61, maxHeight: 61, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .accessibilityLabel("检测 \(site.id)")
        .accessibilityValue(reading.milliseconds.map { "\($0) 毫秒，\(reading.status)" } ?? reading.status)
        .help("\(site.id) · \(reading.status)\n\(site.url)\n\(reading.checkedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "尚未检测")\n\(reading.httpCode.map { "HTTP \($0) · " } ?? "")点击重新检测")
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(storage(snapshot.usedBytes))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                Text("/ \(storage(snapshot.totalBytes))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(secondary)
                Spacer(minLength: 5)
                Text(SubscriptionCountdown.text(expiry:snapshot.expiresAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondary.opacity(0.9))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .lineLimit(1)
            .monospacedDigit()
            .frame(height: 16)
            Spacer().frame(height: 6)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.09))
                    if let fraction = usageFraction {
                        Capsule()
                            .fill(LinearGradient(colors: fraction >= 1 ? [.orange, .red] : [purple, cyan],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(1, max(0, fraction)))
                    }
                }
            }
            .frame(height: 5)
            .accessibilityLabel("套餐已用进度")
            .accessibilityValue(usagePercentage ?? "未知")
        }
        .help(subscriptionHint)
    }

    private var node: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.nodeName != nil ? "network" : "wifi.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(purple)
            Text(snapshot.nodeName.map { snapshot.isConnected ? $0 : "已选：\($0)" } ?? snapshot.metadataIssue ?? snapshot.connectionState)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(snapshot.isConnected ? .middle : .tail)
                .help(([snapshot.groupName, snapshot.nodeName].compactMap { $0 }.joined(separator: " → ") + "\n" + snapshot.connectionState))
            Spacer(minLength: 3)
            Text(snapshot.isConnected ? snapshot.connectionCount.map { "\($0) 连" } ?? "— 连" : "— 连")
                .font(.system(size:9,weight:.medium)).foregroundStyle(secondary).fixedSize()
                .help("当前活跃连接数").accessibilityLabel("当前连接数").accessibilityValue(snapshot.connectionCount.map(String.init) ?? "未知")
            if snapshot.isConnected {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 9, weight: .medium))
                    Text(snapshot.latencyMS.map(String.init) ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if snapshot.latencyMS != nil {
                        Text(snapshot.latencyKind.contains("TCP") ? "ms TCP" : "ms")
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                .foregroundStyle(latencyColor)
                .fixedSize()
                .help("\(snapshot.client.title) · \(snapshot.latencyKind)")
                .accessibilityLabel("节点延迟，\(snapshot.latencyKind)")
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.045), lineWidth: 0.5))
    }

    private var speeds: some View {
        HStack(spacing: 0) {
            speedColumn(title: "下载", symbol: "arrow.down", value: snapshot.downloadBps, color: cyan,
                        history: snapshot.isConnected ? snapshot.speedHistory : [])
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 30).padding(.horizontal, 12)
            speedColumn(title: "上传", symbol: "arrow.up", value: snapshot.uploadBps, color: purple,
                        history: snapshot.isConnected ? snapshot.uploadSpeedHistory : [])
        }
    }

    private func speedColumn(title: String, symbol: String, value: Double?, color: Color, history: [Double]) -> some View {
        let display = speed(snapshot.isConnected ? value : nil)
        return Button(action: toggleTrafficScope) {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                    Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                    trafficDots
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display.value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.identity)
                    Text(display.unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SpeedTrace(values: history, color: color)
                .frame(width: 56, height: 27)
                .padding(.top, 7)
                .help("最近 30 次\(title)速率采样")
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)速度，\(snapshot.trafficLabel)")
        .accessibilityValue("\(display.value) \(display.unit)")
        .help(trafficHelp)
    }

    private var usageFraction: Double? {
        guard let used = snapshot.usedBytes, let total = snapshot.totalBytes,
              used.isFinite, total.isFinite, used >= 0, total > 0 else { return nil }
        let result = used / total
        return result.isFinite ? result : nil
    }

    private var usagePercentage: String? {
        guard let fraction = usageFraction else { return nil }
        return fraction >= 9.99 ? "≥999%" : String(format: "%.0f%%", fraction * 100)
    }

    private var latencyColor: Color {
        guard snapshot.isConnected, let delay = snapshot.latencyMS else { return secondary }
        return delay < 200 ? Color(red: 0.53, green: 0.87, blue: 0.73) : delay < 500 ? .orange : .red
    }

    private var subscriptionHint: String {
        var hint = "当前激活套餐：\(snapshot.profileName ?? "未选择")\n订阅用量包括上传 + 下载"
        if let percentage = usagePercentage { hint += "\n已用：\(percentage)" }
        if let updated = snapshot.subscriptionUpdatedAt {
            hint += "\n套餐数据更新：\(dateText(updated))"
        }
        if let expiry = snapshot.expiresAt { hint += "\n到期日期：\(dateText(expiry))" }
        return hint
    }

    private func dateText(_ date: Date, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = compact ? "MM.dd" : "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private func storage(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = bytes
        var index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return "\(String(format: index == 0 ? "%.0f" : "%.1f", value)) \(units[index])"
    }

    private func speed(_ bytes: Double?) -> (value: String, unit: String) {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return ("—", "") }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytes
        var index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return (String(format: index == 0 || value >= 100 ? "%.0f" : "%.1f", value), units[index])
    }
}

private struct SpeedTrace: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let samples = values.suffix(30).map { $0.isFinite ? max(0, $0) : 0 }
            guard !samples.isEmpty else { return }
            let peak = max(1024, samples.max() ?? 0)
            let points = samples.enumerated().map { index, value in
                CGPoint(x: 1 + (size.width - 3) * Double(30 - samples.count + index) / 29,
                        y: size.height - 2 - (size.height - 4) * value / peak)
            }
            guard let first = points.first, let last = points.last else { return }
            var line = Path()
            line.addLines(points)
            var fill = line
            fill.addLine(to: CGPoint(x: last.x, y: size.height))
            fill.addLine(to: CGPoint(x: first.x, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0.01)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: last.x - 1.5, y: last.y - 1.5, width: 3, height: 3)),
                         with: .color(color))
        }
    }
}
