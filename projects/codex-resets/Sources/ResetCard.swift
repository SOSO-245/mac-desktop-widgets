import SwiftUI

enum CardSize: CaseIterable {
    case small, medium, large
    var width: Double { self == .small ? 164 : 344 }
    var height: Double { self == .large ? 344 : 164 }
}
struct ResetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.21), Color(red: 0.045, green: 0.075, blue: 0.13), Color(red: 0.13, green: 0.13, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { RadialGradient(colors: [Color.mint.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 260) }
    }
}
struct ResetCard: View {
    let snapshot: ResetSnapshot
    let size: CardSize
    var now: Date = Date()
    var refresh: AnyView? = nil
    private let mint = Color(red: 0.57, green: 0.94, blue: 0.79)
    private let muted = Color(red: 0.63, green: 0.72, blue: 0.79)
    private var isSmall: Bool { size == .small }
    private var stale: Bool { snapshot.isStale(at: now) && !snapshot.isSample }
    private var phase: ResetPhase { snapshot.phase(at: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if size == .small { smallContent }
            else if size == .medium { mediumContent }
            else { largeContent }
        }
        .padding(isSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .overlay { ContainerRelativeShape().inset(by: 1).strokeBorder(LinearGradient(colors: [mint.opacity(0.5), .white.opacity(0.05), Color.purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
    }
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: isSmall ? 12 : 14, weight: .semibold)).foregroundStyle(mint)
            Text("Codex 重置").font(.system(size: isSmall ? 13 : 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            if !isSmall {
                HStack(spacing: 4) {
                    Circle().fill(stale ? Color.orange : mint).frame(width: 4, height: 4)
                    Text(updateLabel).font(.system(size: 9, weight: .medium))
                    if let refresh { refresh } else { Image(systemName: "arrow.clockwise").font(.system(size: 9)) }
                }.foregroundStyle(muted).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.06), in: Capsule())
            } else if let refresh { refresh.foregroundStyle(muted) }
        }
    }
    private var updateLabel: String {
        if snapshot.isSample { return "示例" }
        guard let checked = snapshot.checkedAt else { return snapshot.freshness(at: now) }
        return formatted(checked, "HH:mm") + (stale ? " 缓存" : " 更新")
    }
    private var phaseTitle: String {
        switch phase {
        case .scheduled: return stale ? "计划倒计时 · 缓存" : "计划重置倒计时"
        case .awaitingConfirmation: return "已到计划时间"
        case .unscheduledTime: return "已公布重置计划"
        case .watching: return "重置动态"
        case .noSchedule: return "暂无重置计划"
        case .unavailable: return "公告追踪"
        }
    }
    @ViewBuilder private func headline(fontSize: CGFloat) -> some View {
        switch phase {
        case .scheduled(let date):
            Text(timerInterval: now...max(now, date), countsDown: true, showsHours: true)
                .font(.system(size: fontSize, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(mint).lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: fontSize * 1.2, alignment: .leading)
                .accessibilityLabel("距计划重置时间").accessibilityValue(Text(date, style: .relative))
        case .awaitingConfirmation: stateText("待确认", fontSize)
        case .unscheduledTime: stateText("时间待定", fontSize - 5)
        case .watching: stateText("观察中", fontSize - 3)
        case .noSchedule:
            if let last = snapshot.status?.latestReset?.announcedAt {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", max(0, now.timeIntervalSince(last) / 86400))).font(.system(size: fontSize, weight: .light, design: .rounded)).monospacedDigit()
                    Text("天").font(.system(size: 12))
                }.foregroundStyle(mint)
            } else { stateText("暂无记录", fontSize - 5) }
        case .unavailable: stateText("—", fontSize)
        }
    }
    private func stateText(_ value: String, _ size: CGFloat) -> some View {
        Text(value).font(.system(size: size, weight: .light)).foregroundStyle(mint).lineLimit(1).minimumScaleFactor(0.7)
    }
    private var detail: String {
        switch phase {
        case .scheduled(let date): return "计划 " + formatted(date, "M月d日 HH:mm")
        case .awaitingConfirmation: return "等待源站确认执行"
        case .unscheduledTime: return "等待公布具体时间"
        case .watching: return "站点观察，尚未确认"
        case .noSchedule: return snapshot.status?.latestReset == nil ? "等待首条记录" : "距最近重置记录"
        case .unavailable: return snapshot.issue == nil ? "正在读取公开数据" : "暂时无法连接"
        }
    }
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phaseTitle).font(.system(size: 10)).foregroundStyle(muted).padding(.top, 13)
            headline(fontSize: 31)
            Text(detail).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Text("公告追踪").foregroundStyle(muted)
                Spacer(minLength: 0)
                Text(snapshot.isSample ? "示例" : snapshot.status == nil ? snapshot.freshness(at: now) : stale ? "缓存" : "非个人额度").foregroundStyle(muted.opacity(0.9))
            }.font(.system(size: 8))
            Text("数据：Codex Resets ↗").font(.system(size: 8)).foregroundStyle(muted.opacity(0.7))
        }
    }
    private var mediumContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseTitle).font(.system(size: 10)).foregroundStyle(muted)
                    headline(fontSize: 32)
                    Text(detail).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("当前时间").font(.system(size: 10)).foregroundStyle(muted)
                    Text(formatted(now, "HH:mm")).font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                    HStack(spacing: 4) {
                        Text("最近").foregroundStyle(muted)
                        Text(lastDate).foregroundStyle(.white)
                    }.font(.system(size: 10))
                }.frame(width: 108, alignment: .trailing)
            }.padding(.top, 12)
            Spacer(minLength: 4)
            footer
        }
    }
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(phaseTitle).font(.system(size: 11)).foregroundStyle(muted).padding(.top, 18)
            HStack(alignment: .bottom, spacing: 12) {
                headline(fontSize: 43).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前时间").font(.system(size: 10)).foregroundStyle(muted)
                    Text(formatted(now, "HH:mm")).font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                }
            }.padding(.top, 3)
            HStack(spacing: 2) {
                Text(detail)
                if case .scheduled = phase { Text("· " + (TimeZone.current.abbreviation() ?? TimeZone.current.identifier)) }
            }.font(.system(size: 10)).foregroundStyle(muted).padding(.top, 2)
            HStack(spacing: 0) {
                stat("最近一次", lastDate)
                Spacer(minLength: 8)
                stat("累计重置", snapshot.status.map { "\($0.stats.total) 次" } ?? "—")
                Spacer(minLength: 8)
                stat("平均间隔", snapshot.status?.stats.avgIntervalDays.map { String(format: "%.1f 天", $0) } ?? "—")
            }.padding(.top, 19)
            Rectangle().fill(.white.opacity(0.11)).frame(height: 0.5).padding(.top, 15).padding(.bottom, 11)
            HStack { Text("最近记录"); Spacer(); Text("本地时间") }.font(.system(size: 9, weight: .medium)).foregroundStyle(muted)
            if snapshot.history.isEmpty {
                Text(snapshot.status == nil ? "连接后显示重置公告" : snapshot.issue != nil ? "历史暂时无法更新" : "暂无历史记录")
                    .font(.system(size: 11)).foregroundStyle(muted).frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 9) {
                    ForEach(snapshot.history.prefix(3)) { event in
                        HStack(spacing: 7) {
                            Circle().fill(mint.opacity(0.7)).frame(width: 4, height: 4)
                            Text(formatted(event.announcedAt, "MM/dd  HH:mm")).monospacedDigit()
                            Spacer()
                            Text(event.typeLabel).foregroundStyle(muted)
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(mint)
                        }.font(.system(size: 11))
                    }
                }.padding(.top, 11)
                Spacer(minLength: 7)
            }
            footer
        }
    }
    private var lastDate: String { snapshot.status?.latestReset.map { formatted($0.announcedAt, "MM/dd HH:mm") } ?? "—" }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9)).foregroundStyle(muted)
            Text(value).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private var footer: some View {
        HStack(spacing: 4) {
            Text("数据：Codex Resets ↗")
            Spacer(minLength: 0)
            Text("公告追踪 · 非个人额度")
        }.font(.system(size: 8)).foregroundStyle(muted.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.9)
    }
    private func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = format; return f.string(from: date)
    }
}
