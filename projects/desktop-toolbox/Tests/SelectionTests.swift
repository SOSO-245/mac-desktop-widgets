import Foundation

@main struct SelectionTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) { checks += 1; precondition(value, label) }
        let four: Set<String> = ["calendar", "reset", "vpn", "mac"]
        var discovery = ToolboxSelectionDiscovery()
        check(discovery.discover([:], frozen: false).isEmpty, "no phantom cards before responses")
        let selected = discovery.discover(Dictionary(uniqueKeysWithValues: four.map { ($0, true) }), frozen: false)
        check(selected == four, "four installed cards do not wait for two optional applications")
        check(discovery.discover(["calendar": true], frozen: false).isEmpty, "polling never resets a selection")
        check(discovery.discover(["hidden": false], frozen: false).isEmpty, "hidden cards stay unselected")
        check(discovery.discover(["late": true], frozen: false) == ["late"], "late startup response can join untouched preview")
        check(discovery.discover(["new": true], frozen: true).isEmpty, "editing freezes automatic discovery")
        check(ToolboxReadiness.evaluate(selected: four, responding: four, running: four) == .ready, "installed subset can arrange")
        check(ToolboxReadiness.evaluate(selected: [], responding: four, running: four) == .empty, "empty selection asks for selection")
        check(ToolboxReadiness.evaluate(selected: four.union(["optional"]), responding: four, running: four) == .stopped(["optional"]), "unstarted selection names the missing app")
        check(ToolboxReadiness.evaluate(selected: four, responding: four.subtracting(["vpn"]), running: four) == .waiting(["vpn"]), "stale running card blocks unsafe apply")
        check(ToolboxReadiness.evaluate(selected: ["a", "b"], responding: [], running: []) == .stopped(["a", "b"]), "missing names have stable order")
        let draft = ToolboxDraft(selected: four, sizes: ["calendar": "medium", "mac": "large"], order: ["reset", "calendar", "vpn", "mac"], screenIndex: 0, edge: "right", snap: true, automatic: true, unifiedAppearance: true, glass: true, brightness: -6.36, transparency: 38.14, zoomToCards: true)
        let decoded = try JSONDecoder().decode(ToolboxDraft.self, from: JSONEncoder().encode(draft))
        check(decoded == draft, "restart retains selection, order, sizes, appearance and automation draft")
        check(decoded.normalized(moduleIDs: draft.order, screenCount: 1) == draft, "valid draft stays exact")
        var invalid = draft; invalid.order = ["unknown", "mac", "mac"]; invalid.selected.insert("unknown"); invalid.sizes["mac"] = "huge"; invalid.screenIndex = 99
        let normalized = invalid.normalized(moduleIDs: draft.order, screenCount: 2)!
        check(normalized.selected == four, "unknown module removed")
        check(normalized.order == ["mac", "reset", "calendar", "vpn"], "duplicate order repaired without dropping known modules")
        check(normalized.sizes["mac"] == nil, "invalid size cannot reach card commands")
        check(normalized.screenIndex == 1, "removed display falls back to valid display")
        invalid = draft; invalid.brightness = .infinity
        check(invalid.normalized(moduleIDs: draft.order, screenCount: 1) == nil, "nonfinite appearance rejected")
        invalid = draft; invalid.schema = 2
        check(invalid.normalized(moduleIDs: draft.order, screenCount: 1) == nil, "unknown draft schema rejected")
        invalid = draft; invalid.transparency = 81
        check(invalid.normalized(moduleIDs: draft.order, screenCount: 1) == nil, "out of range transparency rejected")
        print("PASS \(checks) selection, readiness and preview preservation checks; no applications or cards changed")
    }
}
