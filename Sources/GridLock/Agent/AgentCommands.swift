import AppKit
import GridLockKit

/// Everything an agent can do in GridLock. Add a command here and the CLI, `help`, and the MCP
/// tools all get it. Each `run` is on the main actor and calls the same code as the menu bar
/// menu, the palette, Settings and the gridlock:// links, so Undo Move and Settings keep up.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the version, whether GridLock may move windows (`accessAllowed`), the current desk, how many displays, desks and custom layouts there are, whether the grid or palette is showing, and what Undo Move would put back.",
                     example: "gridlock status --json", readOnly: true) { _ in
            let library = desks.store.library
            return ["app": AppInfo.name, "version": AppInfo.version, "accessAllowed": AXWindows.isTrusted,
                    "desk": desks.currentDesk?.name ?? NSNull(), "deskID": desks.currentDesk.map { short($0.id) } ?? NSNull(),
                    "displays": liveDisplays().count, "desks": library.desks.count, "customLayouts": library.customLayouts.count,
                    "gridShowing": GridOverlay.shared.isShowing, "paletteShowing": PaletteOverlay.shared.isShowing,
                    "undo": WindowMover.shared.undoTitle ?? NSNull()]
        },

        // MARK: Displays and desks

        AgentCommand(name: "displays list", summary: "List the connected displays, left to right, with each one's grid (columns, rows, gap, margin in points) and palette size at the current desk. Returns `displays` (index, name, key, main, bounds, visible, grid, paletteLayouts) and `desk`.",
                     example: "gridlock displays list --json", readOnly: true) { _ in
            let displays = liveDisplays()
            return ["desk": desks.currentDesk?.name ?? NSNull(),
                    "displays": displays.enumerated().map { displayJSON($1, index: $0 + 1) }, "total": displays.count]
        },
        AgentCommand(name: "desks list", summary: "List the desks: each set of displays GridLock has seen, with its own grids and palettes. Returns `desks` (id, name, current, displays, lastUsed) and `total`.",
                     example: "gridlock desks list --json", readOnly: true) { _ in
            let listed = desks.store.library.listed(current: desks.currentDeskID)
            return ["desks": listed.map { desk -> JSONObject in
                ["id": short(desk.id), "name": desk.name, "current": desk.id == desks.currentDeskID,
                 "displays": desk.displays.map(\.name), "lastUsed": JSON.date(desk.lastUsed)]
            }, "total": listed.count]
        },
        AgentCommand(name: "desks rename", summary: "Rename a desk, as Settings › Desks does.",
                     params: [.init(name: "id", required: true, positional: true, help: "the desk's id (any unique start of it, see `gridlock desks list`)"),
                              .init(name: "name", required: true, help: "the new name")],
                     example: "gridlock desks rename 3f2a9c1e --name \"Home Office\" --json") { args in
            let desk = try findDesk(try args.required("id"))
            let name = try args.required("name").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AgentError.invalid("--name can't be empty") }
            desks.store.rename(desk.id, to: name)
            return ["id": short(desk.id), "name": name, "changed": name != desk.name]
        },

        // MARK: Layouts

        AgentCommand(name: "layouts list", summary: "List a display's palette layouts in palette order, and every custom layout. Returns `palette` (index, title, kind, zones) and `custom` (id, name, zones, inPalette).",
                     params: [displayParam],
                     example: "gridlock layouts list --display 1 --json", readOnly: true) { args in
            let display = try findDisplay(args)
            let custom = desks.store.library.customLayouts
            let palette = desks.settings(for: display).palette
            let inPalette = Set(palette.compactMap { entry -> UUID? in
                if case .custom(let id) = entry.kind { return id }
                return nil
            })
            return ["display": display.name,
                    "palette": palette.enumerated().map { index, entry -> JSONObject in
                        ["index": index + 1, "title": entry.kind.title(custom: custom), "kind": kindName(entry.kind),
                         "zones": entry.kind.zones(custom: custom).count]
                    },
                    "custom": custom.map { layout -> JSONObject in
                        ["id": short(layout.id), "name": layout.name, "zones": layout.zones.count, "inPalette": inPalette.contains(layout.id)]
                    }]
        },
        AgentCommand(name: "layouts show", summary: "Show a layout's zones, numbered left to right then top to bottom, as fractions of the display and as the frames they'd give on it (with its gap and margin).",
                     params: [layoutParam, displayParam],
                     example: "gridlock layouts show Halves --json", readOnly: true) { args in
            let display = try findDisplay(args)
            let (kind, title) = try findLayout(try args.required("layout"), on: display)
            let grid = desks.settings(for: display).grid
            let zones = kind.zones(custom: desks.store.library.customLayouts)
            return ["layout": title, "kind": kindName(kind), "display": display.name,
                    "zones": zones.enumerated().map { index, zone -> JSONObject in
                        ["zone": index + 1, "unit": unitJSON(zone),
                         "frame": rectJSON(GridMath.frame(for: zone, visible: display.visible, gap: grid.gap, margin: grid.margin))]
                    }]
        },
        AgentCommand(name: "layouts apply", summary: "Snap a window into one zone of a layout, as clicking that zone in the palette does. Moves a real window (Undo Move, or `gridlock windows undo`, puts it back). Without --app it's the frontmost window of another app, which is Terminal's when run from Terminal.",
                     params: [layoutParam,
                              .init(name: "zone", kind: .integer, help: "which zone, from 1 (see `gridlock layouts show`). Default 1"),
                              appParam,
                              .init(name: "display", help: "put it on this display instead of the one it's on (an index from `gridlock displays list`, or a name)")],
                     example: "gridlock layouts apply \"Two-Thirds + Third\" --zone 2 --app Safari --json") { args in
            let window = try targetWindow(args)
            let display = args.string("display") != nil ? try findDisplay(args) : try displayHolding(window)
            let (kind, title) = try findLayout(try args.required("layout"), on: display)
            let zones = kind.zones(custom: desks.store.library.customLayouts)
            let number = try args.int("zone", default: 1)
            guard zones.indices.contains(number - 1) else {
                throw AgentError.usage("\(title) has \(zones.count) zone\(zones.count == 1 ? "" : "s"): give --zone 1 to \(zones.count)")
            }
            Actions.shared.snap(window, to: zones[number - 1], on: display)
            return moved(window, on: display, extra: ["layout": title, "zone": number])
        },

        // MARK: Windows

        AgentCommand(name: "windows list", summary: "List the windows GridLock can place, front app first. Returns `windows` (app, title, frame, display, cells on that display's grid, minimized, front) and `total`. Needs Accessibility access.",
                     params: [.init(name: "app", help: "only this app's windows (its name)"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "gridlock windows list --app Safari --json", readOnly: true) { args in
            guard AXWindows.isTrusted else { throw AgentError.noAccess }
            let front = WindowMover.shared.frontmostWindow()
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            var apps = AXWindows.managedApps().sorted { a, b in (a.processIdentifier == frontPID ? 0 : 1) < (b.processIdentifier == frontPID ? 0 : 1) }
            if let name = args.string("app") { apps = try [findApp(name)] }
            let displays = liveDisplays()
            let rows = apps.flatMap { app in
                AXWindows.windows(of: app.processIdentifier).filter(\.isSaveable).map { window -> JSONObject in
                    var json: JSONObject = ["app": app.localizedName ?? "", "title": window.title, "frame": rectJSON(window.frame),
                                            "minimized": window.isMinimized,
                                            "front": front.map { CFEqual($0.element, window.element) } ?? false]
                    if let index = LiveDisplay.index(holding: window.frame, in: displays) {
                        let display = displays[index]
                        json["display"] = index + 1
                        json["cells"] = cellsJSON(GridMath.cells(for: window.frame, grid: desks.settings(for: display).grid, visible: display.visible))
                    }
                    return json
                }
            }
            return try page(rows, args, key: "windows")
        },
        AgentCommand(name: "windows snap", summary: "Snap a window to a named zone, to grid cells, or to the next or previous display (keeping its share of the grid), as the shortcuts and the grid do. Give one of --zone, --cells or --display. Moves a real window (`gridlock windows undo` puts it back). Without --app it's the frontmost window of another app, which is Terminal's when run from Terminal.",
                     params: [.init(name: "zone", help: "one of " + Actions.namedZones.keys.sorted().joined(separator: ", ")),
                              .init(name: "cells", help: "column,row[,columns,rows] on the display's grid, counted from 1: \"1,1,3,2\" is three columns by two rows from the top left"),
                              .init(name: "display", help: "next or previous: move it to another display"),
                              appParam],
                     example: "gridlock windows snap --zone left-half --app Safari --json") { args in
            let given = ["zone", "cells", "display"].filter { args.string($0) != nil }
            guard given.count == 1 else { throw AgentError.usage("give one of --zone, --cells or --display. Example: gridlock windows snap --zone left-half") }
            if let name = args.string("zone") {
                guard let zone = Actions.namedZones[name.lowercased()] else {
                    throw AgentError.usage("no zone \"\(name)\". Zones: \(Actions.namedZones.keys.sorted().joined(separator: ", "))")
                }
                let window = try targetWindow(args)
                let display = try displayHolding(window)
                Actions.shared.snap(window, to: zone, on: display)
                return moved(window, on: display, extra: ["zone": name.lowercased()])
            }
            if let text = args.string("cells") {
                let numbers = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard [2, 4].contains(numbers.count), let values = numbers as? [Int], values.allSatisfy({ $0 >= 1 }) else {
                    throw AgentError.usage("--cells is column,row or column,row,columns,rows, each 1 or more, like \"1,1,3,2\"")
                }
                let window = try targetWindow(args)
                let display = try displayHolding(window)
                let grid = desks.settings(for: display).grid
                let cells = CellRange(column: values[0] - 1, row: values[1] - 1,
                                      columns: values.count == 4 ? values[2] : 1, rows: values.count == 4 ? values[3] : 1)
                guard cells.column + cells.columns <= grid.columns, cells.row + cells.rows <= grid.rows else {
                    throw AgentError.usage("\(display.name)'s grid is \(grid.columns) columns × \(grid.rows) rows: \(text) runs past it")
                }
                Actions.shared.snap(window, to: cells, on: display)
                return moved(window, on: display, extra: ["cells": cellsJSON(cells)])
            }
            let direction = (args.string("display") ?? "").lowercased()
            guard let step = ["next": 1, "previous": -1][direction] else { throw AgentError.usage("--display must be next or previous") }
            let window = try targetWindow(args)
            guard let display = Actions.shared.sendToDisplay(window, step: step) else {
                throw AgentError.invalid("there's only one display, so there's nowhere to send it")
            }
            return moved(window, on: display, extra: ["display": display.name])
        },
        AgentCommand(name: "windows undo", summary: "Undo Move: put the most recently moved window that's still open back where it was, as the menu bar menu's Undo Move does. Moves a real window.",
                     example: "gridlock windows undo --json") { _ in
            guard AXWindows.isTrusted else { throw AgentError.noAccess }
            guard let title = WindowMover.shared.undoTitle else { return ["undone": false, "reason": "nothing to undo"] }
            Actions.shared.undo()
            return ["undone": true, "what": title]
        },

        // MARK: Grids

        AgentCommand(name: "grid set", summary: "Change a display's grid at the current desk, as Settings › Desks does. Only the options you give change.",
                     params: [displayParam,
                              .init(name: "columns", kind: .integer, help: "\(GridSpec.columnRange.lowerBound) to \(GridSpec.columnRange.upperBound)"),
                              .init(name: "rows", kind: .integer, help: "\(GridSpec.rowRange.lowerBound) to \(GridSpec.rowRange.upperBound)"),
                              .init(name: "gap", help: "points between snapped windows, 0 to \(Int(GridSpec.spacingRange.upperBound))"),
                              .init(name: "margin", help: "points around the display's edges, 0 to \(Int(GridSpec.spacingRange.upperBound))")],
                     example: "gridlock grid set --display 1 --columns 12 --rows 6 --gap 8 --json") { args in
            let desk = try currentDesk()
            let display = try findDisplay(args)
            let columns = try args.string("columns").map { _ in try args.int("columns", default: 0) }
            let rows = try args.string("rows").map { _ in try args.int("rows", default: 0) }
            let gap = try spacing(args, "gap"), margin = try spacing(args, "margin")
            guard columns != nil || rows != nil || gap != nil || margin != nil else {
                throw AgentError.usage("give at least one of --columns, --rows, --gap or --margin")
            }
            if let columns, !GridSpec.columnRange.contains(columns) { throw AgentError.usage("--columns must be 1 to \(GridSpec.columnRange.upperBound)") }
            if let rows, !GridSpec.rowRange.contains(rows) { throw AgentError.usage("--rows must be 1 to \(GridSpec.rowRange.upperBound)") }
            let before = desks.settings(for: display).grid
            desks.store.update(desk: desk.id, display: display.key) { settings in
                if let columns { settings.grid.columns = columns }
                if let rows { settings.grid.rows = rows }
                if let gap { settings.grid.gap = gap }
                if let margin { settings.grid.margin = margin }
            }
            let after = desks.settings(for: display).grid
            return ["desk": desk.name, "display": display.name, "grid": gridJSON(after), "changed": after != before]
        },
        AgentCommand(name: "grid reset", summary: "Reset to Defaults: give a display at the current desk the grid and palette GridLock suggests for its shape, as Settings › Desks does. Replaces its palette too. Without --yes it only shows what it would change.",
                     params: [displayParam],
                     example: "gridlock grid reset --display 1 --yes --json", destructive: true) { args in
            let desk = try currentDesk()
            let display = try findDisplay(args)
            let now = desks.settings(for: display)
            let size = desk.displays.first { $0.key == display.key }?.bounds.cgRect.size ?? display.bounds.size
            let suggested = DisplaySettings.suggested(for: size)
            guard args.confirmed else {
                return ["wouldReset": display.name, "desk": desk.name,
                        "now": ["grid": gridJSON(now.grid), "paletteLayouts": now.palette.count] as JSONObject,
                        "after": ["grid": gridJSON(suggested.grid), "paletteLayouts": suggested.palette.count] as JSONObject,
                        "hint": "add --yes to reset it (over MCP, set yes to true). Its palette goes back to the suggested layouts too"]
            }
            desks.store.reset(desk: desk.id, display: display.key)
            let after = desks.settings(for: display)
            return ["reset": display.name, "desk": desk.name, "grid": gridJSON(after.grid), "paletteLayouts": after.palette.count]
        },

        // MARK: Settings

        AgentCommand(name: "settings show", summary: "Show GridLock's settings: Ask before quitting, the Dock and menu bar icons, the keys that open the palette mid-drag, the palette's undo target and version, and every global shortcut.",
                     example: "gridlock settings show --json", readOnly: true) { _ in
            let settings = AppSettings.shared
            let names: [(NSEvent.ModifierFlags, String)] = [(.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command")]
            return ["askBeforeQuitting": settings.confirmQuit, "showInDock": settings.showInDock, "showInMenuBar": settings.showInMenuBar,
                    "paletteDragKeys": names.filter { settings.paletteModifiers.contains($0.0) }.map(\.1),
                    "undoTarget": settings.undoTargetStyle.rawValue, "paletteVersion": settings.showsPaletteVersion,
                    "shortcuts": ShortcutCatalog.all.map { item -> JSONObject in
                        ["id": item.id, "title": item.title, "key": settings.shortcut(item.id)?.display ?? ""]
                    }]
        },
        AgentCommand(name: "settings set", summary: "Change GridLock's settings from Settings › General, and the palette's undo target and version from Settings › Palette. Only the options you give change.",
                     params: [.init(name: "ask-before-quitting", kind: .boolean, help: "true or false"),
                              .init(name: "show-in-dock", kind: .boolean, help: "true or false"),
                              .init(name: "show-in-menu-bar", kind: .boolean, help: "true or false"),
                              .init(name: "undo-target", help: UndoTargetStyle.allCases.map(\.rawValue).joined(separator: ", ")),
                              .init(name: "palette-version", kind: .boolean, help: "true or false: GridLock's name and version on the palette")],
                     example: "gridlock settings set --ask-before-quitting false --json") { args in
            let settings = AppSettings.shared
            let quit = try args.bool("ask-before-quitting"), dock = try args.bool("show-in-dock"), menuBar = try args.bool("show-in-menu-bar")
            let version = try args.bool("palette-version")
            var undoTarget: UndoTargetStyle?
            if let name = args.string("undo-target") {
                guard let style = UndoTargetStyle.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else {
                    throw AgentError.usage("--undo-target must be one of \(UndoTargetStyle.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                undoTarget = style
            }
            guard quit != nil || dock != nil || menuBar != nil || undoTarget != nil || version != nil else {
                throw AgentError.usage("give at least one of --ask-before-quitting, --show-in-dock, --show-in-menu-bar, --undo-target or --palette-version")
            }
            var changed = false
            if let undoTarget, settings.undoTargetStyle != undoTarget { settings.undoTargetStyle = undoTarget; changed = true }
            if let version, settings.showsPaletteVersion != version { settings.showsPaletteVersion = version; changed = true }
            if let quit, settings.confirmQuit != quit { settings.confirmQuit = quit; changed = true }
            if let dock, settings.showInDock != dock { settings.showInDock = dock; changed = true }
            if let menuBar, settings.showInMenuBar != menuBar { settings.showInMenuBar = menuBar; changed = true }
            var result: JSONObject = ["askBeforeQuitting": settings.confirmQuit, "showInDock": settings.showInDock,
                                      "showInMenuBar": settings.showInMenuBar, "undoTarget": settings.undoTargetStyle.rawValue,
                                      "paletteVersion": settings.showsPaletteVersion, "changed": changed]
            if !settings.showInDock && !settings.showInMenuBar {
                result["note"] = AppPresence.hiddenEverywhereNote(appName: "GridLock", settingsName: "Settings")
            }
            return result
        },
        AgentCommand(name: "open", summary: "Bring up a GridLock window: Settings on one of its panes, or Help on a topic.",
                     params: [.init(name: "page", required: true, positional: true,
                                    help: "settings, general, desks, palette, layouts, shortcuts or help"),
                              .init(name: "topic", help: "with help: a topic, like getting-started, grid, palette, desks, layouts, shortcuts, automation or troubleshooting")],
                     example: "gridlock open desks --json") { args in
            let page = try args.required("page").lowercased()
            let tabs = ["settings": "General", "general": "General", "desks": "Desks", "palette": "Palette",
                        "layouts": "Layouts", "shortcuts": "Shortcuts"]
            if page == "help" {
                let topic = args.string("topic")
                if let topic, !Help.topics.contains(where: { $0.id == topic }) {
                    throw AgentError.notFound("no Help topic \"\(topic)\". Topics: \(Help.topics.map(\.id).joined(separator: ", "))")
                }
                HelpWindow.shared.show(topic: topic)
                return ["open": "help", "topic": topic.map { $0 as Any } ?? NSNull()]
            }
            guard let tab = tabs[page] else {
                throw AgentError.notFound("no page \"\(page)\". Pages: settings, general, desks, palette, layouts, shortcuts, help")
            }
            SettingsWindow.shared.show(tab: tab)
            return ["open": "settings", "pane": tab]
        },
    ]

    // MARK: Params

    static let displayParam = AgentCommand.Param(name: "display", help: "a display: its index from `gridlock displays list` (1 is leftmost), its name or its key. Default: the one with the frontmost window, else the main display")
    static let layoutParam = AgentCommand.Param(name: "layout", required: true, positional: true, help: "a palette layout's index or title (see `gridlock layouts list`), or a custom layout's name or id")
    static let appParam = AgentCommand.Param(name: "app", help: "the front window of this app (its name) instead of the frontmost app's")

    // MARK: Finding things

    @MainActor static var desks: DeskTracker { Actions.shared.desks }

    static func short(_ id: UUID) -> String { String(id.uuidString.lowercased().prefix(8)) }

    @MainActor
    static func liveDisplays() -> [LiveDisplay] {
        let live = desks.live.isEmpty ? DisplayCatalog.current() : desks.live
        return live.sorted { ($0.bounds.minX, $0.bounds.minY) < ($1.bounds.minX, $1.bounds.minY) }
    }

    @MainActor
    static func currentDesk() throws -> Desk {
        guard let desk = desks.currentDesk else {
            throw AgentError.busy("GridLock is still recognizing the displays. Try again in a few seconds")
        }
        return desk
    }

    @MainActor
    static func findDesk(_ prefix: String) throws -> Desk {
        let key = prefix.lowercased()
        let matches = desks.store.library.desks.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw AgentError.notFound("no desk with id \(prefix). Run `gridlock desks list`")
        default: throw AgentError.invalid("\(matches.count) desks have ids starting \(prefix). Give more of the id")
        }
    }

    /// --display as an index, name or key; without it the frontmost window's display, else the main one.
    @MainActor
    static func findDisplay(_ args: Args) throws -> LiveDisplay {
        let displays = liveDisplays()
        guard !displays.isEmpty else { throw AgentError.invalid("macOS reports no displays") }
        guard let wanted = args.string("display") else {
            if let window = WindowMover.shared.frontmostWindow(), let index = LiveDisplay.index(holding: window.frame, in: displays) {
                return displays[index]
            }
            return displays.first(where: \.isMain) ?? displays[0]
        }
        if let index = Int(wanted) {
            guard displays.indices.contains(index - 1) else {
                throw AgentError.notFound("no display \(index): there \(displays.count == 1 ? "is 1" : "are \(displays.count)"). Run `gridlock displays list`")
            }
            return displays[index - 1]
        }
        if let match = displays.first(where: { $0.key == wanted || $0.name.localizedCaseInsensitiveCompare(wanted) == .orderedSame }) {
            return match
        }
        throw AgentError.notFound("no display \"\(wanted)\". Run `gridlock displays list`")
    }

    /// A palette entry by its index or title on `display`, else a custom layout by name or id.
    @MainActor
    static func findLayout(_ text: String, on display: LiveDisplay) throws -> (LayoutKind, String) {
        let custom = desks.store.library.customLayouts
        let palette = desks.settings(for: display).palette
        if let index = Int(text) {
            guard palette.indices.contains(index - 1) else {
                throw AgentError.notFound("\(display.name)'s palette has \(palette.count) layouts. Run `gridlock layouts list`")
            }
            return (palette[index - 1].kind, palette[index - 1].kind.title(custom: custom))
        }
        if let entry = palette.first(where: { $0.kind.title(custom: custom).localizedCaseInsensitiveCompare(text) == .orderedSame }) {
            return (entry.kind, entry.kind.title(custom: custom))
        }
        let matches = custom.filter {
            $0.name.localizedCaseInsensitiveCompare(text) == .orderedSame || $0.id.uuidString.lowercased().hasPrefix(text.lowercased())
        }
        if matches.count == 1 { return (.custom(id: matches[0].id), matches[0].name) }
        if matches.count > 1 { throw AgentError.invalid("\(matches.count) custom layouts match \"\(text)\". Give its id") }
        throw AgentError.notFound("no layout \"\(text)\" in \(display.name)'s palette or the custom layouts. Run `gridlock layouts list`")
    }

    @MainActor
    static func findApp(_ name: String) throws -> NSRunningApplication {
        let apps = AXWindows.managedApps()
        if let app = apps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.bundleIdentifier == name }) {
            return app
        }
        throw AgentError.notFound("no running app called \"\(name)\". Run `gridlock windows list` to see the apps with windows")
    }

    /// The window to move: --app's front window, else the frontmost app's, as the shortcuts use.
    @MainActor
    static func targetWindow(_ args: Args) throws -> TargetWindow {
        guard AXWindows.isTrusted else { throw AgentError.noAccess }
        guard let name = args.string("app") else {
            guard let window = WindowMover.shared.frontmostWindow() else {
                throw AgentError.invalid("the frontmost app has no window GridLock can place (the desktop, a full-screen window, or none). Give --app")
            }
            return window
        }
        let app = try findApp(name)
        guard let window = AXWindows.windows(of: app.processIdentifier).first(where: \.isPlaceable) else {
            throw AgentError.invalid("\(app.localizedName ?? name) has no window GridLock can place (minimized, full screen or none)")
        }
        return TargetWindow(element: window.element, pid: app.processIdentifier, appName: app.localizedName ?? name, frame: window.frame)
    }

    @MainActor
    static func displayHolding(_ window: TargetWindow) throws -> LiveDisplay {
        guard let display = desks.display(holding: window.frame) else { throw AgentError.invalid("couldn't tell which display \(window.appName)'s window is on") }
        return display
    }

    // MARK: Results

    @MainActor
    static func moved(_ window: TargetWindow, on display: LiveDisplay, extra: JSONObject) -> JSONObject {
        var json = extra
        json["app"] = window.appName
        json["from"] = rectJSON(window.frame)
        json["to"] = AXWindows.frame(of: window.element).map(rectJSON) ?? NSNull()
        json["onDisplay"] = display.name
        json["undo"] = "gridlock windows undo"
        return json
    }

    @MainActor
    static func displayJSON(_ display: LiveDisplay, index: Int) -> JSONObject {
        let settings = desks.settings(for: display)
        return ["index": index, "name": display.name, "key": display.key, "main": display.isMain, "builtIn": display.isBuiltin,
                "bounds": rectJSON(display.bounds), "visible": rectJSON(display.visible),
                "grid": gridJSON(settings.grid), "paletteLayouts": settings.palette.count, "customized": settings.modified != nil]
    }

    static func gridJSON(_ grid: GridSpec) -> JSONObject {
        ["columns": grid.columns, "rows": grid.rows, "gap": grid.gap, "margin": grid.margin]
    }

    static func rectJSON(_ rect: CGRect) -> JSONObject {
        ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }

    /// Fractions of the display, to four places: a third is 0.3333.
    static func unitJSON(_ rect: UnitRect) -> JSONObject {
        func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
        return ["x": round4(rect.x), "y": round4(rect.y), "width": round4(rect.width), "height": round4(rect.height)]
    }

    /// Counted from 1, as `--cells` takes them.
    static func cellsJSON(_ cells: CellRange) -> JSONObject {
        ["column": cells.column + 1, "row": cells.row + 1, "columns": cells.columns, "rows": cells.rows]
    }

    static func kindName(_ kind: LayoutKind) -> String {
        switch kind {
        case .maximize: "maximize"
        case .center: "center"
        case .columns: "columns"
        case .rows: "rows"
        case .grid: "grid"
        case .split: "split"
        case .custom: "custom"
        }
    }

    static func spacing(_ args: Args, _ name: String) throws -> Double? {
        guard let raw = args.string(name) else { return nil }
        guard let value = Double(raw), GridSpec.spacingRange.contains(value) else {
            throw AgentError.usage("--\(name) must be a number of points from 0 to \(Int(GridSpec.spacingRange.upperBound)), not \"\(raw)\"")
        }
        return value
    }

    static func page(_ all: [JSONObject], _ args: Args, key: String) throws -> JSONObject {
        let limit = try args.int("limit", default: 50)
        let offset = try args.int("offset", default: 0)
        guard limit > 0, offset >= 0 else { throw AgentError.usage("--limit must be 1 or more, and --offset 0 or more") }
        let slice = all.dropFirst(offset).prefix(limit)
        var result: JSONObject = [key: Array(slice), "total": all.count]
        if offset + slice.count < all.count { result["nextOffset"] = offset + slice.count }
        return result
    }
}
