# GridLock build plan

## Done (foundation, 2026-11-02)
- GridLockKit: display keys + settle rule (from WindowKeeper), desks and per-display settings, seeding a new desk from the closest known one, grid math (cells ↔ frames, gap, margin, mapping between grids), layout families and zones, palette defaults, move history. 29 tests.
- App: desk recognition (`DeskTracker`), desk library with per-Mac iCloud mirror (`DeskStore`), Accessibility window access + move with undo (`WindowMover`), `Actions` (snap to zone/cells, undo, URL and shortcut entry points), generalized global shortcuts (`HotKeyCenter` + `ShortcutCatalog`, ⌃⌥G / ⌃⌥Z), menu bar menu, welcome/permission window (S-001), tabbed resizable Settings (General, Desks with plain grid steppers, placeholder Palette/Layouts, Shortcuts), Ask before quitting, Dock/menu bar presence, appearance switch, launch at login, `gridlock://` URLs, debug hook, snapshot mode, release scripts copied from WindowKeeper.

## Sessions
Three sessions run in parallel, each in its own worktree branch; this session merges them.

| Session | Stories | Owns (may edit freely) | Touches lightly |
| --- | --- | --- | --- |
| **Interaction** | S-003–S-005, S-008, S-010–S-013, S-030–S-032 | new `GridOverlay*.swift`, `Palette*.swift`, `DragWatcher.swift`, `EdgeTiling.swift`, `ShortcutsSettings.swift`, `HotKeys.swift` catalog, `Actions.swift` | `Snapshot.swift` (add pages), `GeneralSettings.swift` (tiling note) |
| **Desks UI** | S-006 (desk picture), S-020–S-025 | `DesksSettings.swift`, `PaletteSettings.swift`, `LayoutsSettings.swift`, new layout-editor/thumbnail files, `DeskStore.swift`, GridLockKit desk/palette/layout files | `Snapshot.swift` (add pages), `DeskTracker.swift` |
| **System** | S-040–S-047, S-050, S-051 | copies of the house files (AutoUpdater, UpdatePolicy, UpdateInterval, SettingsSync, SyncUpdateControls, ReleaseNotes/WhatsNew, MenuHub, Help), icon tools, `StatusItemController.swift`, `AppDelegate.swift` | `GeneralSettings.swift` (sync/update sections), `SettingsWindow.swift` (Updates tab, Help buttons), `Info.plist` (ToolHUDActions) |

Shared rule: the palette thumbnail view is owned by **Desks UI** (`LayoutThumbnail.swift`); **Interaction** uses it. If Interaction needs it first, it writes a minimal one in that file and Desks UI restyles it.

Only **Interaction** installs to /Applications and drives real windows. The other two test with unit tests and snapshot mode.

## After the merge
- M6 rest: S-052 README, release, website (after the user tries a build).
- M7 (milestone 2): S-060–S-062 arrangements and per-app rules.
