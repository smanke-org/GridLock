#if DEBUG
import AppKit
import GridLockKit

/// Snapshot pages for the grid and the palette, drawn over a made-up display with one
/// window on it — never the real screen.
@MainActor
enum OverlaySnapshots {
    static let pages = ["overlay-grid", "overlay-grid-selecting", "palette", "palette-hover"]

    /// A 1440 × 900 display with a menu bar and a Dock, in its own top-left space.
    static let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let visible = CGRect(x: 0, y: 33, width: 1440, height: 795)
    static let windowFrame = CGRect(x: 180, y: 120, width: 760, height: 520)
    static let grid = GridSpec(columns: 6, rows: 4, gap: 8, margin: 8)
    static let draggedFrame = CGRect(x: 330, y: 33, width: 760, height: 520)
    static let cursor = CGPoint(x: 720, y: 2)

    private static var window: NSWindow?

    static func render(_ page: String) async -> NSWindow? {
        let window = self.window ?? NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window = window
        window.isReleasedWhenClosed = false
        let palette = page.hasPrefix("palette")
        // For the palette, the window is being dragged at the top of the display.
        let canvas = FakeDesktop(frame: bounds, window: palette ? draggedFrame : windowFrame)
        switch page {
        case "overlay-grid", "overlay-grid-selecting":
            let view = GridView(frame: bounds)
            let selecting = page == "overlay-grid-selecting"
            let cells = selecting ? CellRange(column: 3, row: 0, columns: 3, rows: 2)
                : GridMath.cells(for: windowFrame, grid: grid, visible: visible)
            let target = GridMath.frame(for: cells, grid: grid, visible: visible)
            var state = GridView.State(grid: grid, visible: visible)
            state.selection = cells
            state.target = target
            state.showsTargetSize = selecting
            state.window = windowFrame
            state.label = GridText.label(app: "Safari", frame: selecting ? target : windowFrame, cells: cells)
            state.showsHint = true
            view.state = state
            canvas.addSubview(view)
        case "palette", "palette-hover":
            let model = PaletteModel()
            model.kinds = Palette.suggested(for: grid).map(\.kind)
            model.geometry = PaletteGeometry(count: model.kinds.count, aspect: visible.width / visible.height, maxWidth: 900)
            let frame = model.geometry.frame(under: cursor.x, bounds: bounds, visible: visible)
            if page == "palette-hover" {
                // The cursor over the right zone of the first layout (Halves).
                let zone = model.kinds[1].zones()[2]
                model.highlight = .init(entry: 1, zone: 2)
                let target = GridMath.frame(for: zone, visible: visible, gap: grid.gap, margin: grid.margin)
                let preview = DropPreviewView(frame: target)
                preview.size = target.size
                canvas.addSubview(preview)
            }
            let container = PaletteContainer(model: model)
            container.frame = frame
            canvas.addSubview(container)
        default:
            return nil
        }
        window.contentView = canvas
        window.setFrame(CGRect(x: -20000, y: -20000, width: bounds.width, height: bounds.height), display: true)
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(400))
        return window
    }
}

/// A desktop backdrop with a menu bar strip, a Dock, and one plain window, so overlays have
/// something to sit over.
@MainActor
final class FakeDesktop: NSView {
    private let fakeWindow: CGRect

    init(frame: CGRect, window: CGRect) {
        fakeWindow = window
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let top = dark ? NSColor(red: 0.13, green: 0.17, blue: 0.30, alpha: 1) : NSColor(red: 0.55, green: 0.70, blue: 0.92, alpha: 1)
        let bottom = dark ? NSColor(red: 0.24, green: 0.13, blue: 0.28, alpha: 1) : NSColor(red: 0.93, green: 0.76, blue: 0.80, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
        NSColor.windowBackgroundColor.withAlphaComponent(0.8).setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: 33).fill()
        let dock = NSBezierPath(roundedRect: CGRect(x: bounds.midX - 260, y: bounds.height - 66, width: 520, height: 58), xRadius: 18, yRadius: 18)
        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        dock.fill()

        let shape = NSBezierPath(roundedRect: fakeWindow, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.stroke()
        NSColor.underPageBackgroundColor.setFill()
        CGRect(x: fakeWindow.minX + 1, y: fakeWindow.minY + 1, width: fakeWindow.width - 2, height: 51).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: fakeWindow.minX + 18 + CGFloat(i) * 20, y: fakeWindow.minY + 20, width: 12, height: 12)).fill()
        }
    }
}
#endif
