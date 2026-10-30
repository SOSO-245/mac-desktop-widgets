import AppKit
import SwiftUI
import Combine
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
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    @Published private var settingsRevision = 0
    var settingsContent: AnyView { AnyView(AppUpdateSettingsContent(model:self)) }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—" }
    var statusText: String { startupError != nil ? "更新暂不可用" : availableVersion.map { "发现新版本 \($0)" } ?? "通过 GitHub 获取此软件的正式更新" }
    var canCheck: Bool { startupError != nil || controller.updater.canCheckForUpdates }
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            if !newValue { controller.updater.automaticallyDownloadsUpdates = false }
            controller.updater.automaticallyChecksForUpdates = newValue; refreshItems()
        }
    }
    var automaticDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set {
            if newValue { controller.updater.automaticallyChecksForUpdates = true }
            controller.updater.automaticallyDownloadsUpdates = newValue; refreshItems()
        }
    }
    private var controller: SPUStandardUpdaterController!
    private var checkObservation: AnyCancellable?
    private let dots = NSHashTable<UpdateDot>.weakObjects()
    private var availableVersion: String?
    private var startupError: String?
    var beforeShowingUpdate: (() -> Void)?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do { try controller.updater.start() }
        catch { startupError = error.localizedDescription }
        checkObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshItems() }
    }

    func attach(to status: NSStatusItem) {
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

    @objc func check() {
        beforeShowingUpdate?()
        if let startupError {
            let alert = NSAlert(); alert.messageText = "更新暂不可用"; alert.informativeText = startupError; alert.runModal(); return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
    @objc func showReleases() {
        beforeShowingUpdate?()
        NSWorkspace.shared.open(URL(string: "https://github.com/SOSO-245/mac-desktop-widgets/releases")!)
    }
    private func refreshItems() {
        settingsRevision &+= 1
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

private struct AppUpdateSettingsContent: View {
    @ObservedObject var model: AppUpdater
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            GroupBox {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text("当前版本 \(model.currentVersion)").font(.headline)
                        Text(model.statusText).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("检查更新…") { model.check() }.disabled(!model.canCheck)
                }.padding(10)
            }
            GroupBox("自动更新") {
                VStack(alignment:.leading,spacing:14) {
                    Toggle("每天自动检查更新",isOn:Binding(get:{model.automaticChecks},set:{model.automaticChecks=$0}))
                    Toggle("自动下载并在退出时安装",isOn:Binding(get:{model.automaticDownloads},set:{model.automaticDownloads=$0}))
                    Text("软件更新不影响桌面卡片的数据刷新频率。关闭自动检查时，也会关闭自动下载。").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
            }
            Button("查看 GitHub 发布记录") { model.showReleases() }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
