import AppKit
import Combine
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
    /// Keeps the desk library's sharing in step with "Sync settings with your other Macs".
    private var sharingSubscription: AnyCancellable?
    private lazy var desks = DeskTracker(store: store)
    private let launchAtLogin = LaunchAtLogin()
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything saves a setting: an empty domain means a brand-new install.
        let newInstall = SettingsSync.domainIsEmpty()
        Diagnostics.note("launch \(AppInfo.displayVersion) from \(Bundle.main.bundlePath)")
        AppAppearance.start()
        Actions.shared.desks = desks
        SettingsWindow.shared.desks = desks
        SettingsWindow.shared.launchAtLogin = launchAtLogin
        #if DEBUG
        // A test run of the agent CLI (APP_STORE): its own desks, settings and log, the desk
        // tracker (it only reads the displays) and the agent socket. Nothing else starts: no
        // menu bar item, ToolHUD menu, shortcuts, drag watching, settings sync, updater or
        // login item, and no Accessibility prompt.
        if AgentSocket.isTestRun {
            desks.start()
            AgentSocket.listen { AgentRouter.handle($0) }
            return
        }
        #endif
        statusItem = StatusItemController(desks: desks)
        let mainMenu = AppPresence.mainMenu(appName: "GridLock", settingsTitle: "Settings…",
                                            target: self, settings: #selector(showSettings))
        // Right below About in the app menu.
        let otherApps = NSMenuItem(title: "Our other apps…", action: #selector(showOtherApps), keyEquivalent: "")
        otherApps.target = self
        mainMenu.items.first?.submenu?.insertItem(otherApps, at: 1)
        // Help menu, with the standard ⌘? (macOS adds its search field).
        let helpItem = NSMenuItem()
        let help = NSMenu(title: "Help")
        let helpOpen = NSMenuItem(title: "GridLock Help", action: #selector(showHelp), keyEquivalent: "?")
        helpOpen.target = self
        help.addItem(helpOpen)
        helpItem.submenu = help
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = help
        NSApp.mainMenu = mainMenu
        #if DEBUG
        // Renders pages to PNGs and quits; starts no shortcuts, palette or updates.
        Snapshot.menu = { [statusItem] in statusItem!.freshMenu() }
        if Snapshot.runIfAsked(desks: desks) { return }
        #endif

        NewDeskNotice.shared.start(desks: desks)
        desks.start()
        // `gridlock` and the MCP server talk to the app through this.
        AgentSocket.listen { AgentRouter.handle($0) }
        listenForDebugCommands()
        HotKeyCenter.shared.perform = { id in Actions.shared.perform(shortcut: id) }
        HotKeyCenter.shared.apply()
        Actions.shared.startInteraction()
        ShortcutsLensReport.start { HotKeyCenter.shared.reportedShortcuts }
        WelcomeWindow.shared.onGranted = { [weak self] in self?.statusItem.updateIcon() }
        launchAtLogin.enableOnFirstRun()
        // An automatic update must not restart GridLock while the grid or the palette is up.
        AutoUpdater.shared.appBusyReason = { Actions.shared.isOverlayOpen ? "the grid or the palette is open" : nil }
        SettingsSync.shared.onApply = {
            AppSettings.shared.reload()
            HotKeyCenter.shared.apply()
            MenuHub.shared.reload()
        }
        if newInstall { SettingsSync.shared.adoptOnNewInstall() }
        SettingsSync.shared.start()
        sharingSubscription = SettingsSync.shared.$isEnabled.sink { [weak self] on in
            MainActor.assumeIsolated { self?.store.isSharing = on }
        }
        AutoUpdater.shared.start(newInstall: newInstall)

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

    /// `gridlock://` URLs (from ToolHUD, Shortcuts or a script): `grid`, `undo`, `palette`,
    /// `snap?zone=left-half` (or `snap-left-half`), `settings`; see `URLAction`. They act
    /// on the frontmost window of another app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for action in urls.compactMap(URLAction.init) {
            switch action {
            case .grid: Actions.shared.showGrid()
            case .undo: Actions.shared.undo()
            case .palette: PaletteOverlay.shared.toggleForFrontmostWindow()
            case .snap(let name):
                if let zone = name.flatMap({ Actions.namedZones[$0] }) {
                    Actions.shared.snapFrontmost(to: zone)
                } else {
                    Diagnostics.note("url: unknown zone \(name ?? "nil")")
                }
            case .settings: showSettings()
            }
        }
    }

    @objc func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc func showHelp() { HelpWindow.shared.show() }

    /// The app menu's About item (`AppPresence.mainMenu`).
    @objc func showAbout() { AppInfo.showAbout() }

    /// The developer's site, which lists every app.
    @objc func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }

    /// Development affordance, only with GRIDLOCK_DEBUG=1. A distributed notification
    /// `com.smanke.GridLock.debug` whose object is a command runs it in the installed,
    /// permission-holding build; results go to ~/Library/Logs/GridLock.log. Commands:
    /// `dump:desk`, `dump:menu`, `dump:front`, `show:settings|help|about|<tab>`, `help:<topic>`, `grid:show`, `palette:open`,
    /// `snap:<zone name>`, `undo:last`, `sync:on|off|pull`, `dump:layouts`, `desk:notify` (the new-desk notification for this desk).
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
        case ("show", "help"): HelpWindow.shared.show()
        case ("show", "about"): AppInfo.showAbout()
        case ("help", let topic): HelpWindow.shared.show(topic: topic)
        case ("show", let tab): SettingsWindow.shared.show(tab: tab)
        case ("grid", "show"): Actions.shared.showGrid()
        case ("palette", "open"): PaletteOverlay.shared.toggleForFrontmostWindow()
        case ("snap", let name):
            guard let zone = Actions.namedZones[name] else { return Diagnostics.note("debug: unknown zone \(name)") }
            let w = WindowMover.shared.frontmostWindow()
            Actions.shared.snapFrontmost(to: zone)
            let after = w.flatMap { AXWindows.frame(of: $0.element) }
            Diagnostics.note("debug: snap \(name) \(w?.appName ?? "none") → \(after.map { "\($0)" } ?? "nil")")
        case ("undo", "last"): Actions.shared.undo()
        case ("sync", "on"): SettingsSync.shared.isEnabled = true
        case ("sync", "off"): SettingsSync.shared.isEnabled = false
        case ("sync", "pull"): store.pullFromOtherMacs()
        case ("dump", "layouts"):
            let library = store.library
            Diagnostics.note("debug: sharing=\(store.isSharing) layouts=\(library.customLayouts.map(\.name)) "
                             + "deleted=\(library.deletedLayouts.count) others=\(store.others.map { "\($0.machineName)(shares: \($0.shares))" })")
        case ("desk", "notify"): desks.currentDesk.map(NewDeskNotice.shared.post)
        default: if !Actions.shared.runDebugCommand(parts[0], parts[1]) { Diagnostics.note("debug: unknown command \(command)") }
        }
    }
}

extension Actions {
    /// A global shortcut fired.
    func perform(shortcut id: String) {
        switch id {
        case "grid": showGrid()
        case "undo": undo()
        case "palette": PaletteOverlay.shared.toggleForFrontmostWindow()
        default: performCatalog(shortcut: id)
        }
    }
}
