import AppKit
import GridLockKit

/// The menu bar menu. Rebuilt each time it opens, so the desk name and Undo Move are current.
/// The menu holds actions; preferences live in Settings.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let desks: DeskTracker

    init(desks: DeskTracker) {
        self.desks = desks
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        // Enabled state is set by hand below; auto-enabling would override it.
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon()
        statusItem.isVisible = AppPresence.showInMenuBar
        NotificationCenter.default.addObserver(forName: AppPresence.menuBarDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.isVisible = AppPresence.showInMenuBar }
        }
    }

    /// A grid; a warning sign while access is missing, since nothing works without it.
    func updateIcon() {
        let symbol = AXWindows.isTrusted ? "square.grid.3x3.topleft.filled" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GridLock")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        updateIcon()

        if !AXWindows.isTrusted {
            menu.addItem(withTitle: "Grant Access…", action: #selector(grantAccess), target: self)
                .showIcon("exclamationmark.triangle").toolTip = "GridLock needs access to move and resize other apps' windows."
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: "Show Grid", action: #selector(showGrid), target: self, shortcut: "grid")
            .showIcon("square.grid.3x3")
        let undoTitle = WindowMover.shared.undoTitle
        let undo = menu.addItem(withTitle: undoTitle ?? "Undo Move", action: #selector(undoMove), target: self, shortcut: "undo")
        undo.showIcon("arrow.uturn.backward")
        undo.isEnabled = undoTitle != nil

        menu.addItem(.separator())
        let desk = menu.addItem(withTitle: "Desk: \(desks.currentDesk?.name ?? "Recognizing displays…")", action: #selector(showDesks), target: self)
        desk.toolTip = "Grids and palettes are kept for each desk. Click to change this desk's settings."

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",", target: self).showIcon("gearshape")
        menu.addItem(withTitle: "Quit GridLock", action: #selector(quit), keyEquivalent: "q", target: self)
    }

    /// One line per item, for the debug hook.
    func dumpMenu() -> String {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu.items.map { $0.isSeparatorItem ? "---" : "\($0.plainTitle) [\($0.isEnabled ? "on" : "off")]" }.joined(separator: "\n")
    }

    @objc private func grantAccess() { WelcomeWindow.shared.show() }
    @objc private func showGrid() { Actions.shared.showGrid() }
    @objc private func undoMove() { Actions.shared.undo() }
    @objc private func showDesks() { SettingsWindow.shared.show(tab: "Desks") }
    @objc private func showSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
extension NSMenu {
    /// An item aimed at `target`, optionally showing a global shortcut from Settings (shown
    /// only; Carbon fires it, not the menu).
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String = "", target: AnyObject?, shortcut: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if let id = shortcut, let key = AppSettings.shared.shortcut(id) {
            item.title = title + "\t" + key.display
        }
        addItem(item)
        return item
    }
}
