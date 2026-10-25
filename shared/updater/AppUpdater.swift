import AppKit
import Sparkle

private final class UpdateDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor(calibratedRed: 0.35, green: 1, blue: 0.72, alpha: 1).setFill(); circle.fill()
        NSColor.black.withAlphaComponent(0.45).setStroke(); circle.lineWidth = 1; circle.stroke()
    }
}

/// Sparkle owns scheduling, authenticated download, replacement and relaunch.
/// No global maintenance agent and no access to the host's private preferences.
@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate, NSMenuItemValidation {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController!
    private let checkItems = NSHashTable<NSMenuItem>.weakObjects()
    private let parents = NSHashTable<NSMenuItem>.weakObjects()
    private let dots = NSHashTable<UpdateDot>.weakObjects()
    private let autoItems = NSHashTable<NSMenuItem>.weakObjects()
    private let installItems = NSHashTable<NSMenuItem>.weakObjects()
    private var availableVersion: String?
    private var startupError: String?
    var beforeShowingUpdate: (() -> Void)?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do { try controller.updater.start() }
        catch { startupError = error.localizedDescription }
    }

    func attach(to status: NSStatusItem, menu: NSMenu) {
        addMenu(to: menu)
        guard let button = status.button,
              !button.subviews.contains(where: { $0 is UpdateDot }) else { return }
        let dot = UpdateDot(frame: .zero)
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = availableVersion == nil
        dot.setAccessibilityElement(false)
        button.addSubview(dot)
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2)])
        dots.add(dot)
    }

    func addMenu(to menu: NSMenu) {
        guard !menu.items.contains(where: { $0.identifier?.rawValue == "app-update-menu" }) else { return }
        let parent = NSMenuItem(title: "软件更新", action: nil, keyEquivalent: "")
        parent.identifier = NSUserInterfaceItemIdentifier("app-update-menu")
        let sub = NSMenu(); parent.submenu = sub
        func add(_ title: String, _ action: Selector?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; sub.addItem(item); return item
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        add("当前版本 \(version)", nil).isEnabled = false
        checkItems.add(add("检查更新…", #selector(check)))
        sub.addItem(.separator())
        autoItems.add(add("每天自动检查", #selector(toggleChecks)))
        installItems.add(add("自动下载并在退出时安装", #selector(toggleInstall)))
        _ = add("查看发布记录", #selector(showReleases))
        menu.insertItem(parent, at: max(0, menu.items.count - 1)); parents.add(parent)
        refreshItems()
    }

    @objc func check() {
        beforeShowingUpdate?()
        if let startupError {
            let alert = NSAlert(); alert.messageText = "更新暂不可用"; alert.informativeText = startupError; alert.runModal(); return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
    @objc private func toggleChecks() {
        let next = !controller.updater.automaticallyChecksForUpdates
        if !next { controller.updater.automaticallyDownloadsUpdates = false }
        controller.updater.automaticallyChecksForUpdates = next; refreshItems()
    }
    @objc private func toggleInstall() {
        let next = !controller.updater.automaticallyDownloadsUpdates
        if next { controller.updater.automaticallyChecksForUpdates = true }
        controller.updater.automaticallyDownloadsUpdates = next; refreshItems()
    }
    @objc private func showReleases() {
        beforeShowingUpdate?()
        NSWorkspace.shared.open(URL(string: "https://github.com/SOSO-245/mac-desktop-widgets/releases")!)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        refreshItems()
        if menuItem.action == #selector(check) { return startupError != nil || controller.updater.canCheckForUpdates }
        return true
    }
    private func refreshItems() {
        for item in parents.allObjects { item.title = availableVersion == nil ? "软件更新" : "● 软件更新" }
        for item in checkItems.allObjects { item.title = availableVersion.map { "安装更新 \($0)…" } ?? "检查更新…" }
        for item in autoItems.allObjects { item.state = controller.updater.automaticallyChecksForUpdates ? .on : .off }
        for item in installItems.allObjects { item.state = controller.updater.automaticallyDownloadsUpdates ? .on : .off }
        for dot in dots.allObjects { dot.isHidden = availableVersion == nil }
    }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString; refreshItems()
        if handleShowingUpdate { beforeShowingUpdate?() }
    }
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil; refreshItems() }
    func standardUserDriverWillShowModalAlert() { beforeShowingUpdate?() }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString; refreshItems()
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { availableVersion = nil; refreshItems() }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
