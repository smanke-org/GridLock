import AppKit
import Carbon.HIToolbox
import GridLockKit

/// Show Grid: a grid over every display, the frontmost window's cells selected on the
/// display holding most of it. Drag across cells or use the arrow keys, then let go or press
/// Return to snap; Esc, a click outside the grid, or ⌃⌥G again closes it.
@MainActor
final class GridOverlay {
    static let shared = GridOverlay()

    private struct Screen {
        let display: LiveDisplay
        let grid: GridSpec
        let panel: OverlayPanel
        let view: GridView
    }

    private var screens: [Screen] = []
    /// Kept between showings, so a panel still fading out isn't released mid-animation.
    private var pool: [OverlayPanel] = []
    private var window: TargetWindow?
    private var active = 0
    private var cells = CellRange(column: 0, row: 0, columns: 1, rows: 1)
    /// The cell a mouse drag started on.
    private var anchor: (column: Int, row: Int)?
    /// The selection differs from the window's own cells: show the frame it will get.
    private var changed = false
    private var activationObserver: NSObjectProtocol?

    var isShowing: Bool { !screens.isEmpty }

    func toggle() {
        isShowing ? close() : show()
    }

    func show() {
        guard !isShowing else { return }
        guard let target = WindowMover.shared.frontmostWindow() else {
            return OverlayToast.show(Self.frontmostIsFullScreen() ? "GridLock can't move full-screen windows" : "No window to place")
        }
        var displays = Actions.shared.desks.live
        if displays.isEmpty { displays = DisplayCatalog.current() }
        guard let index = LiveDisplay.index(holding: target.frame, in: displays) else { return }

        window = target
        active = index
        changed = false
        anchor = nil
        screens = displays.enumerated().map { i, display in
            if pool.count <= i { pool.append(OverlayPanel(takesKeys: true, clickThrough: false)) }
            let panel = pool[i]
            let view = GridView(frame: CGRect(origin: .zero, size: display.bounds.size))
            view.events = self
            view.index = i
            panel.contentView = view
            panel.cover(display.bounds)
            return Screen(display: display, grid: Actions.shared.desks.settings(for: display).grid, panel: panel, view: view)
        }
        let screen = screens[active]
        cells = GridMath.cells(for: target.frame, grid: screen.grid, visible: screen.display.visible)
        refresh()
        for (i, s) in screens.enumerated() { s.panel.appear(key: i == active) }
        announce()
        Diagnostics.note("grid: shown on \(screen.display.name) for \(target.appName) \(cells)")

        // Switching to another app (⌘-Tab) takes the keys away: close rather than linger.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, app.processIdentifier != self.window?.pid,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.close()
            }
        }
    }

    /// Closes without moving anything.
    func close() {
        guard isShowing else { return }
        for s in screens { s.panel.disappear() }
        screens = []
        anchor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        // The panel had the keys; hand them back to the app whose window it was.
        if let pid = window?.pid { NSRunningApplication(processIdentifier: pid)?.activate() }
        window = nil
    }

    /// Snaps the window into the selection and closes.
    func snap() {
        guard isShowing, let window else { return }
        let screen = screens[active]
        Actions.shared.snap(window, to: cells, on: screen.display)
        Diagnostics.note("grid: snapped \(window.appName) to \(cells) on \(screen.display.name)")
        close()
    }

    func handle(_ action: GridKeyAction) {
        guard isShowing else { return }
        let next = cells.applying(action, in: screens[active].grid)
        // At an edge the key does nothing: no beep, no wrap.
        guard next != cells else { return }
        cells = next
        changed = true
        refresh()
        announce()
    }

    /// Arrow keys to grid actions: plain moves, ⇧ grows, ⌥⇧ shrinks.
    static func action(keyCode: Int, flags: NSEvent.ModifierFlags) -> GridKeyAction? {
        let direction: GridDirection
        switch keyCode {
        case kVK_LeftArrow: direction = .left
        case kVK_RightArrow: direction = .right
        case kVK_UpArrow: direction = .up
        case kVK_DownArrow: direction = .down
        default: return nil
        }
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) && flags.contains(.option) { return .shrink(direction) }
        if flags.contains(.shift) { return .grow(direction) }
        return .move(direction)
    }

    // MARK: Drawing

    private func refresh() {
        guard let window else { return }
        for (i, s) in screens.enumerated() {
            var state = GridView.State(grid: s.grid, visible: ScreenSpace.local(s.display.visible, in: s.display.bounds))
            if i == active {
                let target = GridMath.frame(for: cells, grid: s.grid, visible: s.display.visible)
                state.selection = cells
                state.target = ScreenSpace.local(target, in: s.display.bounds)
                state.showsTargetSize = changed
                state.label = GridText.label(app: window.appName, frame: changed ? target : window.frame, cells: cells)
                state.showsHint = true
            }
            if s.display.bounds.intersects(window.frame) {
                state.window = ScreenSpace.local(window.frame, in: s.display.bounds)
            }
            s.view.state = state
        }
    }

    private func announce() {
        guard isShowing else { return }
        let text = GridText.announcement(grid: screens[active].grid, cells: cells)
        NSAccessibility.post(element: screens[active].view, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        screens[active].view.setAccessibilityLabel(text)
    }

    /// Whether the frontmost app's window is full screen, to say why there's nothing to place.
    private static func frontmostIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXWindows.appElement(for: app.processIdentifier),
                                            kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        return AXWindows.window(focused as! AXUIElement)?.isFullScreen == true
    }

    /// For the debug hook.
    func dump() -> String {
        guard isShowing, let window else { return "grid: closed" }
        let s = screens[active]
        return "grid: \(s.display.name) \(s.grid.columns)×\(s.grid.rows) \(window.appName) selection \(cells) → "
            + "\(GridMath.frame(for: cells, grid: s.grid, visible: s.display.visible))"
    }
}

extension GridOverlay: GridViewEvents {
    func mouseDown(at point: CGPoint, in index: Int) {
        let s = screens[index]
        let global = CGPoint(x: point.x + s.display.bounds.minX, y: point.y + s.display.bounds.minY)
        guard let cell = GridMath.cell(at: global, grid: s.grid, visible: s.display.visible) else {
            // A click outside the grid (menu bar, Dock, margin) cancels.
            return close()
        }
        if index != active {
            // A press on another display's grid moves the window there.
            active = index
        }
        anchor = cell
        cells = CellRange(from: cell, to: cell)
        changed = true
        refresh()
    }

    func mouseDragged(to point: CGPoint, in index: Int) {
        guard let anchor, index == active else { return }
        let s = screens[active]
        let area = GridMath.inner(s.display.visible, margin: s.grid.margin)
        // Past the grid's edge counts as its last cell, so a fast drag reaches the edge.
        let global = CGPoint(x: min(max(point.x + s.display.bounds.minX, area.minX), area.maxX - 1),
                             y: min(max(point.y + s.display.bounds.minY, area.minY), area.maxY - 1))
        guard let cell = GridMath.cell(at: global, grid: s.grid, visible: s.display.visible) else { return }
        let next = CellRange(from: anchor, to: cell)
        guard next != cells else { return }
        cells = next
        refresh()
    }

    func mouseUp(in index: Int) {
        guard anchor != nil else { return }
        anchor = nil
        snap()
    }

    func keyDown(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter: snap()
        default:
            if let action = Self.action(keyCode: Int(event.keyCode), flags: event.modifierFlags) { handle(action) }
        }
    }
}

@MainActor
protocol GridViewEvents: AnyObject {
    func mouseDown(at point: CGPoint, in index: Int)
    func mouseDragged(to point: CGPoint, in index: Int)
    func mouseUp(in index: Int)
    func keyDown(_ event: NSEvent)
}

/// One display's grid. Top-left coordinates, the display's own: (0, 0) is its top-left corner.
@MainActor
final class GridView: NSView {
    struct State {
        var grid: GridSpec
        /// The display's usable area, display-local.
        var visible: CGRect
        var selection: CellRange?
        /// The frame the window will get.
        var target: CGRect?
        var showsTargetSize = false
        /// Where the window is now.
        var window: CGRect?
        var label: String?
        var showsHint = false
    }

    weak var events: GridViewEvents?
    var index = 0
    var state: State? { didSet { layoutLabels(); needsDisplay = true } }

    private let label = GlassLabel()
    private let sizeLabel = GlassLabel(font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
    private let hint = GlassLabel(font: .systemFont(ofSize: 12))

    static let hintText = "←↑↓→ Move   ⇧ Grow   ⌥⇧ Shrink   ↩ Snap   esc Cancel"

    override init(frame: NSRect) {
        super.init(frame: frame)
        hint.text = Self.hintText
        for v in [label, sizeLabel, hint] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func layoutLabels() {
        guard let state else { return }
        let area = GridMath.inner(state.visible, margin: state.grid.margin)
        label.isHidden = state.label == nil
        label.text = state.label ?? ""
        label.maxWidth = area.width - 40
        label.center(at: CGPoint(x: area.midX, y: area.minY + 32))
        hint.isHidden = !state.showsHint
        hint.center(at: CGPoint(x: area.midX, y: area.maxY - 30))
        sizeLabel.isHidden = !(state.showsTargetSize && state.target != nil)
        if let target = state.target {
            sizeLabel.text = GridText.size(target.size)
            sizeLabel.center(at: CGPoint(x: target.midX, y: target.midY))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let state else { return }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let area = GridMath.inner(state.visible, margin: state.grid.margin)

        // A light veil over the display, a little stronger over the grid.
        NSColor.black.withAlphaComponent(dark ? 0.22 : 0.10).setFill()
        bounds.fill()
        (dark ? NSColor.black : NSColor.white).withAlphaComponent(dark ? 0.18 : 0.22).setFill()
        area.fill(using: .sourceOver)

        // Grid lines.
        let line = NSBezierPath()
        let cw = area.width / CGFloat(state.grid.columns), ch = area.height / CGFloat(state.grid.rows)
        for c in 0...state.grid.columns {
            let x = (area.minX + CGFloat(c) * cw).rounded() + 0.5
            line.move(to: CGPoint(x: x, y: area.minY))
            line.line(to: CGPoint(x: x, y: area.maxY))
        }
        for r in 0...state.grid.rows {
            let y = (area.minY + CGFloat(r) * ch).rounded() + 0.5
            line.move(to: CGPoint(x: area.minX, y: y))
            line.line(to: CGPoint(x: area.maxX, y: y))
        }
        line.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(contrast ? 0.7 : 0.35).setStroke()
        line.stroke()

        // Where the window is now: a thin dashed outline.
        if let window = state.window {
            let path = NSBezierPath(roundedRect: window.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.labelColor.withAlphaComponent(contrast ? 0.8 : 0.45).setStroke()
            path.stroke()
        }

        // The selection: accent fill plus a 2 pt outline, never color alone.
        if let cells = state.selection {
            let rect = CGRect(x: area.minX + CGFloat(cells.column) * cw, y: area.minY + CGFloat(cells.row) * ch,
                              width: CGFloat(cells.columns) * cw, height: CGFloat(cells.rows) * ch)
            NSColor.controlAccentColor.withAlphaComponent(contrast ? 0.45 : 0.28).setFill()
            rect.fill(using: .sourceOver)
            let outline = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            outline.lineWidth = contrast ? 3 : 2
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }

        // The ghost: the frame the window will get, gap and margin applied.
        if let target = state.target {
            let ghost = NSBezierPath(roundedRect: target.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10)
            (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.08).setFill()
            ghost.fill()
            ghost.lineWidth = 2
            NSColor.white.withAlphaComponent(contrast ? 1 : 0.85).setStroke()
            ghost.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        events?.mouseDown(at: convert(event.locationInWindow, from: nil), in: index)
    }

    override func mouseDragged(with event: NSEvent) {
        events?.mouseDragged(to: convert(event.locationInWindow, from: nil), in: index)
    }

    override func mouseUp(with event: NSEvent) {
        events?.mouseUp(in: index)
    }

    override func keyDown(with event: NSEvent) {
        events?.keyDown(event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
