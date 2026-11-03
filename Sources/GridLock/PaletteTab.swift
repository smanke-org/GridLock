import AppKit
import GridLockKit

/// The palette's tab: while a window is dragged, the palette's bottom edge peeks down from
/// under the menu bar at the top center of the display under the pointer, as wide as the
/// palette and `PaletteTab.height` tall, as if the rest were just out of sight. It's the
/// palette's own frame and glass, clipped, so when the pointer reaches it (`DragWatcher`)
/// the palette slides down out of it. It never takes the mouse.
@MainActor
final class PaletteTabOverlay {
    static let shared = PaletteTabOverlay()

    private let panel = OverlayPanel(takesKeys: false, clickThrough: true)
    private let reveal = RevealView(child: PaletteFrame(content: GlassFill()))
    private(set) var display: LiveDisplay?
    /// The tab's frame (the visible edge), global top-left.
    private(set) var frame = CGRect.zero

    var isShowing: Bool { display != nil }

    init() {
        panel.contentView = reveal
    }

    /// Shows the tab on a display, or moves it there.
    func show(on display: LiveDisplay) {
        guard display.key != self.display?.key else { return }
        let count = Actions.shared.desks.settings(for: display).palette.count
        let palette = PaletteOverlay.geometry(for: display, count: count)
            .frame(hangingFrom: display.visible, centerX: display.bounds.midX, bounds: display.bounds)
        frame = PaletteTab.frame(palette: palette, visible: display.visible)
        // The window shows the edge plus room for the shadow at the sides and below; the
        // palette's frame inside it is pulled up so only its bottom edge is in view.
        let m = PaletteFrame.margin
        panel.cover(CGRect(x: palette.minX - m, y: display.visible.minY, width: palette.width + 2 * m, height: PaletteTab.height + m))
        reveal.frame = CGRect(origin: .zero, size: panel.frame.size)
        reveal.topCut = m
        reveal.childHeight = palette.height + 2 * m
        reveal.pulledUp = palette.height - PaletteTab.height
        reveal.layoutSubtreeIfNeeded()
        let moving = self.display != nil
        self.display = display
        if moving { panel.orderFrontRegardless() } else { panel.appear() }
    }

    func close() {
        guard isShowing else { return }
        display = nil
        panel.disappear()
    }
}
