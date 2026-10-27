import SwiftUI

/// Native adaptation of Electric Border CSS's moving turbulence/displacement + glow.
/// Reference: hammadxcm/electric-border-css (MIT, Fyniti 2025).
/// No embedded webpage, network requests, random per-frame jumps or text flashing.
struct ResetElectricBorder: View {
    var color: Color
    var cornerRadius: CGFloat
    // Fixed time is used only for deterministic, offline render verification.
    var fixedTime: Double? = nil
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:fixedTime != nil)) { timeline in
            Canvas { context,size in
                let time=fixedTime ?? timeline.date.timeIntervalSinceReferenceDate
                let path=Self.electricPath(size:size,radius:cornerRadius,time:time)
                var halo=context
                halo.addFilter(.blur(radius:3.0))
                halo.stroke(path,with:.color(color.opacity(0.6)),lineWidth:3.8)
                var glow=context
                glow.addFilter(.blur(radius:0.9))
                glow.stroke(path,with:.color(color.opacity(0.95)),lineWidth:2.2)
                context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:0.95,lineCap:.round,lineJoin:.round))
                context.stroke(path,with:.color(.white.opacity(0.72)),style:StrokeStyle(lineWidth:0.35,lineCap:.round,lineJoin:.round))
            }
        }
    }
    static func electricPath(size:CGSize,radius:CGFloat,time:Double)->Path {
        guard size.width>16,size.height>16 else{return Path()}
        // Inset keeps the bright strand inside the clipped NSPanel at all sizes.
        let rect=CGRect(origin:.zero,size:size).insetBy(dx:6,dy:6)
        let r=min(max(1,radius-6),min(rect.width,rect.height)/2)
        let horizontal=rect.width-2*r,vertical=rect.height-2*r,arc=CGFloat.pi*r/2
        let lengths=[horizontal,arc,vertical,arc,horizontal,arc,vertical,arc]
        let total=lengths.reduce(0,+),count=max(128,Int(total/0.9))
        var path=Path()
        for index in 0..<count {
            var distance=total*CGFloat(index)/CGFloat(count),segment=0
            while segment<7 && distance>lengths[segment] {distance-=lengths[segment];segment+=1}
            var point:CGPoint
            switch segment {
            case 0:point=CGPoint(x:rect.minX+r+distance,y:rect.minY)
            case 2:point=CGPoint(x:rect.maxX,y:rect.minY+r+distance)
            case 4:point=CGPoint(x:rect.maxX-r-distance,y:rect.maxY)
            case 6:point=CGPoint(x:rect.minX,y:rect.maxY-r-distance)
            default:
                let corner=(segment-1)/2
                let centers=[CGPoint(x:rect.maxX-r,y:rect.minY+r),CGPoint(x:rect.maxX-r,y:rect.maxY-r),CGPoint(x:rect.minX+r,y:rect.maxY-r),CGPoint(x:rect.minX+r,y:rect.minY+r)]
                let angle = -CGFloat.pi/2+CGFloat(corner)*CGFloat.pi/2+distance/r
                point=CGPoint(x:centers[corner].x+r*cos(angle),y:centers[corner].y+r*sin(angle))
            }
            let x=Double(point.x)*0.065,y=Double(point.y)*0.065
            // Two independently moving noise channels displace both coordinates,
            // like SVG feTurbulence + feDisplacementMap, with bounded amplitude.
            let dx=turbulence(x:x+time*0.7,y:y-time*0.9,seed:1)
            let dy=turbulence(x:x-time*0.8,y:y+time*0.6,seed:9)
            point.x+=CGFloat(dx*3.8);point.y+=CGFloat(dy*3.8)
            if index==0 {path.move(to:point)} else {path.addLine(to:point)}
        }
        path.closeSubpath()
        return path
    }
    private static func turbulence(x:Double,y:Double,seed:Int)->Double {
        var result=0.0,amplitude=0.45,frequency=1.0
        for octave in 0..<5 {
            result+=noise(x:x*frequency,y:y*frequency,seed:seed+octave*13)*amplitude
            amplitude*=0.65;frequency*=2
        }
        return result
    }
    private static func noise(x:Double,y:Double,seed:Int)->Double {
        let ix=Int(floor(x)),iy=Int(floor(y)),fx=x-floor(x),fy=y-floor(y)
        let u=fx*fx*(3-2*fx),v=fy*fy*(3-2*fy)
        func hash(_ x:Int,_ y:Int)->Double {
            var n=UInt64(bitPattern:Int64(x)) &* 374761393 &+ UInt64(bitPattern:Int64(y)) &* 668265263 &+ UInt64(seed) &* 69069
            n=(n ^ (n>>13)) &* 1274126177
            return Double((n ^ (n>>16)) & 65535)/32767.5-1
        }
        let a=hash(ix,iy),b=hash(ix+1,iy),c=hash(ix,iy+1),d=hash(ix+1,iy+1)
        return (a+(b-a)*u)*(1-v)+(c+(d-c)*u)*v
    }
}

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
    var menuSurface=false
    var desktopSurface=false
    let snapshot: ResetSnapshot
    let size: CardSize
    var now: Date = Date()
    var refresh: AnyView? = nil
    var activity: AnyView? = nil
    var liveWebsite:URL? = nil
    var acknowledge:(()->Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pink=Color(red:1,green:0.59,blue:0.24)
    private var explicitPlan:Bool {
        switch phase {case .scheduled,.awaitingConfirmation:return true;default:return false}
    }
    private let mint = Color(red: 0.57, green: 0.94, blue: 0.79)
    private let muted = Color(red: 0.63, green: 0.72, blue: 0.79)
    private var isSmall: Bool { size == .small }
    private var stale: Bool { snapshot.isStale(at: now) && !snapshot.isSample }
    private var phase: ResetPhase { snapshot.phase(at: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            phaseHeading
            if let liveWebsite, !isSmall {
                Link(destination:liveWebsite) {mainContent.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).contentShape(Rectangle())}.buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("打开 Codex Resets 网页")
            } else {mainContent}
            if let activity {
                activity.padding(.top,4)
                if isSmall {smallContext.padding(.top,4)}
            }
        }
        .padding(isSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keep desktop borders inside the panel even when content has a taller ideal size.
        .frame(width: desktopSurface ? size.width : nil, height: desktopSurface ? size.height : nil)
        .foregroundStyle(.white)
        .overlay { if !menuSurface { ContainerRelativeShape().inset(by: 1).strokeBorder(LinearGradient(colors: [mint.opacity(0.5), .white.opacity(0.05), Color.purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75).allowsHitTesting(false) } }
        .background {
            if explicitPlan {RadialGradient(colors:[pink.opacity(0.06),.clear],center:.topLeading,startRadius:0,endRadius:isSmall ? 200:380).allowsHitTesting(false)}
        }
        .overlay {
            if explicitPlan {
                if acknowledge != nil && !reduceMotion {
                    ResetElectricBorder(color:pink,cornerRadius:desktopSurface ? 28:23)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    ContainerRelativeShape().inset(by:1.5).strokeBorder(pink.opacity(0.45),lineWidth:1.2).allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private var mainContent:some View {
        if size == .small {smallContent} else if size == .medium {mediumContent} else {largeContent}
    }
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: isSmall ? 12 : 14, weight: .semibold)).foregroundStyle(mint)
            Text("Codex 重置").font(.system(size: isSmall ? 13 : 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            if !isSmall {
                HStack(spacing: 4) {
                    Circle().fill(stale ? Color.orange : mint).frame(width: 4, height: 4)
                    Text(activity == nil ? updateLabel : snapshot.checkedAt.map { formatted($0,"HH:mm") } ?? "—").font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
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
    private var phaseHeading:some View {
        HStack(spacing:4) {
            Text(acknowledge != nil && phase != .awaitingConfirmation ? "重置倒计时":phaseTitle)
                .font(.system(size:isSmall ? 10:11,weight:explicitPlan ? .semibold:.regular))
                .foregroundStyle(explicitPlan ? pink:muted).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength:2)
            if let acknowledge {
                Button(action:acknowledge) {Text("知道了").font(.system(size:8,weight:.semibold)).padding(.horizontal,5).padding(.vertical,3)}
                    .buttonStyle(.plain).foregroundStyle(pink).background(pink.opacity(0.13),in:Capsule())
                    .focusEffectDisabled().help("确认本次计划，停止电纹；新计划会再次提醒")
            }
        }.padding(.top,isSmall ? 8:size == .medium ? 12:18)
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
                .foregroundStyle(pink).lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: fontSize * 1.2, alignment: .leading)
                .accessibilityLabel("距计划重置时间").accessibilityValue(Text(date, style: .relative))
        case .awaitingConfirmation: stateText("待确认", fontSize).foregroundStyle(pink)
        case .unscheduledTime: stateText("时间待定", fontSize - 5)
        case .watching: stateText("观察中", fontSize - 3)
        case .noSchedule:
            if let last = snapshot.status?.latestReset?.announcedAt {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", max(0, now.timeIntervalSince(last) / 86400))).font(.system(size: fontSize, weight: .light, design: .rounded)).monospacedDigit()
                    Text("天").font(.system(size: isSmall ? 15:12))
                }.foregroundStyle(mint)
            } else { stateText("暂无记录", fontSize - 5) }
        case .unavailable: stateText("—", fontSize)
        }
    }
    private func stateText(_ value: String, _ size: CGFloat) -> some View {
        Text(value).font(.system(size: size, weight: .light)).foregroundStyle(explicitPlan ? pink:mint).lineLimit(1).minimumScaleFactor(0.7)
    }
    private var detail: String {
        switch phase {
        case .scheduled(let date): return "计划 " + formatted(date, "M月d日 HH:mm")
        case .awaitingConfirmation: return "等待源站确认执行"
        case .unscheduledTime: return "等待公布具体时间"
        case .watching: return "站点观察，尚未确认"
        case .noSchedule: return snapshot.status?.latestReset == nil ? "等待首条记录" : ""
        case .unavailable: return snapshot.issue == nil ? "正在读取公开数据" : "暂时无法连接"
        }
    }
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let liveWebsite {
                Link(destination:liveWebsite) {headline(fontSize:explicitPlan ? 35:43)}.buttonStyle(.plain).focusEffectDisabled()
            } else {headline(fontSize:explicitPlan ? 35:43)}
            recentResetRow
            Group {if !detail.isEmpty {Text(detail).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)}}
            Spacer(minLength: 0)
            if activity == nil {
                smallContext
                Text("数据：Codex Resets ↗").font(.system(size: 8)).foregroundStyle(muted.opacity(0.7))
            }
        }.background {
            if let liveWebsite {Link(destination:liveWebsite) {Color.clear.contentShape(Rectangle())}.buttonStyle(.plain)}
        }
    }
    @ViewBuilder private var recentResetRow:some View {
        if let event=snapshot.status?.latestReset ?? snapshot.history.max(by:{$0.announcedAt<$1.announcedAt}) {
            HStack(spacing:4) {
                Text("最近重置 "+formatted(event.announcedAt,"MM/dd HH:mm"))
                    .font(.system(size:8,weight:.medium)).foregroundStyle(muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength:0)
                if let url=ResetNavigation.originalPostURL(event.source.url) {
                    Link(destination:url) {Text("𝕏").font(.system(size:13,weight:.medium)).frame(width:20,height:20).contentShape(Rectangle())}
                        .buttonStyle(.plain).focusEffectDisabled().foregroundStyle(.white.opacity(0.85))
                        .help("查看本次重置公告原帖").accessibilityLabel("在 X 查看最近重置公告原帖")
                }
            }
        }
    }
    private var smallContext:some View {
        HStack(spacing:3) {
            Text("公告追踪").foregroundStyle(muted)
            Spacer(minLength:0)
            Text(snapshot.isSample ? "示例" : snapshot.status == nil ? snapshot.freshness(at:now) : stale ? "缓存" : "非个人额度").foregroundStyle(muted.opacity(0.9))
        }.font(.system(size:8))
    }
    private var mediumContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    headline(fontSize: 32)
                    Group {if !detail.isEmpty {Text(detail).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)}}
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("当前时间").font(.system(size: 10)).foregroundStyle(muted)
                    Text(formatted(now, "HH:mm")).font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                    HStack(spacing: 4) {
                        Text("最近").foregroundStyle(muted)
                        Text(lastDate).foregroundStyle(.white)
                    }.font(.system(size: 10))
                }.frame(width: 108, alignment: .trailing)
            }.padding(.top, 3)
            Spacer(minLength: 4)
            footer
        }
    }
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        Group {if activity == nil {standardFooter}}
    }
    private var standardFooter: some View {
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
