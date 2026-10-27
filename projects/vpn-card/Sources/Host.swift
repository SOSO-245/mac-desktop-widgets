import AppKit
import SwiftUI
import ServiceManagement

private final class CardPanel: NSPanel {
    var positionLocked = false
    var cardSize: CardSize = .medium
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.window === self,
           let contentView {
            let point = event.locationInWindow
            let size = contentView.bounds.size
            // SwiftUI's text and chart subviews consume the background drag.
            // Handle dragging at the panel, leaving the header controls intact.
            let inHeader = point.y >= size.height - 40 && point.y <= size.height - 12
            let onControl = inHeader && (point.x <= 42 || point.x >= size.width - (cardSize == .small ? 42:65))
            let inSiteList = cardSize == .large && point.y < size.height - 164
            let fromTop = size.height - point.y
            let inSpeeds = point.x >= 14 && point.x <= size.width - 14
                && (cardSize == .small ? (90...120).contains(fromTop) : (110...152).contains(fromTop))
            if NSRect(origin: .zero, size: size).contains(point), !onControl, !inSiteList, !inSpeeds {
                guard !positionLocked else { return }
                performDrag(with: event)
                saveFrame(usingName: "FlClashLiveCardFrame")
                return
            }
        }
        super.sendEvent(event)
    }
}

private final class CardHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor
final class MonitorDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor = MonitorCoordinator()
    private let sites = SiteLatencyMonitor()
    private var size = CardSize(rawValue: UserDefaults.standard.string(forKey: "cardSize") ?? "") ?? .medium
    private var menuSite = UserDefaults.standard.string(forKey: "menuLatencySite") ?? "Google"
    private var cardVisible = !UserDefaults.standard.bool(forKey: "cardHidden")
    private var panel: CardPanel!
    private var host: CardHostingView!
    private var statusItem: NSStatusItem!
    private let statusPopover = StatusPopover()
    private var lastStatusDisplayKey: String?
    private var observer: Any?
    private let nodePicker = NodePickerWindowController()
    private var menuOptions = MenuBarOptions.load()
    private var subscriptions = Set<AnyCancellable>()
    private var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
    private var positionLocked = UserDefaults.standard.bool(forKey: "positionLocked")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProbeSite.all.prefix(6).contains(where: { $0.id == menuSite }) { menuSite = "Google" }
        let size = self.size.dimensions
        panel = CardPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "FlClash 实时卡片"
        panel.identifier = NSUserInterfaceItemIdentifier("FlClashLiveCard")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.cardSize = self.size
        panel.positionLocked = positionLocked
        panel.isMovable = !positionLocked
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        if panel.setFrameUsingName("FlClashLiveCardFrame") {
            // Preserve the user's top-left position while migrating old card sizes.
            let restored = panel.frame
            panel.setFrame(NSRect(x: restored.minX, y: restored.maxY - size.height,
                                  width: size.width, height: size.height), display: false)
        } else {
            panel.center()
        }
        host = CardHostingView(rootView: desktopCard())
        panel.contentView = host
        panel.setFrameAutosaveName("FlClashLiveCardFrame")
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
        updateLevel()
        monitor.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.host.rootView = self.desktopCard()
            self.configureSites()
            self.updateStatus()
        }.store(in: &subscriptions)
        configureSettings()
        createMenu()
        sites.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.host.rootView = self.desktopCard(); self.updateStatus()
        }.store(in: &subscriptions)
        monitor.start()
        configureSites()
        setSize(self.size)
        if cardVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        updateVisibilityMark()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    private func card(preview: Bool = false, native: Bool = false) -> FlClashCard {
        FlClashCard(menuSurface:native, size: preview ? .large : size, siteReadings: sites.readings, siteRoute: sites.routeLabel,
                    onSize: { [weak self] in self?.setSize($0) },
                    menuSite: menuSite, onMenuSite: { [weak self] in self?.setMenuSite($0) },
                    onSiteRefresh: { [weak self] in self?.sites.refresh(siteID: $0) },
                    snapshot: monitor.snapshot, alwaysOnTop: alwaysOnTop, positionLocked: positionLocked,
                    onOpen: { [weak self] in self?.openFlClash() },
                    onSwitch: { [weak self] in self?.switchClient() },
                    onRefresh: { [weak self] in self?.refresh() },
                    onToggleTop: { [weak self] in self?.toggleTop() },
                    onToggleLock: { [weak self] in self?.toggleLock() },
                    onQuit: { NSApp.terminate(nil) }, onMenuSettings:{ [weak self] in self?.showAppSettings() },
                    onTrafficScope: { [weak self] in self?.setTrafficScope($0) },onAppearance:{ AppSettingsController.shared.show("desktop") },
                    onChooseNode: { [weak self] in self?.showNodePicker() })
    }

    private func desktopCard()->AnyView {
        AnyView(DesktopCardSurface(original:card(),plain:card(native:true)))
    }

    private func configureSettings() {
        ToolboxBridge.shared.start(show:{[weak self] visible in guard let self, self.cardVisible != visible else{return}; if visible{self.showCard()}else{self.hideCard()}},size:{[weak self] value in if let s=CardSize(rawValue:value){self?.setSize(s)}})
        AppSettingsController.shared.configure(title: "FlClash 实时卡片", pages: [
            AppSettingsPage(id:"toolbox",title:"桌面排列",symbol:"square.grid.2x2") {AnyView(ToolboxSettingsLink())},
            AppSettingsPage(id: "general", title: "通用", symbol: "gearshape", content: { [weak self] in self?.generalSettings() ?? AnyView(EmptyView()) }),
            AppSettingsPage(id: "desktop", title: "桌面与浮窗", symbol: "rectangle.on.rectangle", content: { [weak self] in self?.desktopSettings() ?? AnyView(EmptyView()) }),
            AppSettingsPage(id: "menubar", title: "菜单栏", symbol: "menubar.rectangle", content: { [weak self] in self?.menuBarSettings() ?? AnyView(EmptyView()) }),
            AppSettingsPage(id: "connection", title: "数据与测速", symbol: "network", content: { [weak self] in self?.connectionSettings() ?? AnyView(EmptyView()) }),
            AppSettingsPage(id: "updates", title: "软件更新", symbol: "arrow.triangle.2.circlepath", content: { AppUpdater.shared.settingsContent })
        ], beforeShow: { [weak self] in self?.statusPopover.close() })
    }

    private func settingsBinding<Value>(get: @escaping @MainActor @Sendable () -> Value, set: @escaping @MainActor @Sendable (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: set)
    }

    private func generalSettings() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 18) {
            Toggle("登录时启动", isOn: settingsBinding(get: { SMAppService.mainApp.status == .enabled }, set: { value in
                if value != (SMAppService.mainApp.status == .enabled) { self.toggleLogin() }
            }))
            Text("登录 Mac 后自动启动实时卡片，保留当前的显示方式。").foregroundStyle(.secondary)
            if SMAppService.mainApp.status == .requiresApproval {
                Button("在系统设置中允许登录启动") { SMAppService.openSystemSettingsLoginItems() }
            }
            Divider()
            LabeledContent("当前数据来源", value: monitor.client.title)
            Text("数据来源、网速统计和延迟目标可在“数据与测速”中调整。").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private func desktopSettings() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 18) {
            Toggle("显示桌面卡片", isOn: settingsBinding(get: { self.cardVisible }, set: { value in
                if value != self.cardVisible { value ? self.showCard() : self.hideCard() }
            }))
            Picker("卡片尺寸", selection: settingsBinding(get: { self.size }, set: { self.setSize($0) })) {
                ForEach(CardSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Toggle("置于其他窗口上方", isOn: settingsBinding(get: { self.alwaysOnTop }, set: { value in
                if value != self.alwaysOnTop { self.toggleTop() }
            }))
            Toggle("锁定卡片位置", isOn: settingsBinding(get: { self.positionLocked }, set: { value in
                if value != self.positionLocked { self.toggleLock() }
            }))
            Button("移到屏幕中央") { self.centerCard() }
            Divider()
            DesktopAppearanceSettings(model: .shared)
            Divider()
            statusPopover.settingsContent
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private func menuBarSettings() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 22) {
            MenuBarSettingsView(onSave: { [weak self] value in
                self?.menuOptions = value; self?.lastStatusDisplayKey = nil; self?.updateStatus()
            })
            Divider()
            Text("高级文字与图标").font(.headline)
            Text("启用高级样式后，菜单栏采用下方的显示内容与文字；关闭后恢复上方的基础显示。").font(.callout).foregroundStyle(.secondary)
            MenuCustomizationView(fields: customMenuFields(), fallback: ProbeSite.icon(menuSite),
                                  extraColors: [("fast", "常规延迟", MenuCustomization.color("#66FFAD")),
                                                ("slow", "超过 2000 ms", MenuCustomization.color("#FF6EC2"))],
                                  onSave: { [weak self] in self?.lastStatusDisplayKey = nil; self?.updateStatus() })
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private func connectionSettings() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 18) {
            Picker("数据来源", selection: settingsBinding(get: { self.monitor.client }, set: { value in
                if value != self.monitor.client { self.switchClient() }
            })) {
                ForEach(ProxyClient.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if monitor.client == .flclash {
                Picker("网速统计", selection: settingsBinding(get: { TrafficScope.load() }, set: { self.setTrafficScope($0) })) {
                    ForEach(TrafficScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } else {
                LabeledContent("网速统计", value: "隧道总流量")
            }
            Text(monitor.snapshot.trafficHint).font(.callout).foregroundStyle(.secondary)
            Divider()
            Picker("菜单栏延迟目标", selection: settingsBinding(get: { self.menuSite }, set: { self.setMenuSite($0) })) {
                ForEach(ProbeSite.all) { Text($0.id).tag($0.id) }
            }
            Button("节点选择与测速…") { self.showNodePicker() }
            Button("刷新数据与测速") { self.refresh() }
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "FlClash 实时卡片")
        statusItem.button?.toolTip = "FlClash 实时卡片"
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        add("显示卡片", #selector(showCard))
        add("打开当前软件", #selector(openFlClash))
        add("切换 FlClash / Shadowrocket", #selector(switchClient))
        add("节点选择与测速…", #selector(showNodePicker))
        add("刷新数据", #selector(refresh))
        add("隐藏卡片", #selector(hideCard))
        menu.addItem(.separator())
        add("退出实时卡片", #selector(quit))
        statusPopover.attach(to:statusItem,menu:menu,size:CardSize.large.dimensions,openTitle:"显示桌面卡片",
            open:{ [weak self] in self?.showCard() },desktopOptions:true,content:{ [weak self] native in
                guard let self else{return AnyView(EmptyView())};return AnyView(self.card(preview:true,native:native))
            })
        statusPopover.visibilityChanged = { [weak self] in self?.configureSites() }
        updateVisibilityMark()
        updateTrafficMenu()
        updateStatus()
    }

    private func updateTrafficMenu() {
        guard let menu = statusPopover.menu.items.first(where: { $0.title == "网速统计" })?.submenu else { return }
        menu.removeAllItems()
        if monitor.client == .shadowrocket {
            let item = NSMenuItem(title: "隧道总流量 · 暂不支持拆分", action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        } else {
            for scope in TrafficScope.allCases {
                let item = NSMenuItem(title: scope.title, action: #selector(selectTrafficScope(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = scope.rawValue
                item.state = TrafficScope.load() == scope ? .on : .off; menu.addItem(item)
            }
        }
    }
    @objc private func selectTrafficScope(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let scope = TrafficScope(rawValue: raw) else { return }
        setTrafficScope(scope)
    }
    private func setTrafficScope(_ scope: TrafficScope) {
        defer { AppSettingsController.shared.refresh() }
        monitor.setTrafficScope(scope); updateTrafficMenu(); host.rootView = desktopCard(); updateStatus()
    }

    private func updateLevel() {
        panel.level = alwaysOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    @objc private func showNodePicker() {
        statusPopover.close()
        nodePicker.show(client: monitor.client, preferredGroup: monitor.snapshot.groupName) { [weak self] in
            self?.monitor.refresh()
            self?.configureSites()
        }
    }
    @objc private func showCard() { cardVisible = true; UserDefaults.standard.set(false,forKey:"cardHidden"); updateVisibilityMark(); configureSites(); panel.orderFrontRegardless() }
    @objc private func hideCard() { if !cardVisible { showCard(); return }; cardVisible = false; UserDefaults.standard.set(true,forKey:"cardHidden"); updateVisibilityMark(); configureSites(); panel.orderOut(nil) }
    private func updateVisibilityMark() {
        defer { AppSettingsController.shared.refresh() }
        statusPopover.menu.items.first(where: { $0.action == #selector(hideCard) })?.state = cardVisible ? .off : .on
        statusPopover.menu.items.first(where: { $0.action == #selector(showCard) })?.state = cardVisible ? .on : .off
    }
    @objc private func centerCard() { panel.center(); showCard() }
    @objc private func openFlClash() {
        statusPopover.close()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: monitor.client.appPath), configuration: configuration)
    }
    private func customMenuFields()->[MenuField] {
        let s=monitor.snapshot,reading=sites.readings[menuSite]
        let palette=MenuBarPalette.load()
        let remaining=MenuBarDisplay.remaining(used:s.usedBytes,total:s.totalBytes)
        return [MenuField(id:"site",title:"站点名称",value:menuSite,color:MenuBarPalette.color(palette.name)),
                MenuField(id:"latency",title:"站点延迟",value:reading?.milliseconds.map { "\($0) ms" } ?? "—",color:MenuBarPalette.color(MenuBarDisplay.isSlow(milliseconds:reading?.milliseconds) ? palette.slow : palette.fast),colorKey:MenuBarDisplay.isSlow(milliseconds:reading?.milliseconds) ? "slow" : "fast"),
                MenuField(id:"profile",title:"套餐名称",value:s.profileName ?? "—"),
                MenuField(id:"ring",title:"剩余额度圆环",value:"",color:MenuBarPalette.color(palette.ring),ring:true,progress:remaining),
                MenuField(id:"quota",title:"剩余额度",value:remaining.map { String(format:"剩 %.0f%%",$0*100) } ?? "剩 —",color:MenuBarPalette.color(palette.ring)),
                MenuField(id:"node",title:"当前节点",value:s.nodeName ?? "—",defaultVisible:false),
                MenuField(id:"connections",title:"当前连接数",value:s.isConnected ? s.connectionCount.map { "\($0) 连接" } ?? "—" : "—",defaultVisible:false),
                MenuField(id:"expiry",title:"到期倒计时",value:SubscriptionCountdown.text(expiry:s.expiresAt),defaultVisible:false),
                MenuField(id:"download",title:"下载速度",value:MenuBarDisplay.rate(s.downloadBps),color:.cyan,defaultVisible:false),
                MenuField(id:"upload",title:"上传速度",value:MenuBarDisplay.rate(s.uploadBps),color:.systemPurple,defaultVisible:false)]
    }
    @objc private func showAppSettings() { AppSettingsController.shared.show() }
    @objc private func customizeMenu() { AppSettingsController.shared.show("menubar") }
    @objc private func showMenuSettings() { AppSettingsController.shared.show("menubar") }
    @objc private func switchClient() {
        defer { AppSettingsController.shared.refresh() }
        nodePicker.close()
        statusPopover.close()
        monitor.switchClient()
        updateTrafficMenu()
        host.rootView = desktopCard()
        openFlClash()
    }
    @objc private func refresh() { monitor.refresh(); sites.refresh() }
    private func configureSites() {
        sites.configure(large: statusPopover.isShown || (cardVisible && size == .large), menuSite: menuSite, snapshot: monitor.snapshot)
    }
    @objc private func selectSize(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let option = CardSize(rawValue: raw) { setSize(option) }
    }
    private func setSize(_ option: CardSize) {
        defer { AppSettingsController.shared.refresh() }
        size = option; panel.cardSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "cardSize")
        let dimensions = size.dimensions, old = panel.frame
        var frame = NSRect(x: old.minX, y: old.maxY - dimensions.height, width: dimensions.width, height: dimensions.height)
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        }
        host.rootView = desktopCard()
        panel.setFrame(frame, display: true)
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
        statusPopover.menu.items.first(where: { $0.title == "卡片尺寸" })?.submenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == size.rawValue ? .on : .off
        }
        configureSites()
    }
    @objc private func selectSite(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String else { return }
        setMenuSite(value)
    }
    private func setMenuSite(_ value: String) {
        defer { AppSettingsController.shared.refresh() }
        guard ProbeSite.all.contains(where: { $0.id == value }) else { return }
        menuSite = value
        UserDefaults.standard.set(value, forKey: "menuLatencySite")
        statusPopover.menu.items.first(where: { $0.title == "状态栏延迟站点" })?.submenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == value ? .on : .off
        }
        configureSites(); updateStatus(); host.rootView = desktopCard()
    }
    private func updateStatus() {
        statusPopover.update()
        guard let button = statusItem?.button else { return }
        let snapshot = monitor.snapshot, reading = sites.readings[menuSite]
        let delay = reading?.milliseconds.map { "\($0) ms" } ?? "—"
        let profile = snapshot.profileName ?? "未选配置"
        let shortProfile = profile.count > 10 ? String(profile.prefix(9)) + "…" : profile
        let remaining = MenuBarDisplay.remaining(used: snapshot.usedBytes, total: snapshot.totalBytes)
        let progress = remaining.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
        let node = snapshot.nodeName.map { $0.count > 18 ? String($0.prefix(17))+"…" : $0 } ?? "—"
        let down = MenuBarDisplay.rate(snapshot.downloadBps), up = MenuBarDisplay.rate(snapshot.uploadBps)
        let displayKey = [menuSite, delay, shortProfile, remaining.map { String(format:"%.6f",$0) } ?? "unknown", menuOptions.node ? node : "", menuOptions.download ? down : "", menuOptions.upload ? up : ""].joined(separator:"|")
        if displayKey != lastStatusDisplayKey {
            button.image = MenuBarDisplay.image(icon: ProbeSite.icon(menuSite), site: menuSite,
                                               delay: delay, milliseconds:reading?.milliseconds, profile: shortProfile, remaining: remaining, options:menuOptions, node:node, download:down, upload:up)
            button.imagePosition = .imageOnly
            lastStatusDisplayKey = displayKey
        }
        button.toolTip = "\(snapshot.client.title) · \(profile)\n\(menuSite)：\(reading?.status ?? "待检测") · \(delay)\n套餐剩余 \(progress) · \(sites.routeLabel)\nHTTPS 首响应，每分钟更新\n网速：\(snapshot.trafficLabel)"
        button.setAccessibilityLabel(button.toolTip)
        MenuCustomizationPanel.apply(button,fields:customMenuFields(),icon:ProbeSite.icon(menuSite))
    }
    @objc private func toggleLogin() {
        defer { AppSettingsController.shared.refresh() }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            statusPopover.menu.items.first(where: { $0.action == #selector(toggleLogin) })?.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert(); alert.messageText = "登录启动未设置成功"
            alert.informativeText = "请在系统设置的登录项中检查实时卡片。"; alert.runModal()
        }
    }
    @objc private func toggleLock() {
        defer { AppSettingsController.shared.refresh() }
        positionLocked.toggle()
        UserDefaults.standard.set(positionLocked, forKey: "positionLocked")
        panel.positionLocked = positionLocked
        panel.isMovable = !positionLocked
        panel.isMovableByWindowBackground = false
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
        host.rootView = desktopCard()
        if let item = statusPopover.menu.items.first(where: { $0.action == #selector(toggleLock) }) {
            item.title = positionLocked ? "解锁位置" : "锁定位置"
        }
    }
    @objc private func toggleTop() {
        defer { AppSettingsController.shared.refresh() }
        alwaysOnTop.toggle()
        UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
        updateLevel(); host.rootView = desktopCard()
        if let item = statusPopover.menu.items.first(where: { $0.action == #selector(toggleTop) }) {
            item.title = alwaysOnTop ? "✓ 置于其他窗口上方" : "置于其他窗口上方"
        }
        if cardVisible { panel.orderFrontRegardless() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCard(); return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        nodePicker.close()
        panel?.saveFrame(usingName: "FlClashLiveCardFrame")
        sites.stop()
        monitor.stop()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

import Combine

@main
enum FlClashLiveApplication {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--enable-login") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                print("LOGIN_STATUS=\(SMAppService.mainApp.status.rawValue)")
            } catch { print("LOGIN_ERROR=\((error as NSError).code)") }
            return
        }
        let app = NSApplication.shared
        let delegate = MonitorDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
