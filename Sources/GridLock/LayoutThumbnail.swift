import GridLockKit
import SwiftUI

/// One layout drawn as a small display split into its zones: the palette's thumbnails, the
/// Palette pane's rows and preview, and the Layouts pane. Fills the frame it's given; callers
/// pick the size (16:10 suits most displays). `highlightedZone` fills that zone with the
/// accent color and outlines it, so the hovered zone reads without relying on color.
struct LayoutThumbnail: View {
    let kind: LayoutKind
    var customLayouts: [CustomLayout] = []
    var highlightedZone: Int? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Scales with the thumbnail: hairline gaps on a row icon, roomier on the palette.
            let inset = max(2, min(size.width, size.height) * 0.06)
            let gap = max(1.5, min(size.width, size.height) * 0.035)
            let area = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let zones = kind.zones(custom: customLayouts)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: inset * 1.2, style: .continuous)
                    .fill(.background.secondary)
                RoundedRectangle(cornerRadius: inset * 1.2, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                ForEach(zones.indices, id: \.self) { i in
                    let rect = frame(of: zones[i], in: area, gap: gap)
                    let lit = i == highlightedZone
                    RoundedRectangle(cornerRadius: gap, style: .continuous)
                        .fill(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .overlay {
                            RoundedRectangle(cornerRadius: gap, style: .continuous)
                                .strokeBorder(lit ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.35)),
                                              lineWidth: lit ? 2 : 0.5)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                if zones.isEmpty {
                    Image(systemName: "questionmark").foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(kind.title(custom: customLayouts))
        .accessibilityValue(highlightedZone.map { "zone \($0 + 1) of \(kind.zones(custom: customLayouts).count)" } ?? "")
    }

    /// A zone's rectangle in the thumbnail, giving up half the gap on every inner edge so
    /// neighbors sit one gap apart, like snapped windows.
    private func frame(of zone: UnitRect, in area: CGRect, gap: CGFloat) -> CGRect {
        let e = 0.0001
        var r = CGRect(x: area.minX + zone.x * area.width, y: area.minY + zone.y * area.height,
                       width: zone.width * area.width, height: zone.height * area.height)
        let half = gap / 2
        if zone.x > e { r.origin.x += half; r.size.width -= half }
        if zone.x + zone.width < 1 - e { r.size.width -= half }
        if zone.y > e { r.origin.y += half; r.size.height -= half }
        if zone.y + zone.height < 1 - e { r.size.height -= half }
        return r
    }
}
