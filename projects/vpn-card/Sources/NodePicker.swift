import AppKit
import SwiftUI

@MainActor
final class NodePickerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let flclash = FlClashNodeController()
    private let shadowrocket = ShadowrocketNodeController()

    func show(client: ProxyClient, preferredGroup: String?, onChanged: @escaping () -> Void) {
        flclash.close()
        shadowrocket.cancel()
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 460, height: 380)
            panel.delegate = self
            panel.center()
            panel.setFrameAutosaveName("FlClashNodePickerFrame")
            window = panel
        }
        flclash.onSelectionChanged = onChanged
        shadowrocket.onSelectionChanged = onChanged
        window?.title = "节点选择与测速 · \(client.title)"
        if client == .flclash {
            window?.contentView = NSHostingView(rootView: FlClashNodePickerView(model: flclash))
            flclash.open(preferredGroup: preferredGroup)
        } else {
            window?.contentView = NSHostingView(rootView: ShadowrocketNodePickerView(model: shadowrocket))
            shadowrocket.load()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { flclash.close(); shadowrocket.cancel(); window?.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { flclash.close(); shadowrocket.cancel() }
}

private struct FlClashNodePickerView: View {
    @ObservedObject var model: FlClashNodeController
    @State private var search = ""
    @State private var sortByLatency = false

    private var group: FlClashNodeGroup? { model.groups.first { $0.name == model.selectedGroupName } }
    private var options: [FlClashNodeOption] {
        let rows = (group?.options ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        guard sortByLatency else { return rows }
        return rows.sorted {
            let a = model.latencies[$0.name]?.milliseconds ?? Int.max
            let b = model.latencies[$1.name]?.milliseconds ?? Int.max
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择节点").font(.title2.bold())
                    Text("FlClash · 打开列表后自动测速，点击节点切换")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading || model.isTesting || model.selectingName != nil { ProgressView().controlSize(.small) }
            }
            if !model.groups.isEmpty {
                Picker("策略组", selection: Binding(get: { model.selectedGroupName ?? "" }, set: { model.setGroup($0) })) {
                    ForEach(model.groups) { item in Text(item.name).tag(item.name) }
                }.disabled(model.selectingName != nil)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索节点", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Button("刷新列表") { model.refresh() }.disabled(model.isLoading || model.selectingName != nil)
                Button(model.isTesting ? "测速中…" : "重新测速") { model.testAll(force: true) }
                    .disabled(model.isTesting || model.selectingName != nil || group == nil)
                Spacer()
                Toggle("延迟排序", isOn: $sortByLatency).toggleStyle(.checkbox)
                    .disabled(model.isTesting || model.selectingName != nil)
            }.font(.caption)
            if let error = model.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(options) { option in nodeRow(option) }
                    if options.isEmpty && !model.isLoading {
                        Text(search.isEmpty ? "没有可手动选择的节点" : "未找到匹配节点")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
            }
            Divider()
            Text("延迟为节点访问测试网址的耗时；测速不会切换节点。自动选择组会继续按其规则选节点。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(minWidth: 420, minHeight: 340).preferredColorScheme(.dark)
            .onChange(of: model.isTesting) { _, testing in if testing { sortByLatency = false } }
    }

    private func nodeRow(_ option: FlClashNodeOption) -> some View {
        let selected = group?.selectedName == option.name
        let reading = model.latencies[option.name]
        return Button { model.select(name: option.name) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : option.isGroup ? "square.stack.3d.up" : "network")
                    .foregroundStyle(selected ? Color.mint : Color.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(option.isGroup ? "\(option.type) · \(option.resolvedNode ?? "尚未选定节点")" : option.type)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.selectingName == option.name { ProgressView().controlSize(.small) }
                else { latency(reading, testable: option.canTest) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.mint.opacity(0.10) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(model.selectingName != nil || model.isLoading)
            .accessibilityLabel((selected ? "已选：" : "切换到：") + option.name)
    }

    @ViewBuilder private func latency(_ reading: FlClashNodeLatency?, testable: Bool) -> some View {
        if !testable { Text("不测速").font(.caption).foregroundStyle(.secondary) }
        else if let reading, reading.state == .testing { ProgressView().controlSize(.small) }
        else if let value = reading?.milliseconds {
            Text("\(value) ms").font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(value < 500 ? Color.mint : value < 2000 ? Color.orange : Color.pink)
        } else {
            Text(reading?.state == .timeout ? "超时" : reading?.state == .failed ? "失败" : "待测")
                .font(.caption).foregroundStyle(reading?.state == .timeout || reading?.state == .failed ? Color.orange : Color.secondary)
        }
    }
}

private struct ShadowrocketNodePickerView: View {
    @ObservedObject var model: ShadowrocketNodeController
    @State private var search = ""
    @State private var sortByLatency = false

    private var nodes: [ShadowrocketNodeOption] {
        let rows = model.nodes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        guard sortByLatency else { return rows }
        return rows.sorted {
            let a = $0.latencyMS ?? Int.max, b = $1.latencyMS ?? Int.max
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择节点").font(.title2.bold())
                    Text("Shadowrocket · \(model.profileName ?? "当前订阅")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading || model.isTesting || model.isSelecting { ProgressView().controlSize(.small) }
            }
            Text("打开列表后自动测速，点击节点交给 Shadowrocket 切换。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索节点", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(9).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Button("刷新列表") { model.load() }.disabled(model.isLoading || model.isSelecting)
                Button(model.isTesting ? "测速中…" : "重新测速") { model.testAll(force: true) }
                    .disabled(model.isTesting || model.isSelecting || model.nodes.isEmpty)
                Spacer()
                Toggle("延迟排序", isOn: $sortByLatency).toggleStyle(.checkbox)
                    .disabled(model.isTesting || model.isSelecting)
            }.font(.caption)
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(nodes) { node in nodeRow(node) }
                    if nodes.isEmpty && !model.isLoading {
                        Text(search.isEmpty ? "当前订阅没有可用节点" : "未找到匹配节点")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
            }
            Divider()
            Text("TCP 延迟仅表示节点连通速度，不等于网站访问耗时。仅测速不会更换节点；切换结果由 Shadowrocket 确认。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(minWidth: 420, minHeight: 340).preferredColorScheme(.dark)
            .onChange(of: model.isTesting) { _, testing in if testing { sortByLatency = false } }
    }

    private func nodeRow(_ node: ShadowrocketNodeOption) -> some View {
        Button { model.selectNode(id: node.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: node.isCurrent ? "checkmark.circle.fill" : "network")
                    .foregroundStyle(node.isCurrent ? Color.mint : Color.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).font(.system(size: 13, weight: node.isCurrent ? .semibold : .regular))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(node.type).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if node.isTesting { ProgressView().controlSize(.small) }
                else if let value = node.latencyMS {
                    Text("\(value) ms TCP").font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(value < 500 ? Color.mint : value < 2000 ? Color.orange : Color.pink)
                } else {
                    Text(node.status).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(node.isCurrent ? Color.mint.opacity(0.10) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(!node.canSelect || model.isSelecting || model.isLoading)
            .help(node.disabledReason ?? "点击选择此节点")
            .accessibilityLabel((node.isCurrent ? "已选：" : "切换到：") + node.name)
    }
}
