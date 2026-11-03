import AppKit
import GridLockKit
import SwiftUI

/// The palette's tab: while a window is dragged, a hint of the palette peeks down from the
/// top center of the display under the pointer, showing its first few layouts, so it's
/// clear there's somewhere to drop the window. `DragWatcher` opens the palette when the
/// pointer reaches it. It never takes the mouse.
@MainActor
final class PaletteTabOverlay {
    static let shared = PaletteTabOverlay()

    /// Room around the tab for its shadow.
    private static let margin: CGFloat = 10

    private let panel = OverlayPanel(takesKeys: false, clickThrough: true)
    private let host = NSHostingView(rootView: PaletteTabView(kinds: [], custom: []))
    private(set) var display: LiveDisplay?
    /// The tab's frame, global top-left.
    private(set) var frame = CGRect.zero

    var isShowing: Bool { display != nil }

    init() {
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Shows the tab on a display, or moves it there.
    func show(on display: LiveDisplay) {
        guard display.key != self.display?.key else { return }
        let kinds = Actions.shared.desks.settings(for: display).palette.map(\.kind)
        let custom = Actions.shared.desks.store.library.customLayouts
        host.rootView = PaletteTabView(kinds: Array(kinds.prefix(PaletteTab.maxLayouts)), custom: custom)
        frame = PaletteTab.frame(count: kinds.count, visible: display.visible)
        // The panel reaches past the tab's sides and bottom for the shadow; its top stays on
        // the menu bar's edge.
        let m = Self.margin
        panel.cover(CGRect(x: frame.minX - m, y: frame.minY, width: frame.width + 2 * m, height: frame.height + m))
        host.frame = CGRect(origin: .zero, size: panel.frame.size)
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

/// The tab: the palette's first layouts in a little strip, with the palette's black keyline
/// down its sides and around its bottom, and a tight shadow.
struct PaletteTabView: View {
    let kinds: [LayoutKind]
    let custom: [CustomLayout]

    var body: some View {
        let shape = TabShape(radius: 9)
        HStack(spacing: PaletteTab.spacing) {
            if kinds.isEmpty {
                RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: PaletteTab.thumbnail.width, height: PaletteTab.thumbnail.height)
            }
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                LayoutThumbnail(kind: kind, customLayouts: custom)
                    .frame(width: PaletteTab.thumbnail.width, height: PaletteTab.thumbnail.height)
            }
        }
        .padding(.horizontal, PaletteTab.padding.horizontal)
        .padding(.top, PaletteTab.padding.top)
        .padding(.bottom, PaletteTab.padding.bottom)
        .background(shape.fill(.regularMaterial))
        .overlay(TabOutline(radius: 9).stroke(.black, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement()
        .accessibilityLabel("Palette: drag the window here to choose a layout")
    }
}

/// Square on top, rounded at the bottom.
private struct TabShape: Shape {
    let radius: CGFloat
    func path(in r: CGRect) -> Path {
        Path(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).path(in: r).cgPath)
    }
}

/// The keyline: down the sides and around the bottom, open along the top where the tab meets
/// the menu bar.
private struct TabOutline: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.75, dy: 0.75)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - radius), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: rect.minY))
        return p
    }
}
