# GridLock — notes for agents

Menu bar window manager. Read `docs/BRIEF.md`, `docs/STORIES.md` (the backlog, with UX blocks) and `docs/GLOSSARY.md` (one name per idea, use it in all UI text) before changing anything.

## Rules
- **Never name the reference apps** (the two paid window managers the brief mentions) anywhere: code, comments, commits, README, UI, tests. Call them "the reference apps". Grep for them before every commit. Copy no code, resources or wording from them; behavior ideas only.
- US spelling in user-facing text. "Settings", never "Preferences".
- Coordinates: GridLockKit and Accessibility use global **top-left** coordinates (`LiveDisplay.bounds/visible`). AppKit windows are bottom-left: convert with `ScreenSpace.flip(_, mainHeight: DisplayCatalog.mainHeight)`.
- Pure logic goes in `GridLockKit` with Swift Testing tests; AppKit/AX stays in the app target.
- Every window move goes through `Actions` / `WindowMover` so Undo Move works.
- Match the surrounding code: comment density, naming, the house helpers (`AppPresence`, `AppAppearance`, `MenuIcon.showIcon`, `Caption`).

## Build and test
- Unit tests: `swift test`
- Settings snapshots without touching the real app or real data:
  `GRIDLOCK_DATA_DIR=<scratch>/data GRIDLOCK_SNAPSHOT=<scratch>/snaps "$(swift build --show-bin-path)/GridLock"` (debug build; add `GRIDLOCK_SNAPSHOT_PAGES=settings-desks,…`). New surfaces add pages in `Snapshot.swift`.
- Signed app: `./build_app.sh` (Developer ID; keeps the Accessibility grant across rebuilds).
- **Only the session that owns window-moving features installs to /Applications** (see docs/PLAN.md). Install in place: `pkill -x GridLock; rsync -a --delete .build/app/GridLock.app/ /Applications/GridLock.app/; open --env GRIDLOCK_DEBUG=1 /Applications/GridLock.app`.
- Shell AX on macOS 27 sees no windows, so test window moves through the installed app's debug hook: post distributed notification `com.smanke.GridLock.debug` with object `dump:desk`, `dump:menu`, `dump:front`, `show:<Tab>`, `grid:show`, `snap:<zone>`, `undo:last`; results in `~/Library/Logs/GridLock.log`. CGEvent drags from the shell do work. Use a throwaway test app's windows, never the user's.
- Never capture the live screen; capture only your own test windows (`screencapture -x -o -l <CGWindowID>`).
- Never run a second GridLock from a build folder alongside the installed one (two sets of hotkeys and menu bar icons); snapshot mode is safe because it starts nothing and quits.
