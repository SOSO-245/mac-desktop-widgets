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
            let onControl = inHeader && (point.x <= 42 || point.x >= size.width - 89)
            let inSiteList = cardSize == .large && point.y < size.height - 164
            if NSRect(origin: .zero, size: size).contains(point), !onControl, !inSiteList {
                guard !positionLocked else { return }
                performDrag(with: event)
                saveFrame(usingName: "NikkiLiveCardFrame")
                return
            }
        }
        super.sendEvent(event)
    }
}

private final class CardHostingView: NSHostingView<NikkiCard> {
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor
final class MonitorDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor = MonitorCoordinator()
    private let sites = SiteLatencyMonitor()
    private var size = CardSize(rawValue: UserDefaults.standard.string(forKey: "cardSize") ?? "") ?? .medium
    private var menuSite = UserDefaults.standard.string(forKey: "menuLatencySite") ?? "Google"
    private var cardVisible = true
    private var panel: CardPanel!
    private var host: CardHostingView!
    private var statusItem: NSStatusItem!
    private var lastStatusDisplayKey: String?
    private var observer: Any?
    private var settingsWindow: NSWindow?
    private var nodesWindow: NSWindow?
    private var menuSettingsWindow: NSWindow?
    private var menuOptions = MenuBarOptions.load()
    private var subscriptions = Set<AnyCancellable>()
    private var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
    private var positionLocked = UserDefaults.standard.bool(forKey: "positionLocked")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProbeSite.all.prefix(6).contains(where: { $0.id == menuSite }) { menuSite = "Google" }
        let size = self.size.dimensions
        panel = CardPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Nikki 实时卡片"
        panel.identifier = NSUserInterfaceItemIdentifier("NikkiLiveCard")
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
        if panel.setFrameUsingName("NikkiLiveCardFrame") {
            // Preserve the user's top-left position while migrating old card sizes.
            let restored = panel.frame
            panel.setFrame(NSRect(x: restored.minX, y: restored.maxY - size.height,
                                  width: size.width, height: size.height), display: false)
        } else {
            panel.center()
        }
        host = CardHostingView(rootView: card())
        panel.contentView = host
        panel.setFrameAutosaveName("NikkiLiveCardFrame")
        panel.saveFrame(usingName: "NikkiLiveCardFrame")
        updateLevel()
        monitor.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.host.rootView = self.card()
            self.configureSites()
            self.updateStatus()
        }.store(in: &subscriptions)
        createMenu()
        sites.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.host.rootView = self.card(); self.updateStatus()
        }.store(in: &subscriptions)
        sites.monitor = monitor
        monitor.start()
        configureSites()
        setSize(self.size)
        panel.orderFrontRegardless()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    private func card() -> NikkiCard {
        NikkiCard(size: size, siteReadings: sites.readings, siteRoute: sites.routeLabel,
                    onSize: { [weak self] in self?.setSize($0) },
                    menuSite: menuSite, onMenuSite: { [weak self] in self?.setMenuSite($0) },
                    onSiteRefresh: { [weak self] in self?.sites.refresh(siteID: $0) },
                    snapshot: monitor.snapshot, alwaysOnTop: alwaysOnTop, positionLocked: positionLocked,
                    onOpen: { [weak self] in self?.openNikki() },
                    onSwitch: { [weak self] in self?.switchClient() },
                    onSettings: { [weak self] in self?.showSettings() },
                    onMenuSettings: { [weak self] in self?.showMenuSettings() },
                    onRefresh: { [weak self] in self?.refresh() },
                    onToggleTop: { [weak self] in self?.toggleTop() },
                    onToggleLock: { [weak self] in self?.toggleLock() },
                    onQuit: { NSApp.terminate(nil) })
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Nikki 实时卡片")
        statusItem.button?.toolTip = "Nikki 实时卡片"
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        add("显示卡片", #selector(showCard))
        add("打开 Nikki 管理网页", #selector(openNikki))
        add("切换节点", #selector(switchClient))
        add("连接设置", #selector(showSettings))
        add("菜单栏显示", #selector(showMenuSettings))
        add("刷新数据", #selector(refresh))
        let sizes = NSMenuItem(title: "卡片尺寸", action: nil, keyEquivalent: "")
        sizes.submenu = NSMenu()
        for option in CardSize.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = option.rawValue
            item.state = size == option ? .on : .off; sizes.submenu?.addItem(item)
        }
        menu.addItem(sizes)
        let latency = NSMenuItem(title: "状态栏延迟站点", action: nil, keyEquivalent: "")
        latency.submenu = NSMenu()
        for site in ProbeSite.all.prefix(6) {
            let item = NSMenuItem(title: site.id, action: #selector(selectSite(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = site.id
            item.image = ProbeSite.icon(site.id)
            item.state = site.id == menuSite ? .on : .off; latency.submenu?.addItem(item)
        }
        menu.addItem(latency)
        add("登录时启动", #selector(toggleLogin))
        menu.items.last?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(alwaysOnTop ? "✓ 置于其他窗口上方" : "置于其他窗口上方", #selector(toggleTop))
        add(positionLocked ? "解锁位置" : "锁定位置", #selector(toggleLock))
        add("卡片移到屏幕中央", #selector(centerCard))
        add("隐藏卡片", #selector(hideCard))
        menu.addItem(.separator())
        add("退出实时卡片", #selector(quit))
        statusItem.menu = menu
        updateStatus()
    }

    private func updateLevel() {
        panel.level = alwaysOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    @objc private func showCard() { cardVisible = true; configureSites(); panel.orderFrontRegardless() }
    @objc private func hideCard() { cardVisible = false; configureSites(); panel.orderOut(nil) }
    @objc private func centerCard() { panel.center(); showCard() }
    @objc private func openNikki() {
        if let endpoint = try? ConnectionSettings.normalized(monitor.settings.endpoint), let url = URL(string:endpoint + "/ui/") { NSWorkspace.shared.open(url) }
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:350),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            settingsWindow?.title = "Nikki · 连接设置"; settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.contentView = NSHostingView(rootView:ConnectionView(monitor:monitor)); settingsWindow?.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func showMenuSettings() {
        if menuSettingsWindow == nil {
            menuSettingsWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:510,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            menuSettingsWindow?.title="Nikki · 菜单栏显示"; menuSettingsWindow?.isReleasedWhenClosed=false
            menuSettingsWindow?.contentView=NSHostingView(rootView:MenuBarSettingsView(onSave:{ [weak self] value in
                self?.menuOptions=value; self?.lastStatusDisplayKey=nil; self?.updateStatus(); self?.menuSettingsWindow?.orderOut(nil)
            }));menuSettingsWindow?.center()
        }
        menuSettingsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func switchClient() {
        if nodesWindow == nil {
            nodesWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:590,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            nodesWindow?.title = "Nikki · 切换节点"; nodesWindow?.isReleasedWhenClosed = false
            nodesWindow?.contentView = NSHostingView(rootView:NodePickerView(monitor:monitor)); nodesWindow?.center()
        }
        monitor.refresh(); nodesWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func refresh() { monitor.refresh(); sites.refresh() }
    private func configureSites() {
        sites.configure(large: cardVisible && size == .large, menuSite: menuSite, snapshot: monitor.snapshot)
    }
    @objc private func selectSize(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let option = CardSize(rawValue: raw) { setSize(option) }
    }
    private func setSize(_ option: CardSize) {
        size = option; panel.cardSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "cardSize")
        let dimensions = size.dimensions, old = panel.frame
        var frame = NSRect(x: old.minX, y: old.maxY - dimensions.height, width: dimensions.width, height: dimensions.height)
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        }
        host.rootView = card()
        panel.setFrame(frame, display: true)
        panel.saveFrame(usingName: "NikkiLiveCardFrame")
        statusItem.menu?.items.first(where: { $0.title == "卡片尺寸" })?.submenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == size.rawValue ? .on : .off
        }
        configureSites()
    }
    @objc private func selectSite(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String else { return }
        setMenuSite(value)
    }
    private func setMenuSite(_ value: String) {
        guard ProbeSite.all.contains(where: { $0.id == value }) else { return }
        menuSite = value
        UserDefaults.standard.set(value, forKey: "menuLatencySite")
        statusItem.menu?.items.first(where: { $0.title == "状态栏延迟站点" })?.submenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == value ? .on : .off
        }
        configureSites(); updateStatus(); host.rootView = card()
    }
    private func updateStatus() {
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
        button.toolTip = "\(snapshot.client.title) · \(profile)\n\(menuSite)：\(reading?.status ?? "待检测") · \(delay)\n套餐剩余 \(progress) · \(sites.routeLabel)\n旁路由策略组测速，每分钟更新"
        button.setAccessibilityLabel(button.toolTip)
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            statusItem.menu?.items.first(where: { $0.action == #selector(toggleLogin) })?.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert(); alert.messageText = "登录启动未设置成功"
            alert.informativeText = "请在系统设置的登录项中检查实时卡片。"; alert.runModal()
        }
    }
    @objc private func toggleLock() {
        positionLocked.toggle()
        UserDefaults.standard.set(positionLocked, forKey: "positionLocked")
        panel.positionLocked = positionLocked
        panel.isMovable = !positionLocked
        panel.isMovableByWindowBackground = false
        panel.saveFrame(usingName: "NikkiLiveCardFrame")
        host.rootView = card()
        if let item = statusItem.menu?.items.first(where: { $0.action == #selector(toggleLock) }) {
            item.title = positionLocked ? "解锁位置" : "锁定位置"
        }
    }
    @objc private func toggleTop() {
        alwaysOnTop.toggle()
        UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
        updateLevel(); host.rootView = card()
        if let item = statusItem.menu?.items.first(where: { $0.action == #selector(toggleTop) }) {
            item.title = alwaysOnTop ? "✓ 置于其他窗口上方" : "置于其他窗口上方"
        }
        panel.orderFrontRegardless()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCard(); return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        panel?.saveFrame(usingName: "NikkiLiveCardFrame")
        sites.stop()
        monitor.stop()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

import Combine

@main
enum NikkiLiveApplication {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--configure-stdin") {
            do {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let values = try JSONSerialization.jsonObject(with:data) as? [String:String], let endpoint = values["endpoint"], let secret = values["secret"] else { throw APIError.message("输入不完整") }
                var settings = ConnectionSettings.load(); settings.endpoint = try ConnectionSettings.normalized(endpoint)
                try Vault.save(secret,endpoint:settings.endpoint); settings.save(); print("已保存连接")
            } catch { print("配置保存失败"); exit(1) }
            return
        }
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
