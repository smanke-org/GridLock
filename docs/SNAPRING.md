# SnapRing

Snap a window with one gesture: hold ⌥⌘, right-click anywhere and keep the button down, flick toward a
side or corner, let go. A small ring appears under the pointer while the button is down and
shows which part of the display the window will take.

Story: S-033 (docs/STORIES.md). Help topic: "SnapRing". Settings: Shortcuts › SnapRing.

## Gesture

1. Hold the SnapRing keys (⌥⌘ by default) and press the SnapRing button (right by default). GridLock swallows
   the click: the app under the pointer never sees it.
2. The ring appears centered on the press point, on the display under the pointer.
3. While the button is down, the direction from the press point to the pointer picks one of
   8 wedges; the distance picks the tier. An outline on the display shows where the window
   will go.
4. Let go to snap. Esc while the button is down cancels: the ring closes, nothing moves.

The modifier keys only have to be down at the press; they may be let go during the flick.

## Wedges and tiers

Directions are 45° sectors centered on right, bottom-right, bottom, … (screen orientation).

| Distance from press | Pick |
| --- | --- |
| under 20 pt (center) | The center action: Maximize (default) or Cancel |
| 20–90 pt (inner tier) | Half or quarter: left/right/top/bottom half, the four quarters |
| over 90 pt (outer tier) | Third: left/right/top/bottom third; corners take a third of the width and half the height |

All zones are laid out with the display's gap and margin at the current desk, like the
palette and zone shortcuts.

## Which window, which display

- **Moves** (setting): *The frontmost window* (default) or *The window under the pointer*.
- The window always goes to the display the ring opened on, so SnapRing also moves windows
  between displays.
- No window to move (desktop with no frontmost window, a full-screen window, no Access):
  "No window to place" toast, and the click is still swallowed.
- Every move goes through `WindowMover`, so Undo Move and the palette's undo target work.

## Look

A Liquid Glass disc about 120 pt across with the ring drawn on top in the accent color.
**Ring style** (setting), shown in the Settings picker:

| Style | Look |
| --- | --- |
| Glass donut (default) | 8 equal segments; the active one fills with the accent color |
| Split petals | 8 separated petals; the active one fills and pops outward |
| Pointer tail | A thick track with an accent arc on the active wedge and a dashed line to the pointer |

In the outer tier, Glass donut and Split petals add a thin accent arc outside the active
wedge; Pointer tail's line simply runs farther. The center shows a filled dot when the center
action is chosen (Maximize or Cancel). The ring appears at once and fades out in 0.15 s
(no fades with Reduce Motion).

## Settings (Settings › Shortcuts › SnapRing), all synced

| Key | Setting | Values | Default |
| --- | --- | --- | --- |
| `snapRingButton` | And | Right-click, Click | Right-click |
| `snapRingModifiers` | Hold | any of ⌃⌥⇧⌘; none turns SnapRing off | ⌥⌘ |
| `snapRingCenter` | Let go in the center | Maximize, Cancel | Maximize |
| `snapRingTarget` | Moves | The frontmost window, The window under the pointer | The frontmost window |
| `snapRingStyle` | Ring style | Glass donut, Split petals, Pointer tail | Glass donut |

The keys must match exactly (⌥⌘ does not fire on ⇧⌥⌘), so other modifier-clicks still reach
their apps. A caption warns that the chosen click no longer reaches other apps. Right-click is
the default because few apps use ⌥⌘-right-click (⌥⌘-drag in Finder makes an alias).

## Implementation

- `GridLockKit/SnapRing.swift`: `SnapRingPick` (pure): offset → center / wedge + tier, and
  wedge + tier → `UnitRect`. Swift Testing tests.
- `SnapRing.swift` (app): an active `CGEventTap` on left and right mouse down/dragged/up (only the chosen button acts) at the session
  level. Created when Access is granted and the keys aren't empty; re-enabled if macOS turns
  it off for a timeout. Swallows the press, its drags and its release.
- `SnapRingView`: draws the three styles; an `OverlayPanel` (click-through) holds it over a
  glass disc; a second click-through panel shows the outline.
- `DragWatcher` ignores drags while SnapRing is active.
- Help topic, Settings section, glossary entry, snapshot page `snapring-<style>`.

## Not in v1

- Click-to-open, move, click-again mode.
- Wedges taken from the palette's layouts.
- Flicking off a display edge to another display.
