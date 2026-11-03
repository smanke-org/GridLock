---
name: gridlock
description: Drive GridLock, the window manager on this Mac, from the shell with the `gridlock` command: see the displays, desks, grids and palette layouts, list windows, snap a window to a zone, a layout or grid cells, send it to another display, undo a move, and change grids and settings. Use when the user asks to arrange, snap, tile or move windows, asks about their grids, layouts or desks, or names GridLock.
---

# GridLock

`gridlock` runs commands in the GridLock app. Changes show at once, and Undo Move works on them.
If the app is closed, the command opens it in the background. If `gridlock` isn't on PATH, use
`/Applications/GridLock.app/Contents/MacOS/GridLock` the same way.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and
  `error.message`, and do what the message says.
- `no_access`: GridLock lacks Accessibility access. Only the person can grant it, in System
  Settings › Privacy & Security › Accessibility. Tell them; never try to get around it.
- Snapping moves the person's real windows. Only snap when they asked. Name the window with
  `--app <name>`: without it, the frontmost window is moved, which is Terminal's (or your own
  app's) when you run from a shell. `gridlock windows undo` puts the last move back.
- Displays are numbered from 1, left to right (`gridlock displays list`); zones and grid cells
  are counted from 1 too.
- `grid reset` only reports what it would change. Show the user that report and ask before you
  run it again with `--yes`: it replaces that display's palette as well as its grid.
- To try something without real data, run a Debug build with `APP_STORE=/tmp/gridlock-test` in
  front. A test copy still moves real windows, so don't snap from one.

## Main commands

| Command | Does |
| --- | --- |
| `gridlock status --json` | Version, Accessibility access, current desk, counts, what Undo Move would do |
| `gridlock displays list --json` | Displays with their grids at this desk |
| `gridlock windows list [--app A] --json` | Windows GridLock can place, with their frames and grid cells |
| `gridlock windows snap --zone left-half --app A --json` | Snap to a named zone; or `--cells 1,1,3,2`, or `--display next` |
| `gridlock layouts list [--display N] --json` / `gridlock layouts show <layout> --json` | Palette layouts and their zones |
| `gridlock layouts apply <layout> --zone N --app A --json` | Snap into one zone of a layout |
| `gridlock grid set --display N [--columns C] [--rows R] [--gap G] [--margin M] --json` | Change a display's grid |

Everything else (desks, settings, open a Settings pane or Help): `gridlock help`, and
`gridlock help <command>` for its options.
