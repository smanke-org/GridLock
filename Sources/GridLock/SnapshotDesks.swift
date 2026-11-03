#if DEBUG
import AppKit
import GridLockKit

/// Snapshot pages for the Desks UI: a desk that isn't connected, and the sheets. Seed the
/// scratch `GRIDLOCK_DATA_DIR` with a few desks (one named "Office") and custom layouts first;
/// with none, the "-other" pages show the current desk.
@MainActor
extension Snapshot {
    static let deskPages = ["settings-desks-other", "settings-palette-other", "desk-rename", "layout-editor"]

    /// Every page starts from the current desk with no sheet open.
    static func resetDeskSelection() {
        let selection = DeskSelection.shared
        selection.deskID = nil
        selection.displayKey = nil
        selection.renaming = nil
        selection.editingLayout = nil
        selection.editingZone = nil
    }

    static func renderDeskPage(_ page: String) async -> NSWindow? {
        let selection = DeskSelection.shared
        let library = SettingsWindow.shared.desks.store.library
        let current = SettingsWindow.shared.desks.currentDeskID
        let other = library.desks.first { $0.name == "Office" && $0.id != current } ?? library.desks.first { $0.id != current }
        switch page {
        case "settings-desks-other", "settings-palette-other":
            if let other {
                // The second display, so the picture shows a selection other than the first.
                selection.select(desk: other.id, display: DeskSelection.ordered(other.displays).dropFirst().first?.key)
            }
            SettingsWindow.shared.show(tab: page.hasPrefix("settings-desks") ? "Desks" : "Palette")
        case "desk-rename":
            SettingsWindow.shared.show(tab: "Desks")
            selection.renaming = current
        case "layout-editor":
            SettingsWindow.shared.show(tab: "Layouts")
            selection.editingZone = 1
            selection.editingLayout = library.customLayouts.first ?? CustomLayout(name: "", zones: [])
        default:
            return nil
        }
        try? await Task.sleep(for: .milliseconds(900))
        let window = SettingsWindow.shared.debugWindow
        return window?.attachedSheet ?? window
    }
}
#endif
