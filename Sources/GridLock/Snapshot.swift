#if DEBUG
import AppKit

/// Snapshot mode, for checking pages without driving the real app:
///
///     GRIDLOCK_DATA_DIR=<scratch folder> GRIDLOCK_SNAPSHOT=<out folder> [GRIDLOCK_SNAPSHOT_PAGES=settings-desks,…] \
///       "$(swift build --show-bin-path)/GridLock"
///
/// Recognizes the displays (into the scratch library), then writes `<page>-light.png` and
/// `<page>-dark.png` for each page and quits. Pages: `settings-<tab>` for every Settings tab
/// (lowercased label). New surfaces (the grid, the palette) add their pages to `render`.
@MainActor
enum Snapshot {
    static func runIfAsked(desks: DeskTracker) -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["GRIDLOCK_SNAPSHOT"] else { return false }
        let folder = URL(filePath: out, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wanted = env["GRIDLOCK_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        desks.start()
        Task {
            // The displays settle after two samples 2 s apart.
            try? await Task.sleep(for: .seconds(2.5))
            for page in pages where wanted?.contains(page) ?? true {
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: appearance)
                    if let window = await render(page) {
                        write(window, to: folder.appending(path: "\(page)-\(suffix).png"))
                    }
                }
            }
            Diagnostics.note("snapshot: wrote pages to \(folder.path)")
            exit(0)
        }
        return true
    }

    static var pages: [String] {
        ["settings-general", "settings-desks", "settings-palette", "settings-layouts", "settings-shortcuts"]
    }

    /// Shows a page and returns the window to capture once it has drawn.
    private static func render(_ page: String) async -> NSWindow? {
        if page.hasPrefix("settings-") {
            let tab = page.dropFirst("settings-".count).capitalized
            SettingsWindow.shared.show(tab: tab)
            try? await Task.sleep(for: .milliseconds(600))
            return SettingsWindow.shared.debugWindow
        }
        Diagnostics.note("snapshot: unknown page \(page)")
        return nil
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
