import AppKit
import SwiftUI

/// Each executable owns one controller and keeps its existing defaults domain.
struct AppSettingsPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var scrolls: Bool = true
    let content: () -> AnyView
}

@MainActor
final class AppSettingsController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AppSettingsController()
    @Published private(set) var pages: [AppSettingsPage] = []
    @Published private(set) var selectedID = ""
    @Published private(set) var visited: Set<String> = []
    @Published private(set) var revision = 0
    private(set) var appTitle = ""
    private var window: NSWindow?
    private var beforeShow: () -> Void = {}
    private let defaults: UserDefaults
    private let presentsWindows: Bool
    var isVisible: Bool { window?.isVisible == true }
    var windowIdentity: ObjectIdentifier? { window.map(ObjectIdentifier.init) }
    func close() { window?.orderOut(nil) }
    init(defaults: UserDefaults = .standard, presentsWindows: Bool = true) {
        self.defaults = defaults
        self.presentsWindows = presentsWindows
        super.init()
    }

    func configure(title: String, pages: [AppSettingsPage], beforeShow: @escaping () -> Void = {}) {
        appTitle = title
        var ids = Set<String>()
        self.pages = pages.filter { !$0.id.isEmpty && ids.insert($0.id).inserted }
        self.beforeShow = beforeShow
        let saved = defaults.string(forKey: "settings.selectedPage.v1")
        selectedID = self.pages.first { $0.id == saved }?.id ?? self.pages.first?.id ?? ""
        visited = selectedID.isEmpty ? [] : [selectedID]
        window?.title = title + " · 设置"
    }

    func show(_ pageID: String? = nil) {
        guard !pages.isEmpty else { return }
        beforeShow()
        if let pageID { select(pageID) }
        if window == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 690),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            created.title = appTitle + " · 设置"
            created.identifier = NSUserInterfaceItemIdentifier("UnifiedAppSettings")
            created.minSize = NSSize(width: 780, height: 560)
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.contentView = NSHostingView(rootView: AppSettingsShell(model: self))
            created.center()
            if presentsWindows { created.setFrameAutosaveName("UnifiedAppSettingsFrame") }
            window = created
        }
        refresh()
        if presentsWindows {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refresh() { revision &+= 1 }
    func select(_ id: String) {
        guard pages.contains(where: { $0.id == id }) else { return }
        visited.insert(id)
        selectedID = id
        defaults.set(id, forKey: "settings.selectedPage.v1")
    }
    func installMenuItem(in menu: NSMenu) {
        guard !menu.items.contains(where: { $0.identifier?.rawValue == "app-settings" || $0.title == "设置…" }) else { return }
        let item = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        item.identifier = NSUserInterfaceItemIdentifier("app-settings")
        item.target = self
        menu.insertItem(item, at: max(0, menu.items.count - 1))
    }
    @objc private func openSettings() { show() }
}

private struct AppSettingsShell: View {
    @ObservedObject var model: AppSettingsController
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.appTitle).font(.headline).padding(.horizontal, 12).padding(.top, 20)
                VStack(spacing: 4) {
                    ForEach(model.pages) { page in
                        Button { model.select(page.id) } label: {
                            Label(page.title, systemImage: page.symbol)
                                .font(.system(size: 13, weight: model.selectedID == page.id ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .background(model.selectedID == page.id ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityAddTraits(model.selectedID == page.id ? [.isSelected] : [])
                    }
                }
                Spacer()
            }.padding(.horizontal, 10).frame(width: 180).background(.quaternary.opacity(0.45))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(model.pages.first { $0.id == model.selectedID }?.title ?? "设置")
                    .font(.system(size: 24, weight: .bold)).padding(.horizontal, 24).padding(.vertical, 21)
                Divider()
                // Retain visited pages, including unsaved connection fields, when
                // navigating. Merely opening settings never initializes a store.
                ZStack(alignment: .topLeading) {
                    ForEach(model.pages.filter { model.visited.contains($0.id) }) { page in
                        Group {
                            if page.scrolls {
                                ScrollView { page.content().frame(maxWidth: .infinity, alignment: .topLeading).padding(24) }
                            } else {
                                page.content().padding(24)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .opacity(model.selectedID == page.id ? 1 : 0)
                            .allowsHitTesting(model.selectedID == page.id)
                            .disabled(model.selectedID != page.id)
                            .accessibilityHidden(model.selectedID != page.id)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 760, minHeight: 520).preferredColorScheme(.dark)
    }
}
