import AppKit
import SwiftUI

final class CardPanel: NSPanel {
    var dragEnabled = false
    override func sendEvent(_ event: NSEvent) {
        if dragEnabled, event.type == .leftMouseDown, event.window === self,
           event.locationInWindow.y > frame.height - 46,
           event.locationInWindow.x < frame.width - 66 {
            performDrag(with: event)
            saveFrame(usingName: "APIUsageDesktop")
            return
        }
        super.sendEvent(event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store(preview: CommandLine.arguments.contains("--preview"))
    var status: NSStatusItem!
    var desktop: CardPanel!
    var floating: CardPanel!
    var settings: NSWindow?
    var outside: Any?
    var local: Any?
    let d = UserDefaults.standard
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--preview") { renderPreview(); return }
        d.register(defaults: ["size": "large", "selection": "openai", "interval": 5, "locked": true, "desktopVisible": true, "darkness": 0.65, "menuIcon": true, "menuColor": "mint", "glass": true, "brightness": -45.0, "transparency": 20.0])
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self; status.button?.action = #selector(clicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        desktop = panel(); desktop.delegate = self
        desktop.setFrameAutosaveName("APIUsageDesktop")
        floating = panel(); floating.level = .popUpMenu
        store.onChange = { [weak self] in self?.updateStatus() }
        apply()
        if !desktop.setFrameUsingName("APIUsageDesktop"), let screen = NSScreen.main {
            desktop.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - desktop.frame.width - 24, y: screen.visibleFrame.maxY - desktop.frame.height - 24))
        }
        ToolboxBridge.shared.start(panel: desktop, changed: { [weak self] in self?.apply() }, settings: { [weak self] in self?.showSettings() })
        store.start(); updateStatus()
        if !store.hasOpenAI && !store.hasDeepSeek { showSettings() }
    }
    func panel() -> CardPanel {
        let p = CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.isReleasedWhenClosed = false
        return p
    }
    func dimensions(_ size: String) -> NSSize { size == "small" ? NSSize(width: 164, height: 164) : size == "medium" ? NSSize(width: 344, height: 164) : NSSize(width: 344, height: 344) }
    func card(_ size: String, desktop: Bool) -> Card {
        Card(store: store, size: size, desktop: desktop, refresh: { [weak self] in Task { await self?.store.refresh() } }, lock: { [weak self] in guard let self else { return }; self.d.set(!self.d.bool(forKey: "locked"), forKey: "locked"); self.apply() }, settings: { [weak self] in self?.showSettings() })
    }
    func apply() {
        guard desktop != nil else { return }
        let size = d.string(forKey: "size") ?? "large"
        let top = desktop.frame.maxY; let oldX = desktop.frame.minX
        desktop.setContentSize(dimensions(size))
        if top > 0 { desktop.setFrameOrigin(NSPoint(x: oldX, y: top - desktop.frame.height)) }
        desktop.contentView = NSHostingView(rootView: card(size, desktop: true))
        desktop.isMovableByWindowBackground = false
        desktop.dragEnabled = !d.bool(forKey: "locked")
        desktop.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        if d.bool(forKey: "desktopVisible") { desktop.orderFrontRegardless() } else { desktop.orderOut(nil) }
        updateStatus()
    }
    func updateStatus() {
        guard let b = status?.button else { return }
        let selection = d.string(forKey: "selection") ?? "openai"
        let title = selection == "deepseek" ? "DeepSeek · " + store.balanceText : selection == "tokens" ? "API · " + (store.snapshot.usage.map { compact($0.value.total) + " Token" } ?? "—") : "API · " + store.costText
        let color: NSColor = d.string(forKey: "menuColor") == "pink" ? .systemPink : d.string(forKey: "menuColor") == "cyan" ? .systemCyan : d.string(forKey: "menuColor") == "white" ? .white : NSColor(red: 0.35, green: 1, blue: 0.77, alpha: 1)
        b.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color])
        b.image = d.bool(forKey: "menuIcon") ? NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "API 用量") : nil
        b.imagePosition = .imageLeading
        b.toolTip = "API 用量卡片 · 左键查看，右键设置"
    }
    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { menu(); return }
        if floating.isVisible { closePopover(); return }
        guard let b = status.button, let window = b.window else { return }
        let rect = window.convertToScreen(b.convert(b.bounds, to: nil))
        let bounds = (window.screen ?? NSScreen.main)!.visibleFrame
        floating.setContentSize(NSSize(width: 344, height: 344))
        floating.contentView = NSHostingView(rootView: card("large", desktop: false))
        floating.setFrameOrigin(NSPoint(x: max(bounds.minX + 8, min(bounds.maxX - 352, rect.midX - 172)), y: rect.minY - 352))
        floating.orderFrontRegardless()
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in Task { @MainActor in self?.closePopover() } }
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { self?.closePopover() }
            else if event.window !== self?.floating && event.window !== self?.status.button?.window { self?.closePopover() }
            return event
        }
    }
    func closePopover() {
        floating?.orderOut(nil)
        if let outside { NSEvent.removeMonitor(outside); self.outside = nil }
        if let local { NSEvent.removeMonitor(local); self.local = nil }
    }
    func menu() {
        let m = NSMenu()
        let settings = NSMenuItem(title: "设置与 API 连接…", action: #selector(settingsAction), keyEquivalent: ","); settings.target = self; m.addItem(settings)
        let toggle = NSMenuItem(title: "显示桌面卡片", action: #selector(toggleDesktop), keyEquivalent: ""); toggle.target = self; toggle.state = d.bool(forKey: "desktopVisible") ? .on : .off; m.addItem(toggle)
        let refresh = NSMenuItem(title: "刷新数据", action: #selector(refreshAction), keyEquivalent: "r"); refresh.target = self; m.addItem(refresh)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "退出 API 用量卡片", action: #selector(quitAction), keyEquivalent: "q"); quit.target = self; m.addItem(quit)
        status.menu = m; status.button?.performClick(nil); status.menu = nil
    }
    @objc func settingsAction() { showSettings() }
    @objc func toggleDesktop() { d.set(!d.bool(forKey: "desktopVisible"), forKey: "desktopVisible"); apply() }
    @objc func refreshAction() { Task { await store.refresh() } }
    @objc func quitAction() { NSApp.terminate(nil) }
    func showSettings() {
        closePopover()
        if settings == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 740), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "API 用量卡片 · 设置"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsPanel(store: store, changed: { [weak self] in self?.apply() }))
            w.center(); settings = w
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func windowDidMove(_ notification: Notification) { desktop?.saveFrame(usingName: "APIUsageDesktop"); ToolboxBridge.shared.didMove() }
    func renderPreview() {
        let dir = CommandLine.arguments.last!
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for size in ["small", "medium", "large"] {
            let s = dimensions(size)
            let renderer = ImageRenderer(content: card(size, desktop: true).frame(width: s.width, height: s.height).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(size + ".png"))
            }
        }
        NSApp.terminate(nil)
    }
}
@main struct Entry {
    static func main() {
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
