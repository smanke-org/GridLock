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

        // Settings can hide the menu bar icon (the app then lives in the Dock, or nowhere),
        // and ToolHUD can take the menu into its own while it runs.
        statusItem.isVisible = MenuHub.shared.showsOwnIcon
        NotificationCenter.default.addObserver(forName: AppPresence.menuBarDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.isVisible = MenuHub.shared.showsOwnIcon }
        }
        MenuHub.shared.start(menu: { [weak self] in
            let menu = NSMenu()
            menu.autoenablesItems = false
            self?.menuNeedsUpdate(menu)
            return menu
        }, icon: { [weak self] in
            self?.updateIcon()
            return self?.statusItem.button?.image
        })
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
        menu.addItem(withTitle: "Open Palette", action: #selector(openPalette), target: self, shortcut: "palette")
            .showIcon("square.grid.3x1.below.line.grid.1x2")
        let undoTitle = WindowMover.shared.undoTitle
        let undo = menu.addItem(withTitle: undoTitle ?? "Undo Move", action: #selector(undoMove), target: self, shortcut: "undo")
        undo.showIcon("arrow.uturn.backward")
        undo.isEnabled = undoTitle != nil

        menu.addItem(.separator())
        let desk = menu.addItem(withTitle: "Desk: \(desks.currentDesk?.name ?? "Recognizing displays…")", action: #selector(showDesks), target: self)
        desk.showIcon("display.2")
        desk.toolTip = "Grids and palettes are kept for each desk. Click to change this desk's settings."

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",", target: self).showIcon("gearshape")
        menu.addItem(withTitle: "GridLock Help", action: #selector(showHelp), target: self).showIcon("questionmark.circle")
        if let staged = AutoUpdater.shared.staged {
            menu.addItem(withTitle: "Update to \(staged.version) Now", action: #selector(installStagedUpdate), target: self)
                .showIcon("arrow.down.circle")
        } else if let pending = UpdateAvailability.shared.pending {
            menu.addItem(withTitle: "Update to \(pending)…", action: #selector(checkForUpdates), target: self)
                .showIcon("arrow.down.circle").toolTip = "A newer release is available. Installing it needs your confirmation."
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), target: self)
                .showIcon("arrow.down.circle")
        }
        menu.addItem(withTitle: "About GridLock", action: #selector(showAbout), target: self)
        menu.addItem(withTitle: "Our other apps…", action: #selector(showOtherApps), target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GridLock", action: #selector(quit), keyEquivalent: "q", target: self)
        menu.addItem(.separator())
        let version = menu.addItem(withTitle: "GridLock \(AppInfo.displayVersion)", action: nil, target: nil)
        version.isEnabled = false
    }

    /// The menu as built when it opens, for the debug hook and snapshot mode.
    func freshMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuNeedsUpdate(menu)
        return menu
    }

    /// One line per item with its shortcut (a global one from Settings, or the menu's own key),
    /// whether it shows an icon, and whether it's disabled — for the debug hook.
    func dumpMenu() -> String {
        freshMenu().items.map { item in
            guard !item.isSeparatorItem else { return "---" }
            let parts = item.plainTitle.split(separator: "\t", maxSplits: 1).map(String.init)
            var line = parts[0]
            if parts.count > 1 { line += "  " + parts[1] }
            if !item.keyEquivalent.isEmpty { line += "  " + item.keyEquivalentDisplay }
            if item.titleIcon != nil { line += "  [icon]" }
            if !item.isEnabled { line += "  (disabled)" }
            return line
        }.joined(separator: "\n")
    }

    @objc private func grantAccess() { WelcomeWindow.shared.show() }
    @objc private func showGrid() { Actions.shared.showGrid() }
    @objc private func openPalette() { PaletteOverlay.shared.toggleForFrontmostWindow() }
    @objc private func undoMove() { Actions.shared.undo() }
    @objc private func showDesks() { SettingsWindow.shared.show(tab: "Desks") }
    @objc private func showSettings() { SettingsWindow.shared.show() }
    @objc private func showHelp() { HelpWindow.shared.show() }
    @objc private func checkForUpdates() { UpdateController.checkForUpdates() }
    @objc private func installStagedUpdate() { AutoUpdater.shared.installNow() }
    @objc private func showAbout() { AppInfo.showAbout() }
    /// The developer's site, which lists every app.
    @objc private func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension NSMenuItem {
    /// The menu's own key as macOS shows it: "⌘,", "⌘Q".
    var keyEquivalentDisplay: String {
        let mask = keyEquivalentModifierMask
        var symbols = ""
        if mask.contains(.control) { symbols += "⌃" }
        if mask.contains(.option) { symbols += "⌥" }
        if mask.contains(.shift) || keyEquivalent != keyEquivalent.lowercased() { symbols += "⇧" }
        if mask.contains(.command) { symbols += "⌘" }
        return symbols + keyEquivalent.uppercased()
    }
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
