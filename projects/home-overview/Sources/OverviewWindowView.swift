import SwiftUI

/// The Mac app and its desktop widgets share the same live, read-only store.
struct OverviewWindowView: View {
    @ObservedObject var store: EnergyStore
    let showSettings: () -> Void
    let openWebsite: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().overlay(.white.opacity(0.06))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ResponsiveOverview(data: HomeSnapshot.live(
                        core: store.snapshot,
                        details: store.overviewDetails,
                        now: context.date
                    ))
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(AtlasStyle.ink)
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Label("家庭概览", systemImage: "house")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasStyle.secondary)
            if store.busy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                    .accessibilityLabel("正在更新家庭数据")
            }
            if let issue = store.brokerIssue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(issue)
            }
            Spacer(minLength: 12)
            Button(action: showSettings) {
                Label("连接设置", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("管理 Home Assistant 连接和桌面小组件")
            Button(action: openWebsite) {
                Label("HA 网页", systemImage: "arrow.up.right.square")
            }
            .help("在默认浏览器中打开 Home Assistant")
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Label(store.busy ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.busy)
            .help("读取最新家庭数据")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.035))
    }
}

/// Cards adapt to the available width independently; narrow windows scroll vertically.
private struct ResponsiveOverview:View {
    let data:HomeSnapshot
    var body:some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 40, 1)
            let wide = width >= 1060
            let gap:CGFloat = 18
            ZStack {
                AtlasBackdrop()
                ScrollView(.vertical) {
                    VStack(spacing:gap) {
                        if wide {
                            fitted(width:width,baseWidth:1760,height:104) {
                                AtlasHeader(data:data)
                            }
                        } else {
                            HStack {
                                Text("家庭概览").font(.system(size:28,weight:.semibold))
                                Spacer()
                                Text(data.dateText).font(.system(size:14)).foregroundStyle(AtlasStyle.secondary)
                            }
                            fitted(width:width,baseWidth:900,height:104) {
                                HStack { WeatherSummary(data:data); Spacer(); Text(data.status).foregroundStyle(AtlasStyle.secondary) }
                            }
                        }
                        if wide {
                            let left = (width-gap) * 0.59
                            HStack(alignment:.top,spacing:gap) {
                                fitted(width:left,baseWidth:1028,height:450) { EnergyPanel(data:data) }
                                fitted(width:width-gap-left,baseWidth:708,height:450) { EnvironmentPanel(data:data) }
                            }
                            let small = (width-gap*2) * 0.29
                            HStack(alignment:.top,spacing:gap) {
                                fitted(width:small,baseWidth:502,height:328) { GaragePanel(data:data) }
                                fitted(width:small,baseWidth:502,height:328) { ChargingPanel(data:data) }
                                fitted(width:width-gap*2-small*2,baseWidth:708,height:328) { NASPanel(data:data) }
                            }
                        } else {
                            fitted(width:width,baseWidth:1028,height:450) { EnergyPanel(data:data) }
                            fitted(width:width,baseWidth:708,height:450) { EnvironmentPanel(data:data) }
                            HStack(alignment:.top,spacing:gap) {
                                fitted(width:(width-gap)/2,baseWidth:502,height:328) { GaragePanel(data:data) }
                                fitted(width:(width-gap)/2,baseWidth:502,height:328) { ChargingPanel(data:data) }
                            }
                            fitted(width:width,baseWidth:708,height:328) { NASPanel(data:data) }
                        }
                    }.padding(20)
                }
            }
        }.foregroundStyle(.white)
    }
    private func fitted<Content:View>(width:CGFloat,baseWidth:CGFloat,height:CGFloat,@ViewBuilder content:()->Content)->some View {
        let scale = width/baseWidth
        return content().frame(width:baseWidth,height:height)
            .scaleEffect(scale,anchor:.topLeading)
            .frame(width:width,height:height*scale,alignment:.topLeading)
    }
}
