import AppKit

// `gridlock <command>` (the app binary under a short name): run it against the running app and
// exit, without starting a second copy. See Agent/AgentCLI.swift.
if let code = AgentCLI.runIfRequested() { exit(code) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // A menu bar app; it has a Dock icon only if the user turned one on.
    app.setActivationPolicy(AppPresence.showInDock ? .regular : .accessory)
    withExtendedLifetime(delegate) { app.run() }
}
