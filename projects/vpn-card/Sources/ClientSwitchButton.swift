import AppKit
import SwiftUI

/// A right click chooses nodes; it must never dispatch the left-click action.
final class ClientSwitchNativeButton: NSButton {
    var chooseNode: (() -> Void)?
    private var rightClickStarted = false

    override func rightMouseDown(with event: NSEvent) {
        rightClickStarted = isEnabled && window?.isVisible == true
            && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func rightMouseUp(with event: NSEvent) {
        let shouldOpen = rightClickStarted && isEnabled && window?.isVisible == true
            && bounds.contains(convert(event.locationInWindow, from: nil))
        rightClickStarted = false
        if shouldOpen { chooseNode?() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rightClickStarted = false
    }
}

struct ClientSwitchButton: NSViewRepresentable {
    let otherClient: String
    let onSwitch: () -> Void
    let onChooseNode: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func click(_ sender: NSButton) { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onSwitch) }
    func makeNSView(context: Context) -> ClientSwitchNativeButton {
        let button = ClientSwitchNativeButton()
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.focusRingType = .none
        button.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.contentTintColor = NSColor(srgbRed: 0.66, green: 0.72, blue: 0.83, alpha: 1)
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.click(_:))
        button.setAccessibilityIdentifier("client-switch-and-node-picker")
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: ClientSwitchNativeButton, context: Context) {
        context.coordinator.action = onSwitch
        button.chooseNode = onChooseNode
        button.toolTip = "左键：切换到 \(otherClient) 并打开\n右键：选择节点并测速"
        button.setAccessibilityLabel("切换到 \(otherClient)；右键选择节点并测速")
        button.setAccessibilityHelp(button.toolTip)
    }
}
