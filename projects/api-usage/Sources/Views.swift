import SwiftUI
import AppKit
import ServiceManagement

let mint = Color(red: 0.35, green: 1, blue: 0.77)
let muted = Color(red: 0.66, green: 0.75, blue: 0.85)
struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct Card: View {
    @ObservedObject var store: Store
    var size: String = "large"
    var desktop = false
    var refresh: () -> Void = {}
    var lock: () -> Void = {}
    var settings: () -> Void = {}
    @AppStorage("locked") var locked = true
    @AppStorage("darkness") var darkness = 0.65
    @AppStorage("selection") var selection = "openai"
    @AppStorage("glass") var glass = true
    @AppStorage("brightness") var brightness = -45.0
    @AppStorage("transparency") var transparency = 20.0
    func openProvider(_ p: String) {
        let url = p == "openai" ? "https://platform.openai.com/usage" : p == "deepseek" ? "https://platform.deepseek.com/usage" : "https://cloud.siliconflow.cn/"
        NSWorkspace.shared.open(URL(string: url)!)
    }
    var points: [CostPoint] { store.snapshot.costHistory?.value ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: size == "large" ? 12 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(mint)
                Text("API 用量").font(.system(size: size == "small" ? 14 : 18, weight: .bold))
                Spacer(minLength: 1)
                Button(action: refresh) { Image(systemName: "arrow.clockwise").font(.system(size: 12)) }.disabled(store.refreshing).help("刷新 API 数据")
                if desktop { Button(action: lock) { Image(systemName: locked ? "lock.fill" : "lock.open").font(.system(size: 11)).foregroundStyle(.cyan) }.help(locked ? "解锁位置" : "锁定位置") }
            }.buttonStyle(.plain)
            if size == "large" { large }
            else if size == "medium" { medium }
            else { small }
        }
        .foregroundStyle(.white).padding(size == "small" ? 14 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                if !store.preview && glass { Glass() }
                else { Color(red: 0.04, green: 0.10, blue: 0.18).opacity(1-transparency/100) }
                LinearGradient(colors: [Color(red: 0.04, green: 0.14, blue: 0.24).opacity(darkness * (1-transparency/100)), Color(red: 0.13, green: 0.09, blue: 0.25).opacity(darkness * (1-transparency/100))], startPoint: .topLeading, endPoint: .bottomTrailing)
                (brightness > 0 ? Color.white : Color.black).opacity(abs(brightness)/100 * 0.25)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size == "small" ? 23 : 28))
        .overlay(RoundedRectangle(cornerRadius: size == "small" ? 23 : 28).strokeBorder(.white.opacity(0.24), lineWidth: 1))
    }
    var large: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text("OpenAI").bold(); Spacer(); Text("本月消耗 ↗").foregroundStyle(muted).font(.system(size: 10)) }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.costText).font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(mint).minimumScaleFactor(0.5).lineLimit(1)
                    Spacer()
                    Text(store.snapshot.usage.map { compact($0.value.total) + " Token" } ?? "Token —").font(.system(size: 10)).foregroundStyle(muted)
                }
            }.contentShape(Rectangle()).onTapGesture { openProvider("openai") }.help("点击查看 OpenAI 官方 API 用量及费用")
            UsageBars(store: store, height: 25)
            stateLine(provider: "openai")
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("DeepSeek").bold(); Spacer(); Text("API 账户 ↗").font(.system(size: 10)).foregroundStyle(muted) }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("余额").font(.system(size: 9)).foregroundStyle(muted)
                        Text(store.balanceText).font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(.cyan).minimumScaleFactor(0.4).lineLimit(1).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("本月消耗").font(.system(size: 9)).foregroundStyle(muted)
                        Text("官网查询 ↗").font(.system(size: 12)).foregroundStyle(muted)
                    }
                }
            }.contentShape(Rectangle()).onTapGesture { openProvider("deepseek") }.help("历史费用接口未接入，点击查询官方账单")
            stateLine(provider: "deepseek")
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("硅基流动").font(.system(size: 12, weight: .bold))
                    Text("余额 / 本月消耗 · 官网查询").font(.system(size: 9)).foregroundStyle(muted)
                }
                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.cyan)
            }.contentShape(Rectangle()).onTapGesture { openProvider("siliconflow") }.help("国内余额接口暂不可用，打开官方控制台")
            Spacer(minLength: 0)
            HStack { Circle().fill(store.preview ? .orange : mint).frame(width: 4, height: 4); Text(store.preview ? "示例数据" : "API · UTC 月份"); Spacer(); Button("设置连接", action: settings).buttonStyle(.plain).foregroundStyle(.cyan) }.font(.system(size: 9)).foregroundStyle(muted)
        }.font(.system(size: 13))
    }
    var medium: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenAI · 本月消耗 ↗").foregroundStyle(muted).font(.system(size: 10))
                Text(store.costText).font(.system(size: 25, weight: .medium)).foregroundStyle(mint).minimumScaleFactor(0.5).lineLimit(1).onTapGesture { openProvider("openai") }
                UsageBars(store: store, height: 19)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text("DeepSeek · 余额 ↗").foregroundStyle(muted).font(.system(size: 10))
                Text(store.balanceText).font(.system(size: 23, weight: .medium)).foregroundStyle(.cyan).minimumScaleFactor(0.4).lineLimit(1)
                Text("本月消耗 · 官网查询").font(.system(size: 9)).foregroundStyle(muted)
                Text(store.preview ? "示例数据" : "硅基流动：设置中查询").font(.system(size: 8)).foregroundStyle(muted)
            }.frame(maxWidth: .infinity, alignment: .trailing).contentShape(Rectangle()).onTapGesture { openProvider("deepseek") }
        }
    }
    var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selection == "deepseek" ? "DeepSeek · 余额 ↗" : selection == "tokens" ? "OpenAI · 本月 Token ↗" : "OpenAI · 本月消耗 ↗").font(.system(size: 9)).foregroundStyle(muted)
            Text(selection == "deepseek" ? store.balanceText : selection == "tokens" ? (store.snapshot.usage.map { compact($0.value.total) } ?? "—") : store.costText).font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(mint).lineLimit(1).minimumScaleFactor(0.3).onTapGesture { openProvider(selection == "deepseek" ? "deepseek" : "openai") }
            if selection != "deepseek" { UsageBars(store: store, height: 18) }
            else { Text("本月消耗 · 官网查询").font(.system(size: 9)).foregroundStyle(muted).onTapGesture { openProvider("deepseek") } }
            Spacer(minLength: 0)
            Text(store.preview ? "示例数据" : "点击查看官方账单").font(.system(size: 8)).foregroundStyle(muted)
        }
    }
    func stateLine(provider: String) -> some View {
        let error = provider == "openai" ? store.errors["openai"] ?? store.errors["costs"] ?? store.errors["usage"] : store.errors["deepseek"]
        let date = provider == "openai" ? store.snapshot.costs?.date : store.snapshot.balances?.date
        return HStack(spacing: 4) {
            Circle().fill(error != nil ? Color.orange : date == nil ? Color.gray : mint).frame(width: 4, height: 4)
            if store.refreshing { Text("正在刷新 · 保留上次读数") }
            else if error != nil { Text("读取失败 · 查看设置") }
            else if let date { Text("更新 " + date.formatted(date: .omitted, time: .shortened)) }
            else { Button("待连接 · 点此设置", action: settings).buttonStyle(.plain) }
        }.font(.system(size: 9)).foregroundStyle(muted)
    }
}
struct SettingsPanel: View {
    @ObservedObject var store: Store
    var changed: () -> Void
    @State private var openKey = ""
    @State private var deepKey = ""
    @State private var project = UserDefaults.standard.string(forKey: "project") ?? ""
    @AppStorage("interval") private var interval = 5
    @AppStorage("size") private var size = "large"
    @AppStorage("selection") private var selection = "openai"
    @AppStorage("darkness") private var darkness = 0.65
    @AppStorage("glass") private var glass = true
    @AppStorage("brightness") private var brightness = -45.0
    @AppStorage("transparency") private var transparency = 20.0
    @AppStorage("menuColor") private var menuColor = "mint"
    @AppStorage("menuIcon") private var menuIcon = true
    @AppStorage("desktopVisible") private var desktopVisible = true
    @AppStorage("locked") private var locked = true
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("API 用量卡片").font(.largeTitle.bold())
                Text("OpenAI 官方 API · DeepSeek · 硅基流动国内站").foregroundStyle(.secondary)
                GroupBox("OpenAI · 组织 API 统计") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("读取 UTC 本月费用和文本生成 Token / 请求数。需要组织 Admin Key；不读取 ChatGPT 或 Codex 订阅套餐。余额暂无官方公开接口。").font(.callout).foregroundStyle(.secondary)
                        SecureField(store.hasOpenAI ? "输入新 Admin Key 替换原连接" : "组织 Admin Key", text: $openKey)
                        TextField("项目 ID（可选；留空显示全组织）", text: $project)
                        HStack {
                            Button("保存并读取") { store.saveConnection("openai", key: openKey, project: project); openKey = "" }.disabled(openKey.isEmpty || store.refreshing)
                            Button("移除连接", role: .destructive) { store.remove("openai") }.disabled(!store.hasOpenAI || store.refreshing)
                            Spacer(); Link("官方用量控制台 ↗", destination: URL(string: "https://platform.openai.com/usage")!)
                        }
                        Text("本月费用：\(store.costText)    余额：不支持查询").font(.headline)
                        CostChart(points: store.snapshot.costHistory?.value ?? [], height: 72)
                            .contentShape(Rectangle()).onTapGesture { NSWorkspace.shared.open(URL(string: "https://platform.openai.com/usage")!) }
                        if let r = store.snapshot.usage {
                            Text("输入 \(compact(r.value.input)) · 输出 \(compact(r.value.output)) · 请求 \(compact(r.value.requests))")
                            Text("Token 为文本生成统计，费用范围由官方 Costs API 决定。").font(.caption).foregroundStyle(.secondary)
                            Text("用量最后成功：\(r.date.formatted())").font(.caption).foregroundStyle(.secondary)
                        }
                        if let r = store.snapshot.costs { Text("费用最后成功：\(r.date.formatted())").font(.caption).foregroundStyle(.secondary) }
                        UsageBars(store: store, height: 72)
                        errorText(["openai", "costs", "usage", "history24", "history7"])
                    }.padding(10)
                }
                GroupBox("DeepSeek · API 余额") {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField(store.hasDeepSeek ? "输入新 API Key 替换原连接" : "DeepSeek API Key", text: $deepKey)
                        HStack {
                            Button("保存并读取") { store.saveConnection("deepseek", key: deepKey); deepKey = "" }.disabled(deepKey.isEmpty || store.refreshing)
                            Button("移除连接", role: .destructive) { store.remove("deepseek") }.disabled(!store.hasDeepSeek || store.refreshing)
                            Spacer(); Link("官方控制台 ↗", destination: URL(string: "https://platform.deepseek.com/usage")!)
                        }
                        ForEach(store.snapshot.balances?.value ?? [], id: \.currency) { b in
                            Text("\(b.currency)  余额 \(money(b.total, b.currency)) · 充值 \(money(b.topped, b.currency)) · 赠送 \(money(b.granted, b.currency))")
                        }
                        Text("本月消耗：官网查询。历史用量未提供，余额变化不作为真实消费额。").font(.caption).foregroundStyle(.secondary)
                        if let r = store.snapshot.balances { Text("余额最后成功：\(r.date.formatted())").font(.caption).foregroundStyle(.secondary) }
                        errorText(["deepseek"])
                    }.padding(10)
                }
                GroupBox("硅基流动 · 国内站") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("旧余额接口已下线，当前不采集密钥或自动查询。余额与用量请查看官方控制台；后续有可用接口再接入。").foregroundStyle(.secondary)
                        HStack { Link("打开控制台 ↗", destination: URL(string: "https://cloud.siliconflow.cn/")!); Link("接口公告 ↗", destination: URL(string: "https://docs.siliconflow.cn/docs/release-notes/overview")!) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("显示与刷新") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("自动刷新", selection: $interval) { ForEach([1,5,15,30], id: \.self) { Text("\($0) 分钟").tag($0) } }.onChange(of: interval) { _, _ in store.schedule() }
                        Picker("桌面卡片", selection: $size) { Text("小号").tag("small"); Text("中号").tag("medium"); Text("大号").tag("large") }.pickerStyle(.segmented)
                        Picker("菜单栏 / 小号卡片指标", selection: $selection) { Text("OpenAI 本月费用").tag("openai"); Text("DeepSeek 余额").tag("deepseek"); Text("OpenAI 本月 Token").tag("tokens") }
                        Picker("菜单栏颜色", selection: $menuColor) { Text("荧光绿").tag("mint"); Text("青色").tag("cyan"); Text("粉红").tag("pink"); Text("白色").tag("white") }
                        Toggle("显示菜单栏图标", isOn: $menuIcon)
                        Toggle("毛玻璃背景", isOn: $glass)
                        HStack { Text("明暗"); Slider(value: $brightness, in: -100...100) }
                        HStack { Text("透明度"); Slider(value: $transparency, in: 0...80) }
                        Button("打开桌面工具箱…") { ToolboxBridge.openToolbox() }
                        Toggle("显示桌面卡片", isOn: $desktopVisible)
                        Toggle("锁定卡片位置", isOn: $locked)
                        Toggle("登录后启动", isOn: $login).onChange(of: login) { _, enabled in
                            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; store.message = SMAppService.mainApp.status == .requiresApproval ? "请在系统登录项中允许启动" : "登录启动设置已更新" }
                            catch { store.message = "登录启动设置失败，请将应用移到应用程序目录后重试"; login = SMAppService.mainApp.status == .enabled }
                        }
                    }.padding(10)
                }
                HStack { Button(store.refreshing ? "正在刷新…" : "刷新全部") { Task { await store.refresh() } }.disabled(store.refreshing); Text(store.message).foregroundStyle(.secondary) }
                Text("密钥仅保存在本机钥匙串。只读统计，不发起模型调用。缓存数据可能滞后，以平台账单为准。").font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.frame(width: 660, height: 740)
        .onChange(of: size) { _, _ in changed() }.onChange(of: desktopVisible) { _, _ in changed() }
        .onChange(of: selection) { _, _ in changed() }.onChange(of: locked) { _, _ in changed() }
        .onChange(of: menuIcon) { _, _ in changed() }.onChange(of: menuColor) { _, _ in changed() }
    }
    func errorText(_ fields: [String]) -> some View {
        VStack(alignment: .leading) { ForEach(fields, id: \.self) { field in if let e = store.errors[field] { Text(e).font(.caption).foregroundStyle(.orange) } } }
    }
}
