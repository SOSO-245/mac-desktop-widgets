import AppKit
import SwiftUI
import ObjectiveC

// These test doubles replace both data controllers. No client data or network is used.
enum ProxyClient { case flclash, shadowrocket; var title: String { self == .flclash ? "FlClash" : "Shadowrocket" } }
struct FlClashNodeOption: Identifiable { let name: String; let type: String; let resolvedNode: String?; let isGroup: Bool; let canTest: Bool; var id: String { name } }
struct FlClashNodeGroup: Identifiable { let name: String; let selectedName: String?; let options: [FlClashNodeOption]; var id: String { name } }
struct FlClashNodeLatency { enum State { case testing, timeout, failed }; let state: State; let milliseconds: Int? }
struct ShadowrocketNodeOption: Identifiable { let id: String; let name: String; let type: String; let latencyMS: Int?; let isTesting: Bool; let isCurrent: Bool; let canSelect: Bool; let status: String; let disabledReason: String? }

@MainActor final class FlClashNodeController: ObservableObject {
    static var instance: FlClashNodeController!
    @Published var groups: [FlClashNodeGroup] = []
    @Published var selectedGroupName: String?
    @Published var latencies: [String: FlClashNodeLatency] = [:]
    @Published var isLoading = false
    @Published var isTesting = false
    @Published var selectingName: String?
    @Published var error: String?
    @Published var notice: String?
    var onSelectionChanged: (() -> Void)?
    var opened = false
    var closes = 0
    var openedGroup: String?
    init() { Self.instance = self }
    func open(preferredGroup: String?) { opened = true; openedGroup = preferredGroup }
    func close() { opened = false; closes += 1 }
    func setGroup(_ value: String) { selectedGroupName = value }
    func refresh() {}
    func testAll(force: Bool) {}
    func select(name: String) {}
}
@MainActor final class ShadowrocketNodeController: ObservableObject {
    static var instance: ShadowrocketNodeController!
    @Published var nodes: [ShadowrocketNodeOption] = []
    @Published var profileName: String?
    @Published var isLoading = false
    @Published var isTesting = false
    @Published var isSelecting = false
    @Published var message: String?
    var onSelectionChanged: (() -> Void)?
    var opened = false
    var cancels = 0
    init() { Self.instance = self }
    func load() { opened = true }
    func cancel() { opened = false; cancels += 1 }
    func testAll(force: Bool) {}
    func selectNode(id: String) {}
}

@MainActor private enum FixtureWindows { static var presented: [NSWindow] = [] }
extension NSWindow {
    // Suppress presentation of the real controller's windows in this fixture executable.
    @objc fileprivate func fixtureMakeKeyAndOrderFront(_ sender: Any?) { FixtureWindows.presented.append(self) }
}
private final class FixtureWindow: NSWindow {
    var fixtureVisible = true
    override var isVisible: Bool { fixtureVisible }
}

@main enum NodePickerInteractionTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
            checks += 1
        }
        let window = FixtureWindow(contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        window.contentView = root
        let button = ClientSwitchNativeButton(frame: NSRect(x: 30, y: 25, width: 20, height: 24))
        root.addSubview(button)
        var leftClicks = 0, rightClicks = 0
        let coordinator = ClientSwitchButton.Coordinator { leftClicks += 1 }
        button.setButtonType(.momentaryChange)
        button.target = coordinator
        button.action = #selector(ClientSwitchButton.Coordinator.click(_:))
        button.chooseNode = { rightClicks += 1 }
        func event(_ type: NSEvent.EventType, inside: Bool = true) -> NSEvent {
            let point = button.convert(NSPoint(x: inside ? 10 : 25, y: 12), to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func down(_ inside: Bool = true) { button.rightMouseDown(with: event(.rightMouseDown, inside: inside)) }
        func up(_ inside: Bool = true) { button.rightMouseUp(with: event(.rightMouseUp, inside: inside)) }
        down(); up()
        expect(rightClicks == 1 && leftClicks == 0, "A right click must invoke only node selection")
        up()
        expect(rightClicks == 1, "A repeated right release must not invoke selection twice")
        button.performClick(nil)
        expect(leftClicks == 1 && rightClicks == 1, "The regular action must invoke only client switching")
        down(false); up()
        expect(rightClicks == 1, "A press outside the control must not select on release inside")
        down(); up(false); up()
        expect(rightClicks == 1, "An outside release must cancel the gesture")
        button.isEnabled = false; down(); up()
        expect(rightClicks == 1, "Disabled controls must not handle right clicks")
        button.isEnabled = true; down(); button.isEnabled = false; up(); button.isEnabled = true
        expect(rightClicks == 1, "Disabling during a press must cancel its release")
        down(); window.fixtureVisible = false; up(); window.fixtureVisible = true; up()
        expect(rightClicks == 1, "A hidden window must cancel a pending right click")
        window.fixtureVisible = false; down(); window.fixtureVisible = true; up()
        expect(rightClicks == 1, "A hidden window must not arm a right click")
        down(); button.removeFromSuperview(); root.addSubview(button); up()
        expect(rightClicks == 1, "Moving the control out of its window must cancel a pending gesture")
        coordinator.action = { leftClicks += 10 }; button.performClick(nil)
        expect(leftClicks == 11, "Replacing the left callback must not retain its previous action")
        button.chooseNode = { rightClicks += 10 }; down(); up()
        expect(rightClicks == 11 && leftClicks == 11, "Replacing the right callback must preserve gesture isolation")

        let normal = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)))!
        let fixture = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.fixtureMakeKeyAndOrderFront(_:)))!
        method_exchangeImplementations(normal, fixture)
        defer { method_exchangeImplementations(normal, fixture) }
        let picker = NodePickerWindowController()
        var oldChanges = 0, newChanges = 0
        picker.show(client: .flclash, preferredGroup: "Fixture group") { oldChanges += 1 }
        let clash = FlClashNodeController.instance!, rocket = ShadowrocketNodeController.instance!
        expect(clash.opened && !rocket.opened && clash.openedGroup == "Fixture group", "Opening FlClash must open only its controller")
        expect(clash.closes == 1 && rocket.cancels == 1, "Opening must first cancel both previous data sources")
        let first = FixtureWindows.presented.last!
        expect(first.delegate === picker && !first.isVisible, "The owned window must use the cancellation delegate without showing test UI")
        picker.show(client: .shadowrocket, preferredGroup: nil) { newChanges += 1 }
        expect(!clash.opened && rocket.opened, "Changing source must cancel the previous source")
        expect(clash.closes == 2 && rocket.cancels == 2, "Changing source must cancel both old request contexts")
        expect(FixtureWindows.presented.last === first, "Repeated openings must reuse one window")
        rocket.onSelectionChanged?()
        expect(newChanges == 1 && oldChanges == 0, "A reused picker must replace the old change callback")
        picker.close()
        expect(!clash.opened && !rocket.opened && clash.closes == 3 && rocket.cancels == 3, "Programmatic closing must cancel both controllers")
        picker.show(client: .flclash, preferredGroup: nil) {}
        first.close()
        expect(!clash.opened && !rocket.opened && clash.closes == 5 && rocket.cancels == 5, "Closing the native window must cancel both controllers")
        expect(FixtureWindows.presented.allSatisfy { !$0.isVisible }, "Fixture lifecycle checks must never display a picker")
        print("Node picker interaction: \(checks) checks passed; no real controllers or network linked")
    }
}
