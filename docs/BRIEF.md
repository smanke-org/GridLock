# GridLock

A menu bar window manager for one person who moves between several desks: drag a window to the top of the screen and drop it on a layout, or call up a grid over the screen and draw where the window should go. Every desk remembers its own grids and palette.

## Replaces
Two paid window managers used side by side: one with a drag-to-top layout palette, one with a grid overlay. Both are referred to only as "the reference apps" in this repo.

## Main jobs
1. **Snap by dragging.** Drag any window's title bar to the top edge of a display. A small palette of layout thumbnails drops down; each thumbnail is split into its zones, and releasing over a zone puts the window there.
2. **Place with the grid.** Press a shortcut (or pick it from the menu). A grid covers the display under the frontmost window, with that window's current cells outlined and its size shown in pixels and cells. Drag across cells, or use the arrow keys (Shift to resize), and press Return to apply.
3. **Fit each desk.** GridLock recognizes the connected monitors and switches to that desk's profile automatically, with each monitor's grid size, gaps and palette as they were last set there.

## Data
- **DeskProfile**: id, name, signature (sorted monitor keys), monitors, lastUsed. One per set of connected monitors, per Mac.
- **MonitorSettings** (inside a desk, per monitor key): grid columns × rows, gap, outer margin, palette.
- **PaletteEntry**: layout pattern + its count (for example "Columns × 3", "Rows × 2", "Grid 3 × 2"), order, shown/hidden.
- **LayoutPattern**: built-ins (halves, thirds, quarters, two-thirds + one-third, sixths, centered, maximize) and user-made custom layouts (named zones on a 0…1 grid).
- **Shortcut**: key combination → layout zone, grid overlay, undo, or "next display".

## Shape
Menu bar app (with optional Dock icon), transparent overlay panels for the palette and grid, and a resizable Settings window with a Desks pane that edits each monitor's grid and palette on a live picture of the desk. macOS 26 or later. Local data, mirrored to this Mac's own iCloud Drive folder. Works offline. No accounts.

## System hooks
Accessibility (move and resize other apps' windows), a global mouse monitor (detect title-bar drags), global hotkeys, `gridlock://` URL actions and the menu hub for ToolHUD, shortcut reports to ShortcutsLens, launch at login, self-updater.

## Reference
Two paid window managers, studied as running apps and on their websites for visual inspiration only. No code, binaries, resources, names or wording are copied. *(Decided with the user, 2026-11-02.)*

## Look
Native Mac (Liquid Glass panels, system accent). Overlays are translucent with a clear accent outline for the chosen cells. Includes the System/Light/Dark switch. *(Decided by the agent.)*

## Decisions
- **A separate app, not part of WindowKeeper.** WindowKeeper quietly restores windows in the background; GridLock is a hands-on tool with a global mouse monitor and overlays. Kept apart, a bug in one can't break the other, and each is released on its own. GridLock reuses WindowKeeper's desk-recognition code (monitor serial keys, settle-before-switching, per-Mac iCloud folder) and suggests WindowKeeper's name for a desk it already knows. *(Decided by the agent.)*
- **Per desk, then per monitor.** Grid size and palette belong to a monitor *at a desk*, so the same Dell can have a 6 × 4 grid at home and 8 × 4 in the office. A new desk starts from the settings of the most similar desk already known (same monitors first), else from the defaults. *(Decided by the agent.)*
- **"How many of each"** means the count for each pattern family (Columns × 2…6, Rows × 2…4, Grid c × r); a family can appear more than once with different counts. *(Agent's reading of the request.)*
- When macOS's own edge tiling is on, GridLock says so and opens the right Settings page; it never changes the setting itself.
- Free, public repo `smanke-org/GridLock`, notarized Developer ID DMG. Bundle id `com.smanke.GridLock`.

## Not in version one (planned for milestone 2)
- Arranging several apps at once ("Safari left, Mail right"), saved per desk.
- Per-app rules (always open X in the left half).

## Never
- Moving windows between Spaces (blocked on macOS 27, as WindowKeeper found).
