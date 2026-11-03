import AppKit
import ApplicationServices
import Carbon.HIToolbox
import GridLockKit

/// Notices when another app's window is dragged by its title bar, shows the palette's tab at
/// the top center of the display under the pointer, opens the palette when the pointer
/// reaches the tab or rests at the top edge of a display (or at once while the drag keys are
/// held), and snaps the window when it's let go over a zone.
///
/// Kept cheap: a global mouse monitor does nothing on a click; on the first drag event it
/// asks Accessibility once which window is under the press, then reads that window's frame a
/// few times (at most every 50 ms) until it moves — a drag — or the checks run out — text
/// being selected, a slider, a resize. After that, mouse moves only compare numbers.
@MainActor
final class DragWatcher {
    static let shared = DragWatcher()

    /// Frame reads before deciding a drag isn't moving its window.
    private static let maxChecks = 12
    private static let checkInterval: TimeInterval = 0.05

    private var monitors: [Any] = []
    private var downAt: CGPoint?
    private var candidate: (window: TargetWindow, start: CGRect)?
    private var checks = 0
    private var lastCheck: TimeInterval = 0
    private var gaveUp = false
    /// The window being dragged, once its position has been seen to change.
    private var dragging: TargetWindow?
    private var dwell = EdgeDwell()
    private var dwellTimer: Timer?
    /// Esc closed the palette: it stays closed for the rest of this drag.
    private var dismissed = false
    /// Looks at the Esc key while the palette is open: a global key monitor didn't always
    /// hear it mid-drag.
    private var escapeTimer: Timer?

    func start() {
        guard monitors.isEmpty else { return }
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { event in
            let type = event.type
            MainActor.assumeIsolated { DragWatcher.shared.handle(type) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            let code = Int(event.keyCode)
            MainActor.assumeIsolated { if code == kVK_Escape { DragWatcher.shared.escape() } }
        }) { monitors.append(m) }
        // Pressing or letting go of the drag keys while the mouse is still sends no drag event.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { _ in
            MainActor.assumeIsolated {
                let watcher = DragWatcher.shared
                if watcher.dragging != nil { watcher.follow(DragWatcher.cursor) }
            }
        }) { monitors.append(m) }
    }

    /// The cursor in global top-left coordinates.
    private static var cursor: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: DisplayCatalog.mainHeight - p.y)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            reset()
            downAt = Self.cursor
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            released()
        default:
            break
        }
    }

    private func dragged() {
        guard let downAt, AXWindows.isTrusted, !GridOverlay.shared.isShowing, !PaletteOverlay.shared.isOpenedByShortcut else { return }
        if dragging == nil {
            guard !gaveUp else { return }
            if candidate == nil {
                guard let window = Self.window(at: downAt) else {
                    gaveUp = true
                    if Diagnostics.isEnabled { Diagnostics.note("drag: no window under \(downAt)") }
                    return
                }
                candidate = (window, window.frame)
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCheck >= Self.checkInterval, let candidate else { return }
            lastCheck = now
            checks += 1
            if let frame = AXWindows.frame(of: candidate.window.element), DragCheck.isMove(from: candidate.start, to: frame) {
                dragging = candidate.window
                Diagnostics.note("drag began: \(candidate.window.appName)")
            } else if checks >= Self.maxChecks {
                gaveUp = true
                if Diagnostics.isEnabled { Diagnostics.note("drag: \(candidate.window.appName) didn't move; not a window drag") }
            }
            return
        }
        follow(Self.cursor)
    }

    /// The cursor moved (or rested) during a window drag.
    private func follow(_ cursor: CGPoint) {
        let palette = PaletteOverlay.shared
        let tab = PaletteTabOverlay.shared
        let held = Self.dragKeysHeld
        if palette.isShowing {
            tab.close()
            // Opened by the drag keys: letting go of them away from the palette closes it.
            if case .modifier = palette.trigger, !held, !palette.isNear(cursor) {
                palette.close()
                dwell.reset()
            } else if !palette.track(cursor) {
                palette.close()
                dwell.reset()
            }
            return
        }
        guard !dismissed, let display = Self.display(under: cursor) else { return tab.close() }
        if held {
            dwellTimer?.invalidate()
            dwellTimer = nil
            tab.close()
            palette.open(on: display, near: cursor)
            _ = palette.track(cursor)
            watchEscape()
            return
        }
        // The tab, on the display the pointer is over; reaching it opens the palette there.
        if AppSettings.shared.showsPaletteTab {
            tab.show(on: display)
            if PaletteTab.reaches(cursor, tab: tab.frame) {
                dwellTimer?.invalidate()
                dwellTimer = nil
                tab.close()
                palette.open(on: display, cursorX: tab.frame.midX)
                _ = palette.track(cursor)
                watchEscape()
                return
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if dwell.update(cursor: cursor, bounds: display.bounds, now: now) {
            dwellTimer?.invalidate()
            tab.close()
            palette.open(on: display, cursorX: cursor.x)
            _ = palette.track(cursor)
            watchEscape()
        } else if EdgeDwell.isAtEdge(cursor, bounds: display.bounds), dwellTimer == nil {
            // A cursor resting at the edge sends no events: look again when the wait is up.
            let timer = Timer(timeInterval: EdgeDwell.delay + 0.01, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let watcher = DragWatcher.shared
                    watcher.dwellTimer = nil
                    if watcher.dragging != nil { watcher.follow(DragWatcher.cursor) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            dwellTimer = timer
        }
    }

    private func released() {
        defer { reset() }
        PaletteTabOverlay.shared.close()
        let palette = PaletteOverlay.shared
        guard let window = dragging, palette.isShowing else { return }
        if let choice = palette.choice {
            palette.close()
            // Let the app finish its own drag first, or it may put the window back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                MainActor.assumeIsolated {
                    Actions.shared.snap(window, to: choice.zone, on: choice.display)
                    Diagnostics.note("palette: snapped \(window.appName) on \(choice.display.name)")
                }
            }
        } else if palette.isOnEditTile {
            palette.close()
            SettingsWindow.shared.show(tab: "Palette")
        } else {
            palette.close()
            Diagnostics.note("palette: closed without a zone")
        }
    }

    private func watchEscape() {
        escapeTimer?.invalidate()
        let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated {
                let watcher = DragWatcher.shared
                guard PaletteOverlay.shared.isShowing else {
                    watcher.escapeTimer?.invalidate()
                    watcher.escapeTimer = nil
                    return
                }
                if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape)) { watcher.escape() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        escapeTimer = timer
    }

    private func escape() {
        guard PaletteOverlay.shared.isShowing || PaletteTabOverlay.shared.isShowing, dragging != nil else { return }
        PaletteOverlay.shared.close()
        PaletteTabOverlay.shared.close()
        dismissed = true
        Diagnostics.note("palette: closed with Esc")
    }

    private func reset() {
        downAt = nil
        candidate = nil
        checks = 0
        lastCheck = 0
        gaveUp = false
        dragging = nil
        dwell.reset()
        dwellTimer?.invalidate()
        dwellTimer = nil
        dismissed = false
        escapeTimer?.invalidate()
        escapeTimer = nil
        PaletteTabOverlay.shared.close()
    }

    /// Whether the keys chosen in Settings › Shortcuts (⌘ by default) are down. More keys
    /// held as well still count.
    private static var dragKeysHeld: Bool {
        let wanted = AppSettings.shared.paletteModifiers
        guard !wanted.isEmpty else { return false }
        let now = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        return now.isSuperset(of: wanted)
    }

    private static func display(under point: CGPoint) -> LiveDisplay? {
        Actions.shared.desks.live.first { $0.bounds.contains(point) }
    }

    /// The window of another app under a point. The window server says which window is on
    /// top there (Accessibility's own hit test answered "menu bar" for some apps); its
    /// app's Accessibility windows are then matched to it by frame.
    private static func window(at point: CGPoint) -> TargetWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        for info in list {
            // Ordinary windows only: overlays, panels and the menu bar sit on higher layers.
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b), bounds.contains(point)
            else { continue }
            guard pid != own, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            // The same frame, else the frontmost of its windows under the point (the two
            // lists can disagree for a moment right after a window moves).
            let windows = AXWindows.windows(of: pid)
            let window = windows.first { WindowMover.close($0.frame, bounds) } ?? windows.first { $0.frame.contains(point) }
            if Diagnostics.isEnabled, window == nil {
                Diagnostics.note("drag: no window of \(app.localizedName ?? "?") at \(bounds); it has \(windows.map(\.frame))")
            }
            guard let window, window.isPlaceable else { return nil }
            return TargetWindow(element: window.element, pid: pid, appName: app.localizedName ?? "App", frame: window.frame)
        }
        return nil
    }
}
