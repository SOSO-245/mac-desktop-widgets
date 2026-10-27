import AppKit
import SwiftUI

private struct Failure: Error, CustomStringConvertible { let description: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(description: message) }
}

private final class TemporaryDefaults {
    let name = "local.mac-desktop-widgets.settings-tests." + UUID().uuidString
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: name)!; defaults.removePersistentDomain(forName: name) }
    func cleanUp() {
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        // CFPreferences can leave an empty plist after domain removal. Remove
        // only this fixture's random domain, never an application's defaults.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: file)
    }
    deinit { cleanUp() }
}

@MainActor private final class DraftRegistry {
    var bindings: [String: Binding<String>] = [:]
    var values: [String: String] = [:]
    var actions = 0
    func capture(_ id: String, value: String, binding: Binding<String>) {
        bindings[id] = binding; values[id] = value
    }
}

private struct DraftProbe: View {
    let id: String
    let registry: DraftRegistry
    @State private var draft = "initial"
    var body: some View {
        let _ = registry.capture(id, value: draft, binding: $draft)
        VStack {
            TextField("Unsaved fixture", text: $draft)
            Toggle("Action fixture", isOn: Binding(get: { false }, set: { _ in registry.actions += 1 }))
            Button("Action fixture") { registry.actions += 1 }
        }
    }
}

@main private enum SettingsTests {
    @MainActor static func layout(_ window: NSWindow) {
        guard let view = window.contentView else { return }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
    }
    @MainActor static func wait(_ window: NSWindow? = nil, until predicate: () -> Bool, message: String) async throws {
        for _ in 0..<100 {
            if let window { layout(window) }
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw Failure(description: message)
    }
    @MainActor static func hiddenWindow(_ controller: AppSettingsController) throws -> NSWindow {
        guard let id = controller.windowIdentity,
              let window = NSApp.windows.first(where: { ObjectIdentifier($0) == id }) else {
            throw Failure(description: "Expected a retained hidden test window")
        }
        try check(!window.isVisible && !controller.isVisible, "Test unexpectedly displayed a window")
        return window
    }
    @MainActor static func attribute(_ node: NSObject, _ selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard node.responds(to: selector) else { return nil }
        return node.perform(selector)?.takeUnretainedValue()
    }
    @MainActor static func accessibleNodes(_ node: Any, seen: inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let element = node as? NSObject,
              seen.insert(ObjectIdentifier(element)).inserted else { return [] }
        let children = attribute(element, "accessibilityChildren") as? [Any] ?? []
        return [element] + children.flatMap { accessibleNodes($0, seen: &seen) }
    }
    @MainActor static func press(_ node: NSObject) -> Bool {
        // SwiftUI's generic accessibility nodes implement this public method
        // without declaring the role-specific NSAccessibilityButton protocol.
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(node.method(for: selector), to: Action.self)
        return action(node, selector)
    }
    @MainActor static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data(("FAIL " + String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // Request the accessibility tree only inside this invisible fixture
        // process; this does not enable VoiceOver or change system settings.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        var passed = 0
        func done(_ title: String) { passed += 1; FileHandle.standardOutput.write(Data(("PASS \(title)\n").utf8)) }
        let a = TemporaryDefaults(), b = TemporaryDefaults()
        defer { a.cleanUp(); b.cleanUp() }
        let pages = [
            AppSettingsPage(id: "general", title: "General", symbol: "gearshape", content: { AnyView(Text("General fixture")) }),
            AppSettingsPage(id: "desktop", title: "Desktop", symbol: "rectangle", content: { AnyView(Text("Desktop fixture")) }),
            AppSettingsPage(id: "menubar", title: "Menu", symbol: "menubar.rectangle", content: { AnyView(Text("Menu fixture")) })
        ]
        let controller = AppSettingsController(defaults: a.defaults, presentsWindows: false)
        a.defaults.set("shadowrocket", forKey: "selectedClient")
        a.defaults.set("large", forKey: "cardSize")
        a.defaults.set(true, forKey: "positionLocked")
        a.defaults.set(Data([1, 2, 3]), forKey: "connection")
        a.defaults.set("unknown-old-page", forKey: "settings.selectedPage.v1")
        controller.configure(title: "Fixture A", pages: pages + [pages[0],
            AppSettingsPage(id: "", title: "Invalid", symbol: "xmark", content: { AnyView(EmptyView()) })])
        try check(controller.pages.count == 3 && controller.selectedID == "general", "Page deduplication or safe fallback failed")
        try check(a.defaults.string(forKey: "settings.selectedPage.v1") == "unknown-old-page", "Configure unexpectedly overwrote a preference")
        controller.select("not-a-page")
        try check(controller.selectedID == "general" && a.defaults.string(forKey: "settings.selectedPage.v1") == "unknown-old-page", "Invalid selection persisted")
        controller.select("desktop")
        try check(controller.selectedID == "desktop" && a.defaults.string(forKey: "settings.selectedPage.v1") == "desktop", "Valid selection was not persisted")
        done("Unique legal pages, fallback without writes and validated selection")

        let other = AppSettingsController(defaults: b.defaults, presentsWindows: false)
        other.configure(title: "Fixture B", pages: pages)
        other.select("menubar")
        try check(a.defaults.string(forKey: "settings.selectedPage.v1") == "desktop", "App B changed app A preferences")
        try check(b.defaults.string(forKey: "settings.selectedPage.v1") == "menubar", "App B did not use its own domain")
        let reloaded = AppSettingsController(defaults: a.defaults, presentsWindows: false)
        reloaded.configure(title: "Fixture A reload", pages: pages)
        try check(reloaded.selectedID == "desktop", "Page preference did not reload from the original domain")
        done("Independent temporary defaults domains retain their own selected pages")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: ""))
        controller.installMenuItem(in: menu); controller.installMenuItem(in: menu)
        let settings = menu.items.filter { $0.identifier?.rawValue == "app-settings" }
        try check(settings.count == 1 && settings[0].keyEquivalent == ",", "Settings menu duplicated or shortcut missing")
        try check(settings[0].target as AnyObject? === controller, "Menu action targets a different settings controller")
        let legacyMenu = NSMenu()
        legacyMenu.addItem(NSMenuItem(title: "设置…", action: nil, keyEquivalent: ""))
        controller.installMenuItem(in: legacyMenu)
        try check(legacyMenu.items.count == 1, "An existing settings entry was duplicated")
        done("One settings menu item across repeated attachment and existing entry")

        controller.show("desktop")
        let firstWindow = try hiddenWindow(controller)
        let identity = controller.windowIdentity
        controller.close(); controller.show("general")
        try check(controller.windowIdentity == identity && controller.selectedID == "general", "Closing recreated the window or lost requested page")
        try check(!firstWindow.isVisible, "A test window became visible")
        controller.close()
        done("Close and reopen reuse the same hidden window without presentation")

        let registry = DraftRegistry()
        let drafts = AppSettingsController(defaults: b.defaults, presentsWindows: false)
        var initialized = Set<String>()
        let draftPages = ["connection", "appearance"].map { id in
            AppSettingsPage(id: id, title: id, symbol: "pencil", content: {
                initialized.insert(id)
                return AnyView(DraftProbe(id: id, registry: registry))
            })
        }
        drafts.configure(title: "Draft fixture", pages: draftPages)
        try check(initialized.isEmpty, "Configure evaluated page content before opening")
        drafts.show("connection")
        let draftWindow = try hiddenWindow(drafts)
        try await wait(draftWindow, until: { registry.bindings["connection"] != nil }, message: "SwiftUI did not mount the initial page")
        try check(!initialized.contains("appearance"), "Unvisited page content was initialized")
        registry.bindings["connection"]?.wrappedValue = "unsaved endpoint fixture"
        try await wait(draftWindow, until: { registry.values["connection"] == "unsaved endpoint fixture" }, message: "Draft fixture edit did not reach SwiftUI state")
        drafts.select("appearance")
        try await wait(draftWindow, until: { registry.bindings["appearance"] != nil }, message: "Second page did not mount")
        registry.bindings["appearance"]?.wrappedValue = "unsaved appearance fixture"
        try await wait(draftWindow, until: { registry.values["appearance"] == "unsaved appearance fixture" }, message: "Second draft did not update")
        drafts.select("connection"); drafts.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        layout(draftWindow)
        try check(registry.bindings["connection"]?.wrappedValue == "unsaved endpoint fixture", "Switching pages destroyed the original draft")
        try check(registry.bindings["appearance"]?.wrappedValue == "unsaved appearance fixture", "Hidden page draft was lost")
        drafts.close(); drafts.show("connection")
        try await Task.sleep(nanoseconds: 100_000_000)
        layout(draftWindow)
        try check(registry.bindings["connection"]?.wrappedValue == "unsaved endpoint fixture", "Reopening reset an unsaved draft")
        try check(registry.actions == 0, "Opening/rendering invoked a control action")
        drafts.close()
        done("Actual hidden SwiftUI pages retain drafts through navigation, refresh and reopen without actions")

        let legacy = Data(##"{"enabled":true,"visible":{"profile":false},"labels":{"latency":"延迟 {值}"},"colors":{"fast":"#112233"},"prefix":"Fixture","separator":" / ","showIcon":false,"icon":"network","emoji":"✨","iconColor":"#445566","fontSize":14}"##.utf8)
        a.defaults.set(legacy, forKey: "customMenuAppearance.v1")
        var loaded = MenuCustomization.load(defaults: a.defaults)
        try check(loaded.enabled && loaded.prefix == "Fixture" && loaded.fontSize == 14 && loaded.visible["profile"] == false,
                  "Legacy customization was not loaded using the existing key")
        loaded.prefix = "Updated fixture"
        loaded.save(defaults: a.defaults)
        try check(MenuCustomization.load(defaults: a.defaults).prefix == "Updated fixture", "Customization round trip failed")
        try check(a.defaults.string(forKey: "selectedClient") == "shadowrocket" && a.defaults.string(forKey: "cardSize") == "large"
                  && a.defaults.bool(forKey: "positionLocked") && a.defaults.data(forKey: "connection") == Data([1, 2, 3]), "Saving appearance cleared business preferences")
        try check(b.defaults.object(forKey: "customMenuAppearance.v1") == nil, "Appearance save leaked into another domain")
        done("Legacy customization key loads and updates without changing business preferences or another domain")

        var saved = 0
        let customization = AppSettingsController(defaults: a.defaults, presentsWindows: false)
        customization.configure(title: "Customization fixture", pages: [
            AppSettingsPage(id: "menubar", title: "Menu", symbol: "menubar.rectangle", content: {
                AnyView(MenuCustomizationView(fields: [MenuField(id: "profile", title: "Profile fixture", value: "Fixture")],
                                              fallback: nil, extraColors: [], defaults: a.defaults, onSave: { saved += 1 }))
            })
        ])
        customization.show()
        let customWindow = try hiddenWindow(customization)
        var toggle: NSObject?
        try await wait(customWindow, until: {
            var seen = Set<ObjectIdentifier>()
            toggle = accessibleNodes(customWindow.contentView!, seen: &seen).first {
                attribute($0, "accessibilityLabel") as? String == "使用自定义菜单栏"
                    && attribute($0, "accessibilityRole") as? String == NSAccessibility.Role.checkBox.rawValue
            }
            return toggle != nil
        }, message: "Cannot locate hidden customization checkbox")
        try check(saved == 0 && MenuCustomization.load(defaults: a.defaults).enabled, "Merely opening customization changed stored settings")
        try check(toggle.map(press) == true, "Customization checkbox rejected its accessibility action")
        try await wait(customWindow, until: { saved > 0 && !MenuCustomization.load(defaults: a.defaults).enabled }, message: "Customization control did not automatically save")
        try check(MenuCustomization.load(defaults: a.defaults).prefix == "Updated fixture", "Editing one setting reset other appearance fields")
        try check(a.defaults.string(forKey: "selectedClient") == "shadowrocket" && a.defaults.data(forKey: "connection") == Data([1, 2, 3]), "Automatic save cleared connection/source state")
        try check(!customWindow.isVisible, "Customization test exposed a real window")
        customization.close()
        done("Real customization control auto-saves to its injected suite without opening writes or business resets")
        print("\(passed) isolated settings checks passed; no app preferences, visible windows or network used")
    }
}
