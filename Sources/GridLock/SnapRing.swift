import AppKit
import Carbon.HIToolbox
import GridLockKit

/// SnapRing (docs/SNAPRING.md): hold the SnapRing keys (⌥⌘), press the right mouse button, flick
/// toward a side or corner and let go to snap a window there.
///
/// An active event tap sees every click; a press with exactly the SnapRing keys is
/// swallowed together with its drags and release, so the app under the pointer never sees
/// it. Any other click passes straight through after one flag comparison.
@MainActor
final class SnapRing {
    static let shared = SnapRing()

    /// Room around the press point for the ring and Pointer tail's line.
    private static let panelRadius: CGFloat = 120
    /// The glass disc behind the ring.
    static let discRadius: CGFloat = 66

    /// True from a SnapRing press to its release.
    private(set) var isActive = false

    private var tap: CFMachPort?
    private var retry: Timer?
    private var escapeTimer: Timer?
    private var origin: CGPoint = .zero
    private var window: TargetWindow?
    private var display: LiveDisplay?
    private var pick = SnapRingPick.center
    private lazy var ringPanel = OverlayPanel(takesKeys: false, clickThrough: true)
    private lazy var previewPanel = OverlayPanel(takesKeys: false, clickThrough: true)
    private let ringView = SnapRingView()

    /// Installs the event tap, or keeps trying every few seconds until GridLock has Access
    /// (macOS only allows an active tap then).
    func start() {
        guard tap == nil else { return }
        if installTap() { retry?.invalidate(); retry = nil; return }
        guard retry == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { SnapRing.shared.start() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retry = timer
    }

    private func installTap() -> Bool {
        guard AXWindows.isTrusted else { return false }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: snapRingTapCallback, userInfo: nil)
        else {
            Diagnostics.note("snapring: no event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Diagnostics.note("snapring: listening")
        return true
    }

    /// Whether to swallow the event.
    fileprivate func handle(_ type: CGEventType, flags: CGEventFlags, at location: CGPoint) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            guard !isActive, Self.isChosenButton(type), Self.keysMatch(flags), !Actions.shared.isOverlayOpen else { return false }
            begin(at: location)
            return true
        case .leftMouseDragged, .rightMouseDragged:
            guard isActive, Self.isChosenButton(type) else { return false }
            follow(location)
            return true
        case .leftMouseUp, .rightMouseUp:
            guard isActive, Self.isChosenButton(type) else { return false }
            finish()
            return true
        default:
            return false
        }
    }

    private static func isChosenButton(_ type: CGEventType) -> Bool {
        let right = type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp
        return right == (AppSettings.shared.snapRingButton == .right)
    }

    /// Exactly the chosen keys, so ⇧⌥⌘-click still reaches the app when ⌥⌘ opens SnapRing.
    private static func keysMatch(_ flags: CGEventFlags) -> Bool {
        let wanted = AppSettings.shared.snapRingModifiers
        guard !wanted.isEmpty else { return false }
        let held = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection([.control, .option, .shift, .command])
        return held == wanted
    }

    private func begin(at point: CGPoint) {
        isActive = true
        origin = point
        pick = .center
        let settings = AppSettings.shared
        window = settings.snapRingTarget == .frontmost ? WindowMover.shared.frontmostWindow() : DragWatcher.window(at: point)
        display = Actions.shared.desks.live.first { $0.bounds.contains(point) }
        guard window != nil, display != nil else {
            OverlayToast.show("No window to place")
            return
        }
        let r = Self.panelRadius
        ringPanel.cover(CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
        if ringPanel.contentView !== ringView.superview || ringView.superview == nil {
            ringPanel.contentView = Self.container(holding: ringView, size: 2 * r)
        }
        ringView.style = settings.snapRingStyle
        ringView.show(pick, offset: .zero)
        ringPanel.alphaValue = 1
        ringPanel.orderFrontRegardless()
        showPreview()
        watchEscape()
        Diagnostics.note("snapring: opened for \(window?.appName ?? "?") on \(display?.name ?? "?")")
    }

    /// The ring over a glass disc.
    private static func container(holding view: SnapRingView, size: CGFloat) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        let glass = NSGlassEffectView(frame: CGRect(x: size / 2 - discRadius, y: size / 2 - discRadius,
                                                    width: 2 * discRadius, height: 2 * discRadius))
        glass.cornerRadius = discRadius
        container.addSubview(glass)
        view.frame = container.bounds
        container.addSubview(view)
        return container
    }

    private func follow(_ point: CGPoint) {
        guard window != nil else { return }
        let offset = CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
        let next = SnapRingPick(offset: offset)
        ringView.show(next, offset: offset)
        guard next != pick else { return }
        pick = next
        showPreview()
    }

    /// The outline of where the window will go; none for a center that cancels.
    private func showPreview() {
        guard let display, !(pick == .center && AppSettings.shared.snapRingCenter == .cancel) else {
            return previewPanel.orderOut(nil)
        }
        let frame = Actions.shared.frame(for: pick.zone, on: display)
        previewPanel.cover(frame)
        if !(previewPanel.contentView is SnapPreviewView) { previewPanel.contentView = SnapPreviewView() }
        previewPanel.contentView?.needsDisplay = true
        previewPanel.order(.below, relativeTo: ringPanel.windowNumber)
    }

    private func finish() {
        let window = self.window, display = self.display, pick = self.pick
        close()
        guard let window, let display else { return }
        if pick == .center, AppSettings.shared.snapRingCenter == .cancel {
            return Diagnostics.note("snapring: let go in the center; canceled")
        }
        Actions.shared.snap(window, to: pick.zone, on: display)
        Diagnostics.note("snapring: snapped \(window.appName) to \(pick) on \(display.name)")
    }

    private func cancel() {
        guard isActive else { return }
        close()
        // The release still belongs to SnapRing: swallow it.
        isActive = true
        window = nil
        Diagnostics.note("snapring: closed with Esc")
    }

    private func close() {
        isActive = false
        escapeTimer?.invalidate()
        escapeTimer = nil
        previewPanel.orderOut(nil)
        ringPanel.disappear()
    }

    /// A global key monitor doesn't hear keys while the button is down in some apps.
    private func watchEscape() {
        escapeTimer?.invalidate()
        let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated {
                if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape)) { SnapRing.shared.cancel() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        escapeTimer = timer
    }
}

#if DEBUG
extension SnapRing {
    /// `snapring-<style>` (pointing top right), `-far` (the outer tier), `-center`.
    static let snapshotPages = SnapRingStyle.allCases.flatMap { style in
        ["", "-far", "-center"].map { "snapring-\(style.rawValue)\($0)" }
    }

    static func snapshotWindow(_ page: String) -> NSWindow {
        let size = 2 * panelRadius
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        let view = SnapRingView()
        view.style = SnapRingStyle.allCases.first { page.hasPrefix("snapring-\($0.rawValue)") } ?? .donut
        let offset = page.hasSuffix("-center") ? CGVector(dx: 4, dy: 3)
            : page.hasSuffix("-far") ? CGVector(dx: 80, dy: -80) : CGVector(dx: 40, dy: -40)
        view.show(SnapRingPick(offset: offset), offset: offset)
        window.contentView = container(holding: view, size: size)
        window.orderFrontRegardless()
        return window
    }
}
#endif

/// The tap runs on the main run loop.
private func snapRingTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let flags = event.flags, location = event.location
    let swallow = MainActor.assumeIsolated { SnapRing.shared.handle(type, flags: flags, at: location) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// The ring itself, in one of three styles, drawn around its center.
@MainActor
final class SnapRingView: NSView {
    var style = SnapRingStyle.donut { didSet { needsDisplay = true } }
    private var pick = SnapRingPick.center
    private var offset = CGVector.zero

    override var isFlipped: Bool { true }

    func show(_ pick: SnapRingPick, offset: CGVector) {
        self.pick = pick
        self.offset = offset
        needsDisplay = true
    }

    private static let half = CGFloat.pi / 8

    override func draw(_ dirtyRect: NSRect) {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let accent = NSColor.controlAccentColor
        let quiet = NSColor.labelColor.withAlphaComponent(0.14)
        let line = NSColor.labelColor.withAlphaComponent(0.25)
        var active: SnapRingDirection?
        var far = false
        if case .wedge(let d, let f) = pick { active = d; far = f }

        switch style {
        case .donut:
            for d in SnapRingDirection.allCases {
                let path = Self.sector(c, 22, 54, d.angle - Self.half, d.angle + Self.half)
                (d == active ? accent : NSColor.clear).setFill()
                path.fill()
                line.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            Self.dot(c, 12, pick == .center ? accent : quiet)
        case .petals:
            for d in SnapRingDirection.allCases {
                let push: CGFloat = d == active ? 5 : 0
                let shifted = CGPoint(x: c.x + push * cos(d.angle), y: c.y + push * sin(d.angle))
                (d == active ? accent : quiet).setFill()
                Self.sector(shifted, 20, 52, d.angle - Self.half * 0.82, d.angle + Self.half * 0.82).fill()
            }
            Self.dot(c, 8, pick == .center ? accent : quiet)
        case .tail:
            let track = Self.sector(c, 36, 44, 0, 2 * .pi)
            quiet.setFill()
            track.fill()
            if let active {
                accent.setFill()
                Self.sector(c, 36, 44, active.angle - Self.half, active.angle + Self.half).fill()
                let length = min(hypot(offset.dx, offset.dy), bounds.width / 2 - 6)
                let angle = atan2(offset.dy, offset.dx)
                let end = CGPoint(x: c.x + length * cos(angle), y: c.y + length * sin(angle))
                let path = NSBezierPath()
                path.move(to: c)
                path.line(to: end)
                path.lineWidth = 1.5
                path.setLineDash([3, 3], count: 2, phase: 0)
                accent.setStroke()
                path.stroke()
                Self.dot(end, 4, accent)
            }
            Self.dot(c, 5, pick == .center ? accent : line)
        }

        // The outer tier: a thin arc outside the active wedge.
        if far, let active, style != .tail {
            accent.setFill()
            Self.sector(c, 58, 62, active.angle - Self.half, active.angle + Self.half).fill()
        }
    }

    /// A ring sector between two radii, angles in radians, y down.
    private static func sector(_ c: CGPoint, _ r1: CGFloat, _ r2: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 24
        func point(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        for i in 0...steps { let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps); i == 0 ? path.move(to: point(r2, a)) : path.line(to: point(r2, a)) }
        for i in (0...steps).reversed() { path.line(to: point(r1, a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps))) }
        path.close()
        return path
    }

    private static func dot(_ p: CGPoint, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
    }
}

/// The outline of where SnapRing will put the window.
@MainActor
final class SnapPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        accent.withAlphaComponent(0.18).setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
