# GridLock stories

No reference screenshots: the reference apps are for inspiration only. `Screens:` names the snapshot pages that will show each story (`GRIDLOCK_SNAPSHOT=<page>`).

Checks: `[snap]` snapshot, `[unit]` unit test in GridLockKit, `[self]` in-app self-test through the debug hook, `[manual]` a person tries it.

## M1 Core loop — place a window with the grid

### S-001 Grant Accessibility on first launch
As the user, I open GridLock for the first time and it tells me why it needs Accessibility, with one button that opens the right Settings page.
Screens: welcome
Acceptance:
- [snap] The welcome window names the permission as macOS 27 does ("Device Control and Data Access") and has one primary button, "Open Privacy Settings".
- [self] With the permission missing, the menu bar icon shows its warning variant and the menu's first item is "Grant Access…".
- [manual] After granting, the window closes on its own within 2 seconds, with no relaunch.
UX:
- Flow: first launch, or "Grant Access…" in the menu → welcome window → "Open Privacy Settings" → user turns GridLock on → window closes itself and the menu icon loses its warning badge
- Surface: new window (a self-contained task people keep beside System Settings while they switch it on)
- States: waiting ("GridLock can't move windows yet."); granted (window closes, notification "GridLock is ready. Press ⌃⌥G to show the grid."); still off after 2 minutes: the window stays, no nagging alerts
- Words: title "Welcome to GridLock"; body "To move and resize other apps' windows, GridLock needs access. Turn on GridLock in Privacy & Security › Device Control and Data Access."; buttons "Open Privacy Settings" (default), "Later"
- Access: Return opens Settings, Esc is Later; VoiceOver reads the body then the buttons
Status: todo

### S-002 Recognize the desk
As the user, I plug into a desk and GridLock knows which monitors are attached, using WindowKeeper's serial-number keys and settle rule.
Depends: S-001
Acceptance:
- [unit] Display keys: built-in → `builtin`; real alphanumeric serial → `sn:`; placeholder numeric serials (0, 1, 0x01010101, 0xFFFFFFFF) fall back to UUID; two identical serial-less monitors get `#2` by position.
- [unit] A desk switches only after two identical samples; partial sets passed through while docking create nothing.
- [unit] The desk signature does not change when monitors are rearranged.
- [self] `dump:desk` logs the signature, every monitor key and the profile chosen.
Status: todo

### S-003 Show the grid over the frontmost window
As the user, I press ⌃⌥G and a grid covers the display under the frontmost window, with that window's cells outlined and its size shown.
Screens: overlay-grid
Depends: S-002
Acceptance:
- [snap] Grid lines, the window's current cells in the accent color, and a label like "1280 × 800 · columns 1–4, rows 1–3".
- [unit] Frame → cells rounds to the nearest cell edges and never returns an empty range.
- [unit] Coordinates convert correctly between AppKit (bottom-left) and Accessibility (top-left) on a display that is above or left of the main display.
- [self] On a three-display desk, the grid appears on the display that holds most of the window.
- [manual] The overlay appears within 150 ms of the shortcut.
UX:
- Flow: ⌃⌥G, menu "Show Grid", or `gridlock://grid` → grid fades in on the display holding most of the frontmost window, its current cells selected → (S-004/S-005) → Return or mouse-up snaps; Esc or ⌃⌥G again closes
- Surface: panel (input people repeat while they watch the result): borderless, non-activating, one per display, ignores Mission Control
- States: no frontmost window (Finder desktop): a small label "No window to place" shows and fades after 1.5 s; full-screen window: "GridLock can't move full-screen windows"; no access: menu shows "Grant Access…" instead of opening the grid
- Words: label "Safari · 1280 × 800 · columns 1–4, rows 1–3"; long window titles truncate in the middle
- Access: whole flow keyboard-only; VoiceOver announces "Grid, 6 columns by 4 rows, selection columns 1 to 4, rows 1 to 3"; Reduce Motion: no fade
Status: done

### S-004 Draw a new spot on the grid
As the user, I drag across grid cells and the window moves there when I let go.
Screens: overlay-grid-selecting
Depends: S-003
Acceptance:
- [snap] While dragging, the chosen cells fill and a ghost outline shows the frame the window will get, with its size in pixels.
- [unit] Cells → frame honors the gap and outer margin and stays inside the visible frame (below the menu bar, clear of the Dock).
- [self] After release, the window's frame read back through Accessibility matches the target within 2 pt (apps with a minimum size: within their minimum).
- [manual] Esc or a click outside the grid cancels without moving anything.
UX:
- Flow: press on a cell → drag across cells → selection fills live, ghost frame and size follow → release snaps; Esc or click outside cancels; ⌃⌥Z undoes
- Surface: same grid panel (S-003)
- States: target smaller than the app's minimum size: ghost shows the size the app will accept; done: grid fades out as the window moves
- Words: size label "960 × 540"; no buttons
- Access: color plus a 2 pt outline, never color alone; selection readable in Increase Contrast
Status: done

### S-005 Move the selection with the keyboard
As the user, I use the arrow keys to move the selection, Shift-arrows to grow it, Option-Shift-arrows to shrink it, and Return to apply.
Screens: overlay-grid-selecting
Depends: S-004
Acceptance:
- [unit] The selection never leaves the grid and never shrinks below one cell.
- [self] Keys sent through the debug hook produce the expected cell range.
- [snap] A small key hint shows along the bottom edge of the grid.
UX:
- Flow: grid open → arrows move the selection → ⇧-arrows grow it, ⌥⇧-arrows shrink it → Return snaps, Esc cancels; Space toggles "move" so the window follows live (later, if cheap)
- Surface: same grid panel (S-003)
- States: at an edge, the key does nothing (no beep, no wrap)
- Words: hint bar "←↑↓→ Move   ⇧ Grow   ⌥⇧ Shrink   ↩ Snap   esc Cancel"
- Access: every mouse action has a key; VoiceOver re-announces the selection after each key
Status: done

### S-006 Change a monitor's grid size
As the user, I change the grid's columns and rows for one monitor at the current desk.
Screens: settings-desks, settings-desks-other
Depends: S-002
Acceptance:
- [snap] The Desks pane shows the current desk as a picture of its monitors; selecting one shows Columns (1–24), Rows (1–16), Gap and Margin.
- [unit] Settings saved for a monitor key at one desk do not change the same monitor at another desk.
- [self] The grid overlay uses the new size immediately.
UX:
- Flow: Settings › Desks (or menu "Settings…" with the grid's gear) → current desk selected → click a display in the desk picture → Columns, Rows, Gap, Margin steppers → change shows at once in the picture's grid lines
- Surface: Settings pane with an inspector beside the desk picture (details of the selection while people keep working)
- States: one display: picture shows just it; a display not connected (another desk): its settings edit fine, label "Not connected"; Columns at 24 / Rows at 16: stepper stops
- Words: section "Grid"; labels "Columns", "Rows", "Gap", "Margin"; desk picture caption "Desk: Office (Dell P4317Q + Built-in)"; help "Each display keeps its own grid at each desk."
- Access: displays in the picture are buttons ("Dell P4317Q, 6 by 4 grid"); steppers have labels and values
Status: done (Desks UI branch; [self] grid-follows check needs the merged app)

### S-007 Settings survive a restart
As the user, I quit and reopen GridLock, and every desk's grids and palettes are as I left them.
Depends: S-006
Acceptance:
- [unit] The library round-trips through JSON; unknown future fields don't fail decoding.
- [self] Local `desks.json` is mirrored to `iCloud Drive/GridLock/Macs/<hardware UUID>/` and only rewritten when the bytes change.
- [self] After deleting the local file, launch adopts the iCloud copy.
Status: todo

### S-008 Undo the last move
As the user, I press ⌃⌥Z (or pick "Undo Last Move" from the menu) and the last window GridLock moved goes back where it was.
Depends: S-004
Acceptance:
- [self] Undo restores the frame from before the most recent move, for up to 10 moves.
- [snap] The menu item names the window: "Undo Move of “Safari”". It is disabled when there is nothing to undo.
UX:
- Flow: ⌃⌥Z, menu "Undo Move of “Safari”", or `gridlock://undo` → window returns to its previous frame → the item names the next window back, or is disabled
- Surface: menu item (inline)
- States: nothing to undo: "Undo Move" disabled; window closed since: skipped silently, the next one is undone
- Words: "Undo Move of “<app>”"; tooltip none (menu)
- Access: the shortcut shows in the menu
Status: done

## M2 Drag palette

### S-010 Detect a title-bar drag
As the user, I drag any window by its title bar, and GridLock notices.
Depends: S-001
Acceptance:
- [self] A CGEvent drag of a test window's title bar logs "drag began" with the window's app; a drag that only selects text in a document does not.
- [manual] No noticeable lag while dragging windows in Safari, Finder and Xcode.
Status: done

### S-011 Open the palette at the top edge
As the user, I drag a window into the top edge of a display and a palette of layout thumbnails drops down under the cursor.
Screens: palette
Depends: S-010
Acceptance:
- [snap] The palette shows the current monitor's palette entries as thumbnails, each split into its zones, in a Liquid Glass panel.
- [self] It opens only after the cursor has stayed within 4 pt of the top edge for 150 ms, on the display under the cursor.
- [manual] Dragging away from the palette and the edge, or pressing Esc, closes it; the window stays where the drag left it.
UX:
- Flow: drag a window by its title bar → touch the top edge of any display → after 150 ms the palette drops down centered under the cursor → (S-012) → drag away or Esc to close without snapping
- Surface: panel (input people repeat while they watch the result): Liquid Glass, non-activating, never takes focus from the dragged app
- States: palette empty for this display: one thumbnail "Edit Palette…" that opens Settings › Palette; more layouts than fit: wraps to a second row, never scrolls mid-drag
- Words: layout captions under thumbnails ("Halves", "Columns × 3", "Grid 3 × 2", custom names); no title
- Access: Reduce Motion: fades instead of dropping; thumbnails readable in Increase Contrast
Status: done

### S-012 Drop on a zone
As the user, I drag over a zone in a thumbnail, see where the window will go, and let go to snap it there.
Screens: palette-hover
Depends: S-011
Acceptance:
- [snap] The zone under the cursor fills with the accent color and a translucent preview shows the target frame on the screen.
- [self] Releasing over a zone sets the window to that zone's frame (within 2 pt), with gap and margin applied.
- [self] The move can be undone with S-008.
UX:
- Flow: drag over a thumbnail → zone under the cursor fills, a translucent preview outlines the target on the display → release snaps the window → palette fades out; release outside a zone closes the palette with no change; ⌃⌥Z undoes
- Surface: same palette panel, plus a click-through preview panel on the display
- States: zone smaller than the app's minimum size: preview shows what the app will allow
- Words: none beyond captions; the preview shows "960 × 1080"
- Access: zone fill plus outline (not color alone)
Status: done

### S-013 Warn about macOS edge tiling
As the user, if macOS's own "Drag windows to screen edges to tile" is on, GridLock tells me it fights the palette and offers to open the setting.
Screens: settings-general
Depends: S-011
Acceptance:
- [self] The setting is read from `com.apple.WindowManager`; GridLock never writes it.
- [snap] A yellow note in General with "Open Desktop & Dock Settings".
Status: done

## M3 Desks — every desk remembers

### S-020 Choose what the palette shows
As the user, I pick which layout patterns appear in a monitor's palette, and in what order.
Screens: settings-palette, settings-palette-other
Depends: S-011, S-006
Acceptance:
- [snap] Two lists: Available patterns and In palette; drag between them and to reorder; a live palette preview underneath.
- [unit] Each monitor at each desk keeps its own palette.
UX:
- Flow: Settings › Palette → Desk and Display pickers (current desk first; others "(Not connected)") → drag a layout from Available into In Palette, or its + button → drag rows to reorder (or Move Up/Move Down in the row's context menu) → drag a row back to Available, or its − button, to take it out → preview redraws at once
- Surface: Settings pane (inline editing of the palette while the preview shows the result)
- States: empty palette: "This palette is empty" with "Add layouts from Available."; desk not connected: "Not connected. Changes apply when you're back at this desk."; long custom names truncate in the middle with the full name as a tooltip
- Words: lists "Available" and "In Palette"; section "Custom Layouts"; tooltips "Add Columns to the palette", "Remove Halves from the palette"; caption "Each display keeps its own palette at each desk."
- Access: + and − buttons and context menus do everything a drag does; rows read as "Columns × 3"; VoiceOver actions Move Up/Move Down on palette rows
Status: done (Desks UI branch)

### S-021 Set how many of each pattern
As the user, I set the count for a pattern family (Columns × 2…6, Rows × 2…4, Grid c × r) and can add the same family twice with different counts.
Screens: settings-palette
Depends: S-020
Acceptance:
- [snap] Each palette row has a stepper (or c × r pair) that redraws its thumbnail.
- [unit] Patterns produce the right zones: Columns × 3 → three equal columns; Grid 3 × 2 → six zones; two-thirds + one-third → two zones, both orders.
UX:
- Flow: In Palette row → stepper (Columns × 2…6, Rows × 2…4) or Grid's columns × rows pair (1…6 each, never 1 × 1) or Split's side menu (⅔ + ⅓, ⅓ + ⅔, ¾ + ¼, ¼ + ¾) → name and thumbnail follow at once; adding a family again picks the next count not yet in the palette
- Surface: inline in the row (changes one value on screen)
- States: at the end of a range the stepper stops
- Words: names follow the count ("Halves", "Columns × 3", "Quarters", "Grid 3 × 2", "Two-Thirds + Third"); tooltips "Number of columns", "Which side is wider"
- Access: steppers labeled "Columns"/"Rows" with their values
Status: done (Desks UI branch)

### S-022 A new desk starts from the closest known desk
As the user, I plug into a desk GridLock hasn't seen, and it starts with settings from the most similar desk.
Depends: S-007
Acceptance:
- [unit] Each monitor takes its settings from the same monitor key at another desk (most recently used first), else from a monitor of the same resolution, else from the defaults.
- [self] A notification says "New desk: Dell P4317Q + Built-in" with "Rename…" and "Settings…".
UX:
- Flow: displays settle on an unknown set → desk made, named as WindowKeeper names those displays or after them, settings from the closest desk → notification "New desk: <name>" → Rename… opens Settings › Desks with Rename Desk; Settings… or a click opens Settings › Desks at that desk
- Surface: notification (information that needs no action now; never an alert)
- States: the very first desk on a fresh install: no notification; notifications off: nothing, noted in the log
- Words: title "New desk: Dell P4317Q + Built-in"; body "Its grids and palettes start from your other desks."; actions "Rename…", "Settings…"
- Access: both actions are in the notification's menu
Status: done (Desks UI branch; [self] needs the merged, installed app: debug command `desk:notify`)

### S-023 Name, rename and forget desks
As the user, I see every desk I've used, rename it, and delete one I'll never use again.
Screens: settings-desks, desk-rename
Depends: S-022
Acceptance:
- [snap] A desk list (current desk marked), each with its monitors and "last used".
- [self] A new desk whose signature WindowKeeper already knows takes WindowKeeper's name (read-only, from its local `profiles.json`).
- [self] Deleting asks for confirmation; the current desk can't be deleted.
UX:
- Flow: Settings › Desks → desk list (current first, marked "Current"; others "Last used 3 days ago") → select a desk to show its picture → Rename… (button, double-click, context menu) opens Rename Desk → Return renames, Esc cancels; Delete… asks "Delete “Office”?" → Delete / Cancel
- Surface: list in the Settings pane; Rename Desk sheet (one short task); confirmation dialog for Delete (destroys settings, can't be undone)
- States: current desk: Delete… disabled, tooltip "You can't delete the desk you're at."; a name WindowKeeper uses for the same displays: context menu "Use WindowKeeper's Name, “Main office desk”"
- Words: "Rename…", "Delete…", "Rename Desk", "Delete “Office”?", "GridLock forgets this desk's grids and palettes. If you connect these displays again, they start as a new desk."
- Access: the list takes arrow keys; Return in the sheet renames, Esc cancels
Status: done (Desks UI branch; WindowKeeper name checked in snapshot mode with a scratch copy of its signatures (`GRIDLOCK_DATA_DIR/WindowKeeper/profiles.json`); delete confirmation not snapshotted)

### S-024 Copy settings from another desk or monitor
As the user, I copy one monitor's grid and palette to another monitor or desk.
Screens: settings-desks
Depends: S-023
Acceptance:
- [snap] Right-click a monitor: "Copy Settings", "Paste Settings", "Reset to Defaults".
- [unit] Paste replaces grid, gap, margin and palette, nothing else.
UX:
- Flow: right-click a display in the desk picture (or the inspector's ⋯ menu) → Copy Settings → choose any display at any desk → Paste Settings; Reset to Defaults puts back what suits the display's shape
- Surface: context menu plus the inspector's menu button (same items, for keyboard and discoverability)
- States: nothing copied yet: Paste Settings disabled
- Words: "Copy Settings", "Paste Settings", "Reset to Defaults"; tooltip "Copy this display's grid and palette, paste another display's, or reset to defaults"
- Access: the ⋯ menu button is labeled "Display Settings"
Status: done (Desks UI branch; menus can't be captured in snapshot mode)

### S-025 Make a custom layout
As the user, I draw my own layout of named zones and add it to any palette.
Screens: settings-layouts, layout-editor
Depends: S-021
Acceptance:
- [snap] The editor shows a canvas with a snapping grid; drag to add a zone, drag edges to resize, Delete to remove.
- [unit] Zones are stored as fractions (0…1), so one layout fits every monitor shape.
- [unit] Overlapping zones are allowed; a zone smaller than 5% of either side is refused.
UX:
- Flow: Settings › Layouts → New Layout… (or Edit…, double-click) → layout editor sheet: name, canvas → drag to draw a zone (also over an unselected zone, so zones can overlap) → drag the selected zone to move it, its edge knobs to resize, arrows nudge, Shift-arrows resize, Delete removes, Option draws without snapping → Save / Add Layout (Return), Cancel (Esc) → add it to a palette in Settings › Palette
- Surface: list in the Settings pane; editor in a sheet (one task that finishes or cancels); confirmation dialog for Delete…
- States: no custom layouts: "No Custom Layouts" with "New Layout…"; a zone under 5%: "Zones must be at least 5% of the display's width and height." under the canvas; no name or no zones: Save disabled with a tooltip; deleting a layout in use: "It's also taken out of 2 palettes."
- Words: "New Layout…", "Edit…", "Duplicate", "Delete…", "New Layout", "Edit Layout", "Add Zone", "Delete Zone", "Add Layout", "Save"
- Access: Add Zone and the arrow keys make and shape zones without a mouse; zones read "Zone 2, left 25%, top 0%, 50% wide, 100% tall"
Status: done (Desks UI branch; drawing and dragging on the canvas are [manual])

## M4 Speed

### S-030 A shortcut for any zone
As the user, I give a palette zone a global shortcut, and pressing it snaps the frontmost window there.
Screens: settings-shortcuts
Depends: S-021
Acceptance:
- [snap] Shortcuts pane: every built-in layout zone with a recorder; defaults ⌃⌥←/→ halves, ⌃⌥↑ maximize, ⌃⌥C center, ⌃⌥G grid, ⌃⌥Z undo.
- [unit] A shortcut taken by another GridLock action is refused with the clashing action's name.
- [self] Shortcuts are reported to ShortcutsLens (`reportedShortcuts`).
Status: done

### S-031 Cycle sizes with a repeated shortcut
As the user, I press ⌃⌥← again and the window cycles through left half, left two-thirds, left third.
Depends: S-030
Acceptance:
- [unit] The cycle follows the order set in Settings and resets after 2 seconds or another window.
Status: done

### S-032 Send a window to the next display
As the user, I press ⌃⌥⌘→ and the window moves to the next display, keeping its cells on that display's grid.
Depends: S-030
Acceptance:
- [unit] Cells map proportionally when the grids differ (4 of 6 columns → 8 of 12).
- [self] Order follows the displays left to right, wrapping.
Status: done

## M5 System

### S-040 Menu bar menu
As the user, I click the menu bar icon and see Show Grid, Undo Last Move, the current desk's name, Settings…, Help, Check for Updates and Quit.
Screens: menu
Depends: S-003
Acceptance:
- [snap] Main items have icons (MenuIcon.showIcon, visible on macOS 27).
- [self] `dump:menu` lists every item with its shortcut.
Status: done (snap: `menu`; dump:menu and real-menu icon alignment need the installed app)

### S-041 Show in Dock / Show in menu bar
As the user, I choose any combination of a Dock icon and a menu bar icon, including neither.
Screens: settings-general
Acceptance:
- [snap] Two checkboxes; with neither, a note says how to get back (open GridLock again).
- [self] Reopening the app with no icons opens Settings; the Dock icon's right-click menu has "Settings…".
Status: done (snap: note with both off; reopen and Dock menu need the installed app)

### S-042 Appearance switch
As the user, I choose System, Light or Dark in Settings › General; overlays follow the system.
Screens: settings-general
Acceptance:
- [snap] Settings windows in both looks.
Status: done (snap: every page in both looks)

### S-043 Settings scroll and drag bigger
As the user, I drag the Settings window larger and it remembers that size.
Screens: settings-desks
Acceptance:
- [self] Size saved per Mac in `settings.contentSize`; panes open at natural height capped to the screen and scroll.
Status: done (snap: a stored `settings.contentSize` sizes every pane; saving after a drag needs the installed app)

### S-044 Updates
As the user, GridLock checks GitHub for updates, with Automatic / Ask / Don't check and an interval.
Screens: settings-updates
Acceptance:
- [self] Shared AutoUpdater/UpdatePolicy/UpdateInterval copies; release notes shown in the update prompt; automatic installs wait while an overlay is open.
Status: done (snap: `settings-general` Updates section, `update-prompt`; installs need a published release)

### S-045 Settings sync
As the user, I turn on iCloud settings sync and my shortcuts, defaults and custom layouts follow me to my other Mac.
Screens: settings-updates
Acceptance:
- [self] Shared SettingsSync with a whitelist; desks stay per Mac.
Status: done (whitelist in SettingsSync.keys; desks stay per Mac; custom layouts live in the desk library and don't sync yet)

### S-046 ToolHUD actions and menu hub
As the user, I trigger GridLock from ToolHUD: `gridlock://grid`, `gridlock://snap?zone=left-half`, `gridlock://undo`, and GridLock's menu shows in ToolHUD's hub.
Depends: S-030
Acceptance:
- [self] Each URL performs its action on the frontmost (non-GridLock) window.
- [self] MenuHub publishes the menu with `imageInTitle` icons.
Status: done (unit: URLAction; ToolHUD and MenuHub need the installed app)

### S-047 Launch at login
As the user, I turn on "Open at login" in General.
Screens: settings-general
Acceptance:
- [self] SMAppService registers the copy in /Applications only (never a build copy).
Status: done (registers only from /Applications)

## M6 Polish

### S-050 App icon
As the user, I see a GridLock icon in Finder and the Dock that matches the suite (symbol "Gl", corner 27).
Acceptance:
- [snap] Icon in light and dark; nameless small variant at 16/32 pt.
Status: done (snap: `icon`)

### S-051 Help
As the user, I press ⌘? or a ? button and read how the palette, grid, desks and shortcuts work.
Screens: help
Acceptance:
- [snap] Help window covers every pane; ? buttons in Settings panes open the right section.
Status: done (snap: `help-<topic>`, `checks.txt` for the ? buttons and ⌘?)

### S-052 README, release and website
As the user, I download GridLock from GitHub as a notarized DMG.
Acceptance:
- [manual] README in the house layout with screenshots; release.sh publishes both asset names; site card and page added.
- [manual] No reference app names anywhere in the repo (grep before every commit).
Status: todo

## M7 Arrangements (milestone 2)

### S-060 Save the current windows as an arrangement
As the user, I save the positions of the windows on screen as a named arrangement for this desk.
Depends: S-023
Acceptance:
- [unit] Each window is stored as an app + zone on a monitor key, not as pixels.
Status: todo

### S-061 Apply an arrangement
As the user, I pick an arrangement from the menu, a shortcut or ToolHUD, and its apps' windows move into their zones.
Depends: S-060
Acceptance:
- [self] Apps that aren't running are skipped, never launched.
Status: todo

### S-062 Per-app rule
As the user, I say "always put new Mail windows in the right third at this desk".
Depends: S-022
Acceptance:
- [self] A new window of that app is placed within 1 second of appearing; a window I've moved myself is left alone.
Status: todo

## Dropped
- Accounts, sharing, teams, analytics, onboarding tours: one user.
- Moving windows between Spaces: blocked on macOS 27.
- Changing macOS's own tiling setting for the user: GridLock only explains and links to it.
