import AppKit
import SwiftUI

/// Explains the one permission GridLock needs and closes itself once it's granted (S-001).
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private var window: NSWindow?
    private var timer: Timer?
    /// Called once access is granted, to refresh the menu bar icon.
    var onGranted: (() -> Void)?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(
                open: { [weak self] in self?.openSettings() },
                later: { [weak self] in self?.window?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to GridLock"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        watch()
    }

    /// The prompt adds GridLock to the list (switched off); then the Settings page opens.
    private func openSettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// No relaunch needed: the grant is noticed within a second and the window closes.
    private func watch() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                Diagnostics.note("access granted")
                self?.timer?.invalidate()
                self?.window?.close()
                self?.onGranted?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Keep watching while access is still off, so the menu bar badge clears when it's granted.
        if AXIsProcessTrusted() { timer?.invalidate() }
    }
}

private struct WelcomeView: View {
    let open: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                Text("Welcome to GridLock").font(.title2.bold())
            }
            Text("GridLock can't move windows yet.")
                .font(.headline)
            Text("To move and resize other apps' windows, GridLock needs access. Turn on GridLock in Privacy & Security › Device Control and Data Access.")
                .fixedSize(horizontal: false, vertical: true)
            Text("This window closes by itself once access is on.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Later", action: later).keyboardShortcut(.cancelAction)
                Button("Open Privacy Settings", action: open).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
