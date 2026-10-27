import AppKit
import SwiftUI
import ServiceManagement

struct VitalsGeneralSettings:View {
    @ObservedObject var app:VitalsDelegate
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("启动与运行").font(.headline)
            Toggle("登录时自动启动",isOn:Binding(get:{app.loginEnabled},set:app.setLogin))
            if !app.loginNote.isEmpty {Text(app.loginNote).font(.callout).foregroundStyle(.secondary)}
            Text("隐藏桌面卡片后，菜单栏、数据采集与桌面小组件继续运行。").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Mac 实时监测").font(.headline)
            Text("在桌面与菜单栏查看这台 Mac 的运行状态。设置独立保存在本机，修改后立即生效。").foregroundStyle(.secondary)
        }.onAppear {app.refreshLogin()}
    }
}

struct VitalsDesktopSettings:View {
    @ObservedObject var app:VitalsDelegate
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Toggle("显示桌面卡片",isOn:Binding(get:{!app.hidden},set:app.setCardVisible))
            Picker("卡片尺寸",selection:Binding(get:{app.size},set:app.setCardSize)) {
                Text("小号").tag("small");Text("中号").tag("medium");Text("大号").tag("large")
            }.pickerStyle(.segmented)
            Toggle("锁定卡片位置",isOn:Binding(get:{app.locked},set:app.setCardLocked))
            Toggle("置于其他窗口上方",isOn:Binding(get:{app.top},set:app.setCardTop))
            Button("移到屏幕中央",action:app.centerCard)
            Divider()
            DesktopAppearanceSettings(model:.shared)
        }
    }
}

struct VitalsDataSettings:View {
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("数据更新").font(.headline)
            Text("菜单栏与卡片每秒更新；系统桌面小组件请求每分钟更新，实际时间由 macOS 调度。").foregroundStyle(.secondary)
            Divider()
            Text("数据说明").font(.headline)
            Text("系统功率为传感器估算，不含外接显示器，也不是插座实测；无法取得时显示芯片功率。")
            Text("CPU 为活跃时间占比。网速合计活跃物理网卡，避免 VPN 重复计数。")
            Text("不可用或过期的数据会显示为待采集，不沿用旧值冒充实时数据。")
            Divider()
            Text("采集器：macmon v0.10.0 · MIT").font(.callout).foregroundStyle(.secondary)
            Link("查看采集器项目",destination:URL(string:"https://github.com/vladkens/macmon")!)
        }
    }
}
