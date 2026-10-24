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
                saveFrame(usingName: "FlClashLiveCardFrame")
                return
            }
        }
        super.sendEvent(event)
    }
}

private final class CardHostingView: NSHostingView<FlClashCard> {
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
    private var lastStatusDisplayKey: String?
    private var observer: Any?
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
        host = CardHostingView(rootView: card())
        panel.contentView = host
        panel.setFrameAutosaveName("FlClashLiveCardFrame")
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
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
        monitor.start()
        configureSites()
        setSize(self.size)
        if cardVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        updateVisibilityMark()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    private func card() -> FlClashCard {
        FlClashCard(size: size, siteReadings: sites.readings, siteRoute: sites.routeLabel,
                    onSize: { [weak self] in self?.setSize($0) },
                    menuSite: menuSite, onMenuSite: { [weak self] in self?.setMenuSite($0) },
                    onSiteRefresh: { [weak self] in self?.sites.refresh(siteID: $0) },
                    snapshot: monitor.snapshot, alwaysOnTop: alwaysOnTop, positionLocked: positionLocked,
                    onOpen: { [weak self] in self?.openFlClash() },
                    onSwitch: { [weak self] in self?.switchClient() },
                    onRefresh: { [weak self] in self?.refresh() },
                    onToggleTop: { [weak self] in self?.toggleTop() },
                    onToggleLock: { [weak self] in self?.toggleLock() },
                    onQuit: { NSApp.terminate(nil) }, onMenuSettings:{ [weak self] in self?.showMenuSettings() })
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
        add("菜单栏显示", #selector(showMenuSettings))
        add("菜单栏文字与图标…", #selector(customizeMenu))
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
        updateVisibilityMark()
        updateStatus()
    }

    private func updateLevel() {
        panel.level = alwaysOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    @objc private func showCard() { cardVisible = true; UserDefaults.standard.set(false,forKey:"cardHidden"); updateVisibilityMark(); configureSites(); panel.orderFrontRegardless() }
    @objc private func hideCard() { if !cardVisible { showCard(); return }; cardVisible = false; UserDefaults.standard.set(true,forKey:"cardHidden"); updateVisibilityMark(); configureSites(); panel.orderOut(nil) }
    private func updateVisibilityMark() {
        statusItem.menu?.items.first(where: { $0.action == #selector(hideCard) })?.state = cardVisible ? .off : .on
        statusItem.menu?.items.first(where: { $0.action == #selector(showCard) })?.state = cardVisible ? .on : .off
    }
    @objc private func centerCard() { panel.center(); showCard() }
    @objc private func openFlClash() {
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
    @objc private func customizeMenu() {
        MenuCustomizationPanel.shared.show(title:monitor.snapshot.client.title,fields:customMenuFields(),icon:ProbeSite.icon(menuSite),extraColors:[("fast","常规延迟",MenuCustomization.color("#66FFAD")),("slow","超过 2000 ms",MenuCustomization.color("#FF6EC2"))]) { [weak self] in
            self?.lastStatusDisplayKey=nil;self?.updateStatus()
        }
    }
    @objc private func showMenuSettings() {
        if menuSettingsWindow == nil {
            menuSettingsWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:510,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            menuSettingsWindow?.title="VPN 卡片 · 菜单栏显示"; menuSettingsWindow?.isReleasedWhenClosed=false
            menuSettingsWindow?.contentView=NSHostingView(rootView:MenuBarSettingsView(onSave:{ [weak self] value in
                self?.menuOptions=value; self?.lastStatusDisplayKey=nil; self?.updateStatus(); self?.menuSettingsWindow?.orderOut(nil)
            }));menuSettingsWindow?.center()
        }
        menuSettingsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func switchClient() {
        monitor.switchClient()
        host.rootView = card()
        openFlClash()
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
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
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
        button.toolTip = "\(snapshot.client.title) · \(profile)\n\(menuSite)：\(reading?.status ?? "待检测") · \(delay)\n套餐剩余 \(progress) · \(sites.routeLabel)\nHTTPS 首响应，每分钟更新"
        button.setAccessibilityLabel(button.toolTip)
        MenuCustomizationPanel.apply(button,fields:customMenuFields(),icon:ProbeSite.icon(menuSite))
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
        panel.saveFrame(usingName: "FlClashLiveCardFrame")
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
