import AppKit
import GridLockKit
import Observation
import SwiftUI

/// The palette: the display's layouts, dropped down under the cursor while a window is
/// dragged at the top edge. It never takes the mouse (the cursor is busy dragging another
/// app's window), so `DragWatcher` feeds it the cursor and it works out the zone itself.
@MainActor
final class PaletteOverlay {
    static let shared = PaletteOverlay()

    private let panel = OverlayPanel(takesKeys: false, clickThrough: true)
    private let preview = OverlayPanel(takesKeys: false, clickThrough: true)
    private let previewView = DropPreviewView()
    private let model = PaletteModel()
    private var display: LiveDisplay?
    /// The palette's frame, global top-left.
    private var frame = CGRect.zero
    private var zones: [[UnitRect]] = []

    private(set) var isShowing = false

    init() {
        panel.contentView = PaletteContainer(model: model)
        preview.contentView = previewView
        // Under the palette, over the dragged window.
        preview.level = .floating
    }

    /// Opens on a display, centered under the cursor.
    func open(on display: LiveDisplay, cursorX: CGFloat) {
        let settings = Actions.shared.desks.settings(for: display)
        let custom = Actions.shared.desks.store.library.customLayouts
        let kinds = settings.palette.map(\.kind)
        self.display = display
        model.kinds = kinds
        model.custom = custom
        model.highlight = nil
        // An empty palette still opens, with one way to fill it.
        zones = kinds.isEmpty ? [[.full]] : kinds.map { $0.zones(custom: custom) }
        let aspect = display.visible.width / max(display.visible.height, 1)
        model.geometry = PaletteGeometry(count: zones.count, aspect: aspect, maxWidth: min(display.bounds.width - 40, 900))
        frame = model.geometry.frame(under: cursorX, bounds: display.bounds, visible: display.visible)
        panel.cover(frame)
        panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
        isShowing = true

        // Drops down from the top edge; with Reduce Motion it only fades in.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let final = panel.frame
        panel.alphaValue = 0
        if !reduce { panel.setFrame(final.offsetBy(dx: 0, dy: 14), display: false) }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
            if !reduce { panel.animator().setFrame(final, display: true) }
        }
        Diagnostics.note("palette: opened on \(display.name) with \(kinds.count) layouts at \(frame)")
    }

    /// Follows the cursor (global). Returns false when the cursor has gone far enough away
    /// that the palette should close.
    func track(_ cursor: CGPoint) -> Bool {
        guard isShowing, let display else { return false }
        guard PaletteGeometry.keepsOpen(cursor: cursor, palette: frame, bounds: display.bounds) else { return false }
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

    /// The zone under the cursor, if any, with its display — what a release snaps to.
    var choice: (zone: UnitRect, display: LiveDisplay)? {
        guard isShowing, let display, let h = model.highlight, !model.kinds.isEmpty else { return nil }
        return (zones[h.entry][h.zone], display)
    }

    /// Whether the cursor is on the "Edit Palette…" tile of an empty palette.
    var isOnEditTile: Bool { isShowing && model.kinds.isEmpty && model.highlight != nil }

    func close() {
        guard isShowing else { return }
        isShowing = false
        panel.disappear()
        preview.disappear()
        model.highlight = nil
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
        return "palette: \(display?.name ?? "") \(frame) layouts=\(model.kinds.count) over \(h ?? "nothing")"
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

/// The palette on Liquid Glass: AppKit's glass behind the SwiftUI thumbnails.
@MainActor
final class PaletteContainer: NSView {
    private let glass = NSGlassEffectView()
    private let host: NSHostingView<PaletteView>

    init(model: PaletteModel) {
        host = NSHostingView(rootView: PaletteView(model: model))
        host.sizingOptions = []
        super.init(frame: .zero)
        glass.cornerRadius = 22
        addSubview(glass)
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glass.frame = bounds
        host.frame = bounds
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
