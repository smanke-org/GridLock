import AppKit
import Carbon.HIToolbox
import GridLockKit

/// Everything GridLock can do to a window, in one place, so the menu, shortcuts, URLs,
/// the grid and the palette all go through the same code.
@MainActor
final class Actions {
    static let shared = Actions()

    /// Set at launch.
    var desks: DeskTracker!

    /// Shows the grid over the display holding the frontmost window. Filled in by the grid
    /// overlay at launch (`startInteraction`).
    var showGridHandler: (() -> Void)?

    /// True while the grid or the palette is on screen; automatic updates wait for it.
    var isOverlayOpen = false

    /// Starts the hands-on parts: the grid behind Show Grid.
    func startInteraction() {
        showGridHandler = { GridOverlay.shared.toggle() }
    }

    func showGrid() {
        guard AXWindows.isTrusted else { return WelcomeWindow.shared.show() }
        if let showGridHandler { showGridHandler() } else { Diagnostics.note("show grid: overlay not built yet") }
    }

    /// Snaps the frontmost window into a zone of the display it's on, with that display's
    /// gap and margin at the current desk.
    @discardableResult
    func snapFrontmost(to zone: UnitRect) -> Bool {
        guard AXWindows.isTrusted else { WelcomeWindow.shared.show(); return false }
        guard let window = WindowMover.shared.frontmostWindow(), let display = desks.display(holding: window.frame) else {
            Diagnostics.note("snap: no window to place")
            return false
        }
        return snap(window, to: zone, on: display)
    }

    @discardableResult
    func snap(_ window: TargetWindow, to zone: UnitRect, on display: LiveDisplay) -> Bool {
        let grid = desks.settings(for: display).grid
        let frame = GridMath.frame(for: zone, visible: display.visible, gap: grid.gap, margin: grid.margin)
        WindowMover.shared.move(window, to: frame)
        return true
    }

    @discardableResult
    func snap(_ window: TargetWindow, to cells: CellRange, on display: LiveDisplay) -> Bool {
        let grid = desks.settings(for: display).grid
        WindowMover.shared.move(window, to: GridMath.frame(for: cells, grid: grid, visible: display.visible))
        return true
    }

    func undo() {
        if !WindowMover.shared.undo() { Diagnostics.note("undo: nothing to undo") }
    }

    /// A global shortcut that `perform(shortcut:)` doesn't handle itself.
    func performCatalog(shortcut id: String) {
        if id.hasPrefix("zone."), let zone = Actions.namedZones[String(id.dropFirst(5))] {
            snapFrontmost(to: zone)
        } else {
            Diagnostics.note("shortcut \(id) has no action")
        }
    }

    /// Debug-hook commands for the grid and the palette (see AppDelegate). False when the
    /// command isn't one of these.
    func runDebugCommand(_ verb: String, _ argument: String) -> Bool {
        switch (verb, argument) {
        case ("grid", "dump"):
            Diagnostics.note("debug: \(GridOverlay.shared.dump())")
        case ("grid", "close"):
            GridOverlay.shared.close()
        case ("grid", "snap"):
            GridOverlay.shared.snap()
        case ("grid", let key) where key.hasPrefix("key-"):
            // grid:key-right, grid:key-shift-left, grid:key-option-shift-up
            let parts = key.dropFirst(4).split(separator: "-")
            let codes = ["left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow]
            guard let last = parts.last, let code = codes[String(last)] else { return false }
            var flags: NSEvent.ModifierFlags = []
            if parts.contains("shift") { flags.insert(.shift) }
            if parts.contains("option") { flags.insert(.option) }
            if let action = GridOverlay.action(keyCode: code, flags: flags) { GridOverlay.shared.handle(action) }
            Diagnostics.note("debug: \(GridOverlay.shared.dump())")
        default:
            return false
        }
        return true
    }

    /// Zones that URLs, shortcuts and the debug hook can name.
    static let namedZones: [String: UnitRect] = [
        "maximize": .full,
        "left-half": UnitRect(x: 0, y: 0, width: 0.5, height: 1),
        "right-half": UnitRect(x: 0.5, y: 0, width: 0.5, height: 1),
        "top-half": UnitRect(x: 0, y: 0, width: 1, height: 0.5),
        "bottom-half": UnitRect(x: 0, y: 0.5, width: 1, height: 0.5),
        "left-third": UnitRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
        "center-third": UnitRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        "right-third": UnitRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        "left-two-thirds": UnitRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
        "right-two-thirds": UnitRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
        "top-left": UnitRect(x: 0, y: 0, width: 0.5, height: 0.5),
        "top-right": UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        "bottom-left": UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
        "bottom-right": UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        "center": UnitRect(x: 0.2, y: 0.125, width: 0.6, height: 0.75),
    ]
}
