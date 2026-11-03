import AppKit
import GridLockKit

/// Quits GridLock without asking: for quitting itself (installing an update, ending a test).
@MainActor
enum QuitConfirmation {
    private(set) static var confirmed = false

    static func quitNow() {
        confirmed = true
        NSApp.terminate(nil)
    }
}

/// Owns the long-lived objects and starts them at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DeskStore()
    private lazy var desks = DeskTracker(store: store)
    private let launchAtLogin = LaunchAtLogin()
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.note("launch \(AppInfo.displayVersion) from \(Bundle.main.bundlePath)")
        AppAppearance.start()
        Actions.shared.desks = desks
        SettingsWindow.shared.desks = desks
        SettingsWindow.shared.launchAtLogin = launchAtLogin
        statusItem = StatusItemController(desks: desks)
        NSApp.mainMenu = AppPresence.mainMenu(appName: "GridLock", settingsTitle: "Settings…",
                                              target: self, settings: #selector(showSettings))
        #if DEBUG
        // Renders pages to PNGs and quits; starts no shortcuts, palette or updates.
        if Snapshot.runIfAsked(desks: desks) { return }
        #endif

        desks.start()
        listenForDebugCommands()
        HotKeyCenter.shared.perform = { id in Actions.shared.perform(shortcut: id) }
        HotKeyCenter.shared.apply()
        ShortcutsLensReport.start { HotKeyCenter.shared.reportedShortcuts }
        WelcomeWindow.shared.onGranted = { [weak self] in self?.statusItem.updateIcon() }
        launchAtLogin.enableOnFirstRun()

        if !AXWindows.isTrusted {
            // First run: say why nothing will happen yet. Opened at launch, which is a
            // deliberate act by the user, never from a background timer.
            WelcomeWindow.shared.show()
        }
    }

    /// Quitting asks first while "Ask before quitting" is on — not when macOS is logging out,
    /// restarting or shutting down, and not when GridLock quits itself to install an update.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        guard AppSettings.shared.confirmQuit, !QuitConfirmation.confirmed, !systemQuit else { return .terminateNow }

        // A menu bar app needs to be a regular one for the alert to come to the front; the
        // old policy goes back a runloop turn later, once the alert is gone.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { DispatchQueue.main.async { NSApp.setActivationPolicy(previousPolicy) } }

        let alert = NSAlert()
        alert.messageText = "Quit GridLock?"
        alert.informativeText = "The palette, the grid and GridLock's shortcuts stop working until you open GridLock again."
        // Quit has no key, so Return does nothing: quitting takes a click, never a stray keystroke.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit").keyEquivalent = ""
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.layout()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if alert.suppressionButton?.state == .on { AppSettings.shared.confirmQuit = false }
        return .terminateNow
    }

    /// The Dock icon's right-click menu, when "Show in Dock" is on.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        AppPresence.dockMenu(title: "Settings…", target: self, action: #selector(showSettings))
    }

    /// Clicking the Dock icon, or opening the app again from Applications or Spotlight,
    /// opens Settings — the way back when both icons are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// `gridlock://` URLs (from ToolHUD, Shortcuts or a script): `grid`, `undo`,
    /// `snap?zone=left-half`, `settings`. They act on the frontmost window of another app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "gridlock" {
            switch url.host {
            case "grid": Actions.shared.showGrid()
            case "undo": Actions.shared.undo()
            case "snap":
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "zone" }?.value
                if let zone = name.flatMap({ Actions.namedZones[$0] }) {
                    Actions.shared.snapFrontmost(to: zone)
                } else {
                    Diagnostics.note("url: unknown zone \(name ?? "nil")")
                }
            default: showSettings()
            }
        }
    }

    @objc func showSettings() {
        SettingsWindow.shared.show()
    }

    /// Development affordance, only with GRIDLOCK_DEBUG=1. A distributed notification
    /// `com.smanke.GridLock.debug` whose object is a command runs it in the installed,
    /// permission-holding build; results go to ~/Library/Logs/GridLock.log. Commands:
    /// `dump:desk`, `dump:menu`, `dump:front`, `show:settings|<tab>`, `grid:show`,
    /// `snap:<zone name>`, `undo:last`.
    private func listenForDebugCommands() {
        guard Diagnostics.isEnabled else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.smanke.GridLock.debug"), object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { [weak self] in self?.runDebugCommand(command) }
        }
        Diagnostics.note("debug commands on")
    }

    private func runDebugCommand(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return Diagnostics.note("debug: bad command \(command)") }
        switch (parts[0], parts[1]) {
        case ("dump", "desk"): Diagnostics.note("debug: \(desks.dump())")
        case ("dump", "menu"): Diagnostics.note("debug: menu\n" + statusItem.dumpMenu())
        case ("dump", "front"):
            let w = WindowMover.shared.frontmostWindow()
            Diagnostics.note("debug: front \(w.map { "\($0.appName) \($0.frame)" } ?? "none")")
        case ("show", "settings"): SettingsWindow.shared.show()
        case ("show", let tab): SettingsWindow.shared.show(tab: tab)
        case ("grid", "show"): Actions.shared.showGrid()
        case ("snap", let name):
            guard let zone = Actions.namedZones[name] else { return Diagnostics.note("debug: unknown zone \(name)") }
            let w = WindowMover.shared.frontmostWindow()
            Actions.shared.snapFrontmost(to: zone)
            let after = w.flatMap { AXWindows.frame(of: $0.element) }
            Diagnostics.note("debug: snap \(name) \(w?.appName ?? "none") → \(after.map { "\($0)" } ?? "nil")")
        case ("undo", "last"): Actions.shared.undo()
        default: Diagnostics.note("debug: unknown command \(command)")
        }
    }
}

extension Actions {
    /// A global shortcut fired.
    func perform(shortcut id: String) {
        switch id {
        case "grid": showGrid()
        case "undo": undo()
        default:
            if id.hasPrefix("zone."), let zone = Actions.namedZones[String(id.dropFirst(5))] {
                snapFrontmost(to: zone)
            } else {
                Diagnostics.note("shortcut \(id) has no action")
            }
        }
    }
}
