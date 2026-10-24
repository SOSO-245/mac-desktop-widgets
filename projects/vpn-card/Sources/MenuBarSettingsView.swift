import SwiftUI

struct MenuBarSettingsView: View {
    @State private var options = MenuBarOptions.load()
    @State private var palette = MenuBarPalette.load()
    let onSave: (MenuBarOptions) -> Void
    private func binding(_ path: WritableKeyPath<MenuBarPalette,String>) -> Binding<Color> {
        Binding(get:{Color(nsColor:MenuBarPalette.color(palette[keyPath:path]))},set:{palette[keyPath:path]=MenuBarPalette.hex(NSColor($0))})
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("菜单栏显示",systemImage:"menubar.rectangle").font(.title2.bold())
            Text("勾选你需要的信息，保存后立即生效。").foregroundStyle(.secondary)
            HStack(spacing:32) {
                VStack(alignment:.leading,spacing:12) {
                    Toggle("站点图标",isOn:$options.icon)
                    Toggle("站点名称",isOn:$options.site)
                    Toggle("站点延迟",isOn:$options.latency)
                    Toggle("套餐名称",isOn:$options.profile)
                    Toggle("当前节点",isOn:$options.node)
                }
                VStack(alignment:.leading,spacing:12) {
                    Toggle("剩余额度圆环",isOn:$options.quotaRing)
                    Toggle("剩余额度文字",isOn:$options.quotaText)
                    Toggle("下载速度",isOn:$options.download)
                    Toggle("上传速度",isOn:$options.upload)
                    Text(" ")
                }
            }.toggleStyle(.checkbox)
            Divider()
            Text("文字与指示颜色").font(.headline)
            Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:10) {
                GridRow { ColorPicker("站点名称",selection:binding(\.name),supportsOpacity:false);ColorPicker("套餐 / 节点 / 额度",selection:binding(\.text),supportsOpacity:false) }
                GridRow { ColorPicker("常规延迟",selection:binding(\.fast),supportsOpacity:false);ColorPicker("延迟 > 2000 ms",selection:binding(\.slow),supportsOpacity:false) }
                GridRow { ColorPicker("剩余额度圆环",selection:binding(\.ring),supportsOpacity:false);ColorPicker("下载速度",selection:binding(\.download),supportsOpacity:false) }
                GridRow { ColorPicker("上传速度",selection:binding(\.upload),supportsOpacity:false) }
            }
            VStack(alignment:.leading,spacing:8) {
                Text("显示预览（示例）").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Image(nsImage:MenuBarDisplay.image(icon:ProbeSite.icon("Google"),site:"Google",delay:"128 ms",milliseconds:128,profile:"示例套餐",remaining:0.72,options:options,node:"示例节点",download:"2.4 MB/s",upload:"128 KB/s",palette:palette))
                        .padding(12)
                }.background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            }
            Text(options.isEmpty ? "全部取消时保留一个图标，方便重新打开设置。" : "默认荧光绿延迟，超过 2000 ms 粉红；颜色可以分别修改。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("恢复默认") { options=MenuBarOptions();palette=MenuBarPalette() }
                Spacer()
                Button("保存显示设置") { options.save(); palette.save(); onSave(options) }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:510,height:580).preferredColorScheme(.dark)
    }
}
