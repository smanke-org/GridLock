import GridLockKit
import SwiftUI

/// A layout drawn small, split into its zones: the palette's thumbnails and Settings' lists.
/// Fills whatever frame it is given. (Minimal version; the Desks UI work restyles it.)
struct LayoutThumbnail: View {
    let kind: LayoutKind
    var customLayouts: [CustomLayout] = []
    /// The zone under the cursor, filled with the accent color.
    var highlightedZone: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let zones = kind.zones(custom: customLayouts)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.08))
                ForEach(zones.indices, id: \.self) { i in
                    let z = zones[i]
                    let lit = i == highlightedZone
                    RoundedRectangle(cornerRadius: 3)
                        .fill(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(lit ? Color.primary.opacity(0.9) : Color.primary.opacity(0.28), lineWidth: lit ? 2 : 1))
                        .frame(width: max(z.width * geo.size.width - 4, 1), height: max(z.height * geo.size.height - 4, 1))
                        .offset(x: z.x * geo.size.width + 2, y: z.y * geo.size.height + 2)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(kind.title(custom: customLayouts))
    }
}
