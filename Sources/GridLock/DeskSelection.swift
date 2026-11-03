import Foundation
import GridLockKit
import Observation

/// Which desk and display the Desks and Palette panes are editing, shared so that picking a
/// display in one pane carries over to the other. Also holds the copied display settings and
/// the sheet that's open, so a notification (or snapshot mode) can open a pane at a desk.
@Observable
@MainActor
final class DeskSelection {
    static let shared = DeskSelection()

    /// Nil means the current desk.
    var deskID: UUID?
    /// Nil means the desk's first display (left to right).
    var displayKey: String?
    /// Copy Settings keeps a display's settings here for Paste Settings, on any desk.
    var clipboard: DisplaySettings?
    /// The desk whose Rename Desk sheet is open.
    var renaming: UUID?
    /// The custom layout open in the layout editor.
    var editingLayout: CustomLayout?

    func desk(in tracker: DeskTracker) -> Desk? {
        tracker.store.desk(id: deskID) ?? tracker.currentDesk
    }

    /// The selected display of a desk, falling back to its first when the key isn't one of it.
    func display(of desk: Desk) -> DisplayRecord? {
        let ordered = Self.ordered(desk.displays)
        return ordered.first { $0.key == displayKey } ?? ordered.first
    }

    func select(desk id: UUID, display key: String? = nil) {
        deskID = id
        displayKey = key
    }

    /// Left to right, then top to bottom, as the desk picture shows them.
    nonisolated static func ordered(_ displays: [DisplayRecord]) -> [DisplayRecord] {
        displays.sorted { ($0.bounds.x, $0.bounds.y) < ($1.bounds.x, $1.bounds.y) }
    }
}

extension DisplayRecord {
    /// The name shown in Settings.
    var title: String { isBuiltin ? "Built-in Display" : name }
}
