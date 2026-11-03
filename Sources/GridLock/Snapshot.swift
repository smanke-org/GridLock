#if DEBUG
import AppKit

/// Snapshot mode, for checking pages without driving the real app:
///
///     GRIDLOCK_DATA_DIR=<scratch folder> GRIDLOCK_SNAPSHOT=<out folder> [GRIDLOCK_SNAPSHOT_PAGES=settings-desks,…] \
///       "$(swift build --show-bin-path)/GridLock"
///
/// Recognizes the displays (into the scratch library), then writes `<page>-light.png` and
/// `<page>-dark.png` for each page and quits. Pages: `settings-<tab>` for every Settings tab
/// (lowercased label), `help-<topic>` for every Help page, `icon`, `menu` (the menu bar menu)
/// and `update-prompt`. New surfaces (the grid, the palette)
/// add their pages to `render`.
@MainActor
enum Snapshot {
    /// Builds the menu bar menu as it opens; set at launch.
    static var menu: (() -> NSMenu)?

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
            + Help.topics.map { "help-\($0.id)" } + ["icon", "menu", "update-prompt"]
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
        if page == "icon" { return iconWindow() }
        if page == "menu" { return menuWindow() }
        if page == "update-prompt" {
            // Sample notes; the real prompt reads them from the GitHub releases.
            let notes = [
                ReleaseNotes.Entry(version: "0.2.0", notes: "- **Palette:** drop a window on any zone\n- Undo Move names the window", isNew: true),
                ReleaseNotes.Entry(version: "0.1.0", notes: "First release."),
            ]
            let alert = UpdateController.makeConfirmAlert(newVersion: "0.2.0", current: "0.1.0", notes: notes)
            alert.layout()
            alert.window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))
            return alert.window
        }
        if page.hasPrefix("help-") {
            HelpWindow.shared.show(topic: String(page.dropFirst("help-".count)))
            try? await Task.sleep(for: .milliseconds(600))
            return HelpWindow.shared.window
        }
        Diagnostics.note("snapshot: unknown page \(page)")
        return nil
    }

    /// The app icon from Resources at Dock size, and the nameless variant at the 32 and 16 pt
    /// Finder uses, on the window background of the current look.
    private static var iconPanel: NSWindow?

    private static func iconWindow() -> NSWindow? {
        let resources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources").standardized
        guard let full = NSImage(contentsOf: resources.appending(path: "AppIcon.png")),
              let small = NSImage(contentsOf: resources.appending(path: "AppIcon-small.png")) else {
            Diagnostics.note("snapshot: no icon in \(resources.path)")
            return nil
        }
        let stack = NSStackView(views: [(full, 128), (small, 32), (small, 16)].map { image, side in
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.widthAnchor.constraint(equalToConstant: CGFloat(side)).isActive = true
            view.heightAnchor.constraint(equalToConstant: CGFloat(side)).isActive = true
            return view
        })
        stack.alignment = .centerY
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let window = iconPanel ?? NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "GridLock icon"
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        iconPanel = window
        return window
    }

    /// The menu bar menu laid out the way it opens (title with its icon, shortcut on the
    /// right, separators), since an open NSMenu can't be drawn to a file.
    private static var menuPanel: NSWindow?

    private static func menuWindow() -> NSWindow? {
        guard let menu = menu?() else { return nil }
        let grid = NSGridView()
        grid.rowSpacing = 4
        grid.columnSpacing = 32
        for item in menu.items {
            if item.isSeparatorItem {
                let line = NSBox()
                line.boxType = .separator
                grid.addRow(with: [line])
                grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: grid.numberOfRows - 1, length: 1))
                continue
            }
            let parts = item.plainTitle.split(separator: "\t", maxSplits: 1).map(String.init)
            let text = NSMutableAttributedString(attributedString: item.attributedTitle
                ?? NSAttributedString(string: item.title, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            // The shortcut goes in its own column.
            if let tab = text.string.firstIndex(of: "\t") {
                text.deleteCharacters(in: NSRange(tab..<text.string.endIndex, in: text.string))
            }
            let color: NSColor = item.isEnabled ? .labelColor : .tertiaryLabelColor
            text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
            let key = NSTextField(labelWithString: parts.count > 1 ? parts[1] : item.keyEquivalent.isEmpty ? "" : item.keyEquivalentDisplay)
            key.font = .menuFont(ofSize: 0)
            key.textColor = .secondaryLabelColor
            grid.addRow(with: [TextRow(text), key])
        }
        grid.column(at: 1).xPlacement = .trailing
        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        let window = menuPanel ?? NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = container
        window.setContentSize(container.fittingSize)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        menuPanel = window
        return window
    }

    /// Draws an attributed string as is: a text field drops the kerning `showIcon` centers
    /// icons with, so their titles would sit off from where the menu puts them.
    private final class TextRow: NSView {
        let text: NSAttributedString
        init(_ text: NSAttributedString) {
            self.text = text
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var intrinsicContentSize: NSSize { text.size() }
        override func draw(_ dirtyRect: NSRect) { text.draw(at: .zero) }
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
