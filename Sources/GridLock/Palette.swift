import AppKit
import Carbon.HIToolbox
import GridLockKit
import Observation
import SwiftUI

/// The palette: the display's layouts, opened three ways.
///
/// - Dragging a window to the top edge drops it down under the cursor.
/// - Holding the drag keys (Settings › Shortcuts, ⌘ by default) while dragging opens it at
///   once next to the cursor, so the top edge, and Mission Control behind it, can be avoided.
/// - The Open Palette shortcut opens it at the top of the display holding the frontmost
///   window; a click on a zone snaps that window.
///
/// While a window is dragged the palette never takes the mouse (the cursor is busy with
/// another app's window), so `DragWatcher` feeds it the cursor and it works out the zone
/// itself. Opened by the shortcut it is a clickable, key-taking panel instead.
@MainActor
final class PaletteOverlay {
    static let shared = PaletteOverlay()

    enum Trigger {
        case edge
        case modifier
        /// Opened by the shortcut, for this window.
        case shortcut(TargetWindow)
    }

    private let panel = OverlayPanel(takesKeys: false, clickThrough: true)
    private let clickPanel = OverlayPanel(takesKeys: true, clickThrough: false)
    private let preview = OverlayPanel(takesKeys: false, clickThrough: true)
    private let previewView = DropPreviewView()
    private let model = PaletteModel()
    private var display: LiveDisplay?
    /// The palette's frame, global top-left.
    private var frame = CGRect.zero
    private var zones: [[UnitRect]] = []
    private(set) var trigger = Trigger.edge
    /// While opened by the shortcut: clicks elsewhere and app switches close it.
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    private(set) var isShowing = false

    var isOpenedByShortcut: Bool {
        if isShowing, case .shortcut = trigger { return true }
        return false
    }

    init() {
        panel.contentView = PaletteContainer(model: model)
        let clickable = PaletteContainer(model: model, clicks: true)
        clickPanel.contentView = clickable
        clickPanel.acceptsMouseMovedEvents = true
        preview.contentView = previewView
        // Under the palette, over the dragged window.
        preview.level = .floating
    }

    /// Opens on a display, centered under the cursor (a drag at the top edge).
    func open(on display: LiveDisplay, cursorX: CGFloat) {
        present(on: display, trigger: .edge) { geometry in
            geometry.frame(under: cursorX, bounds: display.bounds, visible: display.visible)
        }
    }

    /// Opens next to the cursor (the drag keys were held mid-drag).
    func open(on display: LiveDisplay, near cursor: CGPoint) {
        present(on: display, trigger: .modifier) { $0.frame(near: cursor, visible: display.visible) }
    }

    /// The Open Palette shortcut: closes the palette if it's already open that way, else
    /// opens it for the frontmost window, at the top of the display holding it.
    func toggleForFrontmostWindow() {
        if isOpenedByShortcut { return close() }
        guard !isShowing else { return }
        guard AXWindows.isTrusted else { return WelcomeWindow.shared.show() }
        guard let window = WindowMover.shared.frontmostWindow(),
              let display = Actions.shared.desks.display(holding: window.frame) else {
            return OverlayToast.show("No window to place")
        }
        GridOverlay.shared.close(returningFocus: false)
        let mouse = Self.cursor
        let x = display.bounds.contains(mouse) ? mouse.x : display.bounds.midX
        present(on: display, trigger: .shortcut(window)) {
            $0.frame(under: x, bounds: display.bounds, visible: display.visible)
        }
        watchForDismissal(of: window)
        _ = track(mouse)
    }

    private func present(on display: LiveDisplay, trigger: Trigger, frameFor: (PaletteGeometry) -> CGRect) {
        let settings = Actions.shared.desks.settings(for: display)
        let custom = Actions.shared.desks.store.library.customLayouts
        let kinds = settings.palette.map(\.kind)
        self.display = display
        self.trigger = trigger
        model.kinds = kinds
        model.custom = custom
        model.highlight = nil
        // An empty palette still opens, with one way to fill it.
        zones = kinds.isEmpty ? [[.full]] : kinds.map { $0.zones(custom: custom) }
        let aspect = display.visible.width / max(display.visible.height, 1)
        model.geometry = PaletteGeometry(count: zones.count, aspect: aspect, maxWidth: min(display.bounds.width - 40, 900))
        frame = frameFor(model.geometry)
        let panel = activePanel
        panel.cover(frame)
        panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
        isShowing = true

        // Drops down from the top edge; with Reduce Motion it only fades in.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let final = panel.frame
        panel.alphaValue = 0
        if !reduce { panel.setFrame(final.offsetBy(dx: 0, dy: 14), display: false) }
        if case .shortcut = trigger {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
            if !reduce { panel.animator().setFrame(final, display: true) }
        }
        Diagnostics.note("palette: opened (\(trigger.name)) on \(display.name) with \(kinds.count) layouts at \(frame)")
    }

    private var activePanel: OverlayPanel {
        if case .shortcut = trigger { return clickPanel }
        return panel
    }

    /// Follows the cursor (global). Returns false when the cursor has gone far enough away
    /// that the palette should close. Opened by the drag keys or the shortcut, distance
    /// never closes it: letting go of the keys does, or Esc, or a click elsewhere.
    func track(_ cursor: CGPoint) -> Bool {
        guard isShowing, let display else { return false }
        if case .edge = trigger, !PaletteGeometry.keepsOpen(cursor: cursor, palette: frame, bounds: display.bounds) {
            return false
        }
        let local = CGPoint(x: cursor.x - frame.minX, y: cursor.y - frame.minY)
        let hit = model.geometry.hit(local, zones: zones)
        let changed = hit?.entry != model.highlight?.entry || hit?.zone != model.highlight?.zone
        guard changed else { return true }
        model.highlight = hit.map { PaletteModel.Highlight(entry: $0.entry, zone: $0.zone) }
        if let target = hit.flatMap({ targetFrame(for: $0) }) {
            preview.cover(target)
            previewView.size = target.size
            if !preview.isVisible { preview.appear() }
        } else {
            preview.disappear()
        }
        return true
    }

    /// Whether the cursor (global) is on the palette or close to it.
    func isNear(_ cursor: CGPoint) -> Bool {
        isShowing && frame.insetBy(dx: -48, dy: -48).contains(cursor)
    }

    /// The zone under the cursor, if any, with its display — what a release snaps to.
    var choice: (zone: UnitRect, display: LiveDisplay)? {
        guard isShowing, let display, let h = model.highlight, !model.kinds.isEmpty else { return nil }
        return (zones[h.entry][h.zone], display)
    }

    /// Whether the cursor is on the "Edit Palette…" tile of an empty palette.
    var isOnEditTile: Bool { isShowing && model.kinds.isEmpty && model.highlight != nil }

    /// A click on the palette opened by the shortcut: on a zone it snaps the window there.
    func clicked() {
        guard case .shortcut(let window) = trigger else { return }
        _ = track(Self.cursor)
        if let choice {
            close()
            Actions.shared.snap(window, to: choice.zone, on: choice.display)
            Diagnostics.note("palette: snapped \(window.appName) on \(choice.display.name) by click")
        } else if isOnEditTile {
            close(returningFocus: false)
            SettingsWindow.shared.show(tab: "Palette")
        }
        // Between thumbnails: nothing happens.
    }

    /// Closes without moving anything. Opened by the shortcut, the keys go back to the
    /// window's app unless the user has just switched to another one.
    func close(returningFocus: Bool = true) {
        guard isShowing else { return }
        isShowing = false
        activePanel.disappear()
        preview.disappear()
        model.highlight = nil
        if case .shortcut(let window) = trigger {
            for monitor in monitors { NSEvent.removeMonitor(monitor) }
            monitors = []
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
            activationObserver = nil
            if returningFocus { NSRunningApplication(processIdentifier: window.pid)?.activate() }
        }
        trigger = .edge
    }

    /// Opened by the shortcut: a click outside the palette, or switching apps, closes it.
    private func watchForDismissal(of window: TargetWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { _ in
            MainActor.assumeIsolated { PaletteOverlay.shared.close(returningFocus: false) }
        }) { monitors.append(m) }
        // GridLock's own windows (Settings) don't reach the global monitor.
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { event in
            MainActor.assumeIsolated {
                let palette = PaletteOverlay.shared
                if event.window !== palette.clickPanel { palette.close(returningFocus: false) }
            }
            return event
        }) { monitors.append(m) }
        let pid = window.pid
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let app, app.processIdentifier != pid,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                PaletteOverlay.shared.close(returningFocus: false)
            }
        }
    }

    /// The cursor in global top-left coordinates.
    static var cursor: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: DisplayCatalog.mainHeight - p.y)
    }

    private func targetFrame(for hit: (entry: Int, zone: Int)) -> CGRect? {
        guard let display, !model.kinds.isEmpty else { return nil }
        let grid = Actions.shared.desks.settings(for: display).grid
        return GridMath.frame(for: zones[hit.entry][hit.zone], visible: display.visible, gap: grid.gap, margin: grid.margin)
    }

    /// For the debug hook.
    func dump() -> String {
        guard isShowing else { return "palette: closed" }
        let h = model.highlight.map { "\(model.kinds.isEmpty ? "Edit Palette…" : model.kinds[$0.entry].title(custom: model.custom)) zone \($0.zone + 1)" }
        return "palette (\(trigger.name)): \(display?.name ?? "") \(frame) layouts=\(model.kinds.count) over \(h ?? "nothing")"
    }
}

extension PaletteOverlay.Trigger {
    var name: String {
        switch self {
        case .edge: "top edge"
        case .modifier: "drag keys"
        case .shortcut: "shortcut"
        }
    }
}

@Observable
@MainActor
final class PaletteModel {
    struct Highlight: Equatable {
        var entry: Int
        var zone: Int
    }

    var kinds: [LayoutKind] = []
    var custom: [CustomLayout] = []
    var geometry = PaletteGeometry(count: 0, aspect: 1.6, maxWidth: 800)
    var highlight: Highlight?
}

/// The palette's content: thumbnails at the frames `PaletteGeometry` gives, captions
/// under them.
struct PaletteView: View {
    let model: PaletteModel

    var body: some View {
        let g = model.geometry
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.kinds.isEmpty, let rect = g.thumbnails.first {
                editTile(rect)
            }
            ForEach(Array(model.kinds.enumerated()), id: \.offset) { i, kind in
                if i < g.thumbnails.count {
                    let rect = g.thumbnails[i]
                    LayoutThumbnail(kind: kind, customLayouts: model.custom,
                                    highlightedZone: model.highlight?.entry == i ? model.highlight?.zone : nil)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    caption(kind.title(custom: model.custom), under: rect)
                }
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
    }

    private func caption(_ text: String, under rect: CGRect) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: rect.width + PaletteGeometry.spacing - 2)
            .offset(x: rect.minX - PaletteGeometry.spacing / 2 + 1, y: rect.maxY + 2)
    }

    private func editTile(_ rect: CGRect) -> some View {
        let lit = model.highlight != nil
        return Group {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(lit ? Color.accentColor : Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: [4, 3]))
                .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            caption("Edit Palette…", under: rect)
        }
    }
}

/// The palette on Liquid Glass: AppKit's glass behind the SwiftUI thumbnails. Opened by
/// the shortcut it also takes the mouse and keys itself: hovering previews a zone, a click
/// snaps, Esc closes.
@MainActor
final class PaletteContainer: NSView {
    private let glass = NSGlassEffectView()
    private let host: NSHostingView<PaletteView>
    private let clicks: Bool

    init(model: PaletteModel, clicks: Bool = false) {
        host = NSHostingView(rootView: PaletteView(model: model))
        host.sizingOptions = []
        self.clicks = clicks
        super.init(frame: .zero)
        glass.cornerRadius = 22
        addSubview(glass)
        addSubview(host)
        if clicks {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glass.frame = bounds
        host.frame = bounds
    }

    // The thumbnails are drawings: every event inside the palette comes here, not to SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? {
        clicks ? (super.hitTest(point) == nil ? nil : self) : super.hitTest(point)
    }

    override var acceptsFirstResponder: Bool { clicks }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        _ = PaletteOverlay.shared.track(PaletteOverlay.cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard clicks else { return super.mouseDown(with: event) }
        PaletteOverlay.shared.clicked()
    }

    override func keyDown(with event: NSEvent) {
        guard clicks, Int(event.keyCode) == kVK_Escape else { return super.keyDown(with: event) }
        PaletteOverlay.shared.close()
        Diagnostics.note("palette: closed with Esc")
    }
}

/// The translucent outline of where the window will go, with its size.
@MainActor
final class DropPreviewView: NSView {
    private let label = GlassLabel(font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold))

    var size = CGSize.zero {
        didSet {
            label.text = GridText.size(size)
            needsLayout = true
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        label.center(at: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(contrast ? 0.4 : 0.22).setFill()
        shape.fill()
        shape.lineWidth = contrast ? 4 : 3
        NSColor.controlAccentColor.setStroke()
        shape.stroke()
    }
}
