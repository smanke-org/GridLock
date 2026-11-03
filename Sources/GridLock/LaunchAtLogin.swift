import Foundation
import Observation
import ServiceManagement

/// Starting at login is how the palette and shortcuts are there after a restart, so it is
/// switched on the first time the app runs from /Applications. Uses SMAppService.mainApp;
/// there is no helper. Only the copy in /Applications registers: a build folder's copy would
/// otherwise start at every login alongside it.
@Observable
@MainActor
final class LaunchAtLogin {
    private(set) var isEnabled = false
    private(set) var needsApproval = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// Running from /Applications, the only copy that may start at login.
    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    func set(_ enabled: Bool) {
        guard !enabled || Self.isInstalled else {
            Diagnostics.note("launch at login: not registering \(Bundle.main.bundlePath), which isn't in /Applications")
            return refresh()
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Diagnostics.note("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        refresh()
    }

    /// Turns it on once, and only from /Applications: registering a copy running from a
    /// build folder would start that copy at every login.
    func enableOnFirstRun() {
        let settings = AppSettings.shared
        guard !settings.didOfferLaunchAtLogin, Self.isInstalled else { return }
        settings.didOfferLaunchAtLogin = true
        if !isEnabled { set(true) }
        Diagnostics.note("launch at login enabled on first run: \(isEnabled)")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
