#if DEBUG
import AppKit

/// Snapshot mode, for checking pages without driving the real app:
///
///     GRIDLOCK_DATA_DIR=<scratch folder> GRIDLOCK_SNAPSHOT=<out folder> [GRIDLOCK_SNAPSHOT_PAGES=settings-desks,…] \
///       "$(swift build --show-bin-path)/GridLock"
///
/// Recognizes the displays (into the scratch library), then writes `<page>-light.png` and
/// `<page>-dark.png` for each page and quits. Pages: `settings-<tab>` for every Settings tab
/// (lowercased label), `help-<topic>` for every Help page. New surfaces (the grid, the palette)
/// add their pages to `render`.
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
            try? checks().write(to: folder.appending(path: "checks.txt"), atomically: true, encoding: .utf8)
            Diagnostics.note("snapshot: wrote pages to \(folder.path)")
            exit(0)
        }
        return true
    }

    static var pages: [String] {
        ["settings-general", "settings-desks", "settings-palette", "settings-layouts", "settings-shortcuts"]
            + Help.topics.map { "help-\($0.id)" }
    }

    /// What the pictures can't show: each Settings pane's ? button presses through to a Help
    /// page that exists, no Help page is left with an unresolved token, and the menus.
    private static func checks() -> String {
        var lines: [String] = []
        if let tabs = SettingsWindow.shared.debugWindow?.contentViewController as? SettingsTabs {
            for item in tabs.tabViewItems {
                HelpButton(topic: Help.topic(forSettingsTab: item.label)).makeCoordinator().open()
                let opened = HelpWindow.shared.state.selection ?? "-"
                let exists = Help.topics.contains { $0.id == opened }
                lines.append("help button \(item.label) → \(opened) \(exists ? "ok" : "MISSING")")
            }
        }
        let unresolved = Help.topics.filter { $0.blocks.contains { $0.searchText.contains("{") } }.map(\.id)
        lines.append("unresolved tokens: \(unresolved.isEmpty ? "none" : unresolved.joined(separator: ", "))")
        lines.append("help menu: " + (NSApp.helpMenu?.items.map { "\($0.title) ⌘\($0.keyEquivalent)" }.joined(separator: ", ") ?? "none"))
        lines.append("app menu: " + (NSApp.mainMenu?.items.first?.submenu?.items.map { $0.isSeparatorItem ? "---" : $0.title }.joined(separator: " | ") ?? ""))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Shows a page and returns the window to capture once it has drawn.
    private static func render(_ page: String) async -> NSWindow? {
        if page.hasPrefix("settings-") {
            let tab = page.dropFirst("settings-".count).capitalized
            SettingsWindow.shared.show(tab: tab)
            // The tab view resizes the window a beat after the switch; fit it now, so the
            // picture is the pane's own size and not the last pane's.
            (SettingsWindow.shared.debugWindow?.contentViewController as? SettingsTabs)?.refit()
            try? await Task.sleep(for: .milliseconds(600))
            return SettingsWindow.shared.debugWindow
        }
        if page.hasPrefix("help-") {
            HelpWindow.shared.show(topic: String(page.dropFirst("help-".count)))
            try? await Task.sleep(for: .milliseconds(600))
            return HelpWindow.shared.window
        }
        Diagnostics.note("snapshot: unknown page \(page)")
        return nil
    }

    private static func write(_ window: NSWindow, to url: URL) {
        // Drawing the view leaves glass and sidebar materials blank; with
        // GRIDLOCK_SNAPSHOT_CAPTURE=1 the window server captures this window alone instead.
        if ProcessInfo.processInfo.environment["GRIDLOCK_SNAPSHOT_CAPTURE"] == "1" {
            let task = Process()
            task.executableURL = URL(filePath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return }
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
