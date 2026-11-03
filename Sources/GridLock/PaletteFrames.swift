#if DEBUG
import AppKit

/// Ten ways to frame today's palette with a black keyline and a shadow, to choose one
/// from. Snapshot mode only: pages `keyline-01` … `keyline-10`, the palette-hover scene
/// with the frame drawn around the palette.
@MainActor
enum PaletteFrames {
    struct Shadow {
        var alpha: CGFloat
        var blur: CGFloat
        /// Downward offset.
        var y: CGFloat
        var x: CGFloat = 0
    }

    struct Style {
        let name: String
        let line: CGFloat
        let lineAlpha: CGFloat
        /// A white hairline just inside the keyline, like a bevel.
        var highlight = false
        let shadows: [Shadow]
    }

    static let styles: [Style] = [
        Style(name: "Hairline, soft shadow", line: 1, lineAlpha: 0.85, shadows: [Shadow(alpha: 0.22, blur: 18, y: 8)]),
        Style(name: "Light hairline, soft shadow", line: 1, lineAlpha: 0.4, shadows: [Shadow(alpha: 0.22, blur: 18, y: 8)]),
        Style(name: "Fine line, wide shadow", line: 0.5, lineAlpha: 1, shadows: [Shadow(alpha: 0.3, blur: 40, y: 18)]),
        Style(name: "Medium line, tight shadow", line: 1.5, lineAlpha: 1, shadows: [Shadow(alpha: 0.35, blur: 6, y: 3)]),
        Style(name: "Bold line, medium shadow", line: 2, lineAlpha: 1, shadows: [Shadow(alpha: 0.28, blur: 14, y: 6)]),
        Style(name: "Keyline with inner highlight", line: 1, lineAlpha: 0.9, highlight: true, shadows: [Shadow(alpha: 0.25, blur: 20, y: 8)]),
        Style(name: "Window-style layered shadow", line: 1, lineAlpha: 0.7,
              shadows: [Shadow(alpha: 0.25, blur: 3, y: 1), Shadow(alpha: 0.3, blur: 30, y: 14)]),
        Style(name: "Hard offset shadow", line: 1.5, lineAlpha: 1, shadows: [Shadow(alpha: 0.85, blur: 0, y: 5, x: 5)]),
        Style(name: "Heavy line, floating", line: 2.5, lineAlpha: 1,
              shadows: [Shadow(alpha: 0.18, blur: 6, y: 2), Shadow(alpha: 0.35, blur: 50, y: 26)]),
        Style(name: "Keyline with halo", line: 1, lineAlpha: 1, shadows: [Shadow(alpha: 0.45, blur: 24, y: 0)]),
    ]

    static var pages: [String] { styles.indices.map { String(format: "keyline-%02d", $0 + 1) } }

    static func number(of page: String) -> Int? {
        guard page.hasPrefix("keyline-"), let n = Int(page.dropFirst(8)), (1...styles.count).contains(n) else { return nil }
        return n
    }

    /// The palette's corner radius (`PaletteContainer`'s glass).
    static let radius: CGFloat = 22
    /// Room around the palette for the widest shadow.
    static let spill: CGFloat = 90
}

/// The shadows, drawn outside the palette only, so none shows through its glass.
@MainActor
final class PaletteFrameShadow: NSView {
    let style: PaletteFrames.Style

    init(frame: CGRect, style: PaletteFrames.Style) {
        self.style = style
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let panel = bounds.insetBy(dx: PaletteFrames.spill, dy: PaletteFrames.spill)
        let shape = NSBezierPath(roundedRect: panel, xRadius: PaletteFrames.radius, yRadius: PaletteFrames.radius)
        for s in style.shadows {
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: bounds)
            outside.append(shape)
            outside.windingRule = .evenOdd
            outside.addClip()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(s.alpha)
            shadow.shadowBlurRadius = s.blur
            // NSShadow offsets in unflipped space: negative height is down.
            shadow.shadowOffset = NSSize(width: s.x, height: -s.y)
            shadow.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// The keyline, drawn over the palette's edge.
@MainActor
final class PaletteFrameLine: NSView {
    let style: PaletteFrames.Style

    init(frame: CGRect, style: PaletteFrames.Style) {
        self.style = style
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let panel = bounds.insetBy(dx: PaletteFrames.spill, dy: PaletteFrames.spill)
        let w = style.line
        let line = NSBezierPath(roundedRect: panel.insetBy(dx: w / 2, dy: w / 2),
                                xRadius: PaletteFrames.radius - w / 2, yRadius: PaletteFrames.radius - w / 2)
        line.lineWidth = w
        NSColor.black.withAlphaComponent(style.lineAlpha).setStroke()
        line.stroke()
        if style.highlight {
            let inner = NSBezierPath(roundedRect: panel.insetBy(dx: w + 0.5, dy: w + 0.5),
                                     xRadius: PaletteFrames.radius - w - 0.5, yRadius: PaletteFrames.radius - w - 0.5)
            inner.lineWidth = 1
            NSColor.white.withAlphaComponent(0.45).setStroke()
            inner.stroke()
        }
    }
}
#endif
