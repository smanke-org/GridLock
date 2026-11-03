import AppKit
import GridLockKit
import Observation
import SwiftUI

/// macOS's own "Drag windows to screen edges to tile" (Desktop & Dock). With it on, a window
/// dragged to the top edge is also filled by macOS, which fights the palette. GridLock only
/// reads the setting and points to it; it never changes it.
@Observable
@MainActor
final class SystemEdgeTiling {
    static let shared = SystemEdgeTiling()

    private(set) var isOn = SystemEdgeTiling.read()
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        // Read again whenever GridLock comes to the front: after a visit to System Settings.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { SystemEdgeTiling.shared.refresh() }
        }
    }

    func refresh() {
        let now = Self.read()
        if now != isOn { isOn = now }
    }

    private static func read() -> Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        var preferences: [String: Any] = [:]
        if let value = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, domain) {
            preferences["EnableTilingByEdgeDrag"] = value
        }
        return EdgeTiling.isOn(preferences)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The note in Settings › General while macOS's edge tiling is on.
struct EdgeTilingNote: View {
    let tiling = SystemEdgeTiling.shared

    var body: some View {
        if tiling.isOn {
            Section {
                Label {
                    Text("macOS's own tiling is on. A window dragged to the top edge is also filled by macOS, which gets in the way of the palette. Turn off “Drag windows to screen edges to tile” in Desktop & Dock.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                Button("Open Desktop & Dock Settings") { SystemEdgeTiling.openSettings() }
            }
        }
    }
}
