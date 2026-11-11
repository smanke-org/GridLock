import AppKit
import SwiftUI

// MARK: - Content

/// One page of Help. `Help.resolve` swaps `{…}` tokens for the user's own settings, such
/// as their shortcuts, so the text matches what they've set up.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum HelpBlock {
    case text(String)
    case heading(String)
    /// Keys on the left, what they do on the right.
    case keys([(String, String)])
    case tip(String)

    var searchText: String {
        switch self {
        case .text(let s), .heading(let s), .tip(let s): Help.resolve(s)
        case .keys(let rows): rows.map { Help.resolve($0.0) + " " + Help.resolve($0.1) }.joined(separator: " ")
        }
    }
}

@MainActor
enum Help {
    /// `{shortcut:<id>}` shows the user's own key for a shortcut in `ShortcutCatalog`
    /// (`{shortcut:grid}`, `{shortcut:zone.left-half}`); `{dragKeys}` the keys that open the
    /// palette mid-drag.
    static func resolve(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "{dragKeys}", with: dragKeys)
        guard result.contains("{shortcut:") else { return result }
        while let open = result.range(of: "{shortcut:"), let close = result[open.upperBound...].firstIndex(of: "}") {
            let id = String(result[open.upperBound..<close])
            result.replaceSubrange(open.lowerBound...close, with: AppSettings.shared.shortcut(id)?.display ?? "(no shortcut set)")
        }
        return result
    }

    private static var dragKeys: String {
        let keys = AppSettings.shared.paletteModifiers
        guard !keys.isEmpty else { return "the keys you choose (none are set now)" }
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { keys.contains($0.0) }.map(\.1).joined()
    }

    /// The page each Settings pane's ? button opens.
    static func topic(forSettingsTab tab: String) -> String {
        switch tab {
        case "Desks": "desks"
        case "Palette": "palette"
        case "Layouts": "layouts"
        case "Shortcuts": "shortcuts"
        default: "settings"
        }
    }

    static var topics: [HelpTopic] { [
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "sparkles", blocks: [
            .text("GridLock puts windows where you want them: drag a window to the top edge of a display (or hold {dragKeys} while dragging) and drop it on a layout in the palette; press {shortcut:palette} and click a layout in the palette; or press {shortcut:grid} and draw where it goes on the grid."),
            .text("Each set of displays you work at is a desk. GridLock recognizes a desk by its displays' serial numbers and keeps each display's grid and palette there, so the same display can have a different grid at home and at the office."),
            .heading("Allow access"),
            .text("To move and resize other apps' windows, GridLock needs access. Turn on GridLock in System Settings › Privacy & Security › Device Control and Data Access. Until then the menu bar icon shows a warning sign and the menu's first item is \"Grant Access…\"."),
            .tip("Undo Move ({shortcut:undo}) puts the last window GridLock moved back where it was, up to 10 moves back."),
            .tip("While ToolHUD is running, GridLock's menu moves into ToolHUD's menu bar menu as a submenu, and the icon here steps aside until ToolHUD quits. To keep the icon, turn off \"Put in ToolHUD's menu while ToolHUD is running\" in Settings › General."),
            .tip("Quitting asks first, since the palette, the grid and the shortcuts stop working while GridLock is closed. Turn off \"Ask before quitting\" in Settings › General, or tick \"Don't ask again\" when it asks."),
        ]),

        HelpTopic(id: "grid", title: "The Grid", symbol: "square.grid.3x3", blocks: [
            .text("Show Grid lays the grid over the display holding the frontmost window. The window's current cells are outlined, with its size in pixels and cells. Choose new cells and the window snaps to fill them."),
            .keys([
                ("{shortcut:grid}", "Show Grid (also in the menu bar menu)"),
                ("Drag across cells", "Choose the selection; the window snaps when you let go"),
                ("← ↑ ↓ →", "Move the selection"),
                ("⇧ + arrow", "Grow the selection"),
                ("⌥⇧ + arrow", "Shrink the selection"),
                ("↩", "Snap the window to the selection"),
                ("esc", "Close the grid without moving anything"),
            ]),
            .text("Each display keeps its own grid at each desk: its columns, rows, gap (the space between snapped windows) and margin (the space between windows and the display's edges). Change them in Settings › Desks."),
            .tip("Some apps have a minimum size. GridLock shows the size the app will accept, and the window snaps as close as it allows."),
        ]),

        HelpTopic(id: "palette", title: "The Palette", symbol: "square.grid.3x1.below.line.grid.1x2", blocks: [
            .text("Drag any window by its title bar to the top edge of a display. After a moment the palette drops down: a row of layouts, each split into its zones. Drag over a zone to see where the window will go, and let go to snap it there."),
            .keys([
                ("Drag to the top edge", "Open the palette on that display"),
                ("Over a zone", "Preview where the window will go"),
                ("Let go over a zone", "Snap the window into it"),
                ("Drag away, or esc", "Close the palette; the window stays where you dragged it"),
            ]),
            .heading("Undo by dropping"),
            .text("When the window you're dragging is one GridLock has moved, the palette also shows an undo target. Drop the window there and it goes back to where it was before GridLock last moved it, even if other windows moved since. Over the target, an outline shows where the window will go."),
            .text("Choose how the undo target looks, or turn it off, in Settings › Palette › Every Palette. The same section shows or hides GridLock's name and version on the palette."),
            .heading("The palette's tab"),
            .text("While you drag a window, the palette's bottom edge peeks down from under the menu bar at the top center of the display. Drag onto it and the whole palette slides down from there. Turn the tab off in Settings › Shortcuts."),
            .heading("Without the top edge"),
            .text("Pushing a window against the top edge can also open Mission Control, which offers to move the window to another desktop. To skip the edge, hold {dragKeys} while you drag: the palette opens right away, just above the pointer. Let go of the keys away from the palette to close it. Choose the keys in Settings › Shortcuts."),
            .text("Or press {shortcut:palette} (Open Palette) with the window you want to place in front. The palette opens at the top of its display; move over a zone to see where the window will go, and click it to snap the window there. Esc, a click anywhere else, or {shortcut:palette} again closes it."),
            .heading("Choosing the layouts"),
            .text("Settings › Palette picks which layouts each display's palette shows at this desk, and in what order. Layouts in a family have a count (Columns × 3, Rows × 2, Grid 3 × 2), and a family can be in the palette more than once with different counts."),
            .tip("With ⌘ as the key, press it once the drag has started: in some apps ⌘-clicking a window's title shows its folder path."),
            .tip("If macOS's own \"Drag windows to screen edges to tile\" is on, it competes with the palette. Settings › General says so and opens the right page of System Settings; GridLock never changes the setting itself."),
        ]),

        HelpTopic(id: "desks", title: "Desks", symbol: "display.2", blocks: [
            .text("A desk is one set of connected displays. When you plug in or unplug a display, GridLock waits for things to settle, then switches to that desk's grids and palettes. A desk it hasn't seen starts from the most similar desk it knows: the same display elsewhere first, then one of the same resolution, else the defaults."),
            .text("Settings › Desks shows the current desk. Choose a display to set its grid: columns, rows, gap and margin. Each display keeps its own settings at each desk."),
            .keys([
                ("Rename", "Name a desk after where it is"),
                ("Copy Settings / Paste Settings", "Give another display the same grid and palette"),
                ("Delete", "Forget a desk you won't use again (not the current one)"),
            ]),
            .text("Desks are kept on this Mac and copied to a folder for this Mac in iCloud Drive › GridLock. With settings sync on, another Mac at the same set of displays shares their grids and palettes, and a desk that's new to a Mac starts from the others' settings."),
            .tip("If WindowKeeper already knows a desk, a new GridLock desk takes WindowKeeper's name for it."),
        ]),

        HelpTopic(id: "layouts", title: "Layouts", symbol: "rectangle.split.3x1", blocks: [
            .text("A layout is one way of dividing a display: halves, columns, rows, a grid of zones, two-thirds and one-third, centered, or a whole display. Each part is a zone, and a window snaps into a zone."),
            .text("A custom layout is one you draw yourself in Settings › Layouts. Drag on the canvas to add a zone, drag its edges to resize it, and press Delete to remove it. Zones are kept as fractions of the display, so one custom layout fits every display, and it can go in any palette."),
            .tip("With settings sync on, custom layouts are on all your Macs. Changing or deleting one changes or deletes it everywhere."),
        ]),

        HelpTopic(id: "shortcuts", title: "Shortcuts", symbol: "keyboard", blocks: [
            .keys([
                ("{shortcut:grid}", "Show Grid"),
                ("{shortcut:undo}", "Undo Move"),
                ("{shortcut:palette}", "Open Palette, then click a zone"),
                ("{shortcut:zone.left-half}", "Snap to the left half"),
                ("{shortcut:zone.right-half}", "Snap to the right half"),
                ("{shortcut:zone.maximize}", "Snap to the whole display"),
                ("{shortcut:zone.center}", "Snap to the center"),
            ]),
            .text("Shortcuts work from any app and act on the frontmost window. Set them in Settings › Shortcuts: click a box and press the keys; Delete clears it. A shortcut another GridLock action already uses is refused, with that action's name."),
            .tip("ShortcutsLens lists GridLock's shortcuts too."),
        ]),

        HelpTopic(id: "settings", title: "Settings and Sync", symbol: "gearshape", blocks: [
            .keys([
                ("General", "Appearance, opening at login, asking before quitting, the Dock and menu bar icons, iCloud and updates"),
                ("Desks", "Each display's grid at the current desk"),
                ("Palette", "Which layouts each display's palette shows"),
                ("Layouts", "Custom layouts"),
                ("Shortcuts", "Keys for the grid, Undo Move and zones"),
            ]),
            .heading("Where GridLock appears"),
            .text("Show GridLock in the Dock, the menu bar, both, or neither. With neither, open GridLock again from Applications or Spotlight to get back to Settings. With the Dock icon on, its right-click menu has Settings…."),
            .heading("Sync"),
            .text("With \"Sync settings with your other Macs\" on, appearance, shortcuts, asking before quitting, where GridLock appears, the update choices and your custom layouts follow you to every Mac signed in to the same iCloud account. Deleting a custom layout on one Mac deletes it on the others."),
            .text("Grids and palettes follow a desk: change a display's grid or palette, and every Mac at that same set of displays gets the change within a minute. Two laptops at the same monitor share a desk; a Mac mini at that monitor is a desk of its own. A desk that's new to a Mac starts from another Mac's settings for those displays. The newest change wins."),
            .tip("Settings can be dragged bigger to see more at once, and keeps the size you choose."),
        ]),

        HelpTopic(id: "updates", title: "Updates", symbol: "arrow.down.circle", blocks: [
            .text("Settings › General › Updates chooses what GridLock does when a new version is out: install it automatically while your Mac is idle and the grid and the palette are closed, ask you first, or not check at all. Check Now looks right away."),
            .heading("What's new"),
            .text("The update window shows the notes for the latest releases, with the ones you don't have yet marked New. \"Don't remind me about this version\" is ticked to begin with: click Not Now with it ticked, and GridLock stops reminding you about that version (Check Now still offers it)."),
            .text("After an update that installed itself, Settings shows what changed the next time it opens. What's New… beside Check Now shows the notes any time, and About GridLock (in the menu bar menu) shows the last 10 releases."),
        ]),

        HelpTopic(id: "automation", title: "Automation", symbol: "link", blocks: [
            .keys([
                ("gridlock://grid", "Show Grid"),
                ("gridlock://undo", "Undo Move"),
                ("gridlock://snap?zone=left-half", "Snap the frontmost window to a zone"),
                ("gridlock://settings", "Open Settings"),
            ]),
            .text("Zones for snap: left-half, right-half, top-half, bottom-half, left-third, center-third, right-third, left-two-thirds, right-two-thirds, top-left, top-right, bottom-left, bottom-right, center and maximize."),
            .text("Use these links from Shortcuts, scripts or a launcher. ToolHUD's GridLock buttons use them."),
            .heading("Command line and AI agents"),
            .text("GridLock is also a command line tool, so scripts and AI agents such as Claude Code or Codex can see your displays, desks, grids and layouts, list windows, snap a window to a zone, a layout or grid cells, undo a move, and change grids and settings. Commands run in the open app, so Undo Move works on them too. Resetting a display's grid and palette needs --yes."),
            .keys([
                ("gridlock help", "List every command and its options"),
                ("gridlock windows snap --zone left-half", "Snap the frontmost window to a zone; --app picks another app's"),
                ("gridlock layouts apply Halves --zone 2", "Snap the frontmost window into a palette layout's zone"),
                ("gridlock grid set --display 1 --columns 12", "Change a display's grid at this desk"),
                ("gridlock mcp", "Offer the same commands to MCP apps, such as Claude Desktop"),
            ]),
            .text("To type gridlock in Terminal, link it once: ln -s /Applications/GridLock.app/Contents/MacOS/GridLock ~/.local/bin/gridlock (with ~/.local/bin on your PATH). Without --app, snapping acts on the frontmost window, which is Terminal's when you run it there. MCP apps take the full path to that program, followed by mcp."),
        ]),

        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("Windows don't move"),
            .text("GridLock needs access. Choose \"Grant Access…\" in the menu bar menu. If GridLock is on in Device Control and Data Access but nothing moves, remove it from the list and add it again."),
            .heading("The palette doesn't open"),
            .text("Drag by the window's title bar, not its content, and hold the cursor at the very top of the display for a moment. If macOS's edge tiling is on, it may take the drag first; Settings › General shows a note when it is."),
            .heading("A window doesn't fill its zone"),
            .text("Some apps won't go smaller than a minimum size, and full-screen windows can't be moved. Windows on other Spaces aren't moved."),
        ]),
    ] }
}

// MARK: - Window

@Observable
@MainActor
final class HelpState {
    var selection: String? = "getting-started"
    var query = ""
}

@MainActor
final class HelpWindow: NSObject, NSWindowDelegate {
    static let shared = HelpWindow()

    let state = HelpState()
    private(set) var window: NSWindow?

    /// Opens Help, on `topic` when given.
    func show(topic: String? = nil) {
        if let topic { state.query = ""; state.selection = topic }
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(state: state))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let screen = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 820, height: min(600, screen - 80)))
            window.contentMinSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("GridLockHelp")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @Bindable var state: HelpState

    private var matches: [HelpTopic] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Help.topics }
        return Help.topics.filter { topic in
            topic.title.lowercased().contains(query) || topic.blocks.contains { $0.searchText.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $state.selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .overlay {
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        } detail: {
            if let topic = Help.topics.first(where: { $0.id == state.selection }) {
                HelpPage(topic: topic, query: state.query)
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: state.query) {
            // Keep a matching topic on screen while searching.
            if let first = matches.first, !matches.contains(where: { $0.id == state.selection }) { state.selection = first.id }
        }
    }
}

struct HelpPage: View {
    let topic: HelpTopic
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .text(let s):
            Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(Help.resolve(s)).font(.title3.weight(.semibold)).padding(.top, 8)
        case .tip(let s):
            Label { Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .keys(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let keys = Help.resolve(row.0), what = Help.resolve(row.1)
                    let hit = !query.isEmpty && (keys + " " + what).lowercased().contains(query.lowercased())
                    GridRow {
                        Text(keys)
                            .font(.body.monospaced().weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            // The same key column width in every table on every page.
                            .frame(width: 210, alignment: .leading)
                        Text(what).fixedSize(horizontal: false, vertical: true)
                    }
                    .background(hit ? Color.yellow.opacity(0.25) : .clear)
                }
            }
        }
    }
}

/// The round "?" button macOS puts in the corner of settings panes.
struct HelpButton: NSViewRepresentable {
    let topic: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open))
        button.bezelStyle = .helpButton
        button.toolTip = "\(AppInfo.name) Help"
        button.setAccessibilityLabel("Help")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.topic = topic }

    func makeCoordinator() -> Coordinator { Coordinator(topic: topic) }

    @MainActor
    final class Coordinator: NSObject {
        var topic: String
        init(topic: String) { self.topic = topic }
        @objc func open() { HelpWindow.shared.show(topic: topic) }
    }
}
