import AppKit
import SwiftUI
import WidgetKit
import OSLog

@MainActor
final class ResetViewModel: ObservableObject {
    @Published var snapshot: ResetSnapshot = .empty
    @Published var refreshing = false

    func refresh(force: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        snapshot = await ResetClient.load(force: force)
        refreshing = false
        if force {
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexResetsWidget")
        }
    }
}

struct ResetManagerView: View {
    @ObservedObject var store: ResetViewModel
    @State private var showingSamples = false

    private var displayedSnapshot: ResetSnapshot {
        showingSamples ? .sample : store.snapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Codex 重置")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text("重置公告与时间，一眼掌握。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(resetsWebsite)
                    } label: {
                        Label("打开数据网站", systemImage: "arrow.up.right")
                    }
                    Button {
                        Task { await store.refresh(force: true) }
                    } label: {
                        Label(store.refreshing ? "正在更新…" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.refreshing || showingSamples)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.teal)
                    Text("此处追踪第三方网站汇总的重置公告，不显示你的个人剩余额度。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text("桌面小组件预览")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Toggle("显示示例", isOn: $showingSamples)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        preview(.small, label: "小号")
                        preview(.medium, label: "中号")
                    }
                    preview(.large, label: "大号")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("添加到桌面", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("在桌面点右键 → 编辑小组件 → 搜索“Codex 重置”，选择需要的尺寸。")
                    Text("点击组件可打开数据网站；右上角按钮可请求刷新。后台更新时间由 macOS 调度。")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 792, minHeight: 660)
        .task { await store.refresh() }
    }

    private func preview(_ size: CardSize, label: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TimelineView(.everyMinute) { context in
                ResetPreviewCard(snapshot: displayedSnapshot, size: size, now: context.date)
            }
        }
    }
}

struct ResetPreviewCard: View {
    let snapshot: ResetSnapshot
    let size: CardSize
    let now: Date

    var body: some View {
        ResetCard(snapshot: snapshot, size: size, now: now)
            .background(ResetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .frame(width: size.width, height: size.height)
            .containerShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class ResetAppDelegate: NSObject, NSApplicationDelegate {
    private var managerWindow: NSWindow?
    private let store = ResetViewModel()
    private var statusItem: NSStatusItem?
    private var displayTimer: Timer?
    private var maintenanceTimer: Timer?
    private var maintenanceTask: Task<Void, Never>?
    private let navigationLog = Logger(subsystem: "local.homeatlas.CodexResets", category: "navigation")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetSelfRepair.shared.start()
        installMenu()
        installStatusItem()
        maintainData()
        displayTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        if let displayTimer { RunLoop.main.add(displayTimer, forMode: .common) }
        WidgetCenter.shared.reloadTimelines(ofKind: resetsWidgetKind)
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maintainData() }
        }
        // Window creation belongs to a normal application-open event, not launch.
        // A widget URL can start this process without ever showing a manager.
    }

    private func maintainData() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await self.store.refresh()
            self.updateStatusItem()
            self.maintenanceTask = nil
            WidgetCenter.shared.reloadTimelines(ofKind: resetsWidgetKind)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayTimer?.invalidate()
        maintenanceTimer?.invalidate()
        maintenanceTask?.cancel()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        navigationLog.notice("Normal application launch requested management")
        showManager()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        navigationLog.notice("Application reopen requested management")
        showManager()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        application(NSApp, open: [url])
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let destination = urls.compactMap({ ResetNavigation.websiteDestination(for: $0) }).first else { return }
        managerWindow?.orderOut(nil)
        navigationLog.notice("Widget website route; management visible: \(self.managerWindow?.isVisible ?? false)")
        guard NSWorkspace.shared.open(destination) else {
            let alert = NSAlert()
            alert.messageText = "无法打开数据网站"
            alert.informativeText = "请检查默认浏览器设置，或在浏览器访问 codex-resets.com。"
            alert.runModal()
            return
        }
    }

    @objc private func showManager() {
        if managerWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 824, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Codex 重置"
            window.identifier = NSUserInterfaceItemIdentifier("CodexResetsManager")
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentMinSize = NSSize(width: 792, height: 660)
            window.contentView = NSHostingView(rootView: ResetManagerView(store:store))
            window.center()
            managerWindow = window
        }
        managerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        navigationLog.notice("Management window shown")
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName:"clock.arrow.circlepath",accessibilityDescription:"Codex 重置")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        for (title, action) in [("管理与预览…", #selector(showManager)),
                                ("打开重置网站", #selector(openWebsite)),
                                ("刷新重置数据", #selector(refreshStatus)),
                                ("菜单栏显示与配色…", #selector(customizeMenu))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle:"退出 Codex 重置",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        item.menu = menu; statusItem = item
        updateStatusItem()
    }
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let display = ResetMenuDisplay.make(snapshot:store.snapshot,now:Date())
        let color:NSColor
        switch display.tone {
        case .green: color = NSColor(srgbRed:0.40,green:1,blue:0.68,alpha:1)
        case .pink: color = NSColor(srgbRed:1,green:0.43,blue:0.76,alpha:1)
        case .neutral: color = .white
        }
        button.attributedTitle = NSAttributedString(string:" " + display.text,attributes:[
            .font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.semibold),.foregroundColor:color])
        var tooltip = "Codex 重置 · " + display.text + "\n来源：codex-resets.com"
        if let deadline = store.snapshot.status?.scheduledReset?.scheduledFor {
            tooltip += "\n计划时间：" + deadline.formatted(date:.complete,time:.standard)
        }
        tooltip += "\n" + store.snapshot.freshness(at:Date()) + " · 显示每秒更新，公共数据每 5 分钟检查"
        button.toolTip = tooltip; button.setAccessibilityLabel("Codex 重置 " + display.text)
        button.image=NSImage(systemSymbolName:"clock.arrow.circlepath",accessibilityDescription:nil);button.imagePosition = .imageLeading
        MenuCustomizationPanel.apply(button,fields:customMenuFields(),icon:button.image)
    }
    private func customMenuFields()->[MenuField] {
        let snapshot=store.snapshot,display=ResetMenuDisplay.make(snapshot:store.snapshot,now:Date())
        let key=display.tone == .green ? "elapsed" : display.tone == .pink ? "planned" : "neutral"
        let color=MenuCustomization.color(key == "elapsed" ? "#66FFAD" : key == "planned" ? "#FF6EC2" : "#FFFFFF")
        let last=snapshot.status?.stats.lastResetAt ?? snapshot.status?.latestReset?.announcedAt ?? snapshot.history.map(\.announcedAt).max()
        return [MenuField(id:"timer",title:"重置计时 / 状态",value:display.text,color:color,colorKey:key),
                MenuField(id:"name",title:"应用名称",value:"Codex 重置",defaultVisible:false),
                MenuField(id:"last",title:"上次重置日期",value:last?.formatted(date:.abbreviated,time:.shortened) ?? "—",defaultVisible:false),
                MenuField(id:"clock",title:"当前时间",value:Date().formatted(date:.omitted,time:.shortened),defaultVisible:false)]
    }
    @objc private func customizeMenu() {
        MenuCustomizationPanel.shared.show(title:"Codex 重置",fields:customMenuFields(),icon:NSImage(systemSymbolName:"clock.arrow.circlepath",accessibilityDescription:nil),extraColors:[("elapsed","无计划：经过时间",MenuCustomization.color("#66FFAD")),("planned","有计划：倒计时",MenuCustomization.color("#FF6EC2")),("neutral","未知 / 缓存状态",.white)]) { [weak self] in self?.updateStatusItem() }
    }
    @objc private func openWebsite() { NSWorkspace.shared.open(resetsWebsite) }
    @objc private func refreshStatus() {
        Task { await store.refresh(force:true); updateStatusItem() }
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Codex 重置")
        let managerItem = NSMenuItem(title: "管理与预览…", action: #selector(showManager), keyEquivalent: ",")
        managerItem.target = self
        appMenu.addItem(managerItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Codex 重置", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Codex 重置", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
}

@main
enum CodexResetsApp {
    @MainActor
    static func main() {
        if let flag = CommandLine.arguments.firstIndex(of: "--render-previews") {
            let destination = flag + 1 < CommandLine.arguments.count
                ? CommandLine.arguments[flag + 1] : "."
            Self.renderPreviews(to: URL(fileURLWithPath: destination, isDirectory: true))
            exit(0)
        }
        let application = NSApplication.shared
        let delegate = ResetAppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    @MainActor
    private static func renderPreviews(to destination: URL) {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let sizes: [(CardSize, String)] = [(.small, "small"), (.medium, "medium"), (.large, "large")]
            // A real AppKit hosting view preserves the system's Chinese text rasterization.
            // The offscreen window supplies the display scale and appearance without flashing UI.
            _ = NSApplication.shared
            for (size, name) in sizes {
                let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
                let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: ResetPreviewCard(snapshot: .sample, size: size, now: Date()))
                host.frame = frame
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.12))
                host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    throw NSError(domain: "CodexResets.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建预览画布"])
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "CodexResets.Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法编码预览图像"])
                }
                let output = destination.appendingPathComponent("\(name)-示例.png")
                try png.write(to: output, options: .atomic)
                print(output.path)
                window.close()
            }
        } catch {
            fputs("预览导出失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
