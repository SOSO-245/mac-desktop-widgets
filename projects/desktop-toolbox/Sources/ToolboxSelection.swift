import Foundation

/// Discover only responding, visible cards. A missing optional application must
/// not prevent the installed cards from being arranged. Once the user edits the
/// preview, late responses must never change their selection.
struct ToolboxSelectionDiscovery {
    private var seen: Set<String> = []

    mutating func discover(_ visibleByID: [String: Bool], frozen: Bool) -> Set<String> {
        let newcomers = Set(visibleByID.keys).subtracting(seen)
        seen.formUnion(visibleByID.keys)
        return frozen ? [] : Set(newcomers.filter { visibleByID[$0] == true })
    }
}

enum ToolboxReadiness: Equatable {
    case empty
    case stopped([String])
    case waiting([String])
    case ready

    static func evaluate(selected: Set<String>, responding: Set<String>, running: Set<String>) -> Self {
        guard !selected.isEmpty else { return .empty }
        let missing = selected.subtracting(responding)
        let stopped = missing.subtracting(running)
        if !stopped.isEmpty { return .stopped(stopped.sorted()) }
        return missing.isEmpty ? .ready : .waiting(missing.sorted())
    }
}

/// Layout drafts contain no business data. Persisting the preview separately
/// from grid.json never activates snapping or automatic rearrangement.
struct ToolboxDraft: Codable, Equatable {
    var schema = 1
    var selected: Set<String>
    var sizes: [String: String]
    var order: [String]
    var screenIndex: Int
    var edge: String
    var snap: Bool
    var automatic: Bool
    var unifiedAppearance: Bool
    var glass: Bool
    var brightness: Double
    var transparency: Double
    var zoomToCards: Bool

    /// Editing a size is an explicit request to include this card in the draft.
    /// It does not apply the draft or change any live window.
    mutating func selectSize(_ value: String, for id: String) {
        guard order.contains(id), ["small", "medium", "large"].contains(value) else { return }
        sizes[id] = value
        selected.insert(id)
    }

    func normalized(moduleIDs: [String], screenCount: Int) -> Self? {
        guard schema == 1, brightness.isFinite, transparency.isFinite,
              (-100...100).contains(brightness), (0...80).contains(transparency),
              ["left", "right"].contains(edge) else { return nil }
        let known = Set(moduleIDs)
        var result = self
        result.selected.formIntersection(known)
        result.sizes = sizes.filter { known.contains($0.key) && ["small", "medium", "large"].contains($0.value) }
        var ordered = Set<String>()
        result.order = (order + moduleIDs).filter { known.contains($0) && ordered.insert($0).inserted }
        result.screenIndex = min(max(0, screenIndex), max(0, screenCount - 1))
        return result
    }
}
