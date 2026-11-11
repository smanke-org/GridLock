import AppKit
import ApplicationServices
import GridLockKit

/// Another app's window that GridLock is about to place.
struct TargetWindow {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let frame: CGRect
}

/// Finds the window to act on and moves it, remembering where it was for Undo Move.
@MainActor
final class WindowMover {
    static let shared = WindowMover()

    private struct Move {
        let element: AXUIElement
        let pid: pid_t
        let appName: String
        let from: CGRect
    }

    private var history = MoveHistory<Move>()

    /// The front window of the frontmost app other than GridLock: its focused window, else
    /// its first ordinary one. Nil for the desktop, a full-screen window, or without access.
    func frontmostWindow() -> TargetWindow? {
        guard AXWindows.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let appElement = AXWindows.appElement(for: app.processIdentifier)
        var focused: CFTypeRef?
        var window: AXWindow?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            window = AXWindows.window(focused as! AXUIElement)
        }
        if window?.isPlaceable != true {
            window = AXWindows.windows(of: app.processIdentifier).first { $0.isPlaceable }
        }
        guard let window, window.isPlaceable else { return nil }
        return TargetWindow(element: window.element, pid: app.processIdentifier,
                            appName: app.localizedName ?? "App", frame: window.frame)
    }

    /// Moves and resizes a window, keeping its old frame for Undo Move. Returns the frame
    /// the app actually took, which differs when the app has a minimum or fixed size.
    @discardableResult
    func move(_ window: TargetWindow, to frame: CGRect) -> CGRect? {
        history.push(Move(element: window.element, pid: window.pid, appName: window.appName, from: window.frame))
        return place(window.element, pid: window.pid, frame: frame, label: window.appName)
    }

    /// "Undo Move of “Safari”", or nil when there's nothing left to undo.
    var undoTitle: String? {
        history.last(where: isOpen).map { "Undo Move of “\($0.appName)”" }
    }

    /// Puts the most recently moved window that is still open back where it was.
    @discardableResult
    func undo() -> Bool {
        guard let move = history.popLast(where: isOpen) else { return false }
        place(move.element, pid: move.pid, frame: move.from, label: "undo \(move.appName)")
        return true
    }

    /// GridLock's newest move of this window, if it's still open: the app's name and where
    /// the window was before. The palette shows its undo target only when there is one.
    func lastMove(of element: AXUIElement) -> (appName: String, from: CGRect)? {
        history.last { CFEqual($0.element, element) && isOpen($0) }.map { ($0.appName, $0.from) }
    }

    /// Puts this window back where it was before GridLock's newest move of it, even when
    /// other windows moved since (a window dropped on the palette's undo target).
    @discardableResult
    func undo(_ element: AXUIElement) -> Bool {
        guard let move = history.removeLast(where: { CFEqual($0.element, element) }), isOpen(move) else { return false }
        place(move.element, pid: move.pid, frame: move.from, label: "undo \(move.appName)")
        return true
    }

    private func isOpen(_ move: Move) -> Bool {
        AXWindows.frame(of: move.element) != nil
    }

    @discardableResult
    private func place(_ element: AXUIElement, pid: pid_t, frame: CGRect, label: String) -> CGRect? {
        // Apps that turn on enhanced accessibility for VoiceOver animate every frame change,
        // and the animation ends wherever it was when the next attribute arrived. Off for the
        // move, back on after.
        let app = AXWindows.appElement(for: pid)
        let enhanced = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhanced, &value) == .success && (value as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) } }

        AXWindows.setFrame(element, frame)
        let actual = AXWindows.frame(of: element)
        if let actual, !Self.close(actual, frame) {
            Diagnostics.note("move \(label): asked \(frame), got \(actual)")
        }
        return actual
    }

    nonisolated static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
