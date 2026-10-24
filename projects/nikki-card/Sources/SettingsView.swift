import SwiftUI

struct ConnectionView: View {
    @ObservedObject var monitor: MonitorCoordinator
    @State private var endpoint: String
    @State private var secret = ""
    @State private var replaceSecret = false
    @State private var message = ""
    init(monitor: MonitorCoordinator) {
        self.monitor = monitor
        _endpoint = State(initialValue: monitor.settings.endpoint)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Nikki 连接设置", systemImage:"network").font(.title2.bold())
            Text("直接连接旁路由，为桌面卡片提供数据。").foregroundStyle(.secondary)
            Form {
                TextField("控制接口",text:$endpoint)
                SecureField("控制密钥（留空沿用）",text:$secret)
                Toggle("替换已保存密钥",isOn:$replaceSecret)
            }.textFieldStyle(.roundedBorder)
            Text("密钥保存在本机钥匙串。网页地址中的 /ui/ 和查询参数无需填写。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("保存并连接") {
                    do {
                        var new = monitor.settings; new.endpoint = endpoint
                        try monitor.save(new, secret: (!secret.isEmpty || replaceSecret) ? secret : nil)
                        secret = ""; replaceSecret = false; message = "已保存"
                    } catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                Text(message).foregroundStyle(.secondary)
            }
            Label(monitor.snapshot.connectionState,systemImage:monitor.snapshot.isConnected ? "checkmark.circle.fill" : "wifi.exclamationmark")
                .foregroundStyle(monitor.snapshot.isConnected ? Color.mint : Color.secondary)
            if !monitor.subscriptions.isEmpty {
                Picker("展示套餐",selection:Binding(get:{monitor.settings.provider},set:{monitor.chooseProvider($0)})) {
                    Text("自动（仅有一个套餐时）").tag("")
                    ForEach(monitor.subscriptions,id:\.self) { Text($0).tag($0) }
                }
            }
            Spacer(minLength:0)
        }.padding(24).frame(width:500,height:350).preferredColorScheme(.dark)
    }
}

struct NodePickerView: View {
    @ObservedObject var monitor: MonitorCoordinator
    @State private var search = ""
    var nodes: [String] {
        let all = monitor.proxies[monitor.settings.group]?["all"] as? [String] ?? []
        return all.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }
    var current: String? { monitor.proxies[monitor.settings.group]?["now"] as? String }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label("切换节点",systemImage:"arrow.left.arrow.right").font(.title2.bold())
                Spacer()
                Button("刷新") { monitor.refresh() }
            }
            Picker("策略组",selection:Binding(get:{monitor.settings.group},set:{monitor.chooseGroup($0)})) {
                if !monitor.groups.contains(monitor.settings.group) { Text(monitor.settings.group).tag(monitor.settings.group) }
                ForEach(monitor.groups,id:\.self) { Text($0).tag($0) }
            }.disabled(monitor.switching)
            Text("只切换当前选中的策略组；已有连接会自然结束。").font(.callout).foregroundStyle(.secondary)
            TextField("搜索节点或分组",text:$search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing:6) {
                    ForEach(nodes,id:\.self) { name in
                        HStack {
                            Image(systemName:name == current ? "checkmark.circle.fill" : "circle").foregroundStyle(name == current ? Color.mint : Color.secondary)
                            VStack(alignment:.leading,spacing:4) {
                                Text(name).font(.system(size:14,weight:.medium))
                                if let leaf = NikkiData.leaf(name,proxies:monitor.proxies), leaf != name {
                                    Text(leaf).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let leaf = NikkiData.leaf(name,proxies:monitor.proxies), let delay = NikkiData.recentDelay(monitor.proxies[leaf]) {
                                Text("\(delay) ms").foregroundStyle(.mint).monospacedDigit()
                            }
                            Button(name == current ? "已选" : "切换") { monitor.select(node:name) }
                                .disabled(name == current || monitor.switching || !monitor.snapshot.isConnected)
                        }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:10))
                    }
                }
            }
            Text(monitor.actionMessage.isEmpty ? monitor.snapshot.connectionState : monitor.actionMessage)
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }.padding(22).frame(width:590,height:500).preferredColorScheme(.dark)
    }
}

